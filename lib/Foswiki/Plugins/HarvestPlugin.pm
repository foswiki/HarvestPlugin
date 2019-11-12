# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# HarvestPlugin is Copyright (C) 2011-2019 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::HarvestPlugin;

use strict;
use warnings;

=begin TML

---+ package HarvestPlugin

=cut

use Foswiki::Func ();
use Foswiki::Contrib::JsonRpcContrib ();

our $VERSION = '2.20';
our $RELEASE = '12 Nov 2019';
our $SHORTDESCRIPTION = 'Download and archive resources from the web';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

=cut

sub initPlugin {

  Foswiki::Contrib::JsonRpcContrib::registerMethod('HarvestPlugin', 'analyze', sub { return getCore()->jsonRpcAnalyze(@_); });
  Foswiki::Contrib::JsonRpcContrib::registerMethod('HarvestPlugin', 'attach',  sub { return getCore()->jsonRpcAttach(@_); });

  Foswiki::Func::registerRESTHandler('purgeCache', sub { return getCore()->purgeCache(@_); },
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('clearCache', sub { return getCore()->clearCache(@_); },
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('url2tml', sub { 
      return getCore()->restUrl2Tml(@_); 
    }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  ); # TODO: convert to JsonRpcContrib

  return 1;
}

=begin TML

---++ finishPlugin()

=cut

sub finishPlugin {
  undef $core;
}

=begin TML

---++ getCore() -> $harvestCore

returns a singleton core for this plugin

=cut

sub getCore {
  
  unless (defined $core) {
    require Foswiki::Plugins::HarvestPlugin::Core;
    $core = Foswiki::Plugins::HarvestPlugin::Core->new();
  }

  return $core;
}

1;
