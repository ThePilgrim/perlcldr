#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 3;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale_en = Locale::CLDR->new('en_GB');
my $locale_ks = Locale::CLDR->new('ks');

is($locale_en->format_number(12345678, '¤###,###'), '£12,345,678', 'Format currency with default currency');
is($locale_ks->format_number(12345678.9, '¤###,###', 'USD'), 'US$۱۲٬۳۴۵٬۶۷۸٫۹', 'Format with currency with explicit currency');