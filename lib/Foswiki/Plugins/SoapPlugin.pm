# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# SoapPlugin is Copyright (C) 2010 Michael Daum http://michaeldaumconsulting.com
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

our $VERSION = '$Rev$';
our $RELEASE = '0.4';
our $SHORTDESCRIPTION = 'SOAP for Foswiki';
our $NO_PREFS_IN_TOPIC = 1;
our $baseWeb;
our $baseTopic;
our $doneInit;

###############################################################################
sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  Foswiki::Func::registerTagHandler('SOAP', \&SOAP);
  Foswiki::Func::registerTagHandler('SOAPFORMAT', \&SOAPFORMAT);

  $doneInit = 0;
  return 1;
}

###############################################################################
sub finishPlugin {
  return unless $doneInit;

  require Foswiki::Plugins::SoapPlugin::Core;
  Foswiki::Plugins::SoapPlugin::Core::finish();
}

###############################################################################
sub init {
  return if $doneInit;

  $doneInit = 1;

  require Foswiki::Plugins::SoapPlugin::Core;
  Foswiki::Plugins::SoapPlugin::Core::init($baseWeb, $baseTopic);
}

###############################################################################
sub SOAP {
  init();
  return Foswiki::Plugins::SoapPlugin::Core::handleSOAP(@_);
}

###############################################################################
sub SOAPFORMAT {
  init();
  return Foswiki::Plugins::SoapPlugin::Core::handleSOAPFORMAT(@_);
}

1;
