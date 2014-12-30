#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 3;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale_en = Locale::CLDR->new('br_FR');

is($locale_en->format_number(12345678, '¤###,###'), '€12 345 678,00', 'Format currency with default currency');
is($locale_en->format_number(12345678.9, '¤###,###', 'USD'), 'US$12 345 678,90', 'Format currency with explicit currency');