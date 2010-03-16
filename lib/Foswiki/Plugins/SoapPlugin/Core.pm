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

package Foswiki::Plugins::SoapPlugin::Core;

use strict;
use Foswiki::Plugins ();
use Foswiki::Plugins::SoapPlugin::Client();
our $baseWeb;
our $baseTopic;
our %clients;
our %knownSoms;

use constant DEBUG => 0; # toggle me

###############################################################################
sub writeDebug {
  print STDERR "SoapPlugin::Core - $_[0]\n" if DEBUG;
}

##############################################################################
sub init {
  ($baseWeb, $baseTopic) = @_;

  writeDebug("called init");

  foreach my $desc (@{$Foswiki::cfg{SoapPlugin}{Clients}}) {
    my $client = new Foswiki::Plugins::SoapPlugin::Client(%$desc);
    $clients{$client->{id}} = $client;
    writeDebug("created client $client->{id}");
  }
}

##############################################################################
sub finish {
  undef %clients;
  undef %knownSoms;
}

##############################################################################
sub inlineError {
  my $msg = shift;

  return "<span class='foswikiAlert'>Error: $msg </span>";
}

###############################################################################
sub prettyPrint {
  my $xml = shift;

  require File::Temp;
  require Foswiki::Sandbox;

  my $xmlInFile = new File::Temp(SUFFIX => '.xml');

  print $xmlInFile $xml;

  my $xmllintCmd = $Foswiki::cfg{SoapPlugin}{XmlLintCmd} || 
    '/usr/bin/xmllint --format %INFILE|F%';

  my ($output, $exit) = Foswiki::Sandbox->sysCommand(
    $xmllintCmd, 
    INFILE => $xmlInFile->filename,
  );

  if ($exit) {
    return inlineError("Error linting xml: "+$output);
  }

  $output =~ s/<\?.*?\?>[\n\r]?//g;

  return $output;
}

###############################################################################
sub handleSOAP {
  my ($session, $params, $theTopic, $theWeb) = @_;

  writeDebug("called handleSOAP()");
  
  my $theClient = $params->{_DEFAULT} || $params->{client} || '';
  normalizeParams($params);

  my $client = $clients{$theClient};
  return inlineError("unknown client '$theClient'") unless $client;
  
  my $method = $params->{method} || $client->{defaultMethod};
  return inlineError("no method") unless $method;

  my ($som, $error) = $client->call($method, $params);
  $error ||= '';

  return inlineError("Error during SOAP call $error") unless $som;

  my $theId = $params->{id};
  $knownSoms{$theId} = $som if $theId;

  return '' if defined $theId && 
    !$params->{format} &&
    !$params->{verbatim};

  return formatResult($som, $params);
}

###############################################################################
sub normalizeParams {
  my $params = shift;

  $params->{footer} ||= '';
  $params->{header} ||= '';
  $params->{separator} ||= '';
  $params->{hidenull} ||= 'off';
  $params->{hidenull}  = ($params->{hidenull} eq 'on')?1:0;
  $params->{raw} ||= 'off';
  $params->{raw}  = ($params->{raw} eq 'on')?1:0;
  $params->{verbatim} ||= 'off';
  $params->{verbatim}  = ($params->{verbatim} eq 'on')?1:0;
 
  return $params;
}

###############################################################################
sub formatResult {
  my ($som, $params) = @_;

  writeDebug("called formatResult");
  if ($params->{raw} || $params->{verbatim}) {
    my $content = $som->context->transport->http_response->content;
    return $content if $params->{raw};
    $content = prettyPrint($content);
    return '<verbatim>'.$content.'</verbatim>';
  }

  $som->match('//Envelope/Body');
  my @data = ($params->{valueof})?$som->valueof($params->{valueof}):$som->valueof();
  my $data = (scalar(@data) > 1)?\@data:$data[0];
  my $result = stringify($data, $params);

  $result =~ s/\$perce?nt/\%/go;
  $result =~ s/\$nop\b//go;
  $result =~ s/\$n/\n/go;
  $result =~ s/\$dollar/\$/go;

  #writeDebug("result=$result");

  return $result;
}

###############################################################################
sub handleSOAPFORMAT {
  my ($session, $params, $theTopic, $theWeb) = @_;

  normalizeParams($params);

  writeDebug("called handleSOAPFORMAT()");
  my $theId = $params->{_DEFAULT} || $params->{id};
  return inlineError("Error: no id") unless $theId;

  my $som = $knownSoms{$theId};

  return inlineError("Error: unknown som id '$theId'") unless $som;

  return formatResult($som, $params);
}

###############################################################################
sub stringify {
  my ($data, $params, $depth) = @_;

  $depth ||= 1;
  return '' if $params->{depth} && $params->{depth} < $depth;
  return '' unless defined $data;

  my @lines = ();
  if (ref(\$data) eq "SCALAR") {
    #writeDebug("SCALAR");
    return $data;
  } elsif (ref($data) eq "ARRAY") {
    #writeDebug("ARRAY");
    my $index = 1;
    foreach my $value (@$data) {
      my $line = $params->{format};
      $line = '$value' unless defined $line;
      $line =~ s/\$key/$index/g;
      $line =~ s/\$value/stringify($value, $params, $depth +1)/ge;
      $index++;
      push @lines, $line;
    }
  } elsif (ref($data) eq "HASH") {
    #writeDebug("HASH");
    foreach my $key (keys %$data) {
      my $line = $params->{format};
      $line = '$key=$value' unless defined $line;
      $line =~ s/\$key/$key/ge;
      $line =~ s/\$value/stringify($data->{$key}, $params, $depth +1)/ge;
      push @lines, $line;
    }
  }

  return '' if $params->{hidenull} && !@lines;
  return $params->{header}.join($params->{separator}, @lines).$params->{footer};
}

1;

