#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 21;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('fr_FR');
is ($locale->locale_name('fr'), 'français', 'Name without territory');
is ($locale->locale_name('fr_CA'), 'français canadien', 'Name with known territory');
is ($locale->locale_name('fr_BE'), 'français (Belgique)', 'Name with unknown territory');
is ($locale->locale_name('fr_BE'), 'français (Belgique)', 'Cached method');
is ($locale->language_name, 'français', 'Language name');
is ($locale->language_name('wibble'), 'langue indéterminée', 'Unknown Language name');
is ($locale->script_name('Cher'), 'cherokee', 'Script name');
is ($locale->script_name('wibl'), 'écriture inconnue', 'Invalid Script name');
is ($locale->territory_name('GB'), 'Royaume-Uni', 'Territory name');
is ($locale->territory_name('wibble'), 'région indéterminée', 'Invalid Territory name');
is ($locale->variant_name('AREVMDA'), 'arménien occidental', 'Variant name');
throws_ok { $locale->variant_name('WIBBLE') } qr{ \A Invalid \s variant }xms, 'Invalid Variant name';
is ($locale->language_name('i_klingon'), 'klingon', 'Language alias');
is ($locale->territory_name('BQ'), 'Pays-Bas caribéens', 'Territory alias');
is ($locale->territory_name('830'), 'région indéterminée', 'Territory alias');
is ($locale->variant_name('BOKMAL'), '', 'Variant alias');
is ($locale->key_name('ca'), 'calendrier', 'Key name');
is ($locale->key_name('calendar'), 'calendrier', 'Key name');
is ($locale->type_name('ca', 'gregorian'), 'calendrier grégorien', 'Type name');
is ($locale->type_name('calendar', 'gregorian'), 'calendrier grégorien', 'Type name');