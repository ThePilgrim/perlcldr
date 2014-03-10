#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 9;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale_en = Locale::CLDR->new('en');
is_deeply([$locale_en->get_digits], [0 .. 9], 'Get digits en');
my $locale_ks = Locale::CLDR->new('ks');
is_deeply([$locale_ks->get_digits], [qw(۰ ۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹)], 'Get digits ks');
my $format_data = {
	positive 	=> {
		exponent_digits				=> 0,
		exponent_needs_plus			=> 0,
		major_group					=> 3,
		maximum_significant_digits	=> undef,
		minimum_digits				=> 1,
		minimum_significant_digits	=> undef,
		minor_group					=> 3,
		multiplier					=> 1,
		pad_character				=> undef,
		pad_length					=> 0,
		pad_location				=> 'none',
		prefix						=> '',
		rounding					=> 0,
		suffix						=> '',
	},
	negative 	=> {
		exponent_digits				=> 0,
		exponent_needs_plus			=> 0,
		major_group					=> 3,
		maximum_significant_digits	=> undef,
		minimum_digits				=> 1,
		minimum_significant_digits	=> undef,
		minor_group					=> 3,
		pad_character				=> undef,
		pad_length					=> 0,
		pad_location				=> 'none',
		prefix						=> '',
		multiplier					=> 1,
		rounding					=> 0,
		suffix						=> '',
	},
};

is_deeply($locale_en->parse_number_format('###,##0.###'), $format_data, 'Basic Number format');
$format_data->{negative}{pad_character} = 'x';
$format_data->{negative}{pad_length} = 19;
$format_data->{negative}{pad_location}	= 'after suffix';
$format_data->{negative}{suffix} = " food ";
is_deeply($locale_en->parse_number_format('###,##0.###;###,##0.### \'food\' *x'), $format_data, 'A more complex Number format');
is($locale_en->format_number(12345.6, '###,##0.###'), '12,345.6', 'Format a number');
is($locale_en->format_number(12345.6, '###,#00%'), '1,234,560%', 'Format a percent');
is($locale_en->format_number(12345678, '#,####,00%'), '1234,5678,00%', 'Format percent with different grouping');
is($locale_ks->format_number(12345678.9, '#,####,00'), "۱۲٬۳۴۵۶٬۷۸٫۹", 'Format with different grouping and different digits');