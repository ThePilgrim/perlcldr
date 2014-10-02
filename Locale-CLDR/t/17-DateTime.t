#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 4;
use Test::Exception;

use ok 'Locale::CLDR';

use DateTime;

my $en_gb = Locale::CLDR->new('en_GB');
my $en_us = Locale::CLDR->new('en_US');
my $fr_ca = Locale::CLDR->new('fr_CA');

my $dt_en_gb = DateTime->new(
	year => 1966,
	month => 10,
	day        => 25,
    hour       => 7,
    minute     => 15,
    second     => 47,
    locale 	   => $en_gb,
	time_zone  => 'Europe/London',
);

my $dt_en_us = DateTime->new(
	year => 1966,
	month => 10,
	day        => 25,
    hour       => 7,
    minute     => 15,
    second     => 47,
    locale 	   => $en_us,
	time_zone  => 'Europe/London',
);

my $dt_fr_ca = DateTime->new(
	year => 1966,
	month => 10,
	day        => 25,
    hour       => 7,
    minute     => 15,
    second     => 47,
    locale 	   => $fr_ca,
	time_zone  => 'Europe/London',
);

is ($dt_en_gb->format_cldr($en_gb->datetime_format_full), 'Tuesday, 25 October 1966 at 07:15:47 Europe/London', 'Date Time Format Full British English ');
is ($dt_en_us->format_cldr($en_us->datetime_format_full), 'Tuesday, October 25, 1966 at 7:15:47 am Europe/London', 'Date Time Format Full US English ');
is ($dt_fr_ca->format_cldr($fr_ca->datetime_format_full), 'mardi 25 octobre 1966 à 07 h 15 min 47 s Europe/London', 'Date Time Format Full French Canadian');