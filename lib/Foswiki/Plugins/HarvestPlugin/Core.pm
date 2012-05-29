# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# HarvestPlugin is Copyright (C) 2011-2012 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::HarvestPlugin::Core;

use strict;
use warnings;
use Foswiki::Contrib::JsonRpcContrib::Error ();
use Foswiki::AccessControlException ();
use Foswiki::Func ();
use Foswiki::Sandbox ();
use Digest::MD5 ();
use Error qw(:try);
use Encode ();
use URI ();

use constant DEBUG => 0; # toggle me

# Error codes for json-rpc response
# 1000: no url 
# 1001: invalid depth parameter
# 1002: error fetching url 
# 1003: error parsing content
# 1004: http error
# 1005: empty selection

=begin TML

---+ package HarvestPlugin::Core

---++ writeDebug($message(

prints a debug message to STDERR when this module is in DEBUG mode

=cut

sub writeDebug {
  print STDERR "HarvestPlugin::Core - $_[0]\n" if DEBUG;
}

=begin TML

---++ new($class, $baseWeb, $baseTopic)

constructor for the core

=cut

sub new {
  my ($class, $baseWeb, $baseTopic) = @_;

  my $workingDir = Foswiki::Func::getWorkArea('HarvestPlugin');

  my $this = bless({
    baseWeb => $baseWeb,
    baseTopic => $baseTopic,
    cacheRoot => $workingDir.'/cache',
    cacheExpire => "1 h",
  }, $class);

  return $this;
}

=begin TML

---++ DESTROY()

finalizer for the plugin core

=cut

sub DESTROY {
  # my $this = shift;
  # undef $this->{cache};
}

=begin TML

---++ printJSONRPC

DEPRECATED: use JsonRpcContrib instead

prints a json-rpc response 

=cut

sub printJSONRPC {
  my ($this, $response, $code, $text, $id) = @_;

  $response->header(
    -status  => $code?500:200,
    -type    => 'text/plain',
  );

  $id = 'id' unless defined $id;

  my $message;
  
  if ($code) {
    $message = {
      jsonrpc => "2.0",
      error => {
        code => $code,
        message => $text,
        id => $id,
      }
    };
  } else {
    $message = {
      jsonrpc => "2.0",
      result => ($text?$text:'null'),
      id => $id,
    };
  }

  $message = JSON::to_json($message, {pretty=>1});
  $response->print($message);
}

=begin TML

---++ handleUrl2Tml($session, $subject, $verb, $response) -> $string

handles the createTopic REST call

=cut

sub restUrl2Tml {
  my ($this, $session, $subject, $verb, $response) = @_;

  my $result = '';
  my $query = Foswiki::Func::getCgiQuery();

  my $url = $query->param("url");
  unless (defined $url) {
    $this->printJSONRPC($response, 100, "no url");
    return;
  }

  # get content
  my $content;
  my $error;

  try {
    $content = $this->getExternalResource($url);
  }
  catch Error::Simple with {
    $error = shift;
  };

  if ($error) {
    $this->printJSONRPC($response, 1, $error->{-text});
    return;
  }

  # cleanup
  $content =~ s/^.*<body.*?>(.*)<\/body>.*$/$1/s;
  $content =~ s/<!-- .* -->//g;
  $content =~ s/<!\[CDATA\[.*?\]\](>|&gt;)//gs; # remove junk
  $content =~ s/<script.*?>.*?<\/script>//gs;
  $content =~ s/<fb.*?>.*?<\/fb.*?>//gs;
  $content =~ s/onclick=".*?"//g;
  $content =~ s/onclick='.*?'//g;
  $content =~ s/<img ([^>]+?[^\/])>/<img $1 \/>/g; # fixing img tags as convertImage will freak out otherwise
  #print STDERR "CONTENT=$content\n";

  unless ($this->{html2tml}) {
    require Foswiki::Plugins::WysiwygPlugin::HTML2TML;
    $this->{html2tml} = new Foswiki::Plugins::WysiwygPlugin::HTML2TML();
  }

  $result = $this->{html2tml}->convert($content, {
    web => $this->{baseWeb},
    topic => $this->{topicWeb},
    convertImage => \&_convertImage,
    very_clean => 1,
  });

  return $result;
}

sub _convertImage {
  my ($src, $opts) = @_;

  writeDebug("called _convertImage($src)");

  return '%IMAGE{"'.$src.'"}%';
}

=begin TML

---++ jsonRpcAttach($this, $request) -> $result

handles the attach json-rpc method

=cut

sub jsonRpcAttach {
  my ($this, $session, $request) = @_;

  writeDebug("called jsonRpcAttach");
  my $result = '';

  my $web = $this->{baseWeb};
  my $topic = $request->param("topic") || $this->{baseTopic};

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "change access to $topic.$web denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", undef, undef, $topic, $web);

  writeDebug("topic=$web.$topic");

  my $selection = $request->param("selection");

  throw Foswiki::Contrib::JsonRpcContrib::Error(1005, "empty selection")
    unless $selection;

  writeDebug("selection=$selection");
  unless (ref($selection) eq 'ARRAY') {
    $selection = [$selection];
  }

  foreach my $url (@$selection) {
    require File::Temp;

    writeDebug("url=$url");

    my $content = $this->getExternalResource($url);
    next unless $content;

    # SMELL: first have to write it to a temp file before being able to attach it
    my $tempFile = new File::Temp();
    print $tempFile $content;

    my $baseFilename = $url;
    $baseFilename =~ s/^.*[\/\\](.*?)(?:\?.*)?$/$1/;
    $baseFilename =~ s/%([\da-f]{2})/chr(hex($1))/gei;

    my $origName;

    ($baseFilename, $origName) = Foswiki::Sandbox::sanitizeAttachmentName($baseFilename);

    my $size = bytes::length($content);

    writeDebug("file=$baseFilename, size=$size, tmpfile=$tempFile");

    Foswiki::Func::saveAttachment($web, $topic, $baseFilename, {
      file => $tempFile,
      filesize => $size
    });
  }

  return "Successfully downloaded ".scalar(@$selection)." item(s) to $web.$topic";
}

=begin TML

--++ jsonRpcAnalyze($this, $request) -> @result

handles the "analyze" json-rpc method

=cut

sub jsonRpcAnalyze {
  my ($this, $session, $request) = @_;

  writeDebug("called jsonRpcAnalyze");

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "no url")
    unless $request->param("url");

  my $depth = $request->param("depth") || 0;
  my $exclude = $request->param("exclude");
  my $include = $request->param("include");
  my $maxDepth = $Foswiki::cfg{HarvestPlugin}{MaxDepth};
  $maxDepth = 1 unless defined $maxDepth;
  my $timeout = $foswiki::cfg{HarvestPlugin}{TimeOut} || 60;  

  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "invalid depth parameter")
    if $depth < 0 || $depth > $maxDepth;

  my $elementType = lc($request->param("type") || 'image');
  my @result = ();
 
  $this->{_gotAlarm} = 0;
  local $SIG{ALRM} = sub {
    writeDebug("flagging an alarm");
    $this->{_gotAlarm} = 1;
  };
  alarm $timeout;
  @result = $this->crawl($request->param("url"), $elementType, $depth, $exclude, $include);
  alarm 0;

  writeDebug("found=".scalar(@result)." ".$elementType."s");

  return \@result;
}

=begin TML

---++ crawl($url, $elementType, $depth, $exclude, $include, $seen) -> @result

crawls an external url with the given depth and returls a list
of found nodes

=cut

sub crawl {
  my ($this, $url, $elementType, $depth, $exclude, $include, $alreadyCrawled, $result) = @_;

  if ($this->{_gotAlarm}) {
    writeDebug("got timeout");
    return values %$result;
  }

  $depth ||= 0;
  $alreadyCrawled ||= {};
  $result ||= {};

  writeDebug("crawl($url, $elementType, $depth)");

  return () if $depth < 0;
  return () if $alreadyCrawled->{$url};
  $alreadyCrawled->{$url} = 1;

  # get content
  my $content = $this->getExternalResource($url);

  return values %$result unless defined $content;

  # parse the page
  require HTML::TokeParser;
  my $parser = HTML::TokeParser->new(\$content);

  throw Foswiki::Contrib::JsonRpcContrib::Errro(1003, "error parsing content") 
    unless $parser;

  my %foundLinks = ();
  my $baseUri;

  my @wantedTags = ('a', 'base');
  push @wantedTags, 'img' if $elementType =~ /\b(image|gif|png|jpe?g|tiff|bmp)\b/i;

  while (my $node = $parser->get_tag(@wantedTags)) {

    my $record = $this->node2record($node);
    next unless $record;

    next if $exclude && $record->{src} =~ /$exclude/;
    next if $include && $record->{src} !~ /$include/;

    $result->{$record->{src}} = $record if $record->{type} =~ /$elementType/;
    $foundLinks{$record->{src}} = 1 if $depth > 0 && $record->{type} eq 'link';
    $baseUri = $node->[1]{href} if $node->[0] eq 'base';
  }

  $baseUri = $url unless $baseUri;

  # fix relative urls in results
  foreach my $record (values %$result) {
    my $src = $record->{src};
    if (defined($src)) {
      $record->{src} = URI->new_abs($src, $baseUri)->as_string;
    } 
    if ($record->{type} eq 'image') {
      my $thumbnail = $record->{thumbnail};
      if (defined($thumbnail)) {
        $record->{thumbnail} = URI->new_abs($thumbnail, $baseUri)->as_string;
      } 
    }
  }

  # recurse
  foreach my $link (keys %foundLinks) {
    my $link = URI->new_abs($link, $baseUri)->as_string;
    next unless $link =~ /^(http|ftp)/;
    #writeDebug("following $link");
    $this->crawl($link, $elementType, $depth - 1, $exclude, $include, $alreadyCrawled, $result);
    last if $this->{_gotAlarm};
  }

  return values %$result;
}

=begin TML

---++ node2record($node) -> $record

converts an html node as returned by the toke parser to a result record
as we want it.

=cut

sub node2record {
  my ($this, $node) = @_;

  my $record;

  # img
  if ($node->[0] eq 'img') {
    my $src = $node->[1]{src} || '';
    $src =~ s/\?.(.*)$//; # smell
    $record = {
      title => ($node->[1]{alt} || $node->[1]{title}) || $src || '',
      src => $src,
      thumbnail => $src,
      type => "image"
    };
    $record->{width} = $node->[1]{width} if defined $node->[1]{width};
    $record->{height} = $node->[1]{height} if defined $node->[1]{height};
    writeDebug("found image $src");
  }

  # a
  if ($node->[0] eq 'a') {
    my $src = $node->[1]{href} || '';

    return if $src =~ /^#/; # weed out anchors;

    my $type = $this->getMimeType($src);

    if ($type) {
      if ($type =~ /^image\//) {
        $type = "image";
      } elsif ($type =~ /text\/html/) {
        $type = "link";
      }
    } else {
      # normal link
      $type = "link";
    }
    writeDebug("src=$src, type=$type");

    $record = {
      title => $node->[1]{title} || $node->[1]{_content} || $src || '',
      src => $src,
      type => $type,
    };

    if ($type eq 'image') {
      $record->{thumbnail} = $src;
    } else {
      require Foswiki::Plugins::MimeIconPlugin;
      my $ext = '';
      $ext = $1 if $src =~ /\.(\w+)(?:\?.*?)?$/;
      if ($ext) {
        $record->{thumbnail} = Foswiki::Plugins::MimeIconPlugin::getIcon($ext, 'oxygen', 48);
      }
    }

    $record->{rel} = $node->[1]{rel} if defined $node->[1]{rel};
  }

  if ($record->{title} =~ /^https?:.*\/(.*?)$/) {
    $record->{title} = $1;
  }
  if (length($record->{title}) > 40) {
    $record->{shorttitle} = "...".substr($record->{title}, -40);
  } else {
    $record->{shorttitle} = $record->{title};
  }

  # encode to utf8...SMELL: shouldn't that be done inside JsonRpcContrib?
  while (my ($key, $val) = each %$record) {
    $record->{$key} = Encode::encode_utf8($val);
    #print STDERR "$key=$val\n";
  }

  # filter some
  return if $record->{width} && $record->{width} eq 1 && $record->{height} && $record->{height} eq 1;
  return $record;
}

=begin TML

---++ getMimeType($url) -> $mimeType

get the mimetype of the file behind $url by analyzing the
extension suffix. Returns undef if not found in
the =MimeTypesFileName= description.

=cut

sub getMimeType {
  my ($this, $url) = @_;

  my $mimeType;
  
  if ($url && $url =~ /\.(\w+)(?:\?.*?)?$/i) {
    my $suffix = $1;

    unless ($this->{types}) {
      $this->{types} = Foswiki::readFile($Foswiki::cfg{MimeTypesFileName});
    }

    if ($this->{types} =~ /^([^#]\S*).*?\s$suffix(?:\s|$)/im) {
      $mimeType = $1;
    }
  }

  return $mimeType;
}

=begin TML

---++ getExternalResource($url) -> $content

wrapper to Foswiki::Net::getExternalResource() which
adds a cache to it

=cut

sub getExternalResource {
  my ($this, $url) = @_;

  my $cache = $this->_cache;

  $url =~ s/\/$//;

  if ($cache) {
    my $content = $cache->get(_cache_key($url));
    #writeDebug("found content for $url in cache") if defined $content;
    return $content if defined $content;
  }

  my $client = $this->client;
  my $res = $client->get($url);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1002, "error fetching url") 
    unless $res;

  unless ($res->is_success) {
    writeDebug("url=$url, http error=".$res->status_line);
    throw Foswiki::Contrib::JsonRpcContrib::Error(1004, "http error - ".$res->status_line);
  }

  writeDebug("http status=".$res->status_line);

  #my $content = $res->content;
  my $content = $res->decoded_content();

  if ($cache) {
    writeDebug("caching content for $url");
    $cache->set(_cache_key($url), $content);
  }

  return $content;
}

sub _cache_key {
  return _untaint(Digest::MD5::md5_hex($_[0]));
}

sub _untaint {
  my $content = shift;
  if (defined $content && $content =~ /^(.*)$/s) {
    $content = $1;
  }
  return $content;
}

sub _cache {
  my $this = shift;

  unless (defined $this->{cache}) {
    require Cache::FileCache;
    $this->{cache} = Cache::FileCache->new({
      default_expires_in => ($this->{cacheExpire} || "1 h"),
      cache_root => $this->{cacheRoot}
    });
  }

  return $this->{cache};
}

sub client {
  my $this = shift;

  unless (defined $this->{client}) {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    #$ua->timeout(10); # TODO: make it configurable
    $ua->agent('Mozilla/5.0 (compatible; Konqueror/4.5; Linux; X11; en_US) KHTML/4.5.5 (like Gecko) Kubuntu'); # TODO: make it configurable

    my $attachLimit = Foswiki::Func::getPreferencesValue('ATTACHFILESIZELIMIT') || 0;
    $attachLimit =~ s/[^\d]//g;
    if ($attachLimit) {
      $attachLimit *= 1024;
      $ua->max_size($attachLimit);
    }

    my $proxy = $Foswiki::cfg{PROXY}{HOST};
    if ($proxy) {
      my $port = $Foswiki::cfg{PROXY}{PORT};
      $proxy .= ':' . $port if $port;
      $ua->proxy([ 'http', 'https' ], $proxy);

      my $proxySkip = $Foswiki::cfg{PROXY}{SkipProxyForDomains};
      if ($proxySkip) {
        my @skipDomains = split(/\s*,\s*/, $proxySkip);
        $ua->no_proxy(@skipDomains);
      }
    }

    $this->{client} = $ua;
  }

  return $this->{client}
}

1;
