#!/usr/bin/perl
#
# Check Jenkins job build time using the JSON API
#
# Author: Eric Blanchard
#
#
# This Nagios plugin check that running Jenkins jobs are not taking unusual time to complete.
# You can specify one critical and/or one warning threshold express in % of the expected
# building time (estimated by Jenkins with statistics on past builds).
# You can select a given job with -j <job-name> option or check all jobs defined on the master Jenkins
# specified by its url.
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
our $VERSION = '1.5';
my %args;
my $ciMasterUrl;
my $jobName = '(All)';
my $warn    = -1;
my $crit    = -1;
my $awarn   = -1;
my $acrit   = -1;
my $status  = UNKNOWN;
my $debug   = 0;
my $timeout = 10;

# Functions prototypes
sub test_job(\%);
sub print_duration($);
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
    'warning|w=i'    => \$warn,
    'critical|c=i'   => \$crit,
    'absoluteWarn=i' => \$awarn,
    'absoluteCrit=i' => \$acrit,
    'job|j=s'        => \$jobName
  )
  or pod2usage( { '-exitval' => UNKNOWN } );
HelpMessage(
    { '-msg' => 'Missing Jenkins url parameter', '-exitval' => UNKNOWN } )
  if scalar(@ARGV) != 1;
$ciMasterUrl = $ARGV[0];
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
my $url =
    $ciMasterUrl
  . API_SUFFIX
  . '?tree=jobs[name,url,buildable,lastBuild[number,building,timestamp,estimatedDuration]]';
my $req = HTTP::Request->new( GET => $url );
trace( "Get ", $url, " ...\n" );
my $res = $ua->request($req);
if ( !$res->is_success ) {
    print( "UNKNOWN: can't get ", $url, " ($res->{status_line})\n" );
    exit UNKNOWN;
}
my $json    = new JSON;
my $content = {};
eval {
    $content = $json->decode( $res->content );
    1;
  }
  or do {
    $@ =~ s/\n//m;
    print( "UNKNOWN: can't parse JSON content (error $@) from master api: ",
        $url, "\n" );
    return UNKNOWN;
  };
my $jobs       = $content->{'jobs'};    # ref to array
my $jobs_count = scalar(@$jobs);
trace( "Got ", $jobs_count, " jobs\n" );
if ( $jobs_count == 0 ) {
    print("OK: job: All (No Job)\n");
    exit OK;
}
for ( my $i = 0 ; $i < $jobs_count ; $i++ ) {
    if ( $jobName eq '(All)' || $jobs->[$i]->{'name'} eq $jobName ) {
        $status = test_job( %{ $jobs->[$i] } );
    }
    last if ( $status != OK && !$debug );
}
if ( $status == OK ) {
    print( "OK: job: ", $jobName, "\n" );
}
exit $status;

sub test_job(\%) {
    my $job = shift;
    if ( !defined($job) || ref($job) ne 'HASH' ) {
        trace("test_job: No job\n");
    }
    my $job_name = $job->{'name'};
    my $job_url  = $job->{'url'};
    trace( "Job: ", $job_name );
    if ( !$job->{'buildable'} ) {

        # Disabled job
        trace(", disabled \n");
        return OK;
    }
    if ( !defined( $job->{'lastBuild'} ) ) {

        # No build for this job
        trace(", no available build\n");
        return OK;
    }
    my $build_number = $job->{'lastBuild'}->{'number'};
    if ( !$job->{'lastBuild'}->{'building'} ) {

        # This build is not currently running
        trace( ", build number=", $build_number, " is not running \n" );
        return OK;
    }
    my $stamp          = $job->{'lastBuild'}->{'timestamp'};
    my $current_stamp  = time() * 1000;                        # in ms
    my $duration       = $current_stamp - $stamp;
    my $usual_duration = 1000 * 60 * 30;                       # 30 minutes
    if ( defined( $job->{'lastBuild'}->{'estimatedDuration'} )
        && $job->{'lastBuild'}->{'estimatedDuration'} > 0 )
    {
        $usual_duration = $job->{'lastBuild'}->{'estimatedDuration'};
    }
    trace( ", duration=", $duration, ", usual duration=",
        $usual_duration, "\n" );
    if (   $crit != -1
        && $duration > $usual_duration + ( $usual_duration * $crit / 100 ) )
    {
        print(
            'CRITICAL: job: <a href="',      $job_url,
            '">',                            $job_name,
            '</a>, build=',                  $build_number,
            ', duration=',                   print_duration($duration),
            ' exeeds critical threshold =(', $crit,
            '%) of usual duration=',         print_duration($usual_duration),
            "\n"
        );
        return CRITICAL;
    }
    if ( $acrit != -1 && $duration > $acrit * 60 * 1000 ) {
        print(
            'CRITICAL: job: <a href="',
            $job_url,
            '">',
            $job_name,
            '</a>, build=',
            $build_number,
            ', duration=',
            print_duration($duration),
            ' exeeds critical absolute threshold =(',
            $acrit,
            'm)',
            "\n"
        );
        return CRITICAL;
    }
    if (   $warn != -1
        && $duration > $usual_duration + ( $usual_duration * $warn / 100 ) )
    {
        print(
            'WARNING: job: <a href="',      $job_url,
            '">',                           $job_name,
            '</a>, build=',                 $build_number,
            ', duration=',                  print_duration($duration),
            ' exeeds warning threshold =(', $warn,
            '%) of usual duration=',        print_duration($usual_duration),
            "\n"
        );
        return WARNING;
    }
    if ( $awarn != -1 && $duration > $awarn * 60 * 1000 ) {
        print(
            'WARNING: job: <a href="',
            $job_url,
            '">',
            $job_name,
            '</a>, build=',
            $build_number,
            ', duration=',
            print_duration($duration),
            ' exeeds warning absolute threshold =(',
            $awarn,
            'm)',
            "\n"
        );
        return WARNING;
    }
    return OK;
}

sub print_duration($) {
    my $duration = shift;
    return 'NaN' if !defined($duration);
    $duration /= 1000;    # in sec
    if ( $duration < 60 ) {
        return sprintf( '%ds', $duration );
    }
    if ( $duration < 3600 ) {
        return sprintf( '%.1fm', $duration / 60 );
    }
    return sprintf( '%.1fh', $duration / 3600 );
}

sub trace(@) {
    if ($debug) {
        print @_;
    }
}
__END__

=head1 NAME

check_jenkins_job_time - A Nagios plugin that check that Jenkin job(s) has no unusual duration

=head1 SYNOPSIS

check_jenkins_job_time.pl --version

check_jenkins_job_time.pl --help

check_jenkins_job_time.pl --man

check_jenkins_job_time.pl [options] <jenkins-url>

    Options:
      -d --debug               turns on debug traces
      -t --timeout=<timeout>   the timeout in seconds to wait for the
                               request (default 30)
         --proxy=<url>         the http proxy url (default from
                               HTTP_PROXY env)
         --noproxy             do not use HTTP_PROXY env
         --noperfdata          do not output perdata
      -w --warning=<percent>   the percentage of usual duration for the WARNING threshold
      -c --critical=<percent>  the percentage of usual duration for the CRITICAL threshold
         --absoluteWarn=<minutes> the duration in minutes for the WARNING threshold
         --absoluteCrit=<minutes> the duration in minutes for the CRITICAL threshold
      -j --job=<job-name>      the name of the job to monitor (default all jobs)

       
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

=item B<-w> B<--warning=>percent

    The percentage of usual duration for the WARNING threshold

=item B<-c> B<--critical=>percent

    The percentage of usual duration for the CRITICAL threshold
    
=item B<--absoluteWarn=>minutes

    The duration in minutes for the WARNING threshold

=item B<--absoluteCrit=>minutes

    The duration in minutes for the CRITICAL threshold
    
=item B<-j> B<--job=>job-name

    The name of the job to monitor (default all jobs)

=back

=head1 DESCRIPTION

B<check_jenkins_job_time.pl> is a Nagios plugin check that running Jenkins jobs
are not taking unusual time to complete.
You can specify one critical and/or one warning threshold expressed in % of the
expected building time (estimated by Jenkins with statistics on past builds)
or expressed in absolute minutes.
You can select a given job with -j <job-name> option or check all jobs defined
on the master Jenkins specified by its url.
    
=cut
