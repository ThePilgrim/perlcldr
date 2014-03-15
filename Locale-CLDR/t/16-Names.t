#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 4;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en_GB');

my $other_locale = Locale::CLDR->new('fr');
is($locale->locale_name(), 'British English', 'Locale name from current locale');
is($locale->locale_name('fr'), 'French', 'Locale name from string');
is($locale->locale_name($other_locale), 'French', 'Locale name from other locale object');