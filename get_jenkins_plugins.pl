#!/usr/bin/perl 

#
# Get Jenkins plugins
#
# Author: Eric Blanchard
#
# Usage: get_jenkins_plugins.pl [options] jenkins-url [jenkins-url ...]
#

use strict;
use LWP::UserAgent;
use JSON;
use Getopt::Long qw(GetOptions HelpMessage VersionMessage :config no_ignore_case bundling);
use Pod::Usage;


use constant PLUGINS_URL => "/pluginManager";
use constant API_SUFFIX => "/api/json";

our $VERSION = '1.0';
my $debug = 0;
my $timeout = 30;
my $sep = ',';

my %args;
GetOptions(\%args,
           'version|v' => sub { VersionMessage({'-exitval' => 1}) },
           'help|h' => sub { HelpMessage({'-exitval' => 1}) },
           'man' => sub { pod2usage({'-verbose' => 2, '-exitval' => 1}) },
           'debug|d' => \$debug,
           'timeout|t=i' => \$timeout,
           'proxy=s',
           'noproxy',
           'separator|s=s' => \$sep) or pod2usage({'-exitval' => 1});

HelpMessage({'-msg' => 'Missing Jenkins url parameter', '-exitval' => 1}) if scalar(@ARGV) < 1;

my $ua = LWP::UserAgent->new();
$ua->timeout($timeout);
if (defined($args{proxy})) {
    $ua->proxy('http', $args{proxy});
} else {
    if (! defined($args{noproxy})) {
        # Use HTTP_PROXY environment variable
        $ua->env_proxy;
    }
}

my @hosts;
my @urls;
my @instances;
my @versions;
my %plugins_tab;
my $serv_idx = -1;
foreach my $url (@ARGV) {
    $serv_idx++;
    chomp($url);
    $url =~ s/\/$//;
    my($host) = ($url =~ m!^https?://(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\w+)!);
    my($path) = ($url =~ m!^https?://.*/([\w-_]+)$!);
    $urls[$serv_idx] = $url;
    $hosts[$serv_idx] = $host;
    $instances[$serv_idx] = $path;
    my $req = HTTP::Request->new(HEAD => $url . '/');
    trace("HEAD $url/ ...\n");
    my $res = $ua->request($req);
    if (!$res->is_success) {
        trace("can't get $url/ ($res->{status_line})");
        next;
    }
    #trace("headers:\n", $res->headers->as_string(), "\n");
    my $jenkins_version = $res->headers->header('X-Jenkins');
    if (! defined($jenkins_version) || $jenkins_version == '') {
        $jenkins_version = $res->headers->header('X-Hudson');
        if (! defined($jenkins_version) || $jenkins_version == '') {
            trace("Can't find X-Jenkins header in HTTP response\n");
            next;
        }
    }
    $versions[$serv_idx] = $jenkins_version;
    if ($jenkins_version < '1.466') {
        trace("version is less than 1.466, Can't get plugin kist from API\n");
        next;
    }
    # Get PluginManager API
    $req = HTTP::Request->new(GET => $url . PLUGINS_URL . API_SUFFIX . "?depth=1");
    trace("GET $url" . PLUGINS_URL . API_SUFFIX . "?depth=1 ...\n");
    my $res = $ua->request($req);
    if (!$res->is_success) {
        trace("can't get ", $url . PLUGINS_URL . API_SUFFIX, "?depth=1 ($res->{status_line})\n");
        next;
    }
    my $json = new JSON;
    my $obj = {};
    eval {
        $obj = $json->decode($res->content);
        1;
    } or do {
        $@ =~ s/\n//m;
        trace ("can't parse JSON content (error $@) from url: ", $url . PLUGINS_URL . API_SUFFIX, "\n");
        next;
    };
    my $plugins = $obj->{'plugins'}; # ref to array
    trace ("Found " . scalar(@$plugins) . " plugins\n");
    my $require_update_count = 0;
    foreach my $plugin (@$plugins) {
        trace("plugin=$plugin->{'longName'}, version=$plugin->{'version'}");
        my $plug_version = $plugin->{'version'};
        if ($plugin->{'enabled'} && $plugin->{'active'}) {
            if ($plugin->{'hasUpdate'}) {
                $plug_version .= ' +';
            }
        }
        $plugins_tab{$plugin->{'longName'}}[$serv_idx] = $plug_version;
    }
}

print("url,", join($sep, @urls), "\n");
print("host,", join($sep, @hosts), "\n");
print("instance,", join($sep, @instances), "\n");
print("version,", join($sep, @versions), "\n");
for (my $i = 0; $i < scalar(@hosts); $i++) {
    print($sep);
}
print("\n");
foreach my $name ( sort keys %plugins_tab ) {
     print($name, $sep, join($sep, @{$plugins_tab{$name}}), "\n");
}

exit 0;


sub trace {
    if ($debug) {
        print @_;
    }
}

__END__

=head1 NAME

get_jenkins_plugins - A simple scripts that export a CSV listing of Jenkins plugins/versions of a set of Jenkins instances

=head1 SYNOPSIS

get_jenkins_plugins.pl --version

get_jenkins_plugins.pl --help

get_jenkins_plugins.pl --man

get_jenkins_plugins [options] <jenkins-url> [<jenkins-url> [...]]

    Options:
      -d --debug               turns on debug traces
      -t --timeout=<timeout>   the timeout in seconds to wait for the
                               request (default 30)
         --proxy=<url>         the http proxy url (default from
                               HTTP_PROXY env)
         --noproxy             do not use HTTP_PROXY env
      -s --separator=<char>    the delimiter for CSV output (default ',')
       
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

=item B<-s> B<--separator=>char

    The delimiter char for the CSV output (default ',')
    
=back

=head1 DESCRIPTION

B<get_jenkins_plugins.pl> A simple scripts that export a CSV listing of Jenkins plugins/versions of a set og Jenkins intsantces.
The 4 first lines contain the B<url>, B<host>, B<instance> and B<version> of the specified Jenkins instances.
Then comes an empty line and finally the list of plugins name (sorted alphabetically) with their version number.
A 'B<+>' sign is added to plugins versions that have a possible update.
    
=cut
