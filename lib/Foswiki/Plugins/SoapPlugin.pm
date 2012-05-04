# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# SoapPlugin is Copyright (C) 2010-2011 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::SoapPlugin;

use strict;
use Foswiki::Func ();

our $VERSION           = '$Rev$';
our $RELEASE           = '2.00';
our $SHORTDESCRIPTION  = 'SOAP for Foswiki';
our $NO_PREFS_IN_TOPIC = 1;

our $core;

###############################################################################
sub initPlugin {

    Foswiki::Func::registerTagHandler(
        'SOAP',
        sub {
            my $session = shift;
            return getCore($session)->handleSOAP(@_);
        }
    );

    Foswiki::Func::registerTagHandler(
        'SOAPFORMAT',
        sub {
            my $session = shift;
            return getCore($session)->handleSOAPFORMAT(@_);
        }
    );

    $core = undef;
    return 1;
}

###############################################################################
sub getCore {

    unless ($core) {
        require Foswiki::Plugins::SoapPlugin::Core;
        $core = new Foswiki::Plugins::SoapPlugin::Core(@_);
    }

    return $core;
}

1;
