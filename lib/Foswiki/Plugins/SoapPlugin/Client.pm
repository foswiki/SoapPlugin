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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::SoapPlugin::Client;

use strict;
use Foswiki::Func ();    # The plugins API
use Error qw( :try );
use SOAP::Lite;# +trace => ['debug'];
 
use constant DEBUG => 0; # toggle me

use vars qw($currentClient);

###############################################################################
sub SOAP::Transport::HTTP::Client::get_basic_credentials {
  require Foswiki::Plugins::SoapPlugin::Client;
  my $currentClient = $Foswiki::Plugins::SoapPlugin::Client::currentClient;
  if ($currentClient && $currentClient->{user} && $currentClient->{password}) {
    return $currentClient->{user} => $currentClient->{password};
  }
}

###############################################################################
sub writeDebug {
  print STDERR "SoapPlugin::Client - $_[0]\n" if DEBUG;
}

###############################################################################
sub writeWarning {
  Foswiki::Func::writeWarning("SoapPlugin::Client - $_[0]");
}

###############################################################################
sub new {
  my $class = shift;

  my $this = {
    # TODO: defaults
    @_
  };

  bless($this, $class);

  return $this;
}

###############################################################################
sub soap {
  my $this = shift;


  unless ($this->{soap}) {
    writeDebug("creating soap object");
    if ($this->{wsdl}) {
      $this->{soap} = SOAP::Lite
        ->service($this->{wsdl})
        ->autotype(0)
        ->readable(1)
      ;
    } else {
      $this->{soap} = SOAP::Lite
        ->uri($this->{uri})
        ->proxy($this->{proxy})
        ->autotype(0)
        ->readable(1)
      ;
    }
    $this->{soap}->on_fault(\&onFaultHandler);

    foreach my $ns ($this->{namespaces}) {
      next unless $ns;
      writeDebug("registering namespace $ns->[0] for $ns->[1]");
      $this->{soap}->serializer->register_ns($ns->[1], $ns->[0]);
    }

    # foswiki namespace
    $this->{soap}->serializer->register_ns('http://schema.foswiki.org/soap', 'foswiki');

    if ($this->{xmlns}) {
      writeDebug("setting default_ns=$this->{xmlns}");
      $this->{soap}->default_ns($this->{xmlns})
    }

    writeDebug("done creating soap");
  }

  return $this->{soap};
}

###############################################################################
sub onFaultHandler {
  my ($soap, $response) = @_;

  writeDebug("called onFaultHandler");

  if (ref $response) {
    return $response;
  } else {
    writeDebug("got a transport error");
    die($soap->transport->status);
  }
  return new SOAP::SOM;
}

###############################################################################
sub call {
  my ($this, $method, $params) = @_;

  $method ||= $this->{defaultMethod};
  writeDebug("called call($method)");
  $currentClient = $this;

  my @params = ();
  foreach my $key (keys %$params) {
    next if $key =~ /^(_.*|format|header|footer|separator|hidenull|method|verbatim|raw|valueof)$/;
    my $data = SOAP::Data->new(
      name=>$key,
      value=>$params->{$key}
    );
    push @params, $data;
  }

  # foswiki header
  my $session = $Foswiki::Plugins::SESSION;
  my $wikiName = Foswiki::Func::getWikiName();
  my $userName = Foswiki::Func::wikiToUserName($wikiName);
  my $isAdmin = Foswiki::Func::isAnAdmin();
  my $webName = $session->{webName};
  my $topicName = $session->{topicName};

  push @params, 
    SOAP::Header->new(
      name=>'foswiki:wikiName',
      value=>$wikiName,
    ),
    SOAP::Header->new(
      name=>'foswiki:userName',
      value=>$userName,
    ),
    SOAP::Header->new(
      name=>'foswiki:isAdmin',
      value=>$isAdmin,
    ),
    SOAP::Header->new(
      name=>'foswiki:web',
      value=>$webName,
    ),
    SOAP::Header->new(
      name=>'foswiki:topic',
      value=>$topicName,
    );

  my $som;
  my $error;

  $method = SOAP::Data->name($method);

  if ($this->{xmlns}) {
    $method->uri($this->{xmlns});
  }

  try {
    $som = $this->soap->call($method, @params);
    writeDebug("success");
  } catch Error::Simple with {
    writeDebug("error");
    $error = shift;
    $error = $error->{'-text'};
    $error =~ s/ at .*$//s;
    writeDebug("Error during call: $error");
    writeWarning("Error during call: $error");
  };

  writeDebug("done call()");
  $currentClient = undef;

  return ($som, $error);
}

1;
