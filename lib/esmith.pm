#!/usr/bin/perl -w

package esmith;

require v5.6.0;
use strict;
use warnings;

our $VERSION = '1.70';

=head1 NAME

esmith -- a CPAN packaging of e-smith API modules

=head1 SYNOPSIS

    use esmith::db;
    use esmith::config;
    use esmith::util;
    use esmith::cgi;

=head1 DESCRIPTION

This is just a CPAN packaging of the standard e-smith modules.  It is
utterly unsupported, yada yada, and is released by me personally and not
by Mitel.

I did this so that it would be easy to install e-smith modules on other
systems to assist in development of add-on modules, blades, and so on.
If you find it useful, let me know.  If you have problems with it, I'd
suggest actually trying the same thing on an actual e-smith/SMEServer
box.  If you have problems there too, email the devinfo mailing list at
devinfo@lists.e-smith.org.  If the problem is just with my packaging,
well, I *said* it's unsupported, didn't I?

You really want to read the documentation for the other e-smith modules
to find out what everything does.

=head1 SEE ALSO

L<esmith::util>

L<esmith::cgi>

L<esmith::db>

L<esmith::config>

=head1 AUTHOR

Packaged by Kirrily "Skud" Robert <skud@cpan.org>

=cut
