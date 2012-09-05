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

package Foswiki::Plugins::SoapPlugin::Core;

use strict;
use warnings;

use Foswiki::Plugins ();
use Foswiki::Func ();
use Encode ();;
use Foswiki::Plugins::SoapPlugin::Client();

use constant DEBUG => 0; # toggle me

##############################################################################
sub new {
  my ($class, $session) = @_;

  my $this = bless({
    session => $session,
  }, $class);

  foreach my $desc (@{$Foswiki::cfg{SoapPlugin}{Clients}}) {
    $this->createClient($desc);
  }
  
  return $this;
}

###############################################################################
sub createClient {
  my ($this, $desc) = @_;

  my $client = new Foswiki::Plugins::SoapPlugin::Client(%$desc);
  writeDebug("created client $client->{id}");

  return $this->client($client->{id}, $client);
}

###############################################################################
sub client {
  my ($this, $key, $value) = @_;

  $this->{clients}{$key} = $value if defined $value;
  return $this->{clients}{$key};
}

###############################################################################
sub handleSOAP {
  my ($this, $params, $theTopic, $theWeb) = @_;

  writeDebug("called handleSOAP()");
  
  my $theClient = $params->{_DEFAULT} || $params->{client} || '';
  normalizeParams($params);

  my $client = $this->client($theClient);
  return inlineError("Error: unknown client '$theClient'") unless $client;
  
  my $method = $params->{method} || $client->{defaultMethod};
  return inlineError("Error: no method") unless $method;

  my ($som, $error) = $client->call($method, $params);

  return inlineError("Error: $error") if $error;

  my $theId = $params->{id};
  $this->{knownSoms}{$theId} = $som if $theId;

  return '' if defined $theId && 
    !defined($params->{format}) &&
    !$params->{verbatim} &&
    !$params->{xslt};

  return formatResult($som, $params, $theWeb, $theTopic);
}

###############################################################################
sub handleSOAPFORMAT {
  my ($this, $params, $theTopic, $theWeb) = @_;

  normalizeParams($params);

  writeDebug("called handleSOAPFORMAT()");
  my $theId = $params->{_DEFAULT} || $params->{id};

  unless ($theId) {
    return '' unless $params->{warn};
    return inlineError("Error: no id");
  }

  my $som = $this->{knownSoms}{$theId};

  unless ($som) {
    return '' unless $params->{warn};
    return inlineError("Error: unknown som id '$theId'");
  }

  return formatResult($som, $params, $theWeb, $theTopic);
}


###############################################################################
# static
sub writeDebug {
  print STDERR "SoapPlugin::Core - $_[0]\n" if DEBUG;
}

##############################################################################
# static
sub inlineError {
  my $msg = shift;

  return "<span class='foswikiAlert'>$msg</span>";
}

###############################################################################
# static
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
    return inlineError("Error linting xml: ".$output);
  }

  $output =~ s/<\?.*?\?>[\n\r]?//g;

  return $output;
}

###############################################################################
# static
sub normalizeParams {
  my $params = shift;

  $params->{footer} ||= '';
  $params->{header} ||= '';
  $params->{separator} ||= '';
  $params->{hidenull} = Foswiki::Func::isTrue($params->{hidenull}, 0);
  $params->{raw} = Foswiki::Func::isTrue($params->{raw}, 0);
  $params->{verbatim} = Foswiki::Func::isTrue($params->{verbatim}, 0);
  $params->{warn} = Foswiki::Func::isTrue($params->{warn}, 1);
 
  return $params;
}

###############################################################################
# static
sub formatResult {
  my ($som, $params, $web, $topic) = @_;

  writeDebug("called formatResult");
  if ($params->{raw} || $params->{verbatim}) {
    my $content = $som->{_foswiki_content} || $som->context->transport->http_response->content;
    return $content if $params->{raw};
    $content = prettyPrint($content);
    $content =~ s/</&lt;/g;
    $content =~ s/>/&gt;/g;
    return '<pre class="html">'.$content.'</pre>';
  }

  my $result = stringify($som, $params);

  #print STDERR "1:$result=$result\n";

  if (defined $params->{xslt}) {
    my $xsltString = $params->{xslt};
    $xsltString =~ s/\$perce?nt/\%/go;
    $xsltString =~ s/\$nop\b//go;
    $xsltString =~ s/\$n/\n/go;
    $xsltString =~ s/\$dollar/\$/go;
    $xsltString = Foswiki::Func::expandCommonVariables($xsltString, $topic, $web);

    my $error;

    eval {
      require XML::LibXSLT;
      require XML::LibXML;

      my $xslt = XML::LibXSLT->new();
      my $style_doc = XML::LibXML->load_xml(string=>$xsltString, no_cdata=>1);
      my $stylesheet = $xslt->parse_stylesheet($style_doc);
      my $source = XML::LibXML->load_xml(string=>$result);
      $result = $stylesheet->transform($source);
      #$result = toSiteCharSet($stylesheet->output_as_bytes($result)) if defined $result;
      $result = $stylesheet->output_as_bytes($result) if defined $result;
      $result ||= '';
    };
    
    if ($@) {
      $error = $@;
    };

    return inlineError("Error: ".$error) if defined $error;
  }

  $result =~ s/\$perce?nt/\%/go;
  $result =~ s/\$nop\b//go;
  $result =~ s/\$n/\n/go;
  $result =~ s/\$dollar/\$/go;

  writeDebug("result=$result");

  return $result;
}

###############################################################################
# static
sub stringify {
  my ($som, $params, $data, $depth) = @_;

  $depth ||= 1;
  my $currentPath = $params->{valueof}||'';
  unless ($data) {
    my @data;
    @data = $som->dataof($currentPath);
    $som->match($currentPath);
    $data = \@data;
  };

  #writeDebug("called stringify(depth=$depth)");

  my $maxDepth = $params->{depth} || 10;
  return '' if $maxDepth < $depth;
  return '' unless defined $data;

  my @lines = ();

  #print STDERR "data=".Data::Dumper->Dump([$data])."\n";

  my $currentIndex = $params->{_index} || 1;
  foreach my $dataItem (@$data) {
    my $line = $params->{format};
    $line = '$value' unless defined $line;

    $line =~ s/\$(key|name)/fromUtf8($dataItem->name()||'')/ge;
    $line =~ s/\$type/fromUtf8($dataItem->type()||'')/ge;
    $line =~ s/\$uri/fromUtf8($dataItem->uri()||'')/ge;
    $line =~ s/\$prefix/fromUtf8($dataItem->prefix()||'')/ge;
    $line =~ s/\$attr\((.*?)\)/fromUtf8($dataItem->attr($1)||'')/ge;
    $line =~ s/\$index/$currentIndex/g;
    $line =~ s/\$depth/$depth/g;
    $line =~ s/\$valueof\((.*?)\)/fromUtf8($som->valueof($1||'')||'')/ge;

    if ($line =~ /\$value\b/) {
      my $value = $dataItem->value();
      $value = '' unless defined $value;

      my @values = ();
      if (!ref($value) || ref($value) eq "SCALAR") {
	push @values, $value;
      } elsif (ref($value) eq "ARRAY") {
	my $index = 1;
	foreach my $item (@$value) {
	  if (ref($item) eq "SCALAR") {
	    push @values, $item;
	  } else {
	    $params->{_index} = $index;
	    push @values, stringify($som, $params, [SOAP::Data->new(name=>$index, value=>$item)], $depth+1);
	    $index++;
	  }
	}
      } elsif (ref($value) eq "HASH") {
	my $index = 1;
	foreach my $key (keys %$value) {
	  $params->{_index} = $index;
	  push @values, stringify($som, $params, [SOAP::Data->new(name=>$key, value=>$value->{$key})], $depth+1);
	  $index++;
	}
      } elsif (ref($value) eq "REF") {
	push @values, ref($$value);
      } else {
	push @values, ref($value);
      }
      $value = fromUtf8(join('', @values));
      $line =~ s/\$value\b/$value/g;
    }

    $currentIndex++;
    push @lines, $line;
  }
  return '' if $params->{hidenull} && !@lines;

  return $params->{header}.join($params->{separator}, @lines).$params->{footer};
}

###############################################################################
# static
sub fromUtf8 {
  my $string = shift;

  my $charset = $Foswiki::cfg{Site}{CharSet};
  my $octets = Encode::decode('utf-8', $string);
  return Encode::encode($charset, $string);
}

###############################################################################
# static
sub toUtf8 {
  my $string = shift;

  my $charset = $Foswiki::cfg{Site}{CharSet};

  my $octets = Encode::decode($charset, $string);
  $octets = Encode::encode('utf-8', $octets);
  return $octets;

}

##############################################################################
# static
sub toSiteCharSet {
  return Encode::encode($Foswiki::cfg{Site}{CharSet}, $_[0]);
}
1;

