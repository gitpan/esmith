#!/usr/bin/perl -wT

#----------------------------------------------------------------------
# ethernet
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
# Please visit our web site www.e-smith.com for details.
#----------------------------------------------------------------------

package esmith::ethernet;

#----------------------------------------------------------------------

use strict;

=head1 NAME

esmith::ethernet - Ethernet-related utility routines for e-smith

=head1 VERSION

This file documents C<esmith::ethernet> version B<1.4.0>

=head1 SYNOPSIS

    use esmith::ethernet;

=head1 DESCRIPTION

This module contains routines for 

=cut

#----------------------------------------------------------------------
# Private variables
#----------------------------------------------------------------------

my %private_pci_network_cards;
my %private_pci_network_drivers;

BEGIN
{
    # All the routines below need the arrays, so populate them on entry.

    my $proc_version = "/proc/version";

    open(VERSION, "$proc_version")
        or warn "Could not open $proc_version for reading. $!\n";

    my $kernel = (split(' ', <VERSION>))[2];
    close VERSION;

    my $modules = "/lib/modules/" . $kernel . "/net";

    unless (opendir MODULES, $modules)
    {
	warn "Could not open network modules directory $modules: $!\n";
	return;
    }

    my %network_drivers;

    foreach (readdir MODULES)
    {
	next if /^\.\.?$/;		# Ignore "." and ".."
	next if -d;			# Ignore directories

	s/\.o$//;
	++$network_drivers{$_};
    }

    closedir MODULES;

    my $pcitable = "/usr/share/kudzu/pcitable";

    unless (open(PCITABLE, $pcitable))
    {
	warn "Could not open pci table $pcitable: $!\n";
	return;
    }

    my %descriptions;

    while (<PCITABLE>)
    {
	next if (/^\s*#|^\s*$/);

	chomp;
	my @f = split(/\t/);

	next if ($f[2] =~ /^0x/);	# Can't handle sub vendor IDs yet.

	$f[0] =~ s/^0x//;
	$f[1] =~ s/^0x//;
	$f[2] =~ s/"//g;
	$f[3] =~ s/"//g;

	if (exists $network_drivers{$f[2]})
	{
	    my $card = $f[0] . ":" . $f[1];
	    $private_pci_network_cards{$card}{driver} = $f[2];
	    $private_pci_network_cards{$card}{description} = $f[3];

	    my $description = $f[3];
	    $description =~ s/\|.*//;

	    if (exists $private_pci_network_drivers{$f[2]})
	    {
		unless (exists $descriptions{$f[2] . $description})
		{
		    $private_pci_network_drivers{$f[2]} .= " or $description";
		    ++$descriptions{$f[2] . $description};
		}
	    }
	    else
	    {
		$private_pci_network_drivers{$f[2]} = $description;
		++$descriptions{$f[2] . $description};
	    }

	}
    }

    close PCITABLE;
}

=pod

=head2 listDrivers();

List the available drivers

=cut

sub listDrivers ()
{
    my $driver;
    my $drivers = '';

    return "\"unknown driver\"\t\"unknown description\" "
	unless (scalar keys %private_pci_network_drivers);

    foreach $driver (sort keys %private_pci_network_drivers)
    {
	$drivers .=
	    "\""
	    . $driver
	    . "\"\t\""
	    . $private_pci_network_drivers{$driver}
	    . " based adapter\" ";
    }

    return $drivers;
}

=pod

=head2 listAdapters();

List the available adapter cards

=cut

sub listAdapters ()
{
    my $cards = '';

    return "\"unknown driver\"\t\"unknown adapter card\" "
	unless (scalar keys %private_pci_network_cards);

    foreach (sort private_card_by_driver keys %private_pci_network_cards)
    {
	$cards .=
	    "\""
	    . $private_pci_network_cards{$_}{driver}
	    . "\"\t\""
	    . $private_pci_network_cards{$_}{description}
	    . "\" ";
    }

    return $cards;
}

=pod 

=head2 lookupAdapter($adapter);

Find the driver for a particular card

=cut

sub lookupAdapter ($)
{
    my $adapter = shift;

    return "unknown"
	unless (
		    scalar keys %private_pci_network_cards
		    &&
		    $adapter
	    );

    foreach (sort keys %private_pci_network_cards)
    {
	if ($private_pci_network_cards{$_}{description} eq $adapter)
	{
	    return $private_pci_network_cards{$_}{driver};
	}
    }

    return "unknown";
}

=pod

=head2 probeAdapters()

Probe for any recognised adapters

=cut

sub probeAdapters ()
{

    return unless (scalar keys %private_pci_network_cards);

    my $lspci = "/sbin/lspci -n";
    my $max_cards = 2;
    my $adapters = '';

    unless (open(LSPCI, "$lspci | "))
    {
	warn "Could not run $lspci: $!\n";
	return;
    }

    my $index = 1;

    while (<LSPCI>)
    {
	last if ($index > $max_cards);

	chomp;

	my @f = split(' ');

	my $card = $f[3];
	my $driver;
	my $description;

	if (exists $private_pci_network_cards{$card}{driver})
	{
	    $driver = $private_pci_network_cards{$card}{driver};
	    $description = $private_pci_network_cards{$card}{description};
	}
	else
	{
	    next unless /Class 0200:/;
	    $driver = "unknown";
	    $description = "unknown";
	}

	$adapters .=
	    "EthernetDriver"
	    . $index
	    . "\t"
	    . $driver
	    . "\t"
	    . $description
	    . "\n";

	++$index;
    }

    close LSPCI;

    return $adapters;
}


#----------------------------------------------------------------------
# Private method. Sort adapters by their driver type.
#----------------------------------------------------------------------

sub private_card_by_driver ()
{
    # Sort the network cards by their driver type

    $private_pci_network_cards{$a}{driver} cmp
	$private_pci_network_cards{$b}{driver};
}

END
{
}

#----------------------------------------------------------------------
# Return one to make the import process return success.
#----------------------------------------------------------------------

1;

=pod

=head1 AUTHOR

e-smith, inc.

For more information see http://www.e-smith.org/

=cut
