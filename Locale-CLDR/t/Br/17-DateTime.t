#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 2;
use Test::Exception;

use ok 'Locale::CLDR';

use DateTime;

my $locale = Locale::CLDR->new('br_FR');

my $dt_br_fr = DateTime->new(
	year => 1966,
	month => 10,
	day        => 25,
    hour       => 7,
    minute     => 15,
    second     => 47,
    locale 	   => $locale,
	time_zone  => 'Europe/London',
);

is ($dt_br_fr->format_cldr($locale->datetime_format_full), 'Meurzh 25 Here 1966, 07:15:47 Europe/London', 'Date Time Format Full Breton');