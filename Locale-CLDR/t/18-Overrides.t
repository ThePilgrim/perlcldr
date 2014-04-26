#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 111;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('ar_Arab_EG');

my $months = $locale->month_format_wide();
is_deeply ($months, [qw( يناير فبراير مارس أبريل مايو يونيو يوليو أغسطس سبتمبر أكتوبر نوفمبر ديسمبر )], 'Month format wide');
$months = $locale->month_format_abbreviated();
is_deeply ($months, [qw( يناير فبراير مارس أبريل مايو يونيو يوليو أغسطس سبتمبر أكتوبر نوفمبر ديسمبر )], 'Month format abbreviated');
$months = $locale->month_format_narrow();
is_deeply ($months, [qw( ي ف م أ و ن ل غ س ك ب د )], 'Month format narrow');
$months = $locale->month_stand_alone_wide();
is_deeply ($months, [qw( يناير فبراير مارس أبريل مايو يونيو يوليو أغسطس سبتمبر أكتوبر نوفمبر ديسمبر )], 'Month stand alone wide');
$months = $locale->month_stand_alone_abbreviated();
is_deeply ($months, [qw( يناير فبراير مارس أبريل مايو يونيو يوليو أغسطس سبتمبر أكتوبر نوفمبر ديسمبر )], 'Month stand alone abbreviated');
$months = $locale->month_stand_alone_narrow();
is_deeply ($months, [qw( ي ف م أ و ن ل غ س ك ب د )], 'Month stand alone narrow');

my $days = $locale->day_format_wide();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Day format wide');
$days = $locale->day_format_abbreviated();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Day format abbreviated');
$days = $locale->day_format_narrow();
is_deeply ($days, [qw( ن ث ر خ ج س ح )], 'Day format narrow');
$days = $locale->day_stand_alone_wide();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Day stand alone wide');
$days = $locale->day_stand_alone_abbreviated();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Day stand alone abbreviated');
$days = $locale->day_stand_alone_narrow();
is_deeply ($days, [qw( ن ث ر خ ج س ح )], 'Day stand alone narrow');

my $quarters = $locale->quarter_format_wide();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Quarter format wide');
$quarters = $locale->quarter_format_abbreviated();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Quarter format abbreviated');
$quarters = $locale->quarter_format_narrow();
is_deeply ($quarters, [qw( ١ ٢ ٣ ٤ )], 'Quarter format narrow');
$quarters = $locale->quarter_stand_alone_wide();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Quarter stand alone wide');
$quarters = $locale->quarter_stand_alone_abbreviated();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Quarter stand alone abbreviated');
$quarters = $locale->quarter_stand_alone_narrow();
is_deeply ($quarters, [qw( ١ ٢ ٣ ٤ )], 'Quarter stand alone narrow');

my $am_pm = $locale->am_pm_wide();
is_deeply ($am_pm, [qw( ص م )], 'AM PM wide');
$am_pm = $locale->am_pm_abbreviated();
is_deeply ($am_pm, [qw( ص م )], 'AM PM abbreviated');
$am_pm = $locale->am_pm_narrow();
is_deeply ($am_pm, [qw( a p )], 'AM PM narrow');
$am_pm = $locale->am_pm_format_wide();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'AM PM format wide');
$am_pm = $locale->am_pm_format_abbreviated();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'AM PM format abbreviated');
$am_pm = $locale->am_pm_format_narrow();
is_deeply ($am_pm, { am => 'a', noon => 'n', pm => 'p' }, 'AM PM format narrow');
$am_pm = $locale->am_pm_stand_alone_wide();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'AM PM stand alone wide');
$am_pm = $locale->am_pm_stand_alone_abbreviated();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'AM PM stand alone abbreviated');
$am_pm = $locale->am_pm_stand_alone_narrow();
is_deeply ($am_pm, { am => 'a', noon => 'n', pm => 'p' }, 'AM PM stand alone narrow');

my $era = $locale->era_wide();
is_deeply ($era, [ 'قبل الميلاد','ميلادي' ], 'Era wide');
$era = $locale->era_abbreviated();
is_deeply ($era, [ 'ق.م',  'م' ], 'Era abbreviated');
$era = $locale->era_narrow();
is_deeply ($era, [ 'ق.م',  'م' ], 'Era narrow');
$era = $locale->era_format_wide();
is_deeply ($era, [ 'قبل الميلاد','ميلادي' ], 'Era format wide');
$era = $locale->era_format_abbreviated();
is_deeply ($era, [ 'ق.م',  'م' ], 'Era format abbreviated');
$era = $locale->era_format_narrow();
is_deeply ($era, [ 'ق.م',  'م' ], 'Era format narrow');
$era = $locale->era_stand_alone_wide();
is_deeply ($era, [ 'قبل الميلاد','ميلادي' ], 'Era stand alone wide');
$era = $locale->era_stand_alone_abbreviated();
is_deeply ($era, [ 'ق.م',  'م' ], 'Era stand alone abbreviated');
$era = $locale->era_stand_alone_narrow();
is_deeply ($era, [ 'ق.م',  'م' ], 'Era stand alone narrow');

my $day_period_data = $locale->get_day_period('0000');
is($day_period_data, 'ص', 'Day period data AM');
$day_period_data = $locale->get_day_period('1200');
is($day_period_data, 'م', 'Day period data Noon');
$day_period_data = $locale->get_day_period('1210');
is($day_period_data, 'م', 'Day period data PM');

my $date_format = $locale->date_format_full;
is($date_format, 'EEEE، d MMMM، y', 'Date Format Full');
$date_format = $locale->date_format_long;
is($date_format, 'd MMMM، y', 'Date Format Long');
$date_format = $locale->date_format_medium;
is($date_format, 'dd‏/MM‏/y', 'Date Format Medium');
$date_format = $locale->date_format_short;
is($date_format, 'd‏/M‏/y', 'Date Format Short');

my $time_format = $locale->time_format_full;
is($time_format, 'h:mm:ss a zzzz', 'Time Format Full');
$time_format = $locale->time_format_long;
is($time_format, 'h:mm:ss a z', 'Time Format Long');
$time_format = $locale->time_format_medium;
is($time_format, 'h:mm:ss a', 'Time Format Medium');
$time_format = $locale->time_format_short;
is($time_format, 'h:mm a', 'Time Format Short');

my $date_time_format = $locale->datetime_format_full;
is($date_time_format, "EEEE، d MMMM، y h:mm:ss a zzzz", 'Date Time Format Full');
$date_time_format = $locale->datetime_format_long;
is($date_time_format, "d MMMM، y h:mm:ss a z", 'Date Time Format Long');
$date_time_format = $locale->datetime_format_medium;
is($date_time_format, 'dd‏/MM‏/y h:mm:ss a', 'Date Time Format Medium');
$date_time_format = $locale->datetime_format_short;
is($date_time_format, 'd‏/M‏/y h:mm a', 'Date Time Format Short');

is ($locale->prefers_24_hour_time(), 0, 'Prefers 24 hour time');
is ($locale->first_day_of_week(), 6, 'First day of week');

$locale = Locale::CLDR->new('ar_Arab_EG_u_ca_islamic');

$months = $locale->month_format_wide();
is_deeply ($months, [ 'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة' ], 'Islamic Month format wide');
$months = $locale->month_format_abbreviated();
is_deeply ($months, [ 'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة' ], 'Islamic Month format abbreviated');
$months = $locale->month_format_narrow();
is_deeply ($months, [qw( ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩ ١٠ ١١ ١٢ )], 'Islamic Month format narrow');
$months = $locale->month_stand_alone_wide();
is_deeply ($months, ['محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'], 'Islamic Month stand alone wide');
$months = $locale->month_stand_alone_abbreviated();
is_deeply ($months, [ 'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'], 'Islamic Month stand alone abbreviated');
$months = $locale->month_stand_alone_narrow();
is_deeply ($months, [qw( ١ ٢ ٣ 4 ٥ ٦ ٧ ٨ ٩ ١٠ ١١ ١٢ )], 'Islamic Month stand alone narrow');

$days = $locale->day_format_wide();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Islamic Day format wide');
$days = $locale->day_format_abbreviated();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Islamic Day format abbreviated');
$days = $locale->day_format_narrow();
is_deeply ($days, [qw( ن ث ر خ ج س ح )], 'Islamic Day format narrow');
$days = $locale->day_stand_alone_wide();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Islamic Day stand alone wide');
$days = $locale->day_stand_alone_abbreviated();
is_deeply ($days, [qw( الاثنين الثلاثاء الأربعاء الخميس الجمعة السبت الأحد )], 'Islamic Day stand alone abbreviated');
$days = $locale->day_stand_alone_narrow();
is_deeply ($days, [qw( ن ث ر خ ج س ح )], 'Islamic Day stand alone narrow');

$quarters = $locale->quarter_format_wide();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Islamic Quarter format wide');
$quarters = $locale->quarter_format_abbreviated();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Islamic Quarter format abbreviated');
$quarters = $locale->quarter_format_narrow();
is_deeply ($quarters, [qw( ١ ٢ ٣ ٤ )], 'Islamic Quarter format narrow');
$quarters = $locale->quarter_stand_alone_wide();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Islamic Quarter stand alone wide');
$quarters = $locale->quarter_stand_alone_abbreviated();
is_deeply ($quarters, [ 'الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع' ], 'Islamic Quarter stand alone abbreviated');
$quarters = $locale->quarter_stand_alone_narrow();
is_deeply ($quarters, [qw( ١ ٢ ٣ ٤ )], 'Islamic Quarter stand alone narrow');

$am_pm = $locale->am_pm_wide();
is_deeply ($am_pm, [qw( ص م )], 'Islamic AM PM wide');
$am_pm = $locale->am_pm_abbreviated();
is_deeply ($am_pm, [qw( ص م )], 'Islamic AM PM abbreviated');
$am_pm = $locale->am_pm_narrow();
is_deeply ($am_pm, [qw( a p )], 'Islamic AM PM narrow');
$am_pm = $locale->am_pm_format_wide();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'Islamic AM PM format wide');
$am_pm = $locale->am_pm_format_abbreviated();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'Islamic AM PM format abbreviated');
$am_pm = $locale->am_pm_format_narrow();
is_deeply ($am_pm, { am => 'a', noon => 'n', pm => 'p' }, 'Islamic AM PM format narrow');
$am_pm = $locale->am_pm_stand_alone_wide();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'Islamic AM PM stand alone wide');
$am_pm = $locale->am_pm_stand_alone_abbreviated();
is_deeply ($am_pm, { am => 'ص', noon => 'noon', pm => 'م' }, 'Islamic AM PM stand alone abbreviated');
$am_pm = $locale->am_pm_stand_alone_narrow();
is_deeply ($am_pm, { am => 'a', noon => 'n', pm => 'p' }, 'Islamic AM PM stand alone narrow');

$era = $locale->era_wide();
is_deeply ($era, [ 'هـ', undef() ], 'Islamic Era wide');
$era = $locale->era_abbreviated();
is_deeply ($era, [ 'هـ', undef() ], 'Islamic Era abbreviated');
$era = $locale->era_narrow();
is_deeply ($era, [ 'هـ', undef() ], 'Islamic Era narrow');
$era = $locale->era_format_wide();
is_deeply ($era, [ 'هـ'], 'Islamic Era format wide');
$era = $locale->era_format_abbreviated();
is_deeply ($era, [ 'هـ' ], 'Islamic Era format abbreviated');
$era = $locale->era_format_narrow();
is_deeply ($era, [ 'هـ' ], 'Islamic Era format narrow');
$era = $locale->era_stand_alone_wide();
is_deeply ($era, [ 'هـ' ], 'Islamic Era stand alone wide');
$era = $locale->era_stand_alone_abbreviated();
is_deeply ($era, [ 'هـ' ], 'Islamic Era stand alone abbreviated');
$era = $locale->era_stand_alone_narrow();
is_deeply ($era, [ 'هـ' ], 'Islamic Era stand alone narrow');

$day_period_data = $locale->get_day_period('0000');
is($day_period_data, 'ص', 'Islamic Day period data AM');
$day_period_data = $locale->get_day_period('1200');
is($day_period_data, 'م', 'Islamic Day period data Noon');
$day_period_data = $locale->get_day_period('1210');
is($day_period_data, 'م', 'Islamic Day period data PM');

$date_format = $locale->date_format_full;
is($date_format, 'EEEE‏، ‎‏d ‏MMMM‏، y‏ G', 'Islamic Date Format Full');
$date_format = $locale->date_format_long;
is($date_format, 'd‏ MMMM‏، y ‏G', 'Islamic Date Format Long');
$date_format = $locale->date_format_medium;
is($date_format, 'd‏ MMM‏، y ‏G', 'Islamic Date Format Medium');
$date_format = $locale->date_format_short;
is($date_format, 'd‏/M‏/y‏ GGGGG', 'Islamic Date Format Short');

$time_format = $locale->time_format_full;
is($time_format, 'h:mm:ss a zzzz', 'Islamic Time Format Full');
$time_format = $locale->time_format_long;
is($time_format, 'h:mm:ss a z', 'Islamic Time Format Long');
$time_format = $locale->time_format_medium;
is($time_format, 'h:mm:ss a', 'Islamic Time Format Medium');
$time_format = $locale->time_format_short;
is($time_format, 'h:mm a', 'Islamic Time Format Short');

$date_time_format = $locale->datetime_format_full;
is($date_time_format, "EEEE‏، ‎‏d ‏MMMM‏، y‏ G h:mm:ss a zzzz", 'Islamic Date Time Format Full');
$date_time_format = $locale->datetime_format_long;
is($date_time_format, "d‏ MMMM‏، y ‏G h:mm:ss a z", 'Islamic Date Time Format Long');
$date_time_format = $locale->datetime_format_medium;
is($date_time_format, 'd‏ MMM‏، y ‏G h:mm:ss a', 'Islamic Date Time Format Medium');
$date_time_format = $locale->datetime_format_short;
is($date_time_format, 'd‏/M‏/y‏ GGGGG h:mm a', 'Islamic Date Time Format Short');

is ($locale->prefers_24_hour_time(), 0, 'Islamic Prefers 24 hour time');
is ($locale->first_day_of_week(), 6, 'Islamic First day of week');

# Number Overrides
$locale = Locale::CLDR->new('ks');
is_deeply([$locale->get_digits], [qw(۰ ۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹)], 'Get digits ks');
is($locale->format_number(12345678.9, '#,####,00'), "۱۲٬۳۴۵۶٬۷۸٫۹", 'Format with grouping');
$locale = Locale::CLDR->new('ks_u_numbers_latn');
is_deeply([$locale->get_digits], [qw( 0 1 2 3 4 5 6 7 8 9 )], 'Get digits ks');
is($locale->format_number(12345678.9, '#,####,00'), "12,3456,78.9", 'Format with grouping');
