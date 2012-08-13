check_jenkins_job_time
======================

A Nagios plugin to monitor build time of Jenkins jobs.

This Nagios plugin check that running Jenkins jobs are not taking unusual time to complete.

You can specify one critical and/or one warning threshold express in % of the expected
building time (estimated by Jenkins with statistics on past builds).
You can select a given job with -j <job-name> option or check all jobs defined on the master Jenkins
specified by its url.

This module is written in Perl and requite LWP:: and JSON:: packages.

It has been checked on Windows and Linux plateforms and can be run either directly or
through NRPE by Nagios server.

Usage:
------

    check_jenkins_job_time.pl [OPTIONS] <master-jenkins-url>
        where OPTIONS are:\n");
        -h             Print this help\n");
        -d             Turns on debug traces\n");
        -u <user>      User authentication\n");
        -p <password>  Password\n");
        -w <percent>   Warning threshold in %\n");
        -c <percent>   Critical threshold in %\n");
        -j <job>       The job name (default all jobs)\n");