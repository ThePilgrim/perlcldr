#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 2;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en');
is_deeply([$locale->get_digits], [0 .. 9], 'Get digits');