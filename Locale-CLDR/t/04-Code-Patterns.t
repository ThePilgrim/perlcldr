#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 4;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en');

my $test = Locale::CLDR->new('az_latn_az');
is ($locale->code_pattern('language', $test), 'Language: Azerbaijani', 'Code pattern Language');
is ($locale->code_pattern('script', $test), 'Script: Latin', 'Code pattern script');
is ($locale->code_pattern('territory', $test), 'Region: Azerbaijan', 'Code pattern territory');