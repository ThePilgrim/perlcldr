#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 19;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en');
is ($locale->locale_name('fr'), 'French', 'Name without territory');
is ($locale->locale_name('fr_CA'), 'Canadian French', 'Name with known territory') ;
is ($locale->locale_name('fr_BE'), 'French (Belgium)', 'Name with unknown territory') ;
is ($locale->locale_name('fr_BE'), 'French (Belgium)', 'Cached method') ;
is ($locale->language_name, 'English', 'Language name');
is ($locale->language_name('wibble'), 'Unknown Language', 'Unknown Language name');
is ($locale->script_name('Cher'), 'Cherokee', 'Script name');
is ($locale->script_name('wibl'), 'Unknown Script', 'Invalid Script name');
is ($locale->territory_name('GB'), 'United Kingdom', 'Territory name');
is ($locale->territory_name('wibble'), 'Unknown Region', 'Invalid Territory name');
is ($locale->variant_name('AREVMDA'), 'Western Armenian', 'Variant name');
throws_ok { $locale->variant_name('WIBBLE') } qr{ \A Invalid \s variant }xms, 'Invalid Variant name';
is ($locale->language_name('i_klingon'), 'Klingon', 'Language alias');
is ($locale->territory_name('BQ'), 'Caribbean Netherlands', 'Territory alias');
is ($locale->territory_name('830'), 'Unknown Region', 'Territory alias');
is ($locale->variant_name('BOKMAL'), '', 'Variant alias');
is ($locale->key_name('ca'), 'Calendar', 'Key name');
is ($locale->type_name('calendar', 'gregorian'), 'Gregorian Calendar', 'Type name');
