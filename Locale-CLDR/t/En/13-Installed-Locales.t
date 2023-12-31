#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 2;
use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en_GB');

is ( grep( /^En(?:_|$)/, @{$locale->installed_locales}), 107, 'Installed Locales');