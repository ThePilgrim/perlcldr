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

use DateTime;

my $fr_fr = Locale::CLDR->new('fr_FR');
my $fr_be = Locale::CLDR->new('fr_BE');

my $dt_fr_fr = DateTime->new(
	year => 1966,
	month => 10,
	day        => 25,
    hour       => 7,
    minute     => 15,
    second     => 47,
    locale     => $fr_fr,
	time_zone  => 'Europe/London',
);

my $dt_fr_be = DateTime->new(
	year => 1966,
	month => 10,
	day        => 25,
    hour       => 7,
    minute     => 15,
    second     => 47,
    locale     => $fr_be,
	time_zone  => 'Europe/London',
);

is ($dt_fr_fr->format_cldr($fr_fr->datetime_format_full), 'mardi 25 octobre 1966 à 07:15:47 Europe/London', 'Date Time Format Full French');
is ($dt_fr_be->format_cldr($fr_be->datetime_format_full), 'mardi 25 octobre 1966 à 7 h 15 min 47 s Europe/London', 'Date Time Format Full Belgium French');