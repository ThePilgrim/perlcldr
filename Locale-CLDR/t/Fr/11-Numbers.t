#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 12;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale_en = Locale::CLDR->new('fr_FR');
is_deeply([$locale_en->get_digits], [0 .. 9], 'Get digits fr');

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
is($locale_en->format_number(12345.6, '###,##0.###'), '12 345,6', 'Format a number');
is($locale_en->format_number(12345.6, '###,#00%'), '1 234 560%', 'Format a percent');
is($locale_en->format_number(12345.6, '###,#00‰'), '12 345 600‰', 'Format a per thousand' );
is($locale_en->format_number(12345678, '#,####,00%'), '1234 5678 00%', 'Format percent with different grouping');

# RBNF
is($locale_en->format_number(0, 'spellout-numbering-year'), 'zéro', 'RBNF: Spell out year 0');
is($locale_en->format_number('-0.0', 'spellout-numbering'), 'moins zéro virgule zéro', 'RBNF: Spell out -0.0');
is($locale_en->format_number(123456, 'roman-lower'), '123 456', 'Roman number grater than max value');
is($locale_en->format_number(1234, 'roman-lower'), 'mccxxxiv', 'Roman Number');

