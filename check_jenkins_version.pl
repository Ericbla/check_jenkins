#!/usr/bin/perl 
#
# Check Jenkins version
#
# Author: Eric Blanchard
#
# Usage: check_jenkins_version -I <address> [-p <port>] [-u <url>] [-t <timeout>] [-w <min-version>] [-c <min-version>]
#
# This Nagios plugin check the version number of a Jenkins instance (throuh HTTP request)
#
use strict;
use LWP::UserAgent;
use JSON;
use Getopt::Long
  qw(GetOptions HelpMessage VersionMessage :config no_ignore_case bundling);
use Pod::Usage qw(pod2usage);

# Nagios return values
use constant {
    OK       => 0,
    WARNING  => 1,
    CRITICAL => 2,
    UNKNOWN  => 3,
};
use constant PLUGINS_URL => "/pluginManager";
use constant API_SUFFIX  => "/api/json";
our $VERSION = '1.3';
my $debug       = 0;
my $warn_vers   = -1;
my $crit_vers   = -1;
my $status_line = '';
my $exit_code   = UNKNOWN;
my $timeout     = 10;
my %args;

# Functions prototypes
sub trace(@);

GetOptions(
    \%args,
    'version|v' => sub { VersionMessage( { '-exitval' => UNKNOWN } ) },
    'help|h'    => sub { HelpMessage(    { '-exitval' => UNKNOWN } ) },
    'man' => sub { pod2usage( { '-verbose' => 2, '-exitval' => UNKNOWN } ) },
    'debug|d'     => \$debug,
    'timeout|t=i' => \$timeout,
    'proxy=s',
    'noproxy',
    'warning|w=s'  => \$warn_vers,
    'critical|c=s' => \$crit_vers
  )
  or pod2usage( { '-exitval' => UNKNOWN } );
HelpMessage(
    { '-msg' => 'Missing Jenkins url parameter', '-exitval' => UNKNOWN } )
  if scalar(@ARGV) != 1;
my $ciMasterUrl = $ARGV[0];
$ciMasterUrl =~ s/\/$//;
my $ua = LWP::UserAgent->new();
$ua->timeout($timeout);

if ( defined( $args{proxy} ) ) {
    $ua->proxy( 'http', $args{proxy} );
}
else {
    if ( !defined( $args{noproxy} ) ) {

        # Use HTTP_PROXY environment variable
        $ua->env_proxy;
    }
}
my $req = HTTP::Request->new( HEAD => $ciMasterUrl . '/' );
trace("HEAD $ciMasterUrl/ ...\n");
my $res = $ua->request($req);
if ( !$res->is_success ) {
    print("UNKNOWN: can't get $ciMasterUrl/ ($res->{status_line})");
    exit UNKNOWN;
}
trace( "headers:\n", $res->headers->as_string(), "\n" );
my $jenkins_version = $res->headers->header('X-Jenkins');
if ( !defined($jenkins_version) || $jenkins_version == '' ) {
    $jenkins_version = $res->headers->header('X-Hudson');
    if ( !defined($jenkins_version) || $jenkins_version == '' ) {
        print("UNKNOWN: Can't find x-Jenkins header in HTTP response\n");
        exit UNKNOWN;
    }
}
$exit_code   = OK;
$status_line = "OK: Jenkins version: $jenkins_version\n";
my $status_line_ext = '';
if ( $jenkins_version < $crit_vers ) {
    $status_line =
      "CRITICAL: Jenkins version: $jenkins_version < crit: $crit_vers\n";
    $exit_code = CRITICAL;
}
if ( $jenkins_version < $warn_vers ) {
    $status_line =
      "WARNING: Jenkins version: $jenkins_version < warn: $warn_vers\n";
    $exit_code = WARNING;
}
if ( $jenkins_version >= '1.466' ) {

    # Get PluginManager API
    my $url =
        $ciMasterUrl
      . PLUGINS_URL
      . API_SUFFIX
      . '?tree=plugins[active,enabled,hasUpdate,longName,version]';
    $req = HTTP::Request->new( GET => $url );
    trace("GET $url \n");
    my $res = $ua->request($req);
    if ( !$res->is_success ) {
        print("UNKNOWN: can't get $url ($res->{status_line})");
        exit UNKNOWN;
    }
    my $json    = new JSON;
    my $obj     = $json->decode( $res->content );
    my $plugins = $obj->{'plugins'};                # ref to array
    trace( "Found " . scalar(@$plugins) . " plugins\n" );
    my $require_update_count = 0;
    foreach my $plugin (@$plugins) {
        trace("plugin=$plugin->{'longName'}, version=$plugin->{'version'}");
        if ( $plugin->{'enabled'} && $plugin->{'active'} ) {
            if ( $plugin->{'hasUpdate'} ) {
                trace(" ==> NEEDS UPDATE");
                $status_line_ext .=
                  "$plugin->{'longName'}, v=$plugin->{'version'}\n";
                $require_update_count++;
            }
        }
        trace("\n");
    }
    $status_line .= " "
      . scalar(@$plugins)
      . " plugins installed ($require_update_count need update)\n";
}
print($status_line);
print($status_line_ext);
exit $exit_code;

sub trace (@){
    if ($debug) {
        print @_;
    }
}
__END__

=head1 NAME

check_jenkins_version - A Nagios plugin that check the version number of a Jenkins instance (throuh HTTP request)

=head1 SYNOPSIS

check_jenkins_version.pl --version

check_jenkins_version.pl --help

check_jenkins_version.pl --man

check_jenkins_version.pl [options] <jenkins-url>

    Options:
      -d --debug               turns on debug traces
      -t --timeout=<timeout>   the timeout in seconds to wait for the
                               request (default 10)
         --proxy=<url>         the http proxy url (default from
                               HTTP_PROXY env)
         --noproxy             do not use HTTP_PROXY env
      -w --warning=<version>   the minimum version for WARNING threshold
      -c --critical=<version>  the minimum version for CRITICAL threshold
       
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

    The timeout in seconds to wait for the request (default 10)
    
=item B<--proxy=>url

    The http proxy url (default from HTTP_PROXY env)

=item B<--noproxy>

    Do not use HTTP_PROXY env

=item B<-w> B<--warning=>version

    The minimum version for WARNING threshold

=item B<-c> B<--critical=>version

    The minimum version for CRITICAL threshold
    
=back

=head1 DESCRIPTION

B<check_jenkins_version.pl> is a Nagios plugin that check the version number of a Jenkins instance.
With jenkins version B<1.466> and above, it also check if some plugins need to be updated.

=cut
