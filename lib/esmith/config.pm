#!/usr/bin/perl -wT

#----------------------------------------------------------------------
# copyright (C) 1999-2001 e-smith, inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA
#
# Technical support for this program is available from e-smith, inc.
# For details, please visit our web site at www.e-smith.com or
# call us on 1 888 ESMITH 1 (US/Canada toll free) or +1 613 564 8000
#----------------------------------------------------------------------

package esmith::config;
use strict;
use Sys::Syslog qw(:DEFAULT setlogsock);

=pod

=head1 NAME

esmith::config - Access e-smith config files via tied hashes

=head1 VERSION

This file documents C<esmith::config> version B<1.4.0>

=head1 SYNOPSIS

    use esmith::config;

=head1 DESCRIPTION

The esmith::config package enables Perl programs to read
and write entries from the e-smith configuration file
using a tied hash table.

The configuration file has a simple ASCII representation,
with one "key=value" entry per line.

Usage example:

    #!/usr/bin/perl -wT

    use esmith::config;
    use strict;

    my %conf;
    tie %conf, 'esmith::config', '/etc/testconfig';

    # write value to config file
    $conf {'DomainName'} = 'mycompany.xxx';

    read value from config file
    print $conf {'DomainName'} . "\n";

    # dump contents of config file
    while (($key,$value) = each %conf)
    {
        print "$key=$value\n";
    }

=cut 

BEGIN
{
    use Exporter ();
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT      = ();
    @EXPORT_OK   = ();
    %EXPORT_TAGS = ();
}

#------------------------------------------------------------
# readconf is a private subroutine.
#
# It takes two arguments: the name of the config file and a
# reference to a hash.
#
# The hash is cleared and then filled with key->value
# mappings read from the file.
#------------------------------------------------------------

sub readconf ($$)
{
    my ($filename, $confref) = @_;

    %$confref = ();

    # If the file cannot be opened, assume it hasn't been
    # created yet and return with an empty hash table.

    if (! open (FH, $filename))
    {
	if (-f $filename)
	{
	    &log("Config: ERROR: \"$filename\" exists but is not readable");
	}
	return;
    }

    while (<FH>)
    {
	chomp;

	# ignore comments and blank lines
	next if (/^\s*(#\s+.*?)?$/);

	# untaint data
	if (/^([\w\W]*)$/)
	{
	    $_ = $1;
	}

	my ($key, $value) = split (/=/, $_, 2);
	$$confref {$key} = $value;
    }

    close (FH);
    return;
}

#------------------------------------------------------------
# writeconf is a private subroutine.
#
# It takes two arguments: the name of the config file and a
# reference to a hash.
#
# The file is overwritten with the key->value mappings from
# the hash.
#------------------------------------------------------------

sub writeconf ($$)
{
    use Fcntl;

    my ($filename, $confref) = @_;
    if (-f $filename && ! -r $filename)
    {
	&log("Config: ERROR: \"$filename\" exists but is not readable");
	&log("Config: \"$filename\" will not be updated");
	return;
    }

    sysopen (FH, "$filename.$$", O_RDWR | O_CREAT, 0600)
	or die "Cannot open $filename.$$: $!\n";

    (my $header = <<EOF) =~ s/^\s+//gm;
      # DO NOT MODIFY THIS FILE.
      # This file is automatically maintained by the March Networks SME Server
      # configuration software.  Manually editing this file may put your 
      # system in an unknown state. 
EOF
    print FH $header;

    foreach (sort keys %$confref)
    {
	print FH $_ . "=" . $$confref{$_} . "\n";
    }

    close (FH);

    rename("$filename.$$", $filename)
	or die "Couldn't rename $filename.$$ to $filename: $!";
    return;
}

#------------------------------------------------------------
# Constructor for the tied hash. If filename not specified,
# defaults to '/home/e-smith/configuration'.
#------------------------------------------------------------

sub TIEHASH
{
    my $self = shift;
    my $filename = shift || '/home/e-smith/configuration';

    my $node =
    {
	FILENAME => $filename,
	ENVCACHE => {},
    };

    readconf ($filename, $node->{'ENVCACHE'});

    return bless $node, $self;
}

#------------------------------------------------------------
# Look up a configuration parameter.
#------------------------------------------------------------

sub FETCH
{
    my $self = shift;
    my $key  = shift;

    return $self->{ENVCACHE} {$key};
}

#------------------------------------------------------------
# Store a configuration parameter.
#------------------------------------------------------------

sub STORE
{
    my $self  = shift;
    my $key   = shift;
    my $value = shift;

    # read in config again, just in case it changed
    readconf ($self->{FILENAME}, $self->{ENVCACHE});

    if (exists $self->{ENVCACHE} {$key} and
    	$self->{ENVCACHE} {$key} eq $value)
    {
	return undef;
    }

    my $msg = "$self->{FILENAME}: OLD $key=";

    if (exists $self->{ENVCACHE}{$key})
    {
	$msg .= "$self->{ENVCACHE}{$key}";
    }
    else
    {
	$msg .= "(undefined)";
    }

    &log($msg);

    $self->{ENVCACHE} {$key} = $value;
    &log("$self->{FILENAME}: NEW $key=$self->{ENVCACHE}{$key}");

    writeconf ($self->{FILENAME}, $self->{ENVCACHE});

    return undef;
}

#------------------------------------------------------------
# Delete a configuration parameter.
#------------------------------------------------------------

sub DELETE
{
    my $self = shift;
    my $key = shift;

    # read in config again, just in case it changed
    readconf ($self->{FILENAME}, $self->{ENVCACHE});

    my $previous = delete $self->{ENVCACHE} {$key};
    writeconf ($self->{FILENAME}, $self->{ENVCACHE});

    &log("$self->{FILENAME}: DELETE $key");

    return $previous;
}

#------------------------------------------------------------
# Clear the configuration file.
#------------------------------------------------------------

sub CLEAR
{
    my $self = shift;

    $self->{ENVCACHE} = ();
    writeconf ($self->{FILENAME}, $self->{ENVCACHE});

    &log("$self->{FILENAME}: CLEAR");

    return undef;
}

#------------------------------------------------------------
# Check whether a particular key exists in the configuration file.
#------------------------------------------------------------

sub EXISTS
{
    my $self = shift;
    my $key = shift;

    return exists $self->{ENVCACHE} {$key};
}

#------------------------------------------------------------
# FIRSTKEY is called whenever we start iterating over the
# configuration table. We cache the configuration table at
# this point to ensure reasonable results if the
# configuration file is changed by another program during
# the iteration.
#------------------------------------------------------------

sub FIRSTKEY
{
    my $self = shift;

    my $discard = keys %{$self->{ENVCACHE}};    # reset each() iterator

    return each %{$self->{ENVCACHE}};
}

#------------------------------------------------------------
# NEXTKEY is called for all iterations after the first.  We
# just keep returning results from the cached configuration
# table.  A null array is returned at the end. If the caller
# starts a new iteration, the FIRSTKEY subroutine is called
# again, causing the cache to be reloaded.
#------------------------------------------------------------

sub NEXTKEY
{
    my $self = shift;
    return each %{$self->{ENVCACHE}};
}

#------------------------------------------------------------
# No special instructions for the destructor.
#------------------------------------------------------------

sub DESTROY
{
}

#------------------------------------------------------------
# Log messages to syslog
#------------------------------------------------------------

sub log
{
    # There is a bug in Perl 5.00504 and above. If you are using the unix
    # domain socket, do NOT use ndelay as part of the second argument
    # to openlog().

    my $msg = shift;
    my $program = $0;

    # Cook % characters. syslog formats messages using sprintf().

    $msg =~ s/%/%%/g;

    setlogsock 'unix';
    openlog($program, 'pid', 'local1');
    syslog('info', $msg);
    closelog();
}

#------------------------------------------------------------
# No module clean-up code required.
#------------------------------------------------------------

END
{
}

#------------------------------------------------------------
# Return "1" to make the import process return success.
#------------------------------------------------------------

1;

=pod

=head1 AUTHOR

e-smith, inc.

For more information, see http://www.e-smith.org/

=cut
