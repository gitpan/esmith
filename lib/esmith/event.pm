#!/usr/bin/perl -w

#----------------------------------------------------------------------
# Copyright (c) 2001 Mitel Networks Corporation 
# 
# Technical support for this program is available from Mitel Networks
# Corporation.  Please visit our web site www.e-smith.com for details.
#----------------------------------------------------------------------

package esmith::event;

use strict;
use Exporter;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );

=pod

=head1 NAME

esmith::event - Routines for handling e-smith events

=head1 VERSION

This file documents C<esmith::event> version B<0.1.0>

=head1 SYNOPSIS

    use esmith::event;

=head1 DESCRIPTION

=cut

BEGIN
{
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT      = qw(event_signal);

    @EXPORT_OK   = ();
    %EXPORT_TAGS = ();
}

sub event_signal
{
    my ($event, @args) = @_;
    my $handlerDir = "/etc/e-smith/events/$event";

    #------------------------------------------------------------
    # We don't want to exit from a remote session while running
    # an event. SIGHUPing sshd can lose current connections
    #------------------------------------------------------------
    #$SIG{'HUP'} = 'IGNORE';

    #------------------------------------------------------------
    # We want to turn off cursor positioning code and colour
    # code in init.d scripts
    #------------------------------------------------------------
    #$ENV{'BOOTUP'}="nocolour";

    #------------------------------------------------------------
    # get event handler filenames
    #------------------------------------------------------------

    opendir (DIR, $handlerDir)
        || die "Can't open directory /etc/e-smith/events/$event\n";

    # drop the "." and ".." directories
    my @handlers = sort (grep (!/^\.\.?$/, readdir (DIR)));

    closedir (DIR);

    #------------------------------------------------------------
    # Execute all handlers, sending any output to the system log.
    #
    # Event handlers are not supposed to generate error messages
    # under normal conditions, so we do not provide a mechanism
    # for event handlers to signal errors to the user. Errors can
    # only be written to the log file.
    #------------------------------------------------------------

    # Safe pipe to avoid taint checks (see perlsec manpage)
    open (LOG, "|-") or exec ("/usr/bin/logger", '-i', '-t', "e-smith");

    #------------------------------------------------------------
    # Ensure output is autoflushed.
    #------------------------------------------------------------

    my $ofh = select (LOG);
    $| = 1;
    select ($ofh);

    print LOG "Processing event: @ARGV\n";

    #------------------------------------------------------------
    # Run handlers, logging all output.
    #------------------------------------------------------------

    # assume success
    my $exitcode = 1;

    # save old filehandles
    open(OLDSTDOUT, ">&STDOUT");
    open(OLDSTDERR, ">&STDERR");

    # dup filehandles to LOG
    open(STDOUT, ">&LOG");
    open(STDERR, ">&LOG");

    foreach my $handler (@handlers)
    {
        my $filename = "$handlerDir/$handler";
	my $startTime = [gettimeofday];

        if (-f $filename)
        {
            print LOG "Running event handler: $filename\n";

            unless ( system($filename, @ARGV) == 0 )
            {
		# if any handler fails, the entire event fails
                $exitcode = 0;
            }
        }
        else
        {
            print LOG "Skipping unknown event handler: $filename\n";
        }

	my $endTime = [gettimeofday];
	my $elapsedTime = tv_interval($startTime, $endTime);
        print LOG "$handler=action|Event|$event|Action|$handler|Start|@$startTime|End|@$endTime|Elapsed|$elapsedTime\n";
    }
    close STDERR;
    close STDOUT;
    close LOG;

    # restore old filehandles
    open STDOUT, ">&OLDSTDOUT";
    open STDERR, ">&OLDSTDERR";
    close OLDSTDOUT;
    close OLDSTDERR;

    return $exitcode;

}

#------------------------------------------------------------
# Attempt to eval perl handlers for efficiency - not currently used
# return 1 on success; 0 on error
#------------------------------------------------------------
sub _runHandler($)
{
    my ($filename) = @_;

    open(FILE, $filename) || die "Couldn't open $filename: $!";
    my @lines = <FILE>;
    close FILE;

    my $string = "";

    unless ( $lines[0] =~ /^#!.*perl/ )
    {
	# STDOUT and STDERR are both redirected going to LOG
	return (system($filename, @ARGV) == 0) ? 1 : 0;
    }

    map { $string .= $_ } @lines;

    print "Eval of $filename...";

    # Override 'exit' in symbol table for handlers
    sub exit { die "$_[0]\n" };
    *CORE::GLOBAL::exit = \&esmith::event::exit;

    my $status = eval $string;
    chomp $@;

    # if $@ is defined, then die or exit was called - use that status
    $status = $@ if defined $@;
    
    # for all exit values except 0, assume failure
    if ($@)
    {
        print "Eval of $filename failed:  $status\n";
        return 0;
    }

    print "$status\n";
    return 1;
}
1;
