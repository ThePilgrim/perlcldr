#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 55;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('bg_u_ca_islamic');

my $months = $locale->month_format_wide();
is_deeply ($months, [ 'януари', 'февруари', 'март', 'април', 'май', 'юни', ], 'Islamic Month format wide');
$months = $locale->month_format_abbreviated();
is_deeply ($months, [ 'ян.', 'февр.', 'март', 'апр.', ], 'Islamic Month format abbreviated');
$months = $locale->month_format_narrow();
is_deeply ($months, [qw( я ф м а)], 'Islamic Month format narrow');
$months = $locale->month_stand_alone_wide();
is_deeply ($months, ['януари', 'февруари', 'март', 'април', ], 'Islamic Month stand alone wide');
$months = $locale->month_stand_alone_abbreviated();
is_deeply ($months, [ 'ян.', 'февр.', 'март', 'апр.', ], 'Islamic Month stand alone abbreviated');
$months = $locale->month_stand_alone_narrow();
is_deeply ($months, [qw( я ф м а)], 'Islamic Month stand alone narrow');

my $days = $locale->day_format_wide();
is_deeply ($days, [qw( понеделник )], 'Islamic Day format wide');
$days = $locale->day_format_abbreviated();
is_deeply ($days, [qw( пн )], 'Islamic Day format abbreviated');
$days = $locale->day_format_narrow();
is_deeply ($days, [qw( п ث ر خ ج س ح )], 'Islamic Day format narrow');
$days = $locale->day_stand_alone_wide();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Islamic Day stand alone wide');
$days = $locale->day_stand_alone_abbreviated();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Islamic Day stand alone abbreviated');
$days = $locale->day_stand_alone_narrow();
is_deeply ($days, [qw( ن ث ر خ ج س ح )], 'Islamic Day stand alone narrow');

my $quarters = $locale->quarter_format_wide();
is_deeply ($quarters, [ '1. тримесечие', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Islamic Quarter format wide');
$quarters = $locale->quarter_format_abbreviated();
is_deeply ($quarters, [ '1. трим.', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Islamic Quarter format abbreviated');
$quarters = $locale->quarter_format_narrow();
is_deeply ($quarters, [qw( 1 2 3 4 )], 'Islamic Quarter format narrow');
$quarters = $locale->quarter_stand_alone_wide();
is_deeply ($quarters, [ '1. тримесечие' ], 'Islamic Quarter stand alone wide');
$quarters = $locale->quarter_stand_alone_abbreviated();
is_deeply ($quarters, [ '1. трим.' ], 'Islamic Quarter stand alone abbreviated');
$quarters = $locale->quarter_stand_alone_narrow();
is_deeply ($quarters, [qw( 1 2 3 4 )], 'Islamic Quarter stand alone narrow');

my $am_pm = $locale->am_pm_wide();
is_deeply ($am_pm, [qw( пр.об. сл.об. )], 'Islamic AM PM wide');
$am_pm = $locale->am_pm_abbreviated();
is_deeply ($am_pm, [qw( пр.об. сл.об. )], 'Islamic AM PM abbreviated');
$am_pm = $locale->am_pm_narrow();
is_deeply ($am_pm, [qw( пр.об. сл.об. )], 'Islamic AM PM narrow');
$am_pm = $locale->am_pm_format_wide();
is_deeply ($am_pm, { am => 'пр.об.', noon => 'пладне', pm => 'сл.об.' }, 'Islamic AM PM format wide');
$am_pm = $locale->am_pm_format_abbreviated();
is_deeply ($am_pm, { am => 'пр.об.', noon => 'пладне', pm => 'сл.об.' }, 'Islamic AM PM format abbreviated');
$am_pm = $locale->am_pm_format_narrow();
is_deeply ($am_pm, { am => 'пр.об.', noon => 'пл.', pm => 'сл.об.' }, 'Islamic AM PM format narrow');
$am_pm = $locale->am_pm_stand_alone_wide();
is_deeply ($am_pm, { am => 'пр.об.', noon => 'пладне', pm => 'сл.об.' }, 'Islamic AM PM stand alone wide');
$am_pm = $locale->am_pm_stand_alone_abbreviated();
is_deeply ($am_pm, { am => 'пр.об.', noon => 'пладне', pm => 'сл.об.' }, 'Islamic AM PM stand alone abbreviated');
$am_pm = $locale->am_pm_stand_alone_narrow();
is_deeply ($am_pm, { am => 'пр.об.', noon => 'пл.', pm => 'сл.об.' }, 'Islamic AM PM stand alone narrow');

my $era = $locale->era_wide();
is_deeply ($era, [ 'преди Христа', 'след Христа' ], 'Islamic Era wide');
$era = $locale->era_abbreviated();
is_deeply ($era, [ 'пр.Хр.', 'сл.Хр.'], 'Islamic Era abbreviated');
$era = $locale->era_narrow();
is_deeply ($era, [ undef(), 'сл.н.е.' ], 'Islamic Era narrow');
$era = $locale->era_format_wide();
is_deeply ($era, [ 'преди Христа', 'след Христа'], 'Islamic Era format wide');
$era = $locale->era_format_abbreviated();
is_deeply ($era, [ 'пр.Хр.', 'сл.Хр.' ], 'Islamic Era format abbreviated');
$era = $locale->era_format_narrow();
is_deeply ($era, [ undef, 'сл.н.е.' ], 'Islamic Era format narrow');
$era = $locale->era_stand_alone_wide();
is_deeply ($era, [ 'преди Христа', 'след Христа' ], 'Islamic Era stand alone wide');
$era = $locale->era_stand_alone_abbreviated();
is_deeply ($era, [ 'пр.Хр.', 'сл.Хр.' ], 'Islamic Era stand alone abbreviated');
$era = $locale->era_stand_alone_narrow();
is_deeply ($era, [ undef, 'сл.н.е.' ], 'Islamic Era stand alone narrow');

my $day_period_data = $locale->get_day_period('0000');
is($day_period_data, undef, 'Islamic Day period data AM');
$day_period_data = $locale->get_day_period('1200');
is($day_period_data, 'пладне', 'Islamic Day period data Noon');
$day_period_data = $locale->get_day_period('1210');
is($day_period_data, undef, 'Islamic Day period data PM');

my $date_format = $locale->date_format_full;
is($date_format, q(EEEE, d MMMM y 'г'.), 'Islamic Date Format Full');
$date_format = $locale->date_format_long;
is($date_format, q(d MMMM y 'г'.), 'Islamic Date Format Long');
$date_format = $locale->date_format_medium;
is($date_format, q(d.MM.y 'г'.), 'Islamic Date Format Medium');
$date_format = $locale->date_format_short;
is($date_format, q(d.MM.yy 'г'.), 'Islamic Date Format Short');

my $time_format = $locale->time_format_full;
is($time_format, 'H:mm:ss zzzz', 'Islamic Time Format Full');
$time_format = $locale->time_format_long;
is($time_format, 'H:mm:ss z', 'Islamic Time Format Long');
$time_format = $locale->time_format_medium;
is($time_format, 'H:mm:ss', 'Islamic Time Format Medium');
$time_format = $locale->time_format_short;
is($time_format, 'H:mm', 'Islamic Time Format Short');

my $date_time_format = $locale->datetime_format_full;
is($date_time_format, q(EEEE, d MMMM y 'г'., H:mm:ss zzzz), 'Islamic Date Time Format Full');
$date_time_format = $locale->datetime_format_long;
is($date_time_format, q(d MMMM y 'г'., H:mm:ss z), 'Islamic Date Time Format Long');
$date_time_format = $locale->datetime_format_medium;
is($date_time_format, q(d.MM.y 'г'., H:mm:ss), 'Islamic Date Time Format Medium');
$date_time_format = $locale->datetime_format_short;
is($date_time_format, q(d.MM.yy 'г'., H:mm), 'Islamic Date Time Format Short');

is ($locale->prefers_24_hour_time(), 1, 'Islamic Prefers 24 hour time');
is ($locale->first_day_of_week(), 1, 'Islamic First day of week');

# Number Overrides
$locale = Locale::CLDR->new('bg_u_numbers_roman');
is($locale->format_number(12345, '#,####,00'), "ↂMMCCCXLV", 'Format Roman override');