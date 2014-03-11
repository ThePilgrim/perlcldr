#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 8;
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