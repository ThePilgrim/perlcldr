#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 68;
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
is ($locale->language_name('i_klingon'), 'Klingon', 'Language alias');
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
is ($locale->truncated_word_beginning('abc'), '… abc','Truncated word beginning');
is ($locale->truncated_word_between('abc','def'), 'abc … def','Truncated word between');
is ($locale->truncated_word_end('abc'), 'abc …','Truncated word end');
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

# Measurement System
$locale = Locale::CLDR->new('en_GB');
is($locale->measurement, 'metric', 'GB uses metric measurement');
is($locale->paper, 'A4', 'GB uses A4 paper');
$locale = Locale::CLDR->new('en_US');
is($locale->measurement, 'US', 'US uses US measurement');
is($locale->paper, 'US-Letter', 'US uses US-Letter paper');

__END__
# Units
$locale = Locale::CLDR->new('en_GB');
is($locale->unit(1, 'day', 'short'), '1 day', 'English 1 day short form');
is($locale->unit(2, 'day', 'short'), '2 days', 'English 2 days short form');
is($locale->unit(1, 'day'), '1 day', 'English 1 day');
is($locale->unit(2, 'day'), '2 days', 'English 2 days');
is($locale->unit(1, 'day-future', 'short'), 'In 1 day', 'English 1 day future short form');
is($locale->unit(2, 'day-future', 'short'), 'In 2 days', 'English 2 days future short form');
is($locale->unit(1, 'day-future'), 'In 1 day', 'English 1 day future');
is($locale->unit(2, 'day-future'), 'In 2 days', 'English 2 days future');
is($locale->unit(1, 'day-past', 'short'), '1 day ago', 'English 1 day past short form');
is($locale->unit(2, 'day-past', 'short'), '2 days ago', 'English 2 days past short form');
is($locale->unit(1, 'day-past'), '1 day ago', 'English 1 day past');
is($locale->unit(2, 'day-past'), '2 days ago', 'English 2 days past');
is($locale->unit(1, 'hour', 'short'), '1 hr', 'English 1 hour short form');
is($locale->unit(2, 'hour', 'short'), '2 hrs', 'English 2 hours short form');
is($locale->unit(1, 'hour'), '1 hour', 'English 1 hour');
is($locale->unit(2, 'hour'), '2 hours', 'English 2 hours');
is($locale->unit(1, 'hour-future', 'short'), 'In 1 hour', 'English 1 hour future short form');
is($locale->unit(2, 'hour-future', 'short'), 'In 2 hours', 'English 2 hours future short form');
is($locale->unit(1, 'hour-future'), 'In 1 hour', 'English 1 hour future');
is($locale->unit(2, 'hour-future'), 'In 2 hours', 'English 2 hours future');
is($locale->unit(1, 'hour-past', 'short'), '1 hour ago', 'English 1 hour past short form');
is($locale->unit(2, 'hour-past', 'short'), '2 hours ago', 'English 2 hours past short form');
is($locale->unit(1, 'hour-past'), '1 hour ago', 'English 1 hour past');
is($locale->unit(2, 'hour-past'), '2 hours ago', 'English 2 hours past');
is($locale->unit(1, 'minute', 'short'), '1 min', 'English 1 minute short form');
is($locale->unit(2, 'minute', 'short'), '2 mins', 'English 2 minutes short form');
is($locale->unit(1, 'minute'), '1 minute', 'English 1 minute');
is($locale->unit(2, 'minute'), '2 minutes', 'English 2 minutes');
is($locale->unit(1, 'minute-future', 'short'), 'In 1 minute', 'English 1 minute future short form');
is($locale->unit(2, 'minute-future', 'short'), 'In 2 minutes', 'English 2 minutes future short form');
is($locale->unit(1, 'minute-future'), 'In 1 minute', 'English 1 minute future');
is($locale->unit(2, 'minute-future'), 'In 2 minutes', 'English 2 minutes future');
is($locale->unit(1, 'minute-past', 'short'), '1 minute ago', 'English 1 minute past short form');
is($locale->unit(2, 'minute-past', 'short'), '2 minutes ago', 'English 2 minutes past short form');
is($locale->unit(1, 'minute-past'), '1 minute ago', 'English 1 minute past');
is($locale->unit(2, 'minute-past'), '2 minutes ago', 'English 2 minutes past');
is($locale->unit(1, 'month', 'short'), '1 mth', 'English 1 month short form');
is($locale->unit(2, 'month', 'short'), '2 mths', 'English 2 months short form');
is($locale->unit(1, 'month'), '1 month', 'English 1 month');
is($locale->unit(2, 'month'), '2 months', 'English 2 months');
is($locale->unit(1, 'month-future', 'short'), 'In 1 month', 'English 1 month future short form');
is($locale->unit(2, 'month-future', 'short'), 'In 2 months', 'English 2 months future short form');
is($locale->unit(1, 'month-future'), 'In 1 month', 'English 1 month future');
is($locale->unit(2, 'month-future'), 'In 2 months', 'English 2 months future');
is($locale->unit(1, 'month-past', 'short'), '1 month ago', 'English 1 month past short form');
is($locale->unit(2, 'month-past', 'short'), '2 months ago', 'English 2 month past short form');
is($locale->unit(1, 'month-past'), '1 month ago', 'English 1 month past');
is($locale->unit(2, 'month-past'), '2 months ago', 'English 2 month past');
is($locale->unit(1, 'second', 'short'), '1 sec', 'English 1 second short form');
is($locale->unit(2, 'second', 'short'), '2 secs', 'English 2 seconds short form');
is($locale->unit(1, 'second'), '1 second', 'English 1 second');
is($locale->unit(2, 'second'), '2 seconds', 'English 2 seconds');
is($locale->unit(1, 'second-future', 'short'), 'In 1 second', 'English 1 second future short form');
is($locale->unit(2, 'second-future', 'short'), 'In 2 seconds', 'English 2 seconds future short form');
is($locale->unit(1, 'second-future'), 'In 1 second', 'English 1 second future');
is($locale->unit(2, 'second-future'), 'In 2 seconds', 'English 2 seconds future');
is($locale->unit(1, 'second-past', 'short'), '1 second ago', 'English 1 second past short form');
is($locale->unit(2, 'second-past', 'short'), '2 seconds ago', 'English 2 seconds past short form');
is($locale->unit(1, 'second-past'), '1 second ago', 'English 1 second past');
is($locale->unit(2, 'second-past'), '2 seconds ago', 'English 2 seconds past');

$locale = Locale::CLDR->new('bg_BG');
is($locale->unit(1, 'day', 'short'), '1 дн.', 'Bulgarian 1 day short form');
is($locale->unit(2, 'day', 'short'), '2 дн.', 'Bulgarian 2 days short form');
is($locale->unit(1, 'day'), '1 ден', 'Bulgarian 1 day');
is($locale->unit(2, 'day'), '2 дена', 'Bulgarian 2 days');
is($locale->unit(1, 'day-future', 'short'), 'След 1 дни', 'Bulgarian 1 day future short form');
is($locale->unit(2, 'day-future', 'short'), 'След 2 дни', 'Bulgarian 2 days future short form');
is($locale->unit(1, 'day-future'), 'След 1 дни', 'Bulgarian 1 day future');
is($locale->unit(2, 'day-future'), 'След 2 дни', 'Bulgarian 2 days future');
is($locale->unit(1, 'day-past', 'short'), 'Преди 1 ден', 'Bulgarian 1 day past short form');
is($locale->unit(2, 'day-past', 'short'), 'Преди 2 дни', 'Bulgarian 2 days past short form');
is($locale->unit(1, 'day-past'), 'Преди 1 ден', 'Bulgarian 1 day past');
is($locale->unit(2, 'day-past'), 'Преди 2 дни', 'Bulgarian 2 days past');
is($locale->unit(1, 'hour', 'short'), '1 ч', 'Bulgarian 1 hour short form');
is($locale->unit(2, 'hour', 'short'), '2 ч', 'Bulgarian 2 hours short form');
is($locale->unit(1, 'hour'), '1 час', 'Bulgarian 1 hour');
is($locale->unit(2, 'hour'), '2 часа', 'Bulgarian 2 hours');
is($locale->unit(1, 'hour-future', 'short'), 'След 1 час', 'Bulgarian 1 hour future short form');
is($locale->unit(2, 'hour-future', 'short'), 'След 2 часа', 'Bulgarian 2 hours future short form');
is($locale->unit(1, 'hour-future'), 'След 1 час', 'Bulgarian 1 hour future');
is($locale->unit(2, 'hour-future'), 'След 2 часа', 'Bulgarian 2 hours future');
is($locale->unit(1, 'hour-past', 'short'), 'Преди 1 час', 'Bulgarian 1 hour past short form');
is($locale->unit(2, 'hour-past', 'short'), 'Преди 2 часа', 'Bulgarian 2 hours past short form');
is($locale->unit(1, 'hour-past'), 'Преди 1 час', 'Bulgarian 1 hour past');
is($locale->unit(2, 'hour-past'), 'Преди 2 часа', 'Bulgarian 2 hours past');
is($locale->unit(1, 'minute', 'short'), '1 мин', 'Bulgarian 1 minute short form');
is($locale->unit(2, 'minute', 'short'), '2 мин', 'Bulgarian 2 minutes short form');
is($locale->unit(1, 'minute'), '1 минута', 'Bulgarian 1 minute');
is($locale->unit(2, 'minute'), '2 минути', 'Bulgarian 2 minutes');
is($locale->unit(1, 'minute-future', 'short'), 'След 1 минута', 'Bulgarian 1 minute future short form');
is($locale->unit(2, 'minute-future', 'short'), 'След 2 минути', 'Bulgarian 2 minutes future short form');
is($locale->unit(1, 'minute-future'), 'След 1 минута', 'Bulgarian 1 minute future');
is($locale->unit(2, 'minute-future'), 'След 2 минути', 'Bulgarian 2 minutes future');
is($locale->unit(1, 'minute-past', 'short'), 'Преди 1 минута', 'Bulgarian 1 minute past short form');
is($locale->unit(2, 'minute-past', 'short'), 'Преди 2 минути', 'Bulgarian 2 minutes past short form');
is($locale->unit(1, 'minute-past'), 'Преди 1 минута', 'Bulgarian 1 minute past');
is($locale->unit(2, 'minute-past'), 'Преди 2 минути', 'Bulgarian 2 minutes past');
is($locale->unit(1, 'month', 'short'), '1 мес.', 'Bulgarian 1 month short form');
is($locale->unit(2, 'month', 'short'), '2 мес.', 'Bulgarian 2 months short form');
is($locale->unit(1, 'month'), '1 месец', 'Bulgarian 1 month');
is($locale->unit(2, 'month'), '2 месеца', 'Bulgarian 2 months');
is($locale->unit(1, 'month-future', 'short'), 'След 1 месец', 'Bulgarian 1 month future short form');
is($locale->unit(2, 'month-future', 'short'), 'След 2 месеца', 'Bulgarian 2 months future short form');
is($locale->unit(1, 'month-future'), 'След 1 месец', 'Bulgarian 1 month future');
is($locale->unit(2, 'month-future'), 'След 2 месеца', 'Bulgarian 2 months future');
is($locale->unit(1, 'month-past', 'short'), 'Преди 1 месец', 'Bulgarian 1 month past short form');
is($locale->unit(2, 'month-past', 'short'), 'Преди 2 месеца', 'Bulgarian 2 months past short form');
is($locale->unit(1, 'month-past'), 'Преди 1 месец', 'Bulgarian 1 month past');
is($locale->unit(2, 'month-past'), 'Преди 2 месеца', 'Bulgarian 2 months past');
is($locale->unit(1, 'second'), '1 секунда', 'Bulgarian 1 second');
is($locale->unit(2, 'second'), '2 секунди', 'Bulgarian 2 seconds');
is($locale->unit(1, 'second-future', 'short'), 'След 1 секунда', 'Bulgarian 1 second future short form');
is($locale->unit(2, 'second-future', 'short'), 'След 2 секунди', 'Bulgarian 2 seconds future short form');
is($locale->unit(1, 'second-future'), 'След 1 секунда', 'Bulgarian 1 second future');
is($locale->unit(2, 'second-future'), 'След 2 секунди', 'Bulgarian 2 seconds future');
is($locale->unit(1, 'second-past', 'short'), 'Преди 1 секунда', 'Bulgarian 1 second past short form');
is($locale->unit(2, 'second-past', 'short'), 'Преди 2 секунди', 'Bulgarian 2 seconds past short form');
is($locale->unit(1, 'second-past'), 'Преди 1 секунда', 'Bulgarian 1 second past');
is($locale->unit(2, 'second-past'), 'Преди 2 секунди', 'Bulgarian 2 seconds past');

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
