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

package esmith::cgi;

use strict;
use esmith::config;
use esmith::db;
use esmith::util;

BEGIN
{
}


=pod

=head1 NAME

esmith::cgi - Useful CGI routines for e-smith server and gateway

=head1 VERSION

This file documents C<esmith::cgi> version B<1.4.0>

=head1 SYNOPSIS

    use esmith::cgi;

=head1 DESCRIPTION

This module contains a collection of useful routines for working with
the e-smith manager's CGI interface.

=head1 WEB PAGE HEADER GENERATION ROUTINES

=head2 genHeaderNonCacheable($q, $confref, $title)

=cut

sub genHeaderNonCacheable ($$$)
{
    my ($q, $confref, $title) = @_;
    genHeader ($q, $confref, $title, '-20y', 1);
}

=pod

=head2 genHeaderCacheableNoPasswordCheck($q, $confref, $title)

=cut

sub genHeaderCacheableNoPasswordCheck ($$$)
{
    my ($q, $confref, $title) = @_;
    genHeader ($q, $confref, $title, '+1d', 0);
}

=pod

=head2 genHeaderCacheableNoPasswordCheck($q, $confref, $title)

=cut

sub genHeaderNonCacheableNoPasswordCheck ($$$)
{
    my ($q, $confref, $title) = @_;
    genHeader ($q, $confref, $title, '-20y', 0);
}

=pod

=head2 genHeader($q, $confref, $title, $expiry, $checkpassword)

=cut

sub genHeader ($$$$$)
{
    my ($q, $confref, $title, $expiry, $checkpassword) = @_;

    print $q->header (-EXPIRES => $expiry);

    genHeaderStartHTML ($q);

    print $q->table ({-BORDER      => "0",
		      -CELLSPACING => "0",
		      -CELLPADDING => "1",
		      -WIDTH       => "100%",
		      -ALIGN       => "LEFT"},
		     $q->Tr ({-VALIGN => "BOTTOM"},
			     $q->td ({-BACKGROUND 
				    => "/server-common/banner-shim.gif",},
				 $q->img ({-SRC    => $ENV{'IMGHDR_SRC'},
					   -BORDER => '0',
					   -ALT    => 'March Networks SME server manager'}))));
    print $q->br ({-CLEAR => 'ALL'});
    print $q->div ({-STYLE =>
			'position: absolute; visibility: inherit; top: 120px; left:' .
			    ' 16px; width: 85%; z-index: 2'});

    print '<FONT FACE="Helvetica,Arial">';

    if ($checkpassword)
    {
	if (defined db_get($confref ,'PasswordSet') &&
	    db_get($confref ,'PasswordSet') ne 'yes')
	{
	    print $q->div ({-STYLE => 'color: #FF3E00'},
			   $q->h5 ('Warning: you have not yet changed the default system password.'));
	}

	my $TelnetAccess = db_get_prop($confref, 'telnet', 'access');
        my $TelnetMode = db_get_prop($confref, 'telnet', 'status');
	if ($TelnetAccess eq 'public' && $TelnetMode eq 'enabled')
	{
	    print $q->div ({-STYLE => 'color: #FF3E00'},
			   $q->h5 ('Warning: the current security settings permit public telnet access.'));
	}
    }

    print $q->h2 ($title);
}

=pod

=head2 genNavigationHeader($q)

=cut

sub genNavigationHeader ($)
{
    my ($q) = @_;

    print $q->header (-EXPIRES => '-20y');

    genHeaderStartHTML ($q);

    if ((-f '/home/e-smith/web/common/edition/image.gif') && (-f '/home/e-smith/web/common/edition/info.txt'))
    {
	# first line of info file contains URL, second line contains ALT text:

	open (RD, "</home/e-smith/web/common/edition/info.txt");
	my $url = <RD>;
	my $alt = <RD>;
	close RD;

	print $q->table ({border => 0, cellspacing => 0, cellpadding => 0},
	    $q->Tr ($q->td
		($q->table ({border => 0, cellspacing => 0, cellpadding => 10},
		    $q->Tr ($q->td($q->a ({-HREF => $url, -TARGET => '_top'},
			$q->img ({-BORDER => '0',
				  -ALT    => $alt,
				  -ALIGN  => 'top',
				  -SRC    => '/server-brand/edition/image.gif'}))))))),
			$q->Tr ($q->td ($q->img ({-HEIGHT => '40',
					       -WIDTH  => '200',
					       -BORDER => '0',
					       -ALT    => $alt,
					       -ALIGN  => 'top',
					       -SRC    => '/server-common/special-edition.gif'}))));

	print $q->div ({-STYLE  => 'position: absolute; visibility: inherit; left: 16px; z-index: 2'});
    }
    else
    {
	print $q->a ({-HREF => 'http://www.e-smith.com/', -TARGET => '_top'},
		     $q->img ({-BORDER => '0',
			       -ALT    => 'March Networks Logo',
			       -ALIGN  => 'top',
			       -SRC    => '/server-common/march-networks-logo.gif'}));

	print $q->div ({-STYLE  => 'position: absolute; visibility: inherit; top: 120px; left: 16px; z-index: 2'});
    }
}

=pod

=head2 genNoframesHeader($q)

=cut

sub genNoframesHeader ($)
{
    my ($q) = @_;

    print $q->header (-EXPIRES => '-20y');
    genHeaderStartHTML ($q);
}

=pod

=head2 genHeaderStartHTML($q)

=cut

sub genHeaderStartHTML ($)
{
    my ($q) = @_;

    print $q->start_html (-TITLE        => 'March Networks SME Server manager',
			  -AUTHOR       => 'bugs@e-smith.com',
			  -META         => {'copyright' => 'Copyright 2001 Mitel Networks Corporation'},
			  -STYLE        =>
			      {-src => '/server-common/css/manager.css'},
			  -BGCOLOR      => '#FFFFFF',
			  -LINK         => '#707070',
			  -VLINK        => '#707070',
			  -ALINK        => '#707070',
			  -TEXT         => '#000000',
			  -MARGINWIDTH  => '0',
			  -MARGINHEIGHT => '0',
			  -LEFTMARGIN   => '0',
			  -TOPMARGIN    => '0');
}

=pod

=head1 WEB PAGE FOOTER GENERATION ROUTINES

=head2 genFooter($q)

=cut

sub genFooter ($)
{
    my ($q) = @_;
   
    my $release = esmith::util::determineRelease();

    print $q->p ($q->hr, $q->font ({size => "-1"},
        "March Networks SME Server V${release}<BR>" .
        "Copyright 2001 Mitel Networks Corporation.<BR>" .
	"All rights reserved.")
        );

    print '</FONT>';
    print '</DIV>';
    print $q->end_html;
}

=pod

=head2 genFooterNoCopyright($q)

=cut

sub genFooterNoCopyright ($)
{
    my ($q) = @_;

    print $q->p ($q->hr);

    print '</FONT>';
    print '</DIV>';
    print $q->end_html;
}

=pod

=head2 genNavigationFooter($q)

=cut

sub genNavigationFooter ($)
{
    my ($q) = @_;

    print '</DIV>';
    print $q->end_html;
}

=pod

=head2 genNoframesFooter($q)

=cut

sub genNoframesFooter ($)
{
    my ($q) = @_;

    print $q->end_html;
}

=pod

=head1 FONT ROUTINES

=head2 curFont()

Returns the preferred font faces eg. "Helvetica,Arial".

=cut

sub curFont ()
{
    return "Helvetica,Arial";
}

=pod

=head1 TABLE GENERATION ROUTINES

=head2 genCell($q, $text)

=cut

sub genCell ($$)
{
    my ($q, $text) = @_;

    if ($text =~ /^\s*$/)
    {
	$text = "&nbsp;"
    }

    return $q->td ($q->font ({face => "Helvetica,Arial"}, $text));
}

=pod

=head2 genDoubleCell($q, $text);

Generates a cell which spans two columns, containing the text specified.

=cut

sub genDoubleCell ($$)
{
    my ($q, $text) = @_;

    if ($text =~ /^\s*$/)
    {
	$text = "&nbsp;"
    }

    return $q->td ({colspan => 2}, $q->font ({face => "Helvetica,Arial"}, $text));
}

=pod

=head2 genSmallCell($q, $text)

Generates a cell with "small" text (font size -1).

=cut

sub genSmallCell ($$)
{
    my ($q, $text) = @_;

    if ($text =~ /^\s*$/)
    {
	$text = "&nbsp;"
    }

    return $q->td ($q->font ({size => -1, face => "Helvetica,Arial"}, $text));
}

=pod

=head2 genSmallRedCell($q, $text)

Generates a cell with "small" (font size -1) red text.

=cut

sub genSmallRedCell ($$)
{
    my ($q, $text) = @_;

    if ($text =~ /^\s*$/)
    {
	$text = "&nbsp;"
    }

    return $q->td
	($q->font ({size => -1, face => "Helvetica,Arial", color => "Red"},
		   $q->i ($text)));
}

=pod

=head2 genTextRow($q, $text)

Returns a table row containing a two-column cell containing $text.

=cut

sub genTextRow ($$)
{
    my ($q, $text) = @_;

    if ($text =~ /^\s*$/)
    {
	$text = "&nbsp;"
    }

    return $q->Tr ($q->td ({colspan => 2}, $q->font ({face => "Helvetica,Arial"}, $text)));
}

=pod

=head2 genButtonRow($q, $button)

Returns a table row containing an empty first cell and a second cell
containing a button with the value $button.

=cut

sub genButtonRow ($$)
{
    my ($q, $button) = @_;

    return $q->Tr ($q->td ('&nbsp;'),
		   $q->td ($q->font ({face => "Helvetica,Arial"}, $q->b ($button))));
}

=pod

=head2 genNameValueRow($q, $fieldlabel, $fieldname, $fieldvalue)

Returns a table row with two cells.  The first has the text
"$fieldlabel:" in it, and the second has a text field with the default
value $fieldvalue and the name $fieldname.

=cut

sub genNameValueRow ($$$$)
{
    my ($q, $fieldlabel, $fieldname, $fieldvalue) = @_;

    return $q->Tr ($q->td ($q->font ({face => "Helvetica,Arial"}, "$fieldlabel:")),
		   $q->td ($q->font ({face => "Helvetica,Arial"}, $q->textfield (-name     => $fieldname,
					  -override => 1,
					  -default  => $fieldvalue,
					  -size     => 32))));
}

=pod

=head2 genNamePasswordRow($q, $fieldlabel, $fieldname, $fieldvalue)

As for C<genNameValueRow()> above, but instead of a text field it
generates a password field so that user input is obscured.

Possible buglet: if $fieldvalue is given, the password field defaults to
this value, so the number of stars may indicate to the end-user what the 
previous value was.

=cut

sub genNamePasswdRow ($$$$)
{
    my ($q, $fieldlabel, $fieldname, $fieldvalue) = @_;

    return $q->Tr ($q->td ($q->font ({face => "Helvetica,Arial"}, "$fieldlabel:")),
		   $q->td ($q->font ({face => "Helvetica,Arial"}, $q->password_field (-name     => $fieldname,
					       -override => 1,
					       -default  => $fieldvalue,
					       -size     => 32))));
}

=pod

sub genWidgetRow($q, $fieldlabel, $popup)

=cut

sub genWidgetRow ($$$)
{
    my ($q, $fieldlabel, $popup) = @_;

    return $q->Tr ($q->td ($q->font ({face => "Helvetica,Arial"}, "$fieldlabel:")),
		   $q->td ($q->font ({face => "Helvetica,Arial"}, $popup)));
}

=pod 

=head1 STATUS AND ERROR REPORT GENERATION ROUTINES

=head2 genResult($q, $msg)

Generates a "status report" page, including the footer

=cut

sub genResult ($$)
{
    my ($q, $msg) = @_;

    print $q->p ($msg);
    genFooter ($q);
}

=pod

=head2 genStateError($q, $confref)

Subroutine to generate "unknown state" error message.

=cut

sub genStateError ($$)
{
    my ($q, $confref) = @_;

    genHeaderNonCacheable ($q, $confref, "Internal error");
    genResult ($q, "Internal error! Unknown state: " . $q->param ("state") . ".");
}

END
{
}

#------------------------------------------------------------
# return "1" to make the import process return success
#------------------------------------------------------------

1;

=pod

=head1 AUTHOR

March Networks Corporation

For more information, see http://e-smith.org/

=cut

