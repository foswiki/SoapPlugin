# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
# 
# SoapPlugin is Copyright (C) 2010-2012 Michael Daum http://michaeldaumconsulting.com
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
use warnings;

use Foswiki::Func ();    # The plugins API
use Foswiki::Attrs ();
use Error qw( :try );
use SOAP::Lite;# +trace => ['debug']; 
use Cache::FileCache ();
#use Data::Dumper ();

use constant DEBUG => 0; # toggle me
use constant DEFAULT_EXPIRE => 86400; # 24h

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

  $this->{cacheDir} = Foswiki::Func::getWorkArea("SoapPlugin")."/".$this->{id};
  mkdir $this->{cacheDir} unless -d $this->{cacheDir};

  writeDebug("cacheDir=$this->{cacheDir}");
  $this->{cache} = Cache::FileCache->new({
    cache_root => $this->{cacheDir},
    default_expires_in => DEFAULT_EXPIRE,
    }
  );

  return $this;
}

###############################################################################
sub soap {
  my $this = shift;

  unless ($this->{soap}) {
    writeDebug("creating soap object");
    if ($this->{wsdl}) {
      $this->{soap} = SOAP::Lite
        ->cache_dir($this->{cacheDir})
        ->service($this->{wsdl})
        ->autotype(1)
        ->readable(1)
      ;
      $this->{soap}->proxy($this->{proxy}) if defined $this->{proxy};
      $this->{soap}->uri($this->{uri}) if defined $this->{uri};
    } else {
      $this->{soap} = SOAP::Lite
        ->cache_dir($this->{cacheDir})
        ->uri($this->{uri})
        ->proxy($this->{proxy})
        ->autotype(1)
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
      #$this->{soap}->default_ns($this->{xmlns});
      $this->{soap}->serializer->namespace($this->{xmlns});
    }

    writeDebug("done creating soap");
  }

  return $this->{soap};
}

###############################################################################
sub onFaultHandler {
  my ($soap, $response) = @_;

  writeDebug("called onFaultHandler()");

  return if $soap->{_insideOnFaultHandler};
  $soap->{_insideOnFaultHandler} = 1;

  unless (defined $response) {
    writeDebug("got a transport error");
    #writeDebug($soap->transport->http_response->content);
    die($soap->transport->status);
  }

  if (ref($response)) {
    #writeDebug("response=".Data::Dumper->Dump([$response]));
    return $response;
  } else {
    writeDebug("Error: $response");
    die $response;
  }

  return new SOAP::SOM;
}

###############################################################################
sub parseParams {
  my ($this, $params, $result) = @_;

  $result ||= [];

  foreach my $key (sort keys %$params) {
    next if $key =~ /^(_.*|format|header|footer|separator|hidenull|method|verbatim|raw|valueof|id|warn|cache|expire|xslt)$/;
    my $val = $params->{$key};
    $key =~ s/^param\d+?_//;
    my $attrs = new Foswiki::Attrs($val);
    my $data;
    if (scalar(keys %$attrs)>2) {
      my @val = $this->parseParams($attrs);
      $data = SOAP::Data->name($key => \SOAP::Data->value(@val));
    } else {
      $data = SOAP::Data->name($key => $val);
    }
    
    push @$result, $data;
  }
  #print STDERR "data=".Data::Dumper->Dump([$result])."\n";

  return @$result;
}

###############################################################################
sub call {
  my ($this, $method, $params) = @_;

  $method ||= $this->{defaultMethod};
  writeDebug("called call($method)");

  my $som;
  my $error;

  my $expire = $params->{expire} || $params->{cache};
  my $useCache = Foswiki::Func::isTrue($params->{cache}, 0);

  my $cacheKey;

  if ($useCache) {
    $cacheKey = $this->_cacheKey($method, $params);

    my $query = Foswiki::Func::getCgiQuery();
    my $refresh = $query->param("refresh");
    if (defined($refresh) && ($refresh =~ /^(on|soap)$/)) {
      writeDebug("refreshing soap cache");
      $this->_cacheRemove($cacheKey);
    } else {
      $som = $this->_cacheGet($cacheKey);
    }

    if ($som) {
      writeDebug("found in cache");
      return ($som, $error);
    }
  } else {
    writeDebug("not using caching");
  }

  $currentClient = $this;

  my @params = $this->parseParams($params);

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

  $method = SOAP::Data->name($method);

  if ($this->{xmlns}) {
    #$method->uri($this->{xmlns});
    $method->attr({xmlns => $this->{xmlns}});
  }

  try {
    writeDebug("calling soap");
    $som = $this->soap->call($method, @params);
    if ($som->fault) {
      $error = $som->faultcode.' - '.$som->faultstring.' - '.$som->faultdetail;
      writeDebug($error);
    } else {
      writeDebug("success");
      $this->_cacheSet($cacheKey, $expire, $som) if $useCache;
    }

  } catch Error::Simple with {
    $error = shift;
    $error = $error->{'-text'};
    writeWarning("Error: $error");
    writeDebug("Error: $error");
    $error =~ s/ at .*$//s;
  };

  writeDebug("done call()");
  $currentClient = undef;

  return ($som, $error);
}

sub clearCache {
  my $this = shift;
  my $cache = $this->{cache};
  return unless defined $cache;

  writeCmisDebug("clearing cache");
  return $cache->clear(@_);
}
sub purgeCache {
  my $this = shift;
  my $cache = $this->{cache};
  return unless defined $cache;

  return $cache->purge(@_);
}

# internal cache layer
sub _cacheGet {
  my $this = shift;
  my $key = shift;

  my $cache = $this->{cache};
  return unless defined $cache;

  my $val = $cache->get($key, @_);

  return unless $val;

  $val = _untaint($val);

  my $som = SOAP::Deserializer->deserialize($val);

  $som->context($this->soap);
  $som->{_foswiki_content} = $val; # trick in the orig content

  return $som;
}

sub _cacheSet {
  my $this = shift;
  my $key = shift;
  my $expire = shift;
  my $som = shift;

  $expire = DEFAULT_EXPIRE unless defined $expire;

  my $cache = $this->{cache};
  return unless defined $cache;

  my $val = _untaint($som->context->transport->http_response->content);
  return $cache->set($key, $val, $expire);
}

sub _cacheRemove {
  my $this = shift;
  my $key = shift;

  my $cache = $this->{cache};
  return unless defined $cache;

  return $cache->remove($key, @_);
}

sub _cacheKey {
  my ($this, $method, $params) = @_;
  return _untaint($method.'-'.$params->stringify);
}

sub _untaint {
  my $content = shift;
  if (defined $content && $content =~ /^(.*)$/s) {
    $content = $1;
  }
  return $content;
}


1;
