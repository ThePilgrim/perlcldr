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

my $locale = Locale::CLDR->new('cy_GB');
is ($locale->locale_name('fr'), 'Ffrangeg', 'Name without territory');
is ($locale->locale_name('fr_CA'), 'Ffrangeg Canada', 'Name with known territory');
is ($locale->locale_name('fr_BE'), 'Ffrangeg (Gwlad Belg)', 'Name with unknown territory');
is ($locale->locale_name('fr_BE'), 'Ffrangeg (Gwlad Belg)', 'Cached method');
is ($locale->language_name, 'Cymraeg', 'Language name');
is ($locale->language_name('wibble'), 'Iaith Anhysbys', 'Unknown Language name');
is ($locale->script_name('Guru'), 'Gwrmwci', 'Script name');
is ($locale->script_name('wibl'), 'Sgript anhysbys', 'Invalid Script name');
is ($locale->territory_name('GB'), 'Y Deyrnas Unedig', 'Territory name');
is ($locale->territory_name('wibble'), 'Rhanbarth Anhysbys', 'Invalid Territory name');
is ($locale->variant_name('AREVMDA'), '', 'Variant name');
throws_ok { $locale->variant_name('WIBBLE') } qr{ \A Invalid \s variant }xms, 'Invalid Variant name';
is ($locale->language_name('i_klingon'), 'Klingon', 'Language alias');
is ($locale->territory_name('BQ'), 'Antilles yr Iseldiroedd', 'Territory alias');
is ($locale->territory_name('830'), 'Rhanbarth Anhysbys', 'Territory alias');
is ($locale->variant_name('BOKMAL'), '', 'Variant alias');
is ($locale->key_name('ca'), 'Calendr', 'Key name');
is ($locale->key_name('calendar'), 'Calendr', 'Key name');
is ($locale->type_name('ca', 'gregorian'), 'Calendr Gregori', 'Type name');
is ($locale->type_name('calendar', 'gregorian'), 'Calendr Gregori', 'Type name');