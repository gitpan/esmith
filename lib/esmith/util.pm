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

package esmith::util;

use strict;

use Text::Template 'fill_in_file';
use POSIX qw (setsid);
use Errno;
use esmith::config;
use esmith::db;

use File::Basename;
use File::stat;
use FileHandle;

=pod

=head1 NAME

esmith::util - Utilities for e-smith server and gateway development

=head1 VERSION

This file documents C<esmith::util> version B<1.4.0>

=head1 SYNOPSIS

    use esmith::util;

=head1 DESCRIPTION

This module provides general utilities of use to developers of the
e-smith server and gateway.

=head1 GENERAL UTILITIES

=cut


#------------------------------------------------------------
# 
#------------------------------------------------------------

BEGIN
{
}


=pod

=head2 setRealToEffective()

Sets the real UID to the effective UID and the real GID to the effective
GID.

=cut

sub setRealToEffective ()
{
    $< = $>;
    $( = $);
}

=pod

=head2 processTemplate({ CONFREF => $conf, TEMPLATE_PATH => $path })

The processTemplate function takes as arguments a tied reference to
the e-smith configuration file, and the name of the output file to
produce. The template is found by prepending a template source path
to the filename.

We also allow a parallel template hierarchy C</etc/e-smith/templates-custom>
which is used in preference to the standard templates in 
C</etc/e-smith/templates>

The templates in C</etc/e-smith/templates-custom> are merged with the standard
templates in C</etc/e-smith/templates> so only modified/additional fragments
need appear in C<templates-custom>.

It is possible to override a file based template with a customised
directory based template (and vice-versa if you really want to).

Example 1: we have a template C</etc/e-smith/templates/etc/hosts>
that we want to expand to C</etc/hosts>

Solution 1a: use the old syntax (passing scalars):

    processTemplate(\%conf, '/etc/hosts')

Solution 1b: use the new syntax (passing a hash of named parameters):
    processTemplate({
        CONFREF => \%conf,
        TEMPLATE_PATH => '/etc/hosts',
    });

NOTE: this will use the TEMPLATE_EXPAND_QUEUE defaults, and since
OUTPUT_FILENAME wasn't specified, TEMPLATE_PATH will be used for
output

Example 2: we have a template C</etc/e-smith/templates-user/qmail>
that we want to expand to C</home/e-smith/files/users/$username/.qmail>

Solution: must use the new syntax (passing a hash of named parameters):

    processTemplate({ 
        CONFREF => \%conf, 
        TEMPLATE_PATH => '/qmail',
        TEMPLATE_EXPAND_QUEUE => [
            '/etc/e-smith/templates-user-custom',
            '/etc/e-smith/templates-user',
        ],
        OUTPUT_PREFIX => '/home/e-smith/files/users/$username',
        OUTPUT_FILENAME => '/.qmail',
        UID => $username,
        GID => $username,
        PERMS => 0644,
    });

=cut

sub processTemplate
{
    ######################################
    # set the default values to use if not 
    #  specified in parameters
    # every valid parameter should have a default
    ######################################

    my %defaults = (
	CONFREF => {},
#	FILE_PATH => '',		# deprecated as of e-smith-lib-1.1.0-12
	TEMPLATE_PATH => '',	# replaces FILE_PATH
#	FILE_PATH_LIST => [],	# deprecated as of e-smith-lib-1.1.0-12
	OUTPUT_FILENAME => '',	# replaces FILE_PATH_LIST
	TEMPLATE_EXPAND_QUEUE => [ 
	    '/etc/e-smith/templates-custom',
	    '/etc/e-smith/templates', 
	    '/etc/e-smith/templates-default', 
	],
#	TARGET => '',			# deprecated as of e-smith-lib-1.1.0-12
	OUTPUT_PREFIX => '',	# replaces TARGET
	UID => 0,
	GID => 0,
	PERMS=> 0644,
    );

    my $conf_or_params_ref = shift;
    my $path = shift;
    my %params_hash;
    if (defined $path)
    {
	# This is the old syntax, so we just grab the the two or maybe
	# three parameters ...
	%params_hash = (
	    CONFREF => $conf_or_params_ref,
	    TEMPLATE_PATH => $path,
	);
	if (my $source = shift)
	{
	    $params_hash{'TEMPLATE_EXPAND_QUEUE'} = [ $source ];
	}
    }
    else
    {
        %params_hash = %$conf_or_params_ref;
    }

    #######################################################
    # warn on deprecated or unknown parameters
    #######################################################
    foreach my $key (keys %params_hash) 
    {
	unless (exists $defaults{$key})
	{
	    warn "Warning: unknown parameter '$key' passed to processTemplate\n";
	}
    }


    ########################################################
    # merge incoming parameters with the defaults 
    # -this is backwards compatible with the old positional 
    #	parameters $confref, $filename, and $source
    ########################################################
    my %p = (%defaults, %params_hash); 
   
    unless (exists $p{'TEMPLATE_PATH'})
    {
	warn "Warning: 'TEMPLATE_PATH' parameter missing in processTemplate\n";
    }

    #################################################
    # open target before servicing the template queue
    #################################################

    # use POSIX::open to set permissions on create
    my $filename = $p{'TEMPLATE_PATH'};
    my $target = $p{'OUTPUT_PREFIX'};
    my $perms = $p{'PERMS'};
    
    if (-d "$target/$filename")
    {
	warn ("Could not expand $target/$filename - it is a directory\n");
	return;
    }

    my $fd = POSIX::open ("$target/$filename.$$",
	&POSIX::O_CREAT | &POSIX::O_WRONLY | &POSIX::O_TRUNC,
	$perms)
	    || die "Cannot create output file ${target}/${filename}.$$: $!\n";

    # create a filehandle reference to the newly opened file
    my $fh = new FileHandle;
    $fh->fdopen($fd, "w")
	|| die "Cannot open output file ${target}/${filename}.$$: $!\n";

    # error checking and conversions for uid
    my $uid = $p{'UID'};
    if ($uid =~ /^\d+$/) 
    {
	unless (defined getpwuid $uid)
	{
	    warn "Invalid user: ${uid}, defaulting to 'root' user (0).\n";
	    $uid = 0;
	}
    }
    else
    {
	my $uname = $uid;
	$uid = getpwnam $uid;
	unless (defined $uid)
	{
	    warn "Invalid user: ${uname}, defaulting to 'root' user (0).\n";
	    $uid = 0;
	}
    }
    
    # error checking and conversions for gid
    my $gid = $p{'GID'};
    if ($gid =~ /^\d+$/)
    {
	unless (defined getgrgid $gid)
	{
	    warn "Invalid group: ${gid}, defaulting to 'root' group (0).\n";
	    $gid = 0;
	}
    }
    else 
    {
	my $gname = $gid;
	$gid = getgrnam $gid;
	unless (defined $gid)
	{
	    warn "Invalid group: ${gname}, defaulting to 'root' group (0).\n";
	    $gid = 0;
	}
    }
    # now do chown on our new target
    chown ($uid, $gid, "$target/$filename.$$")
	    || die "Error chown'ing file $target/$filename.$$: $!\n";
    # Now do chmod as well - POSIX::open does not change permissions
    # of a preexisting file
    chmod ($perms, "$target/$filename.$$")
	    || die "Error chmod'ing file $target/$filename.$$: $!\n";
    
    ############################################################
    # Construct a hash containing mapping each template fragment 
    # to its path.  Subsequent mappings of the same fragment
    # override the previous fragment (ie: merge new fragments 
    # and override existing fragments)
    ############################################################
    
    # use queue to store template source directories in order
    my @template_queue = @{ $p{'TEMPLATE_EXPAND_QUEUE'} };

    # use a hash to store template fragments
    my %template_hash =
	(merge_templates($filename, @{ $p{'TEMPLATE_EXPAND_QUEUE'}}));

    # the subroutine that does all the template merging
    sub merge_templates 
    {
	my %template_hash = ();
	my $filename = shift;
	my @template_queue = @_;
	my $source;
	while ($source = pop @template_queue) 
	{
	    # if template is a flat template file overwrite the hash
	    if (-f "$source/$filename") 
	    {
		%template_hash = ( $filename => "$source/$filename" );
	    }
	    # otherwise, merge new fragments with the hash
	    elsif (-d "$source/$filename") 
	    {
		delete $template_hash{"$filename"};
		# if dir exists but can't be opened then we have a problem
		opendir (DIR, "$source/$filename")
		  || warn "Can't open template source directory:"
			. " $source/$filename - skipping."
			&& next;	
		# fill the hash with template fragments	
		while ( defined (my $file = readdir(DIR)) ) 
		{
		    next if ($file =~ /^\.{1,2}$/);

		    # Skip over files left over by rpm from upgrade
		    # and other temp files etc.
		    if ($file =~ /(~|\.(swp|orig|rpmsave|rpmnew|rpmorig))$/o)
		    {
			warn "Skipping $source/$filename/$file";
			next;
		    }

		    if (-f "$source/$filename/$file")
		    {
		    	$template_hash{"$filename/$file"} =
			    "$source/$filename/$file";
		    }
		    elsif (-d "$source/$filename/$file")
		    {
			# Skip over revision control directories
			if ($file =~ /^(RCS|CVS|SCCS)$/o)
			{
			    warn "Skipping directory $source/$filename/$file";
			}
			else
			{
			    # in-order traversal of template fragment
			    # directories 
			    %template_hash =
				(%template_hash, 
				    merge_templates ($file, 
					@{ [ "$source/$filename" ] })
			    );	
			}
		    }
		}
		closedir(DIR);
	    }
	    else 
	    { 
		next;
	    }
	}
	%template_hash;
    }
	 
    # if template hash is empty produce an error 
    unless (scalar %template_hash) 
    {
	die "No templates were found for $target/$filename.\n";
    }

    #####################################################
    # Process the template fragments and build the target
    #####################################################

    # sort subroutine for use by 'sort' function to order template fragments
    sub template_order 
    {
	my $file_a = basename($a);
	my $file_b = basename($b);
	if ($file_a eq "template-begin" 
	    || $file_b eq "template-end") { -1; }
	elsif ($file_a eq "template-end" 
	    || $file_b eq "template-begin") { 1; }
	else { $file_a cmp $file_b; }
    }
    # need a package level increment to assign
    # each template a unique package namespace
    {
        no strict;
        $TEMPLATE_COUNT++;
    }

    # expand the template fragments into the target file
    foreach my $key (sort template_order keys %template_hash) 
    {
	my $filepath = $template_hash{$key};

	# Text::Template doesn't like zero length files so skip them
	unless (-s "$filepath") { next }

	if (($p{'CONFREF'}{'DebugTemplateExpansion'})
	    && ($p{'CONFREF'}{'DebugTemplateExpansion'}  eq 'enabled') )
	{
	    print "Expanding template fragment $filepath\n";
	}
	local $SIG{__WARN__} = sub { print STDERR "In $filepath: $_[0]"; };
	{
            # create unique package namespace for this template
	    # namespace is used by all template fragments
	    my $pkg;
            { 
                no strict;
                $pkg = "esmith::__TEMPLATE__::${TEMPLATE_COUNT}";
            }

	    # prime the package namespace 
	    # use statements will only be run once per template
	    eval " 
	    	package $pkg;
	    	use esmith::db;
	    ";
            # process the templates
	    fill_in_file ("$filepath",
		HASH    => { confref => \$p{'CONFREF'}, %{$p{'CONFREF'}} },
		PACKAGE => $pkg, 
		OUTPUT  => \*$fh)
	    || die "\t\t[ ERROR ]\nCannot process template $filepath: $!\n";
       }
    }
    # This should close the file descripter AND file handle 
    close $fh;

    # set OUTPUT_FILENAME to TEMPLATE_PATH if it wasn't explicitly set
    unless ($p{'OUTPUT_FILENAME'})
    {
	# if OUTPUT_FILENAME exists, it holds an array of target filenames
	$p{'OUTPUT_FILENAME'} = $p{'TEMPLATE_PATH'};
    }

    # don't need to back up old target file; rename is an atomic operation
    # (actually Tony, it's not :-))
    # make filename point to new inode
    my $outputfile = $p{'OUTPUT_FILENAME'};
    rename ("$target/$filename.$$", "$target/$outputfile")
	or die ("Could not rename $target/$filename.$$ " .
	    "to $target/$outputfile\n");
    # copy any additional files

    # We aren't interested in any of the old copies or proposed new
    # copies that RPM leaves lying around. Tidy up - remove them.
 
    -f "$target/$filename.rpmsave" and unlink "$target/$filename.rpmsave";
    -f "$target/$filename.rpmnew" and unlink "$target/$filename.rpmnew";
}

#------------------------------------------------------------

=pod

=head2 chownfile($user, $group, $file)

This routine changes the ownership of a file, automatically converting
usernames and groupnames to UIDs and GIDs respectively.

=cut
 
sub chownFile ($$$)
{
    my ($user, $group, $file) = @_;

    unless (-e $file)
    {
	warn("can't chownFile $file: $!\n");
	return;
    }
    my $uid = defined $user ? getpwnam ($user) : stat($file)->uid;
    my $gid = defined $group ? getgrnam ($group) : stat($file)->gid;

    chown ($uid, $gid, $file);
}

=pod

=head2 determineRelease()

Returns the current release version of the software. 

=cut

sub determineRelease()
{
    my $release = "(unknown version)";

    my @rpmCommand = qw(/bin/rpm -q e-smith-release);

    my $pid = open(RES, "-|"); # perldoc perlipc

    if ($pid) # parent
    {
        my $value = <RES>;
        chomp($value);
        if ($value =~ /e-smith-release-([^-]*)-(.*)/ )
        {
            $release = $1;
        }
    }
    else
    {
        exec @rpmCommand;
        die "exec of @rpmCommand failed";
    }

    close RES || die "Closing rpm query failed: $! $?";

    return $release;
}

=pod

=head1 NETWORK ADDRESS TRANSLATION UTILITIES

=head2 IPquadToAddr($ip)

Convert IP address from "xxx.xxx.xxx.xxx" notation to a 32-bit
integer.

=cut

sub IPquadToAddr ($)
{
    my ($quad) = @_;
    if ($quad =~  /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
    {
        return ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;
    }
    return 0;
}

=pod

=head2 IPaddrToQuad($address)

Convert IP address from a 32-bit integer to "xxx.xxx.xxx.xxx"
notation.

=cut

sub IPaddrToQuad ($)
{
    my ($addrBits) = @_;
    return sprintf ("%d.%d.%d.%d", ($addrBits >> 24) & 0xff,
			($addrBits >> 16) & 0xff,
			($addrBits >> 8) & 0xff,
			$addrBits & 0xff);
}

=pod

=head2 IPaddrToBackwardQuad($address)

Convert IP address from a 32-bit integer to reversed
"xxx.xxx.xxx.xxx.in-addr.arpa" notation for BIND files.

=cut

sub IPaddrToBackwardQuad ($)
{
    my ($addrBits) = @_;
    return sprintf ("%d.%d.%d.%d.in-addr.arpa.", $addrBits & 0xff,
				($addrBits >> 8) & 0xff,
				($addrBits >> 16) & 0xff,
				($addrBits >> 24) & 0xff);
}

=pod

=head2 computeNetworkAndBroadcast($ipaddr, $netmask)

Given an IP address and netmask (both in "xxx.xxx.xxx.xxx" format)
compute the network and broadcast addresses and output them in the
same format.

=cut

sub computeNetworkAndBroadcast ($$)
{
    my ($ipaddr, $netmask) = @_;

    my $ipaddrBits  = IPquadToAddr ($ipaddr);
    my $netmaskBits = IPquadToAddr ($netmask);

    my $network   = IPaddrToQuad ($ipaddrBits & $netmaskBits);
    my $broadcast = IPaddrToQuad ($ipaddrBits | (~ $netmaskBits));

    return ($network, $broadcast); 
}

=pod

=head2 computeLocalNetworkPrefix($ipaddr, $netmask)

Given an IP address and netmask, the computeLocalNetworkPrefix
function computes the network prefix for local machines.

i.e. for an IP address of 192.168.8.4 and netmask of 255.255.255.0,
this function will return "192.168.8.".

This string is suitable for use in configuration files (such as
/etc/proftpd.conf) when the more precise notation

    xxx.xxx.xxx.xxx/yyy.yyy.yyy.yyy

is not supported.

=cut

sub computeLocalNetworkPrefix ($$)
{
    my ($ipaddr, $netmask) = @_;

    my $ipaddrBits  = IPquadToAddr ($ipaddr);
    my $netmaskBits = IPquadToAddr ($netmask);

    # check for class A IP address
    if (($netmaskBits & 0xffffff) == 0)
    {
	return sprintf ("%d.", ($ipaddrBits >> 24) & 0xff);
    }

    # check for class B IP address
    if (($netmaskBits & 0xffff) == 0)
    {
	return sprintf ("%d.%d.", ($ipaddrBits >> 24) & 0xff,
		                  ($ipaddrBits >> 16) & 0xff);
    }

    # check for class C IP address
    if (($netmaskBits & 0xff) == 0)
    {
	return sprintf ("%d.%d.%d.", ($ipaddrBits >> 24) & 0xff,
		                     ($ipaddrBits >> 16) & 0xff,
		                     ($ipaddrBits >> 8) & 0xff);
    }

    # Bummer. This subnet cannot be described in prefix notation so
    # we'll have to return the entire IP address.

    return $ipaddr;
}


=pod

=head2 computeLocalNetworkShortSpec($ipaddr, $netmask)

Given an IP address and netmask, the computeLocalNetworkShortSpec
function computes a valid xxx.xxx.xxx.xxx/yyy specifier where yyy
is the number of bits specifying the network.

i.e. for an IP address of 192.168.8.4 and netmask of 255.255.255.0,
this function will return "192.168.8.0/24".

This string is suitable for use in configuration files (such as
/etc/proftpd.conf) when the more precise notation

    xxx.xxx.xxx.xxx/yyy.yyy.yyy.yyy

is not supported.

NOTE: This code only handles standard class A, B or C networks.

=cut

sub computeLocalNetworkShortSpec ($$)
{
    my ($ipaddr, $netmask) = @_;

    my %netmask2bits = ( "255.255.255.255" => 32,
			 "255.255.255.254" => 31,
			 "255.255.255.252" => 30,
			 "255.255.255.248" => 29,
			 "255.255.255.240" => 28,
			 "255.255.255.224" => 27,
			 "255.255.255.192" => 26,
			 "255.255.255.128" => 25,
			 "255.255.255.0"   => 24,
			 "255.255.254.0"   => 23,
			 "255.255.252.0"   => 22,
			 "255.255.248.0"   => 21,
			 "255.255.240.0"   => 20,
			 "255.255.224.0"   => 19,
			 "255.255.192.0"   => 18,
			 "255.255.128.0"   => 17,
			 "255.255.0.0"     => 16,
			 "255.254.0.0"     => 15,
			 "255.252.0.0"     => 14,
			 "255.248.0.0"     => 13,
			 "255.240.0.0"     => 12,
			 "255.224.0.0"     => 11,
			 "255.192.0.0"     => 10,
			 "255.128.0.0"     => 9,
			 "255.0.0.0"       => 8,
			 "254.0.0.0"       => 7,
			 "252.0.0.0"       => 6,
			 "248.0.0.0"       => 5,
			 "240.0.0.0"       => 4,
			 "224.0.0.0"       => 3,
			 "192.0.0.0"       => 2,
			 "128.0.0.0"       => 1,
			 "0.0.0.0"         => 0
			);

    my $ipaddrBits  = IPquadToAddr ($ipaddr);
    my $netmaskBits = IPquadToAddr ($netmask);

    my $network   = IPaddrToQuad ($ipaddrBits & $netmaskBits);

    return "$network/$netmask2bits{$netmask}";
}

=pod 

=head2 computeLocalNetworkSpec($ipaddr, $netmask)

Given an IP address and netmask, the computeLocalNetworkSpec function
computes a valid xxx.xxx.xxx.xxx/yyy.yyy.yyy.yyy specifier.

=cut

sub computeLocalNetworkSpec ($$)
{
    my ($ipaddr, $netmask) = @_;

    my $ipaddrBits  = IPquadToAddr ($ipaddr);
    my $netmaskBits = IPquadToAddr ($netmask);

    # check for all-ones netmask
    if (($netmaskBits & 0xffffffff) == 0xffffffff)
    {
	return IPaddrToQuad ($ipaddrBits);
    }

    return IPaddrToQuad ($ipaddrBits) . "/" . IPaddrToQuad ($netmaskBits);
}

=pod 

=head2 computeNetmaskFromBits ($bits)

Given a number of bits of network address, calculate the appropriate
netmask.

=cut

sub computeNetmaskFromBits ($)
{
    my ($ones) = @_;

    my $netmask = 0;
    my $zeros = 32 - $ones;

    while ($ones--)
    {
	$netmask <<= 1;
	$netmask |= 1;
    }

    while ($zeros--)
    {
	$netmask <<= 1;
    }
    esmith::util::IPaddrToQuad ($netmask);
}

=pod 

=head2 computeLocalNetworkReversed($ipaddr, $netmask)

Given an IP address and netmask, the computeLocalNetworkReversed
function computes the appropriate DNS domain field.
 
NOTE: The return value is aligned to the next available byte boundary, i.e. 

     192.168.8.4/255.255.255.0 returns "4.168.192.in-addr.arpa."
     192.168.8.4/255.255.252.0 returns "168.192.in-addr.arpa."
     192.168.8.4/255.255.0.0   returns "168.192.in-addr.arpa."
     192.168.8.4/255.252.0.0   returns "192.in-addr.arpa."
     192.168.8.4/255.0.0.0     returns "192.in-addr.arpa."

This string is suitable for use in BIND configuration files.

=cut

sub computeLocalNetworkReversed ($$)
{
    my ($ipaddr, $netmask) = @_;

    my @addressBytes = split(/\./, $ipaddr);
    my @maskBytes = split(/\./, $netmask);
   
    my @result;

    push(@result, "in-addr.arpa.");

    foreach ( @maskBytes )
    {
          last unless ($_ eq "255");

          unshift(@result, shift(@addressBytes));
    }

    return join('.', @result);
}

=pod

=head2 computeLocalAccessSpec ($ipaddr, $netmask, %networks [,$access])

Given a network specification (IP address and netmask), and a reference to
a networks database, compute the network/netmask entries which are to
treated as local access.

There is also an optional access parameter which can further restrict 
the values returned. If C<access> is C<localhost>, this routine will only
return a single value, equating to access from localhost only.

If called in scalar context, the returned string is suitable for 
use in /etc/hosts.allow, smb.conf and httpd.conf, for example:

127.0.0.1 192.168.1.1/255.255.255.0

Note: The elements are space separated, which is suitable for use in
hosts.allow, smb.conf and httpd.conf. httpd.conf does not permit 
comma separated lists in C<allow from> directives.

If called in list context, returns the array of network/netmask strings.

=cut

sub computeLocalAccessSpec ($$%;$)
{
    my ($ipaddr, $netmask, $networksRef, $access) = @_;

    $access = "private" unless ( defined $access );

    my ($network, $broadcast) =
	esmith::util::computeNetworkAndBroadcast ($ipaddr, $netmask);

    my @localAccess = ( "127.0.0.1" );

    if ( $access eq "localhost" )
    {
	# Nothing more to do
    }
    elsif ( $access eq "private" )
    {
        push @localAccess, "$network/$netmask";

        my @networks = grep { db_get_type($networksRef, $_) eq 'network' } 
				keys %$networksRef;

        foreach my $network ( @networks )
        {
	    my $mask = db_get_prop($networksRef, $network, 'Mask');

	    push(@localAccess, 
	        esmith::util::computeLocalNetworkSpec($network, $mask) );
        }
    }
    elsif ( $access eq "public" )
    {
        push @localAccess, "ALL";
    }
    else
    {
	warn "computeLocalAccessSpec: unknown access value $access\n";
    }

    return wantarray ? @localAccess : "@localAccess";
}

=pod

=head2 computeHostsAllowSpec ( 
	NAME=>serviceName,
	[ DAEMON=>daemonName, ]
	SERVICES=>\%services,
	NETWORKS=>\%networks
	IPADDR=>ipaddress,
	NETMASK=>netmask,
	)

Given a service, return the string suitable for /etc/hosts.allow,
checking to see if the service is defined, whether it is enabled and
whether access is set to public, private, or localhost. For example, one 
of the following:

# smtpd is not defined in the configuration database
# smtpd is disabled in the configuration database
smtpd: 127.0.0.1
smtpd: 127.0.0.1 192.168.1.1/255.255.255.0
smtpd: ALL

In array, context, the zeroth element is the tag, and the other elements are
the matching network entries

And here's the hosts.allow fragment:

{
    my %networks;
    tie %networks, 'esmith::config', '/home/e-smith/networks';

    $OUT = esmith::util::computeHostsAllowSpec(
        NAME=>'smtpd',
        SERVICES=>{ smtpd => $smtpd },
        NETWORKS=>\%networks,
        IPADDR=>$LocalIP,
        NETMASK=>$LocalNetmask );
}

=cut

sub computeHostsAllowSpec(%)
{
    my %params = @_;

    unless ( defined $params{'DAEMON'} )
    {
	$params{'DAEMON'} = $params{'NAME'};
    }

    my $status = db_get_prop( $params{'SERVICES'}, $params{'NAME'}, "status");

    unless ( defined $status )
    {
	return "# $params{'NAME'} is not defined in the configuration database";
    }

    unless ( $status eq "enabled" )
    {
	return "# $params{'NAME'} is disabled in the configuration database";
    }

    my $access = db_get_prop($params{'SERVICES'}, $params{'NAME'}, "access") ||
	 "private";

    my @spec = ( "$params{'DAEMON'}:", esmith::util::computeLocalAccessSpec(
		$params{'IPADDR'},
		$params{'NETMASK'},
		$params{'NETWORKS'},
		$access ) );

    return wantarray ? @spec : "@spec";
}

=pod

=head2 computeHostRange($ipaddr, $netmask)

Given a network specification (IP address and netmask), compute
the total number of hosts in that network, as well as the first
and last IP addresses in the range.

=cut

sub computeHostRange ($$)
{
    my ($ipaddr, $netmask) = @_;

    my $ipaddrBits   = IPquadToAddr ($ipaddr);
    my $netmaskBits  = IPquadToAddr ($netmask);
    my $hostmaskBits = ((~ $netmaskBits) & 0xffffffff);

    my $firstAddrBits = $ipaddrBits & $netmaskBits;
    my $lastAddrBits  = $ipaddrBits | $hostmaskBits;

    my $totalHosts = 1;
    
    for ( ; $hostmaskBits; $hostmaskBits /= 2)
    {
	if (($hostmaskBits & 0x1) == 0x1)
	{
	    $totalHosts *= 2;
	}
    }

    return ($totalHosts, IPaddrToQuad ($firstAddrBits), IPaddrToQuad ($lastAddrBits));
}

=pod

=head2 ldapBase($domain)

Given a domain name such as foo.bar.com, generate the
LDAP base name "dc=foo,dc=bar,dc=com".

=cut

sub ldapBase ($)
{
    my ($domainName) = @_;
    $domainName =~ s/\./,dc=/g; 
    return "dc=" . $domainName;
}

=pod

=head2 backgroundCommand($delaySec, @command)

Run command in background after a specified delay.

=cut

sub backgroundCommand ($@)
{
    my ($delaySec, @command) = @_;

    # now would be a good time to flush output buffers, so the partial
    # buffers don't get copied

    $| = 1;
    print "";

    # create child process
    my $pid = fork;

    # if fork failed, bail out
    die "Cannot fork: $!" unless defined ($pid);

    # If fork succeeded, make parent process return immediately.
    # We are not waiting on the child, so it will become a zombie
    # process when it completes. However, this subroutine is only
    # intended for use by the e-smith signal-event program, which
    # doesn't run very long. Once the parent terminates, the zombie
    # will become owned by "init" and will be reaped automatically.

    return if ($pid);

    # detach ourselves from the terminal
    setsid || die "Cannot start a new session: $!";

    # change working directory
    chdir "/";

    # clear file creation mask
    umask 0;

    # close STDIN, STDOUT, and STDERR
    close STDIN;
    close STDOUT;
    close STDERR;

    # reopen stderr, stdout, stdin
    open (STDIN, '/dev/null');

    my $loggerPid = open(STDOUT, "|-");
    die "Can't fork: $!\n" unless defined $loggerPid;

    unless ($loggerPid)
    {
	exec qw(/usr/bin/logger -p local1.info -t e-smith-bg);
    }

    open (STDERR, '>&STDOUT');

    # make child wait for specified delay.
    sleep $delaySec;

    # execute command
    exec { $command[0] } @command;
}

=pod

=head1 PASSWORD UTILITIES

Low-level password-changing utilities. These utilities each
change passwords for a single underlying password database,
for example /etc/passwd, /etc/smbpasswd, etc.

=head2 setUnixPassword($username, $password)

Set Unix password

=cut

sub setUnixPassword ($$)
{
    my ($username, $password) = @_;
    my $success = 0;

    my $autoPasswdProg = '/usr/bin/autopassword';
    
    my $pid = open(RES, "-|"); # perldoc perlipc

    if ($pid) # parent
    {
	while (<RES>)
	{
	    if (/^\+RESULT Password changed successfully.$/)
	    {
		$success = 1;
	    }
	}
    }
    else
    {
	exec $autoPasswdProg, $username, $password, $password;
	die "exec of '$autoPasswdProg $username pass pass' failed: $!";
    }

    if ($success == 0)
    {
	die "Failed to set Unix password for account $username.\n";
    }

    return 1;  # success
}

=pod

=head2 setUnixPasswordRequirePrevious($username, $oldpassword, $newpassword)

Set Unix password but require previous password for authentication.

=cut

# setUnixPasswordRequirePrevious is left as an exercise for the reader :-)
sub setUnixPasswordRequirePrevious ($$$)
{
    my ($username, $oldpassword, $newpassword) = @_;
    my $success = 0;

    my $autoPasswdProg = '/usr/bin/autopassword';
    
    my $pid = open(RES, "-|"); # perldoc perlipc

    if ($pid) # parent
    {
	while (<RES>)
	{
	    if (/^\+RESULT Password changed successfully.$/)
	    {
		$success = 1;
	    }
	}
    }
    else
    {
	exec $autoPasswdProg,
	    $username, $oldpassword, $newpassword, $newpassword;
	die "exec of '$autoPasswdProg $username old new new' failed: $!";
    }

    if ($success == 0)
    {
	die "Failed to set Unix password for account $username.\n";
    }

    return 1;  # success
}

=pod

=head2 setSambaPassword($username, $password)

Set Samba password

=cut

sub setSambaPassword ($$)
{
    my ($username, $password) = @_;

    #----------------------------------------
    # then set the password
    #----------------------------------------

    my $smbPasswdProg = '/usr/bin/smbpasswd';
    # see perldoc perlipc (search for 'Safe Pipe Opens')
    my $pid = open(DISCARD, "|-");

    if ($pid) # parent
    {
	print DISCARD "$password\n$password\n";
	close(DISCARD) || die "Child exited early.";
    }
    else # child
    {
	my $retval = system("$smbPasswdProg -a -s $username >/dev/null");
	($retval/256) &&
	    die "Failed to set Samba password for account $username.\n";
	exit 0;
    }

    my $retval = system("$smbPasswdProg -e -s $username >/dev/null");
    ($retval/256) &&
	die "Failed to enable Samba account $username.\n";

    return 1;  # success
}

=pod

=head2 cancelSambaPassword($username)

Cancel Samba password

=cut

sub cancelSambaPassword ($)
{
    my ($username) = @_;

    #----------------------------------------
    # Gordon Rowell <gordonr@e-smith.com> June 7, 2000
    # We really should maintain old users, which would mean we can just use
    # smbpasswd -d, but the current policy is to remove them. If we are
    # doing that (see below), there is no need to disable them first.
    #----------------------------------------
#    my $discard = `/usr/bin/smbpasswd -d -s $username`;
#    if ($? != 0)
#    {
#	die "Failed to disable Samba account $username.\n";
#    }

    #----------------------------------------
    # Delete the smbpasswd entry. If we don't, re-adding the same
    # username will result in a mismatch of UIDs between /etc/passwd
    # and /etc/smbpasswd
    #----------------------------------------
    # Michael Brader <mbrader@stoic.com.au> June 2, 2000
    # We have a locking problem here.
    # If two copies of this are run at once you could see your entry reappear
    # Proposed solution (file locking):

    # If we do a 'use Fcntl, we'll probably get the locking constants
    # defined, but for now:

    # NB. hard to test

    my $LOCK_EX = 2;
    my $LOCK_UN = 8;

    my $smbPasswdFile = '/etc/smbpasswd';

    open(RDWR, "+<$smbPasswdFile") || # +< == fopen(path, "r+",...
	die "Cannot open file $smbPasswdFile: $!\n";

    my $nolock = 1;
    my $attempts;
    for ($attempts = 1;
	 ($attempts <= 5 && $nolock);
	 $attempts++)
    {
	if (flock(RDWR, $LOCK_EX))
	{
	    $nolock = 0;
	}
	else
	{
	    sleep $attempts;
	}
    }

    $nolock && die "Could not get exclusive lock on $smbPasswdFile\n";

    my $outputString = '';
    while (<RDWR>)
    {
	(/^$username:/) || ($outputString .= $_);
    }

    # clear file and go to beginning
    truncate(RDWR, 0) || die "truncate failed"; # not 'strict' safe why???
    seek(RDWR, 0, 0) || die "seek failed";
    print RDWR $outputString;
    flock(RDWR, $LOCK_UN)
	|| warn "Couldn't remove exclusive lock on $smbPasswdFile\n";
    close RDWR || die "close failed";

    chmod 0600, $smbPasswdFile;

    return 1;  # success
}

=pod

=head2 LdapPassword()

Returns the LDAP password from the file C</etc/openldap/ldap.pw>.
If the file does not exist, a suitable password is created, stored
in the file, then returned to the caller.

Returns undef if the password could not be generated/retrieved.

=cut

sub genLdapPassword ()
{
    # Otherwise generate a suitable new password, store it in the
    # correct file, and return it to the caller.

    use MIME::Base64 qw(encode_base64);

    unless ( open(RANDOM, "/dev/random") )
    {
	warn "Could not open /dev/random: $!";
	return undef;
    }

    my $buf = "not set";
    # 57 bytes is a full line of Base64 coding, and contains
    # 456 bits of randomness - given a perfectly random /dev/random
    if (read(RANDOM, $buf, 57) != 57)
    {
	warn("Short read from /dev/random: $!");
	return undef;
    }
    close RANDOM;

    my $umask = umask 0077;
    my $password = encode_base64($buf);

    unless ( open (WR, ">/etc/openldap/ldap.pw") )
    {
	warn "Could not write LDAP password file.\n";
	return undef;
    }

    print WR $password;
    close WR;
    umask $umask;

    chmod 0600, "/etc/openldap/ldap.pw";

    return $password;
}

sub LdapPassword ()
{
    # Read the password from the file /etc/openldap/ldap.pw if it
    # exists.
    if ( -f "/etc/openldap/ldap.pw" )
    {
	open (LDAPPW, "</etc/openldap/ldap.pw") ||
	    die "Could not open LDAP password file.\n";
	my $password = <LDAPPW>;
	chomp $password;
	close LDAPPW;
	return $password;
    }
    else
    {
	return genLdapPassword();
    }
}


=pod

=head1 HIGH LEVEL PASSWORD UTILITIES

High-level password-changing utilities. These utilities
each change passwords for a single e-smith entity (system,
user or ibay). Each one works by calling the appropriate
low-level password changing utilities.

=head2 setUnixSystemPassword($password)

Set the e-smith system password

=cut

sub setUnixSystemPassword ($)
{
    my ($password) = @_;
    
    setUnixPassword   ("root",  $password);
    setUnixPassword   ("admin", $password);
}

=pod

=head2 setServerSystemPassword($password)

Set the samba administrator password.

=cut

sub setServerSystemPassword ($)
{
    my ($password) = @_;

    setSambaPassword  ("admin", $password);
}

=pod

=head2 setUserPassword($username, $password)

Set e-smith user password

=cut

sub setUserPassword ($$)
{
    my ($username, $password) = @_;

    setUnixPassword   ($username, $password);
    setSambaPassword  ($username, $password);
}

=pod

=head2 setUserPasswordRequirePrevious($username, $oldpassword, $newpassword)

Set e-smith user password - require previous password

=cut

sub setUserPasswordRequirePrevious ($$$)
{
    my ($username, $oldpassword, $newpassword) = @_;

    # if old password is not valid, this statement will call "die"
    setUnixPasswordRequirePrevious ($username, $oldpassword, $newpassword);

    # if we get this far, the old password must have been valid
    setSambaPassword  ($username, $newpassword);
}

=pod

=head2 cancelUserPassword

Cancel user password. This is called when a user is deleted from the
system. We assume that the Unix "useradd/userdel" programs are
called separately. Since "userdel" automatically removes the
/etc/passwd entry, we only need to worry about the /etc/smbpasswd
entry.

=cut

sub cancelUserPassword ($)
{
    my ($username) = @_;

    cancelSambaPassword ($username);
}

=pod

=head2 setIbayPassword($ibayname, $password)

Set ibay password

=cut

sub setIbayPassword ($$)
{
    my ($ibayname, $password) = @_;

    setUnixPassword ($ibayname, $password);
}

=pod

=head1 SERVICE MANAGEMENT UTILITIES

=head2 serviceControl()

Manage services - enable, disable, stop/start/restart/reload
Returns 1 for success, 0 if something went wrong

    serviceControl( 
        NAME=>serviceName, 
        ACTION=>enable[d]|disable[d]|delete|start|stop|restart|reload|graceful
        [ ORDER=>serviceOrdering (required for enable) ]
        [ BACKGROUND=>true|false (default is true) ]
    );

EXAMPLE:

    serviceControl( NAME=>'smtpfwdd', ACTION=>'enable', ORDER=>81 );

NOTES:

enable and disable both ensure that the Sxx script exists. We enable/disable
services as a property of the service. The 'd' at the end of enable/disable
is optional to simplify interworking with the services entries.

The BACKGROUND parameter is optional and can be set to false if
start/stop/restart/etc. is to be done synchronously rather than
with backgroundCommand()

BUGS:

=over 4

=item

We don't currently manage the Kxx scripts - that's up to the package itself

=item

The service name must match filename for the rc.d directory

=back

=cut

sub serviceControl
{
    my %params = @_;

    my $serviceName = $params{NAME};
    unless (defined $serviceName)
    {
	warn "serviceControl: NAME must be specified\n";
	return 0;
    }

    my $serviceAction = $params{ACTION};
    if (defined $serviceAction)
    {
	$serviceAction =~ s/(enable|disable)d?/$1/;
    }
    else
    {
	warn "serviceControl: ACTION must be specified\n";
	return 0;
    }

    my $startdir = "/etc/rc.d/rc7.d";

    my $initdir = "/etc/rc.d/init.d";
    my $initScript = "${initdir}/${serviceName}";

    my %conf;
    tie %conf, 'esmith::config';

    my $serviceOrder = $params{ORDER};

    if ( defined $serviceOrder )
    {
	unless (db_set_prop(\%conf, $serviceName, 'InitscriptOrder', 
					$serviceOrder))
	{
	    warn "serviceControl: Can't set InitscriptOrder of $serviceName";
	    return 0;
	}
    }

    if ( $serviceAction eq "enable" )
    {
	unless ( defined($serviceOrder) )
	{
	    warn "serviceControl: ORDER must be specified for enable\n";
	    return 0;
	}

    }
    else
    {
	$serviceOrder = db_get_prop(\%conf, $serviceName, 'InitscriptOrder');

	unless (defined $serviceOrder)
	{
	    warn "serviceControl: Couldn't get InitscriptOrder of $serviceName";
	    return 0;
	}
    }

    untie %conf;

    my $startScript = "${startdir}/S${serviceOrder}${serviceName}";

    my $metaScript  = "${initdir}/e-smith-service";

    if ( -f $metaScript )
    {
	$initScript = $metaScript;
    }

    unless ( -e "${initScript}" )
    {
	warn "serviceControl: ${initScript} does not exist\n";
	return 0;
    }

    if ( $serviceAction =~ /^(start|stop|restart|reload|graceful)$/ )
    {
	unless ( -e $startScript )
	{
	    warn "serviceControl: $startScript not found\n";
	    return 0;
	}

	my $background = $params{'BACKGROUND'} || 'true';

	if ($background eq 'true')
	{
	    backgroundCommand (0, $startScript, $serviceAction);
	}
	elsif ($background eq 'false')
	{
	    unless ( system($startScript, $serviceAction) == 0 )
	    {
		warn "serviceControl: Couldn't system($startScript, $serviceAction): $!\n";
		return 0;
	    }
	}
        else
        {
	    warn "serviceControl: Unsupported BACKGROUND=>$background: $!\n";
	    return 0;
        }

        return 1;
    }
    
    if ( $serviceAction =~ /^(en|dis)able$/ )
    {
        # We always want the initscript installed - the enable/disable
        # of the service is a property of the service

	unlink ($startScript);

	unless (symlink($initScript, $startScript))
	{
	    warn "serviceControl: Couldn't symlink($initScript, $startScript)\n";
	    return 0;
	}

	return 1; 
    }

    if ( $serviceAction eq "delete" )
    {
	if ( -e $startScript)
	{
	    unless (unlink($startScript))
	    {
		warn "serviceControl: Couldn't unlink existing ${startScript}\n";
		return 0;
	    }
	}
	return 1;
    }

    warn "serviceControl: Unknown serviceAction $serviceAction\n";

    0;
}

=pod

=head1 LOCALISATION SERVICES

=head2 translate($fm, @files)

$fm is the FormMagick object (so we can use it to call $fm->add_lexicon())
@files is the names of the translation files to add (usually this will be 
same name as the script in /etc/e-smith/web/functions that's calling this 
routine.  For instance, /etc/e-smith/web/functions/emailretrieval would 
usually call esmith::util::translate($fm, 'emailretrieval')

=cut

sub translate {
    my $fm = shift;
    my @files = @_;
    my $locale_dir = "/etc/e-smith/locale";

    my @langs = split(/, /, $ENV{HTTP_ACCEPT_LANG});

    foreach my $l (@langs) {
        my %lex;
        foreach my $f (@files) {
            open (TRANS, "$locale_dir/$l/$f");
            local $/ = "\n\n";
            warn "Can't open translation file $locale_dir/$l/$f";
                while (<TRANS>) {
                my ($base, $trans) = split "\n";
                chomp $base;
                chomp $trans;
                $lex{$base} = $trans;
            }
            close TRANS;
        }
        $fm->add_lexicon($l, \%lex);
    }
}

=pod

=head2 getLicenses()

Return all available licenses

In scalar context, returns one string combining all licenses
In array context, returns an array of individual licenses

=cut

sub getLicenses()
{
    my $dir = "/etc/e-smith/licenses";

    my @licenses;

    opendir(DIR, $dir) || die "Couldn't open licenses directory\n";

    foreach my $license ( readdir(DIR) )
    {
	my $file = "${dir}/${license}";

	next unless ( -f $file );

	open(LICENSE, $file) || die "Couldn't open license $file\n";

	push @licenses, <LICENSE>;

	close LICENSE;
    }

    return wantarray ? @licenses : "@licenses";
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

=head1 AUTHOR

e-smith, inc.

For more information, see http://www.e-smith.org/

=cut
