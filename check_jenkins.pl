#!/usr/bin/perl
#
# This Nagios plugin count the number of jobs of a Jenkins instance.
# It can check that the total number of jobs will not exeed the WARNING and CRITICAL thresholds.
# It also count the number of disabled, passed, running and failed jobs and can check that the ratio
# of failed jobs against active jobs is over a WARNING and CRITICAL thresholds.
# Performance data are:
# jobs=<count>;<warn>;<crit> passed=<count> failed=<count>;<warn>;<crit> disabled=<count> running=<count>
#
# Author: Eric Blanchard
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
use constant API_SUFFIX => "/api/json";
our $VERSION = '1.7';
my %args;
my $ciMasterUrl;
my $jobs_warn   = -1;
my $jobs_crit   = -1;
my $fail_warn   = 100;
my $fail_crit   = 100;
my $debug       = 0;
my $status_line = '';
my $exit_code   = UNKNOWN;
my $timeout     = 10;

# Functions prototypes
sub trace(@);

# Main
GetOptions(
    \%args,
    'version|v' => sub { VersionMessage( { '-exitval' => UNKNOWN } ) },
    'help|h'    => sub { HelpMessage(    { '-exitval' => UNKNOWN } ) },
    'man' => sub { pod2usage( { '-verbose' => 2, '-exitval' => UNKNOWN } ) },
    'debug|d'     => \$debug,
    'timeout|t=i' => \$timeout,
    'proxy=s',
    'noproxy',
    'noperfdata',
    'warning|w=i'  => \$jobs_warn,
    'critical|c=i' => \$jobs_crit,
    'failedwarn=i' => \$fail_warn,
    'failedcrit=i' => \$fail_crit
  )
  or pod2usage( { '-exitval' => UNKNOWN } );
HelpMessage(
    { '-msg' => 'Missing Jenkins url parameter', '-exitval' => UNKNOWN } )
  if scalar(@ARGV) != 1;
$ciMasterUrl = $ARGV[0];
$ciMasterUrl =~ s/\/$//;

# Master API request
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
my $url = $ciMasterUrl . API_SUFFIX . '?tree=jobs[color,name]';
my $req = HTTP::Request->new( GET => $url );
trace("GET $url ...\n");
my $res = $ua->request($req);
if ( !$res->is_success ) {
    print "Failed retrieving $url ($res->{status_line})";
    exit UNKNOWN;
}
my $json       = new JSON;
my $obj        = $json->decode( $res->content );
my $jobs       = $obj->{'jobs'};                   # ref to array
my $jobs_count = scalar(@$jobs);
trace( "Found " . $jobs_count . " jobs\n" );
my $disabled_jobs = 0;
my $failed_jobs   = 0;
my $passed_jobs   = 0;
my $running_jobs  = 0;

foreach my $job (@$jobs) {
    trace( 'job: ', $job->{'name'}, ' color=', $job->{'color'}, "\n" );
    $disabled_jobs++ if $job->{'color'} eq 'disabled';
    $passed_jobs++   if $job->{'color'} eq 'blue';
    $failed_jobs++   if $job->{'color'} eq 'red';
}
my $arctive_jobs = $jobs_count - $disabled_jobs;
my $perfdata     = '';
if ( !defined( $args{noperfdata} ) ) {
    $perfdata = 'jobs='
      . $jobs_count . ';'
      . ( $jobs_warn == -1 ? '' : $jobs_warn ) . ';'
      . ( $jobs_crit == -1 ? '' : $jobs_crit );
    $perfdata .= ' passed=' . $passed_jobs;
    $perfdata .=
      ' failed=' . $failed_jobs . ';' . $fail_warn . ';' . $fail_crit;
    $perfdata .= ' disabled=' . $disabled_jobs;
    $perfdata .= ' running=' . ( $arctive_jobs - $passed_jobs - $failed_jobs );
}
if ( $jobs_crit != -1 && $jobs_count > $jobs_crit ) {
    print "CRITICAL: jobs count: ", $jobs_count, " exeeds critical threshold: ",
      $jobs_crit, "\n";
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit CRITICAL;
}
if ( $jobs_warn != -1 && $jobs_count > $jobs_warn ) {
    print "WARNING: jobs count: ", $jobs_count, " exeeds warning threshold: ",
      $jobs_warn, "\n";
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit WARNING;
}
my $failed_ratio = $failed_jobs * 100 / $arctive_jobs;
if ( $failed_ratio > $fail_crit ) {
    print(
        "CRITICAL: jobs count: ",
        $jobs_count, " Failed jobs ratio: ",
        $failed_ratio, '%'
    );
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit CRITICAL;
}
if ( $failed_ratio > $fail_warn ) {
    print(
        "WARNING: jobs count: ",
        $jobs_count, " Failed jobs ratio: ",
        $failed_ratio, '%'
    );
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit WARNING;
}
print( 'OK: jobs count: ', $jobs_count );
if ( !defined( $args{noperfdata} ) ) {
    print( '|', $perfdata, "\n" );
}
exit OK;

sub trace(@) {
    if ($debug) {
        print @_;
    }
}
__END__

=head1 NAME

check_jenkins - A Nagios plugin that count the number of jobs of a Jenkins instance (throuh HTTP request)

=head1 SYNOPSIS


check_jenkins.pl --version

check_jenkins.pl --help

check_jenkins.pl --man

check_jenkins.pl [options] <jenkins-url>

    Options:
      -d --debug               turns on debug traces
      -t --timeout=<timeout>   the timeout in seconds to wait for the
                               request (default 30)
         --proxy=<url>         the http proxy url (default from
                               HTTP_PROXY env)
         --noproxy             do not use HTTP_PROXY env
         --noperfdata          do not output perdata
      -w --warning=<count>     the maximum total jobs count for WARNING threshold
      -c --critical=<count>    the maximum total jobs count for CRITICAL threshold
         --failedwarn=<%>      the maximum ratio of failed jobs per enabled
                               jobs for WARNING threshold
         --failedcrit=<%>      the maximum ratio of failed jobs per enabled
                               jobs for CRITICAL threshold
       
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

=item B<-w> B<--warning=>count

    The maximum total jobs count for WARNING threshold

=item B<-c> B<--critical=>count

    The maximum total jobs count for CRITICAL threshold
    
=item B<--failedwarn=>%

    The maximum ratio of failed jobs per enabled jobs for WARNING threshold
    
=item B<--failedcrit=>%

    The maximum ratio of failed jobs per enabled jobs for CRITICAL threshold
    
=back

=head1 DESCRIPTION

B<check_jenkins.pl> is a Nagios plugin that count the number of jobs of a Jenkins instance.
It can check that the total number of jobs will not exeed the WARNING and CRITICAL thresholds. It also count the number of disabled, passed, running and failed jobs and can check that the ratio of failed jobs against active jobs is over a WARNING and CRITICAL thresholds.
    
    
=cut
