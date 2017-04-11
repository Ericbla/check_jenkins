#!/usr/bin/perl
#
# Check Jenkins slaves status using the JSON API
#
# Author: Eric Blanchard
#
#
# This Nagios plugin check the status of the slaves of a Jenkins instance.
# You can specify one critical and/or one warning threshold express in %
# of offline slave.
#
# You can select a given slave with -s <slave-name> option or check all defined
# slaves
#
use strict;
use LWP::UserAgent;
use JSON;
use Getopt::Long
  qw(GetOptions HelpMessage VersionMessage :config no_ignore_case bundling);
use Pod::Usage qw(pod2usage);
use File::Spec qw(tmpdir);

#use Dumpvalue;
# Nagios return values
use constant {
    OK       => 0,
    WARNING  => 1,
    CRITICAL => 2,
    UNKNOWN  => 3,
};
use constant {
    API_SUFFIX              => "/api/json",
    COMPUTER_SUFFIX         => "/computer",
    PERSISTENCY_FILE_PREFIX => "jenkins_slaves_",
};
our $VERSION = '1.1';
my %args;
my $ciMasterUrl;
my $slaveName             = '(All)';
my $warn                  = -1;
my $crit                  = -1;
my $ewarn                 = -1;
my $ecrit                 = -1;
my $status                = UNKNOWN;
my $debug                 = 0;
my $compare               = 0;
my $timeout               = 10;
my $total_computers_count = 0;
my $total_offline_count   = 0;
my $total_executors_count = 0;
my $total_running_ex      = 0;
my $status_line           = '';
my $status_line_ex        = '';
my $perfdata              = '';
my $persitency_file;
my %slaves_status;

#my $dumper = Dumpvalue->new();

# Functions prototypes
sub test_slave(\%);
sub read_slaves_status();
sub save_slaves_status(\%);
sub trace(@);

# Main
GetOptions(
    \%args,
    'version|v' => sub { VersionMessage({'-exitval' => UNKNOWN}) },
    'help|h'    => sub { HelpMessage({'-exitval'    => UNKNOWN}) },
    'man' => sub { pod2usage({'-verbose' => 2, '-exitval' => UNKNOWN}) },
    'debug|d'     => \$debug,
    'timeout|t=i' => \$timeout,
    'proxy=s',
    'noproxy',
    'noperfdata',
    'statefull|s'    => \$compare,
    'warning|w=i'    => \$warn,
    'critical|c=i'   => \$crit,
    'executorWarn=i' => \$ewarn,
    'executorCrit=i' => \$ecrit,
    'slave-name|n=s' => \$slaveName
  )
  or pod2usage({'-exitval' => UNKNOWN});
HelpMessage({'-msg' => 'Missing Jenkins url parameter', '-exitval' => UNKNOWN})
  if scalar(@ARGV) != 1;
$ciMasterUrl = $ARGV[0];
$ciMasterUrl =~ s#/$##;
my $instance_id = $ciMasterUrl;
$instance_id =~ s#^http.*?://##;
$instance_id =~ tr#/ :,;#_#s;
$persitency_file =
  File::Spec->tmpdir() . '/' . PERSISTENCY_FILE_PREFIX . $instance_id . '.log';
my $ua = LWP::UserAgent->new();
$ua->timeout($timeout);

if (defined($args{proxy})) {
    $ua->proxy('http', $args{proxy});
} else {
    if (!defined($args{noproxy})) {

        # Use HTTP_PROXY environment variable
        $ua->env_proxy;
    }
}
my $url =
    $ciMasterUrl
  . COMPUTER_SUFFIX
  . API_SUFFIX
  . '?tree=computer[displayName,executors[idle],idle,offline,offlineCause[description],temporarilyOffline]';
my $req = HTTP::Request->new(GET => $url);
trace("Get ", $url, " ...\n");
my $res = $ua->request($req);
if (!$res->is_success) {
    print("UNKNOWN: can't get ", $url, " ($res->{status_line})\n");
    exit UNKNOWN;
}
my $json    = new JSON;
my $content = {};
eval {
    $content = $json->decode($res->content);
    1;
  }
  or do {
    $@ =~ s/\n//m;
    print("UNKNOWN: can't parse JSON content (error $@) from master api: ",
        $url, "\n");
    return UNKNOWN;
  };
my $computers = $content->{'computer'};    # ref to array of slaves
$total_computers_count = scalar(@$computers);
trace("Got $total_computers_count slaves\n");
if ($total_computers_count == 0) {
    print("OK: No slave\n");
    exit OK;
}
$status = OK;

# Loop on each slave
for (my $i = 0; $i < $total_computers_count; $i++) {
    if (   $slaveName eq '(All)'
        || $computers->[$i]->{'displayName'} eq $slaveName) {
        my ($stat, $line) = (test_slave(%{$computers->[$i]}));

        # Save greatest value of status
        if ($stat > $status) {
            $status      = $stat;
            $status_line = $line;
        }
    }
}

# Retrieve old cached slaves status
my $old_slaves_status;
if ($compare) {
    $old_slaves_status = read_slaves_status();

    #$dumper->dumpValue($old_slaves_status);
}

# Save current slaves status
save_slaves_status(%slaves_status);

# Make $_warn and $_crit to represent the the absolute lower bundary of online
# slaves (regarding $warn and $crit %)
my $_warn = 0;
if ($warn != -1) {
    $_warn = (100 - $warn) * $total_computers_count / 100;
}
my $_crit = 0;
if ($crit != -1) {
    $_crit = (100 - $crit) * $total_computers_count / 100;
}

# Make $_ewarn and $_ecrit to represent the the absolute upper bundary of
# running executors (regarding $ewarn and $ecrit %)
my $_ewarn = $total_executors_count;
if ($ewarn != -1) {
    $_ewarn = $ewarn * $total_executors_count / 100;
}
my $_ecrit = $total_executors_count;
if ($ecrit != -1) {
    $_ecrit = $ecrit * $total_executors_count / 100;
}

# Compute performance data
my $active_slaves = $total_computers_count - $total_offline_count;
if (!defined $args{'noperfdata'}) {
    $perfdata =
        "|slaves=$active_slaves;$_warn;$_crit;$total_computers_count"
      . " executors=$total_running_ex;$_ewarn;$_ecrit;$total_executors_count";
} else {
    $perfdata = '';
}

# Check slaves status compared to previous ones (if any)
if (defined $old_slaves_status && scalar(keys(%{$old_slaves_status})) > 0) {
    trace("Processing old slaves status\n");
    foreach my $name (keys(%slaves_status)) {
        if (exists $old_slaves_status->{$name}) {
            if ("$old_slaves_status->{$name}" ne "$slaves_status{$name}") {
                if ("$slaves_status{$name}" eq 'offline') {
                    trace("$name: turned offline\n");
                    $status_line_ex .= "$name: turned offline\n";
                    $status      = CRITICAL;
                    $status_line = "CRITICAL: Slave $name: turned offline";
                } else {
                    trace("$name: turned online\n");
                    $status_line_ex .= "$name: turned online\n";
                    if ($status != CRITICAL) {
                        $status      = WARNING;
                        $status_line = "WARNING: Slave $name turned online";
                    }
                }
            } else {

                # Unchanged status
                trace("$name: unchanged $slaves_status{$name} status\n");
            }
            delete $old_slaves_status->{$name};
        } else {

            # New slave
            trace("$name: new $slaves_status{$name} slave\n");
            $status_line_ex .= "$name: new $slaves_status{$name} slave\n";
            if ($status != CRITICAL) {
                $status      = WARNING;
                $status_line =
                  "WARNING: New $name slave ($slaves_status{$name})";
            }
        }
    }
    foreach my $name (keys(%{$old_slaves_status})) {

        # Old slave
        trace("$name: removed slave\n");
        $status_line_ex .= "$name: removed slave\n";
        if ($status != CRITICAL) {
            $status      = WARNING;
            $status_line = "WARNING: Slave $name removed";
        }
    }
}

# Check thresholds
if ($status == OK) {

    # Check CRITICAL threshold of offline slaves
    if ($crit != -1
        && (($total_offline_count * 100) / $total_computers_count) > $crit) {
        $status_line =
          "CRITICAL: $total_offline_count slaves offline / $total_computers_count > $crit\%";
        $status = CRITICAL;
    }

    # Check WARNING threshold of offline slaves
    elsif ($warn != -1
        && (($total_offline_count * 100) / $total_computers_count) > $warn) {
        $status_line =
          "WARNING: $total_offline_count slaves offline / $total_computers_count > $warn\%";
        $status = WARNING;
    }

    # Check CRITICAL threshold of total used executors
    elsif ($ecrit != -1
        && $total_executors_count > 0
        && ($total_running_ex * 100 / $total_executors_count) >= $ecrit) {
        $status_line =
          "CRITICAL: $total_running_ex / $total_executors_count running executors >= $ecrit\%";
        $status = CRITICAL;
    }

    # Check WARNING threshold of total used executors
    elsif ($ewarn != -1
        && $total_executors_count > 0
        && ($total_running_ex * 100 / $total_executors_count) >= $ewarn) {
        $status_line =
          "WARNING: $total_running_ex / $total_executors_count running executors >= $ewarn\%";
        $status = WARNING;
    }

    # All is OK
    else {
        $status_line =
          "OK: $active_slaves online slaves (over $total_computers_count slaves)";
    }
}

# Print output status
print($status_line , $perfdata, "\n", $status_line_ex);
exit $status;

# Functions

sub test_slave(\%) {
    my $slave     = shift;
    my $info_line = '';
    if (!defined($slave) || ref($slave) ne 'HASH') {
        trace("test_slave: No slave\n");
        return (UNKNOWN, 'test_slave: internal error');
    }
    my $slave_name = $slave->{'displayName'};
    my $executors  = $slave->{'executors'};
    $info_line = "$slave_name";
    my $executors_count = 0;
    my $running_ex      = 0;
    if (defined $executors) {
        $executors_count = scalar(@$executors);
        $total_executors_count += $executors_count;
        for (my $i = 0; $i < $executors_count; $i++) {
            next if $executors->[$i]->{'idle'};
            $running_ex++;
            $total_running_ex++;
        }
    }
    $info_line .= ", $running_ex/$executors_count executors";
    if ($slave->{'offline'}) {
        $info_line .= ", <b>OFFLINE</b>";
        $total_offline_count++;
        $slaves_status{$slave_name} = 'offline';
    } else {
        $slaves_status{$slave_name} = 'online';
        if (!$slave->{'idle'}) {
            $info_line .= ", working";
        }
    }
    if ($slave->{'temporarilyOffline'}) {
        $info_line .= ", temp offline";
    }
    if (defined($slave->{'offlineCause'})) {
        $info_line .= " cause: $slave->{'offlineCause'}->{'description'}";
    }
    $info_line .= "\n";
    trace($info_line);
    $status_line_ex .= $info_line;
    if (   $ecrit != -1
        && $executors_count > 0
        && ($running_ex * 100 / $executors_count) >= $ecrit) {
        return (CRITICAL,
            "CRITICAL: slave $slave_name has $running_ex / $executors_count running executors >= $ecrit\%"
        );
    }
    if (   $ewarn != -1
        && $executors_count > 0
        && ($running_ex * 100 / $executors_count) >= $ewarn) {
        return (WARNING,
            "WARNING: slave $slave_name has $running_ex / $executors_count running executors >= $ewarn\%"
        );
    }
    return (OK, '');
}

sub read_slaves_status() {
    trace("read_slaves_status: from file $persitency_file\n");
    my $ref_hash = {};
    my $fh;
    if (!open($fh, '<:encoding(UTF-8)', $persitency_file)) {
        trace("Can't open file $persitency_file\n");
        return $ref_hash;
    }
    while (<$fh>) {
        chomp;
        next if /^#/;
        next if /^$/;
        my ($key, $val) = split(/=/);
        $ref_hash->{$key} = $val;

        #trace(" >> $key=$val\n");
    }
    close($fh);
    return $ref_hash;
}

sub save_slaves_status(\%) {
    my $slaves = shift;
    trace("save_slaves_status: to file $persitency_file\n");
    my $fh;
    if (!open($fh, '>:encoding(UTF-8)', $persitency_file)) {
        trace("Can't write file $persitency_file\n");
        return;
    }
    foreach my $name (keys(%{$slaves})) {
        print $fh $name, "=", $slaves->{$name}, "\n";

        #trace (" << $name=$slaves->{$name}\n");
    }
    close($fh);
}

sub trace(@) {
    if ($debug) {
        print @_;
    }
}
__END__

=head1 NAME

check_jenkins_slaves - A Nagios plugin that check the status of the slaves of a Jenkins instance.

=head1 SYNOPSIS

check_jenkins_slaves.pl --version

check_jenkins_slaves.pl --help

check_jenkins_slaves.pl --man

check_jenkins_slaves.pl [options] <jenkins-url>

    Options:
      -d --debug                   turns on debug traces
      -t --timeout=<timeout>       the timeout in seconds to wait for the
                                   request (default 10)
         --proxy=<url>             the http proxy url (default from
                                   HTTP_PROXY env)
         --noproxy                 do not use HTTP_PROXY env
         --noperfdata              do not output perdata
      -s --statefull               turns on statefull (check difference with old states)
      -w --warning=<percent>       the percentage of offline slaves for the WARNING threshold
      -c --critical=<percent>      the percentage of offline slaves for the CRITICAL threshold
         --executorWarn=<percent>  the percentage of used executors for the WARNING threshold
         --executorCrit=<percent>  the percentage of used executors for the CRITICAL threshold
      -n --slave-name=<slave-name> the name of the slave to monitor (default all slaves)

       
=head1 OPTIONS

=over 8

=item B<--help>

    Print a brief help message and exits.

=item B<--version>

    Prints the version of this tool and exits.

=item B<--man>

    Prints manual and exits.

=item B<-d> B<--debug>

    Turns on debug traces

=item B<-t> B<--timeout=>timeout

    The timeout in seconds to wait for the request (default 30)
    
=item B<--proxy=>url

    The http proxy url (default from HTTP_PROXY env)

=item B<--noproxy>

    Do not use HTTP_PROXY env

=item B<--noperfdata>

    Do not output perdata
    
=item B<-s> B<--statefull>

    Turns on statefull behaviour. The status of each slave is persisted
    between calls and compared with new status. CRITICAL is raised when a slave
    turns from online to offline whereas WARNING is raised when a slave turns
    from offline to online, epear or disapear.

=item B<-w> B<--warning=>percent

    The percentage of offline slaves for the WARNING threshold

=item B<-c> B<--critical=>percent

    The percentage of offline slaves for the CRITICAL threshold
    
=item B<executorWarn=>percent

    The percentage of used executors for the WARNING threshold

=item B<executorCrit=>percent

    The percentage of used executors for the CRITICAL threshold
    
=item B<-n> B<--slave-name=>slave-name

    The name of the slave to monitor (default all slaves)

=back

=head1 DESCRIPTION

B<check_jenkins_slaves.pl> is a Nagios plugin check the status (online/offline)
of the slaves of a Jenkins instance.
You can specify one critical and/or one warning threshold express in % of the
ratio of offline slaves.
You can also specify warning/critical thresolds in % for the used executors
ratio (per slave and globally)
You can choose to monitor state changes (with option --statefull) and be
alerted when any slave has a status changed regarding previous call of this
plugin.
You can select a given slave with -n <slave-name> option or check all slaves
defined on the master Jenkins specified by its url.
    
=cut
