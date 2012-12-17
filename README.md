check_jenkins
=============

A set of 4 Nagios plugins to monitor Jenkins health.

*  check_jenkins.pl
*  check_jenkins_version.pl
*  check_jenkins_job_time.pl
*  check_jenkins_slaves.pl

These 4 perl scripts use HTTP requests to query Jenkins API (json).

## check_jenkins.pl ##

This Nagios plugin count the number of jobs of a Jenkins instance.

It can check that the total number of jobs will not exeed the WARNING and CRITICAL thresholds.

It also count the number of disabled, passed, running and failed jobs and can check that the ratio of failed jobs against active jobs is over a WARNING and CRITICAL thresholds.

Performance data are:

    jobs=<count>;<warn>;<crit> passed=<count> failed=<count>;<warn>;<crit> disabled=<count> running=<count>
    
### Usage: ###

    check_jenkins.pl --man
        will print the manual page for this command
    
## check_jenkins_version.pl ##

This Nagios plugin check the version number of a Jenkins instance.

It can verify that the version is greater than specified versions for WARNING ant CRITICAL thresholds.

With jenkins version **1.466** and above, it also check if some plugins need to be updated.

### Usage: ###

    check_jenkins_version.pl --man
        will print the manual page for this command


## check_jenkings_job_time.pl ##

This Nagios plugin check that running Jenkins jobs are not taking unusual time to complete.

You can specify one critical and/or one warning threshold express in % of the expected
building time (estimated by Jenkins with statistics on past builds).
You can select a given job with -j <job-name> option or check all jobs defined on the master Jenkins
specified by its url.

This module is written in Perl and requite LWP:: and JSON:: packages.

It has been checked on Windows and Linux plateforms and can be run either directly or
through NRPE by Nagios server.

### Usage: ###

    check_jenkins_job_time.pl --man
        will print the manual page for this command
        
## check_jenkings_slaves.pl ##

This Nagios plugin check the status of slaves of a Jenkins instance.

You can specify one critical and/or one warning threshold express in % of the
ratio of offline slaves.
You can also specify warning/critical thresholds in % for the used executors
ratio (per slave and globally)
You can select a given slave with -n <slave-name> option or check all slaves
defined on the master Jenkins specified by its url.
You can choose to monitor state changes (with option --statefull) and be
alerted when any slave has a status changed regarding previous call of this
plugin.

This module is written in Perl 5 and requires LWP::, JSON::, Getopt::,
File::Spec and Pod:: packages.

It has been checked on Windows and Linux platforms and can be run either directly or
through NRPE by Nagios server.

### Usage: ###

    check_jenkins_slaves.pl --man
        will print the manual page for this command
