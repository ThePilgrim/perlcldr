#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 27;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('fr_FR');

is($locale->format_number(12345678, '¤###,###'), '€12 345 678,00', 'Format currency with default currency');
is($locale->format_number(12345678.9, '¤###,###', 'USD'), 'US$12 345 678,90', 'Format currency with explicit currency');

is($locale->format_number(12345678, '¤###,###'), '€12 345 678,00', 'Format currency with default currency');
is($locale->currency_format('standard'), '#,##0.00 ¤', 'Standard currency format');
is($locale->currency_format('accounting'), '#,##0.00 ¤;(#,##0.00 ¤)', 'Accountcy currency format');

$locale = Locale::CLDR->new('fr_FR_u_cf_standard');
is($locale->currency_format(), '#,##0.00 ¤', 'Currency format with standard default');
is($locale->format_currency(123456.78), '123 456,78 €', 'Format currency with standard format, positive number and financial rounding');
is($locale->format_currency(123456.78, 'cash'), '123 456,78 €', 'Format currency with standard format, positive number and cash rounding');
is($locale->format_currency(-123456.78), '-123 456,78 €', 'Format currency with standard format, negitive number and financial rounding');
is($locale->format_currency(-123456.78, 'cash'), '-123 456,78 €', 'Format currency with standard format, negitive number and cash rounding');

$locale = Locale::CLDR->new('fr_FR_u_cf_standard_cu_gbp');
is($locale->currency_format(), '#,##0.00 ¤', 'Currency format with standard default');
is($locale->format_currency(123456.78), '123 456,78 £', 'Format currency with standard format, positive number and financial rounding and pound currency');
is($locale->format_currency(123456.78, 'cash'), '123 456,78 £', 'Format currency with standard format, positive number and cash rounding and pound currency');
is($locale->format_currency(-123456.78), '-123 456,78 £', 'Format currency with standard format, negitive number and financial rounding and pound currency');
is($locale->format_currency(-123456.78, 'cash'), '-123 456,78 £', 'Format currency with standard format, negitive number and cash rounding and pound currency');

$locale = Locale::CLDR->new('fr_FR_u_cf_account');
is($locale->currency_format(), '#,##0.00 ¤;(#,##0.00 ¤)', 'Currency format with account default');
is($locale->format_currency(123456.78), '123 456,78 €', 'Format currency with accountancy format, positive number and financial rounding');
is($locale->format_currency(123456.78, 'cash'), '123 456,78 €', 'Format currency with accountancy format, positive number and cash rounding');
is($locale->format_currency(-123456.78), '(123 456,78 €)', 'Format currency with accountancy format, negitive number and financial rounding');
is($locale->format_currency(-123456.78, 'cash'), '(123 456,78 €)', 'Format currency with accountancy format, negitive number and cash rounding');

$locale = Locale::CLDR->new('fr_FR_u_cf_account_cu_gbp');
is($locale->currency_format(), '#,##0.00 ¤;(#,##0.00 ¤)', 'Currency format with account default');
is($locale->format_currency(123456.78), '123 456,78 £', 'Format currency with accountancy format, positive number and financial rounding and pound currency');
is($locale->format_currency(123456.78, 'cash'), '123 456,78 £', 'Format currency with accountancy format, positive number and cash rounding and pound currency');
is($locale->format_currency(-123456.78), '(123 456,78 £)', 'Format currency with accountancy format, negitive number and financial rounding and pound currency');
is($locale->format_currency(-123456.78, 'cash'), '(123 456,78 £)', 'Format currency with accountancy format, negitive number and cash rounding and pound currency');

$locale=Locale::CLDR->new('fr_US');
is($locale->format_number(12345678, '¤###,###'), 'US$12 345 678,00', 'Format currency with default currency when using the US region');
