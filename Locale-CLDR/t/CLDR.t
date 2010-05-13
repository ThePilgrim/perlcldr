#!perl
use strict;
use warnings;

use Test::More tests => 40;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new(language => 'en');
is("$locale", 'en', 'Set Language explicitly');

$locale = Locale::CLDR->new('en');
is("$locale", 'en', 'Set Language implicitly');

$locale = Locale::CLDR->new(language => 'en', territory => 'gb');
is("$locale", 'en_GB', 'Set Language and Territory explicitly');

$locale = Locale::CLDR->new('en-gb');
is("$locale", 'en_GB', 'Set Language and Territory implicitly');

$locale = Locale::CLDR->new(language => 'en', script => 'latn');
is("$locale", 'en_Latn', 'Set Language and Script explicitly');

$locale = Locale::CLDR->new('en-latn');
is("$locale", 'en_Latn', 'Set Language and Script implicitly');

$locale = Locale::CLDR->new(language => 'en', territory => 'gb', script => 'latn');
is("$locale", 'en_Latn_GB', 'Set Language, Territory and Script explicitly');

$locale = Locale::CLDR->new('en-latn-gb');
is("$locale", 'en_Latn_GB', 'Set Language, Territory and Script implicitly');

$locale = Locale::CLDR->new(language => 'en', variant => '1994');
is("$locale", 'en_1994', 'Set Language and Variant from string explicitly');

$locale = Locale::CLDR->new('en_1994');
is("$locale", 'en_1994', 'Set Language and variant implicitly');

$locale = Locale::CLDR->new('en_latn_gb_1994');
is("$locale", 'en_Latn_GB_1994', 'Set Language, Territory, Script and variant implicitly');

throws_ok { $locale = Locale::CLDR->new('wibble') } qr/Invalid language/, "Caught invalid language";
throws_ok { $locale = Locale::CLDR->new('en_wi') } qr/Invalid territory/, "Caught invalid territory";
throws_ok { $locale = Locale::CLDR->new('en_wibb') } qr/Invalid script/, "Caught invalid script";

$locale = Locale::CLDR->new('en');
is ($locale->locale_name('fr'), 'French', 'Name without territory');
is ($locale->locale_name('fr_CA'), 'Canadian French', 'Name with known territory') ;
is ($locale->locale_name('fr_BE'), 'French (Belgium)', 'Name with unknown territory') ;
is ($locale->locale_name('fr_BE'), 'French (Belgium)', 'Cached method') ;
$locale = Locale::CLDR->new('en');
is ($locale->language_name, 'English', 'Language name');
is ($locale->language_name('wibble'), 'Unknown or Invalid Language', 'Unknown Language name');
is ($locale->script_name('Cher'), 'Cherokee', 'Script name');
is ($locale->script_name('wibl'), 'Unknown or Invalid Script', 'Invalid Script name');
is ($locale->territory_name('GB'), 'United Kingdom', 'Territory name');
is ($locale->territory_name('wibble'), 'Unknown or Invalid Region', 'Invalid Territory name');
is ($locale->variant_name('AREVMDA'), 'Western Armenian', 'Variant name');
throws_ok { $locale->variant_name('WIBBLE') } qr/ \A Invalid \s variant /xms, 'Invalid Variant name';
is ($locale->language_name('i-klingon'), 'Klingon', 'Language alias');
is ($locale->territory_name('BQ'), 'British Antarctic Territory', 'Territory alias');
is ($locale->territory_name('830'), 'Channel Islands', 'Territory alias');
is ($locale->variant_name('BOKMAL'), '', 'Variant alias');
is ($locale->key_name('ca'), 'Calendar', 'Key name');
is ($locale->type_name('calendar', 'gregorian'), 'Gregorian Calendar', 'Type name');

# Mesurement systems
is ($locale->measurement_system_name('us'), 'US', 'Measurement system US');
is ($locale->measurement_system_name('metric'), 'Metric', 'Measurement system Metric');

# Code patterns
my $test = Locale::CLDR->new('en_Latn_GB');
is ($locale->code_pattern('language', $test), 'Language: English', 'Code pattern Language');
is ($locale->code_pattern('script', $test), 'Script: Latin', 'Code pattern script');
is ($locale->code_pattern('territory', $test), 'Region: United Kingdom', 'Code pattern territory');

# Orientation
is ($locale->text_orientation->{lines}, 'top-to-bottom', 'Line orientation');
is ($locale->text_orientation->{characters}, 'left-to-right', 'Line orientation');
