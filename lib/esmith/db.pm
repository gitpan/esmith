#!/usr/bin/perl -w

#--------------------------------------------------------------------------
# copyright (C) 2000-2001 e-smith, inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA
#
# Technical support for this program is available from e-smith, inc.
# Please visit our web site www.e-smith.com for details.
#--------------------------------------------------------------------------

package esmith::db;

use strict;
use Exporter;

=pod

=head1 NAME

esmith::db - Routines for handling the e-smith configuration database

=head1 VERSION

This file documents C<esmith::db> version B<1.4.0>

=head1 SYNOPSIS

    use esmith::db;

=head1 DESCRIPTION

The e-smith server and gateway keeps most of its configuration in a flat
text file C</home/e-smith/configuration>.  This module provides utility
routines for manipulating that configuration data.

=cut

#--------------------------------------------------------------------------
# subroutines to manipulate hashes for e-smith config files
#--------------------------------------------------------------------------

BEGIN
{
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT      = qw(
			db_set
			db_get
			db_delete

			db_set_type
			db_get_type

			db_get_prop
			db_set_prop
			db_delete_prop

			db_print
			db_show

			db_print_type
			db_print_prop
		);

    @EXPORT_OK   = ();
    %EXPORT_TAGS = ();
}

=pod

=head2 db_set($hash, $key, $new_value, $hashref)

Takes a reference to a hash, a scalar key and a scalar value and an
optional hash reference. If the hash reference is provided, a new
value is constructed from the scalar value and the referred to hash.
It then sets the key/value pair.

It returns one on success and undef on failure.

=cut

sub db_set (%$$;$)
{
    my ($hash, $key, $new_value, $hashref) = @_;

    if (defined $hashref)
    {
	my $properties = private_db_hash_to_string($hashref);
	if (defined $properties && $properties ne '')
	{
	    $new_value .= "|$properties";
	}
    }
    $$hash{$key} = $new_value;
    return undef unless defined db_get($hash, $key);
    return 1;
}

=pod

=head2 db_get($hashref, $key)

Takes a reference to a hash and an optional scalar key. If the scalar
key is not provided, it returns a list of keys. If the scalar key is
provided, it returns the value of that key (in array context, as a list
suitable for assigning to a type and properties hash list) 
or undef if the key does not exist.

=cut

sub db_get (%;$)
{
    my ($hash, $key) = @_;

    return sort keys %$hash unless defined $key;
    return undef unless exists $$hash{$key};
    return wantarray() ? private_db_string_to_type_and_hash($$hash{$key}) :
	    $$hash{$key};
}

=pod

=head2 db_delete($hashref, $key)

Takes a reference to a hash and a scalar key and deletes the key. It
returns one on success and undef if the key does not exist.

=cut

sub db_delete (%$;)
{
    my ($hash, $key) = @_;

    return undef unless defined db_get($hash, $key);

    delete $$hash{$key};
    return 1;
}

=pod

=head2 db_set_type($hashref, $key, $type)

Takes a reference to a hash, a scalar key and a scalar value and sets
the type for the key. It returns one on success and undef on failure.

=cut

sub db_set_type (%$$;)
{
    my ($hash, $key, $type) = @_;

    return undef unless defined db_get($hash, $key);

    my %properties = db_get_prop($hash, $key);

    return db_set($hash, $key, $type, \%properties);
}

=pod

=head2 db_get_type($hashref, $key);

Takes a reference to a hash and a scalar key and returns the type
associated with the key. It returns undef if the key does not exist.

=cut

sub db_get_type (%$;)
{
    my ($hash, $key) = @_;

    return undef unless defined db_get($hash, $key);

    my ($type, undef) =
	private_db_string_to_type_and_hash(db_get($hash, $key));
    return $type;
}

=pod

=head2 db_set_prop($hashref, $key, $prop, $new_value)

Takes a reference to a hash, a scalar key, a scalar property and a
scalar value and sets the property from the value. It returns with
the return status of db_set or undef if the key does not exist.

=cut

sub db_set_prop (%$$$;)
{
    my ($hash, $key, $prop, $new_value) = @_;

    return undef unless defined db_get($hash, $key);

    my $type = db_get_type($hash, $key);
    my %properties = db_get_prop($hash, $key);
    $properties{$prop} = $new_value;
    return db_set($hash, $key, $type, \%properties);
}

=pod

=head2 db_get_prop($hashref, $key, $prop)

Takes a reference to a hash, a scalar key and an optional scalar
property. If the property is supplied, it returns the value associated
with that property. If the property is not supplied, it returns a
hash of all properties for the key. It returns undef if the key or
the property does not exist.

=cut

sub db_get_prop (%$;$)
{
    my ($hash, $key, $prop) = @_;

    my $val = db_get($hash, $key);
    return (defined $prop ? undef : ()) unless defined $val;

    my (undef, %properties) = private_db_string_to_type_and_hash($val);

    return %properties unless defined $prop;
    return undef unless exists $properties{$prop};
    return $properties{$prop};
}

=pod

=head2 db_delete_prop($hashref, $key, $prop)

Takes a reference to a hash, a scalar key and a scalar property and
deletes the property from the value. It returns with the return status
of db_set or undef if the key or the property do not exist.

=cut

sub db_delete_prop (%$$;)
{
    my ($hash, $key, $prop) = @_;

    return undef unless defined db_get($hash, $key);

    my $type = db_get_type($hash, $key);
    my %properties = db_get_prop($hash, $key);
    delete $properties{$prop};
    return db_set($hash, $key, $type, \%properties);
}

=pod

=head2 db_print($hash, $key)

Takes a reference to a hash and an optional scalar key. If the scalar
key is not provided, it prints key=value for each key in the hash. If
the scalar key is provided, it prints key=value for that key. It
returns one on success or undef if the key does not exist.

=cut

sub db_print (%;$)
{
    my ($hash, $key) = @_;

    my @list;

    if (defined $key)
    {
	return undef unless defined db_get($hash, $key);
	@list = $key;
    }
    else
    {
	@list = db_get($hash);
    }

    return undef unless scalar @list;

    foreach (@list)
    {
	print "$_=", scalar db_get($hash, $_),"\n";
    }

    return 1;
}

=pod

=head2 db_show($hashref, $key)

Takes a reference to a hash and an optional scalar key. If the scalar
key is not provided, it prints key/value pairs for each key in the
hash. If the scalar key is provided, it prints the key/value for
that key. The value is expanded to show properties. It returns one
on success or undef if the key does not exist.

=cut

sub db_show (%;$)
{
    my ($hash, $key) = @_;

    my @list;

    if (defined $key)
    {
	return undef unless defined db_get($hash, $key);
	@list = $key;
    }
    else
    {
	@list = db_get($hash) unless defined $key;
    }

    return undef unless scalar @list;

    foreach (@list)
    {
	print "$_=";

	my $type = db_get_type($hash, $_);

	if (defined $type)
	{
	    print "$type\n";
	}
	else
	{
	    print "\n";
	    next;
	}

	my %properties = db_get_prop($hash, $_);
	next unless scalar keys %properties;

	foreach my $property (sort keys %properties)
	{
	    print "    $property=$properties{$property}\n";
	}
    }

    return 1;
}

=pod

=head2 db_print_type($hashref, $key)

Takes a reference to a hash and an optional scalar key. If the scalar
key is not provided, it prints key=type for each key in the hash. If
the scalar key is provided, it prints key=type for that key. It
returns one on success or undef if the key does not exist.

=cut

sub db_print_type (%;$)
{
    my ($hash, $key) = @_;

    my @list;

    if (defined $key)
    {
	return undef unless defined db_get($hash, $key);
	@list = $key;
    }
    else
    {
	@list = db_get($hash);
    }

    return undef unless scalar @list;

    foreach (@list)
    {
	print "$_=";

	my $type = db_get_type($hash, $_);

	print db_get_type($hash, $_),"\n" if defined $type;
	print "\n" unless defined $type;
    }

    return 1;
}

=pod

=head2 db_print_prop($hashref, $key, $prop)

Takes a reference to a hash, a scalar key and an optional scalar
property. If the scalar property is not provided, it prints prop=value
for each property associated with the key. If the scalar property is
provided, it prints prop=value for that key. It returns one on success
or undef if the key or property does not exist.

=cut

sub db_print_prop (%$;$)
{
    my ($hash, $key, $prop) = @_;

    my @list;
    my %list;

    return undef unless defined db_get($hash, $key);

    if (defined $prop)
    {
	my $value = db_get_prop($hash, $key, $prop);
	return undef unless defined $value;

	%list = ($prop => $value);
    }
    else
    {
	%list = db_get_prop($hash, $key);
    }

    return undef unless scalar keys %list;

    foreach (sort keys %list)
    {
	print "$_=$list{$_}\n";
    }

    return 1;
}

=pod

=head2 private_db_hash_to_string($hashref)

Takes a reference to a hash and returns a string of pipe "|" delimited
pairs.

=cut

sub private_db_hash_to_string (%;)
{
    my ($hash) = @_;
    my $string = '';

    foreach (sort keys %$hash)
    {
	$string .= '|' if length($string);
	$string .= "$_|";
	$string .= $$hash{$_} if defined $$hash{$_};
    }

    return $string;
}

=pod

=head2 private_db_string_to_type_and_hash($arg)

Takes a string and expands it on the assumption that the string is
a type string, followed by a list of pipe "|" delimited pairs.
It returns the expanded string as an array, which can be assigned to
a type and property hash.

=cut

sub private_db_string_to_type_and_hash ($;)
{
    my ($arg) = @_;
    my ($type, $string) = split(/\|/, $arg, 2);
    my %hash = ();

    if (defined $string)
    {
	if ($string =~ /\|/)
	{
	    %hash = split(/\|/, $string, -1);
	}
	else
	{
	    %hash = ($string => '');
	}
    }

    return ($type, %hash);
}

END
{
}

#------------------------------------------------------------
# Return one to make the import process return success.
#------------------------------------------------------------

1;

=pod

=head1 AUTHOR

e-smith, inc.

For more information, see http://www.e-smith.org/

=cut
