#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 40;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en_GB');
my $months = $locale->month_format_wide();
is_deeply ($months, [qw( January February March April May June July August September October November December )], 'Month format wide');
$months = $locale->month_format_abbreviated();
is_deeply ($months, [qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec )], 'Month format abbreviated');
$months = $locale->month_format_narrow();
is_deeply ($months, [qw( J F M A M J J A S O N D )], 'Month format narrow');
$months = $locale->month_stand_alone_wide();
is_deeply ($months, [qw( January February March April May June July August September October November December )], 'Month stand alone wide');
$months = $locale->month_stand_alone_abbreviated();
is_deeply ($months, [qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec )], 'Month stand alone abbreviated');
$months = $locale->month_stand_alone_narrow();
is_deeply ($months, [qw( J F M A M J J A S O N D )], 'Month stand alone narrow');

my $days = $locale->day_format_wide();
is_deeply ($days, [qw( Monday Tuesday Wednesday Thursday Friday Saturday Sunday )], 'Day format wide');
$days = $locale->day_format_abbreviated();
is_deeply ($days, [qw( Mon Tue Wed Thu Fri Sat Sun )], 'Day format abbreviated');
$days = $locale->day_format_narrow();
is_deeply ($days, [qw( M T W T F S S )], 'Day format narrow');
$days = $locale->day_stand_alone_wide();
is_deeply ($days, [qw( Monday Tuesday Wednesday Thursday Friday Saturday Sunday )], 'Day stand alone wide');
$days = $locale->day_stand_alone_abbreviated();
is_deeply ($days, [qw( Mon Tue Wed Thu Fri Sat Sun )], 'Day stand alone abbreviated');
$days = $locale->day_stand_alone_narrow();
is_deeply ($days, [qw( M T W T F S S )], 'Day stand alone narrow');

my $quarters = $locale->quarter_format_wide();
is_deeply ($quarters, ['1st quarter', '2nd quarter', '3rd quarter', '4th quarter'], 'Quarter format wide');
$quarters = $locale->quarter_format_abbreviated();
is_deeply ($quarters, [qw( Q1 Q2 Q3 Q4 )], 'Quarter format abbreviated');
$quarters = $locale->quarter_format_narrow();
is_deeply ($quarters, [qw( 1 2 3 4 )], 'Quarter format narrow');
$quarters = $locale->quarter_stand_alone_wide();
is_deeply ($quarters, [ '1st quarter', '2nd quarter', '3rd quarter', '4th quarter' ], 'Quarter stand alone wide');
$quarters = $locale->quarter_stand_alone_abbreviated();
is_deeply ($quarters, [qw( Q1 Q2 Q3 Q4 )], 'Quarter stand alone abbreviated');
$quarters = $locale->quarter_stand_alone_narrow();
is_deeply ($quarters, [qw( 1 2 3 4 )], 'Quarter stand alone narrow');

my $am_pm = $locale->am_pm_wide();
is_deeply ($am_pm, [qw( a.m. p.m. )], 'AM PM wide');
$am_pm = $locale->am_pm_abbreviated();
is_deeply ($am_pm, [qw( a.m. p.m. )], 'AM PM abbreviated');
$am_pm = $locale->am_pm_narrow();
is_deeply ($am_pm, [qw( a p )], 'AM PM narrow');
$am_pm = $locale->am_pm_format_wide();
is_deeply ($am_pm, { am => 'a.m.', noon => 'noon', pm => 'p.m.' }, 'AM PM format wide');
$am_pm = $locale->am_pm_format_abbreviated();
is_deeply ($am_pm, { am => 'a.m.', noon => 'noon', pm => 'p.m.' }, 'AM PM format abbreviated');
$am_pm = $locale->am_pm_format_narrow();
is_deeply ($am_pm, { am => 'a', noon => 'n', pm => 'p' }, 'AM PM format narrow');
$am_pm = $locale->am_pm_stand_alone_wide();
is_deeply ($am_pm, { am => 'a.m.', noon => 'noon', pm => 'p.m.' }, 'AM PM stand alone wide');
$am_pm = $locale->am_pm_stand_alone_abbreviated();
is_deeply ($am_pm, { am => 'a.m.', noon => 'noon', pm => 'p.m.' }, 'AM PM stand alone abbreviated');
$am_pm = $locale->am_pm_stand_alone_narrow();
is_deeply ($am_pm, { am => 'a', noon => 'n', pm => 'p' }, 'AM PM stand alone narrow');

my $era = $locale->era_wide();
is_deeply ($era, ['Before Christ', 'Anno Domini'], 'Era wide');
$era = $locale->era_abbreviated();
is_deeply ($era, [qw( BC AD )], 'Era abbreviated');
$era = $locale->era_narrow();
is_deeply ($era, [qw( B A )], 'Era narrow');
$era = $locale->era_format_wide();
is_deeply ($era, { 0 => 'Before Christ', 1 => 'Anno Domini' }, 'Era format wide');
$era = $locale->era_format_abbreviated();
is_deeply ($era, { 0 => 'BC', 1 => 'AD' }, 'Era format abbreviated');
$era = $locale->era_format_narrow();
is_deeply ($era, { 0 => 'B', 1 => 'A' }, 'Era format narrow');
$era = $locale->era_stand_alone_wide();
is_deeply ($era, { 0 => 'Before Christ', 1 => 'Anno Domini' }, 'Era stand alone wide');
$era = $locale->era_stand_alone_abbreviated();
is_deeply ($era, { 0 => 'BC', 1 => 'AD' }, 'Era stand alone abbreviated');
$era = $locale->era_stand_alone_narrow();
is_deeply ($era, { 0 => 'B', 1 => 'A' }, 'Era stand alone narrow');

my $day_period_data = $locale->get_day_period('0000');
is($day_period_data, 'a.m.', 'Day period data AM');
$day_period_data = $locale->get_day_period('1200');
is($day_period_data, 'noon', 'Day period data Noon');
$day_period_data = $locale->get_day_period('1210');
is($day_period_data, 'p.m.', 'Day period data PM');

