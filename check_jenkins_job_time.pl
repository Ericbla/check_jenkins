#!/usr/bin/perl

#
# Check Jenkins job build time using the JSON API
#
# Author: Eric Blanchard
# Derivated from the work of Jon Cowie on the check_jenkins_job_extended plugin
#
# Usage: check_jenkins [-h][-d][-w percent] [-c percent] [-j job] url 
#
# This Nagios plugin check that running Jenkins jobs are not taking unusual time to complete.
# You can specify one critical and/or one warning threshold express in % of the expected
# building time (estimated by Jenkins with statistics on past builds).
# You can select a given job with -j <job-name> option or check all jobs defined on the master Jenkins
# specified by its url.

use strict;
use LWP::UserAgent;
use JSON;
use Getopt::Std qw(getopts);

# Nagios return values
use constant {
  OK => 0,
  WARNING => 1,
  CRITICAL => 2,
  UNKNOWN => 3,
};

use constant API_SUFFIX => "/api/json";

my %args;
my $ciMasterUrl;
my $jobName = '(All)';
my $userName;
my $password;
my $warn = -1;
my $crit = -1;
my $status = UNKNOWN;
my $debug = 0;

getopts('hdu:p:j:w:c:', \%args) or usage();
usage($0) if defined $args{h};
usage($0) if (@ARGV != 1);
$ciMasterUrl = $ARGV[0];
$userName = $args{u} if defined $args{u};
$password = $args{p} if defined $args{p};
$warn = $args{w} if defined $args{w};
$crit = $args{c} if defined $args{c};
$jobName = $args{j} if defined $args{j};
$debug = 1 if defined $args{d};

if ($jobName eq '(All)') {
    # All jobs
    my $ua = LWP::UserAgent->new();
    my $req = HTTP::Request->new(GET => $ciMasterUrl . API_SUFFIX);
    if ($userName ne '') {
        $req->authorization_basic($userName, $password);
    }
    my $res = $ua->request($req);
    if (!$res->is_success) {
        print "UNKNOWN: can't get Master API ($res->{status_line})";
        exit UNKNOWN;
    }
    my $json = new JSON;
    my $obj = $json->decode($res->content);
    my $jobs = $obj->{'jobs'}; # ref to array
    my $jobs_count = scalar(@$jobs);

    for (my $i = 0; $i <$jobs_count; $i++) {
        my $job_url = $jobs->[$i]{'url'};
        $status = test_job($job_url);
        last if ($status != OK && ! $debug);
    }
} else {
    $status = test_job($ciMasterUrl . '/job/' . $jobName . API_SUFFIX);
}

if ($status == OK) {
    print "OK: job: ", $jobName, "\n";
}
exit $status;

sub test_job {
    my $job_url = shift;
    my $ua = LWP::UserAgent->new();
    my $req = HTTP::Request->new( GET => $job_url . API_SUFFIX);
    $req->authorization_basic($userName, $password) if ($userName ne '');
    
    my $res = $ua->request($req);
    if (! $res->is_success) {
        print "UNKNOWN: can't get job api: ", $job_url, "\n";
        return UNKNOWN;
    }
    
    my $json = new JSON;
    my $obj = $json->decode($res->content);
    my $job_name = $obj->{'name'};
    trace("Job: ", $job_name);
    if (! $obj->{'buildable'}) {
        # Disabled job
        trace(", disabled\n");
        return OK;
    }
    if (! defined($obj->{'lastBuild'})) {
        # No build for this job
        trace(", no available build\n");
        return OK;
    }
    my $build_number = $obj->{'lastBuild'}->{'number'};
    if (defined($obj->{'lastCompletedBuild'})) {
        if ($obj->{'lastCompletedBuild'}->{'number'} == $build_number) {
            # This last build is completed, so not running
            trace(", build number=", $build_number, " is completed \n");
            return OK;
        }
    }
    my $build_url = $obj->{'lastBuild'}->{'url'};
    $ua = LWP::UserAgent->new();
    $req = HTTP::Request->new( GET => $build_url . API_SUFFIX);
    $req->authorization_basic($userName, $password) if ($userName ne '');
    $res = $ua->request($req);
    if (! $res->is_success) {
        # Can't get the build API
        print "UNKNOWN: job: ", $job_name, ", can't get build api: ", $build_url, " for build number=", $build_number, ", url=", $job_url, "\n";
        return UNKNOWN;
    }
    my $json = new JSON;
    my $obj = $json->decode($res->content);
    if (! $obj->{'building'}) {
        # This build is not currently running 
        trace(", build number=", $build_number, " is not running \n");
        return OK;
    }
    my $stamp = $obj->{'timestamp'};
    my $current_stamp = time() * 1000;
    my $duration = $current_stamp - $stamp;
    my $usual_duration = 1000 * 60 * 20; # 20 minutes
    if (defined($obj->{'estimatedDuration'}) && $obj->{'estimatedDuration'} > 0) {
        $usual_duration = $obj->{'estimatedDuration'};
    }
    trace(", duration=", $duration, ", usual duration=", $usual_duration, "\n");
    if ($crit != -1 && $duration > $usual_duration + ($usual_duration * $crit / 100)) {
        print "CRITICAL: job: ", $job_name, ", url=", $job_url, ", build=", $build_number, ", duration=", $duration, "ms exeeds critical threshold =(", $crit, "%) of usual duration=", $usual_duration, "ms\n";
        return CRITICAL;
    }
    if ($warn != -1 && $duration > $usual_duration + ($usual_duration * $warn / 100)) {
        print "WARNING: job: ", $job_name, ", url=", $job_url, ", build=", $build_number, ", duration=", $duration, "ms exeeds warning threshold =(", $warn, "%) of usual duration=", $usual_duration, "ms\n";
        return WARNING;
    }
    return OK;
}

sub trace {
    if ($debug) {
        print @_;
    }
}

sub usage {
    my $cmd = shift;
    #print (scalar(@ARGV));
    print ("Usage: $cmd [OPTIONS] <master-jenkins-url>\n");
    print ("       where OPTIONS are:\n");
    print ("       -h             Print this help\n");
    print ("       -d             Turns on debug traces\n");
    print ("       -u <user>      User authentication\n");
    print ("       -p <password>  Password\n");
    print ("       -w <percent>   Warning threshold in %\n");
    print ("       -c <percent>   Critical threshold in %\n");
    print ("       -j <job>       The job name (default all jobs)\n");
    exit UNKNOWN;
}