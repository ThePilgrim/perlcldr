#!/usr/bin/perl
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 61;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new(language_id => 'en');
is($locale->id, 'en', 'Set Language explicitly');

$locale = Locale::CLDR->new('en');
is($locale->id, 'en', 'Set Language implicitly');

$locale = Locale::CLDR->new(language_id => 'en', territory_id => 'gb');
is($locale->id, 'en_GB', 'Set Language and Territory explicitly');

$locale = Locale::CLDR->new('en-gb');
is($locale->id, 'en_GB', 'Set Language and Territory implicitly');

$locale = Locale::CLDR->new(language_id => 'en', script_id => 'latn');
is($locale->id, 'en_Latn', 'Set Language and Script explicitly');

$locale = Locale::CLDR->new('en-latn');
is($locale->id, 'en_Latn', 'Set Language and Script implicitly');

$locale = Locale::CLDR->new(language_id => 'en', territory_id => 'gb', script_id => 'latn');
is($locale->id, 'en_Latn_GB', 'Set Language, Territory and Script explicitly');

$locale = Locale::CLDR->new('en-latn-gb');
is($locale->id, 'en_Latn_GB', 'Set Language, Territory and Script implicitly');

$locale = Locale::CLDR->new(language_id => 'en', variant_id => '1994');
is($locale->id, 'en_1994', 'Set Language and Variant from string explicitly');

$locale = Locale::CLDR->new('en_1994');
is($locale->id, 'en_1994', 'Set Language and variant implicitly');

$locale = Locale::CLDR->new('en_latn_gb_1994');
is($locale->id, 'en_Latn_GB_1994', 'Set Language, Territory, Script and variant implicitly');

throws_ok { $locale = Locale::CLDR->new('wibble') } qr/Invalid language/, "Caught invalid language";
throws_ok { $locale = Locale::CLDR->new('en_wi') } qr/Invalid territory/, "Caught invalid territory";
throws_ok { $locale = Locale::CLDR->new('en_wibb') } qr/Invalid script/, "Caught invalid script";

$locale = Locale::CLDR->new('en');
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
is ($locale->language_name('i-klingon'), 'Klingon', 'Language alias');
is ($locale->territory_name('BQ'), 'Caribbean Netherlands', 'Territory alias');
is ($locale->territory_name('830'), 'Unknown Region', 'Territory alias');
is ($locale->variant_name('BOKMAL'), '', 'Variant alias');
is ($locale->key_name('ca'), 'Calendar', 'Key name');
is ($locale->type_name('calendar', 'gregorian'), 'Gregorian Calendar', 'Type name');

# Mesurement systems
is ($locale->measurement_system_name('us'), 'US', 'Measurement system US');
is ($locale->measurement_system_name('metric'), 'Metric', 'Measurement system Metric');

# Code patterns
my $test = Locale::CLDR->new('az_latn_az');
is ($locale->code_pattern('language', $test), 'Language: Azerbaijani', 'Code pattern Language');
is ($locale->code_pattern('script', $test), 'Script: Latin', 'Code pattern script');
is ($locale->code_pattern('territory', $test), 'Region: Azerbaijan', 'Code pattern territory');

# Orientation
is ($locale->text_orientation('lines'), 'top-to-bottom', 'Line orientation');
is ($locale->text_orientation('characters'), 'left-to-right', 'Character orientation');

# Segmentation
my $text = "adf543., Tiếng Viết\n\r45dfr.A new sentence";
my @grapheme_clusters = $locale->split_grapheme_clusters($text);
is_deeply(\@grapheme_clusters, [
	'a', 'd', 'f', '5', '4', '3', '.', ',', ' ', 'T', 'i', 'ế', 'n', 'g',
	' ', 'V', 'i', 'ế', 't', "\n", "\r", '4', '5', 'd', 'f', 'r', '.', 
	'A', ' ', 'n', 'e', 'w', ' ', 's', 'e', 'n', 't', 'e', 'n', 'c', 'e'
], 'Split grapheme clusters');
my @words = $locale->split_words($text);
is_deeply(\@words, [
	'adf543', '.', ', ', 'Tiếng ', 'Viết', "\n", "\r", '45dfr.', 'A ', 'new ',
	'sentence'
], 'Split words');
my @sentences = $locale->split_sentences($text);
is_deeply(\@sentences, [
	"adf543., Tiếng Viết",
	"\n",
	"\r",
	"45dfr.",
	"A new sentence",
], 'Split sentences');
my @lines=$locale->split_lines($text);
is_deeply(\@lines, [
	"adf543., ",
	"Tiếng ",
	"Viết\n",
	"\r",
	"45dfr.A ",
	"new ",
	"sentence",
], 'Split lines');

#exemplar characters
ok($locale->is_exemplar_character("A"), 'Is Exemplar Character');
ok(!$locale->is_exemplar_character('@'), 'Is not Exemplar Character');
ok($locale->is_exemplar_character('auxiliary', "\N{U+00EA}"), 'Is Auxiliary Exemplar Character');
ok(!$locale->is_exemplar_character('auxiliary','@'), 'Is not Auxiliary Exemplar Character');
ok($locale->is_exemplar_character('punctuation', "!"), 'Is Punctiation Exemplar Character');
ok(!$locale->is_exemplar_character('punctuation', 'a'), 'Is not Punctiation Exemplar Character');
is("@{$locale->index_characters()}", 'A B C D E F G H I J K L M N O P Q R S T U V W X Y Z', 'Index Characters');

# Ellipsis
is ($locale->truncated_beginning('abc'), '…abc','Truncated beginning');
is ($locale->truncated_between('abc','def'), 'abc…def','Truncated between');
is ($locale->truncated_end('abc'), 'abc…','Truncated end');

is($locale->more_information(), '?','More Information');

# Delimiters
$locale = Locale::CLDR->new('en_GB');
my $quoted = $locale->quote('abc');
is($quoted, '“abc”', 'Quote en_GB');
$quoted = $locale->quote("z $quoted z");
is($quoted, '“z ‘abc’ z”', 'Quote en_GB');
$quoted = $locale->quote("dd 'z $quoted z dd");
is($quoted, '“dd \'z ‘z “abc” z’ z dd”', 'Quote en_GB');

$locale = Locale::CLDR->new('fr');
$quoted = $locale->quote('abc');
is($quoted, '«abc»', 'Quote fr');
$quoted = $locale->quote("z $quoted z");
is($quoted, "«z «abc» z»", 'Quote fr');
$quoted = $locale->quote("dd 'z $quoted z dd");
is($quoted, "«dd \'z «z «abc» z» z dd»", 'Quote fr');

#Measurement System
__END__
# Calendars
$locale = Locale::CLDR->new('en_GB');
my $months = $locale->month_format_wide();
is_deeply ($months, [qw( January February March April May June July August September October November December )], 'Month format wide');
$months = $locale->month_format_abbreviated();
is_deeply ($months, [qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec )], 'Month format abbreviated');
$months = $locale->month_format_narrow();
is_deeply ($months, [qw( 1 2 3 4 5 6 7 8 9 10 11 12 )], 'Month format abbreviated');
$months = $locale->month_stand_alone_wide();
is_deeply ($months, [qw( January February March April May June July August September October November December )], 'Month stand alone wide');
$months = $locale->month_stand_alone_abbreviated();
is_deeply ($months, [qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec )], 'Month stand alone abbreviated');
$months = $locale->month_stand_alone_narrow();
is_deeply ($months, [qw( 1 2 3 4 5 6 7 8 9 10 11 12 )], 'Month stand alone narrow');
