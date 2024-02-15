#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 31;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en');
is_deeply([$locale->get_digits], [0 .. 9], 'Get digits en');
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
		prefix						=> '\\-',
		multiplier					=> 1,
		rounding					=> 0,
		suffix						=> '',
	},
};

is_deeply($locale->parse_number_format('###,##0.###'), $format_data, 'Basic Number format');
$format_data->{negative}{pad_character} = 'x';
$format_data->{negative}{pad_length} = 19;
$format_data->{negative}{pad_location}	= 'after suffix';
$format_data->{negative}{suffix} = " food ";
$format_data->{negative}{prefix} = "";
is_deeply($locale->parse_number_format('###,##0.###;###,##0.### \'food\' *x'), $format_data, 'A more complex Number format');
is($locale->format_number(12345.6, '###,##0.###'), '12,345.6', 'Format a number');
is($locale->format_number(12345.6, '###,#00%'), '1,234,560%', 'Format a percent');
is($locale->format_number(12345.6, '###,#00‰'), '12,345,600‰', 'Format a per thousand' );
is($locale->format_number(12345678, '#,####,00%'), '1234,5678,00%', 'Format percent with different grouping');

# Negative numbers
is($locale->format_number(-12345.6, '###,##0.###'), '-12,345.6', 'Format a negative number');
is($locale->format_number(-12345.6, '###,#00%'), '-1,234,560%', 'Format a negative percent');
is($locale->format_number(-12345.6, '###,#00‰'), '-12,345,600‰', 'Format a negative per thousand' );
is($locale->format_number(-12345678, '#,####,00%'), '-1234,5678,00%', 'Format negative percent with different grouping');


# RBNF
is($locale->format_number(0, 'spellout-numbering-year'), 'zero', 'RBNF: Spell out year 0');
is($locale->format_number('-0.0', 'spellout-numbering'), 'minus zero point zero', 'RBNF: Spell out -0.0');
is($locale->format_number(123456, 'roman-lower'), '123,456', 'Roman Number grater than max value');
is($locale->format_number(1234, 'roman-lower'), 'mccxxxiv', 'Roman Number');
is($locale->format_number(123, 'digits-ordinal'), '123rd', 'Ordinal Numbers');

# Now with number override
$locale = Locale::CLDR->new('en-u-numbers-adlm');
is_deeply([$locale->get_digits], [qw(𞥐 𞥑 𞥒 𞥓 𞥔 𞥕 𞥖 𞥗 𞥘 𞥙)], 'Get digits en with Adlam didgits');
is($locale->format_number(12345.6, '###,##0.###'), '𞥑𞥒,𞥓𞥔𞥕.𞥖', 'Format a number with Adlam didgits');
is($locale->format_number(12345.6, '###,#00%'), '𞥑,𞥒𞥓𞥔,𞥕𞥖𞥐%', 'Format a percent with Adlam didgits');
is($locale->format_number(12345.6, '###,#00‰'), '𞥑𞥒,𞥓𞥔𞥕,𞥖𞥐𞥐‰', 'Format a per thousand with Adlam didgits' );
is($locale->format_number(12345678, '#,####,00%'), '𞥑𞥒𞥓𞥔,𞥕𞥖𞥗𞥘,𞥐𞥐%', 'Format percent with different grouping with Adlam didgits');

# Negative numbers
is($locale->format_number(-12345.6, '###,##0.###'), '-𞥑𞥒,𞥓𞥔𞥕.𞥖', 'Format a negative number with Adlam didgits');
is($locale->format_number(-12345.6, '###,#00%'), '-𞥑,𞥒𞥓𞥔,𞥕𞥖𞥐%', 'Format a negative percent with Adlam didgits');
is($locale->format_number(-12345.6, '###,#00‰'), '-𞥑𞥒,𞥓𞥔𞥕,𞥖𞥐𞥐‰', 'Format a negative per thousand with Adlam didgits' );
is($locale->format_number(-12345678, '#,####,00%'), '-𞥑𞥒𞥓𞥔,𞥕𞥖𞥗𞥘,𞥐𞥐%', 'Format negative percent with different grouping with Adlam didgits');


# RBNF
is($locale->format_number(0, 'spellout-numbering-year'), 'zero', 'RBNF: Spell out year 0 with Adlam didgits');
is($locale->format_number('-0.0', 'spellout-numbering'), 'minus zero point zero', 'RBNF: Spell out -0.0 with Adlam didgits');
is($locale->format_number(123456, 'roman-lower'), '𞥑𞥒𞥓,𞥔𞥕𞥖', 'Roman Number grater than max value with Adlam didgits');
is($locale->format_number(1234, 'roman-lower'), 'mccxxxiv', 'Roman Number with Adlam didgits');
is($locale->format_number(123, 'digits-ordinal'), '𞥑𞥒𞥓rd', 'Ordinal Numbers with Adlam didgits');
