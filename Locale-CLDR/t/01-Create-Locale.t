#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 16;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new();
is($locale->id, 'und', 'Empty Locale');

$locale = Locale::CLDR->new(language_id => 'en');
is($locale->id, 'en', 'Set Language explicitly');

$locale = Locale::CLDR->new('en');
is($locale->id, 'en', 'Set Language implicitly');

$locale = Locale::CLDR->new(language_id => 'en', territory_id => 'gb');
is($locale->id, 'en_GB', 'Set Language and Territory explicitly');

$locale = Locale::CLDR->new('en-gb');
is($locale->id, 'en_GB', 'Set Language and Territory implicitly');

$locale = Locale::CLDR->new(language_id => 'en', script_id => 'latn');
is($locale->id, 'en_Latn', 'Set Language and Script explicitly');

$locale = Locale::CLDR->new('en-latn');
is($locale->id, 'en_Latn', 'Set Language and Script implicitly');

$locale = Locale::CLDR->new(language_id => 'en', territory_id => 'gb', script_id => 'latn');
is($locale->id, 'en_Latn_GB', 'Set Language, Territory and Script explicitly');

$locale = Locale::CLDR->new('en-latn-gb');
is($locale->id, 'en_Latn_GB', 'Set Language, Territory and Script implicitly');

$locale = Locale::CLDR->new(language_id => 'en', variant_id => '1994');
is($locale->id, 'en_1994', 'Set Language and Variant from string explicitly');

$locale = Locale::CLDR->new('en_1994');
is($locale->id, 'en_1994', 'Set Language and variant implicitly');

$locale = Locale::CLDR->new('en_latn_gb_1994');
is($locale->id, 'en_Latn_GB_1994', 'Set Language, Territory, Script and variant implicitly');

throws_ok { $locale = Locale::CLDR->new('wibble') } qr/Invalid language/, "Caught invalid language";
throws_ok { $locale = Locale::CLDR->new('en_wi') } qr/Invalid territory/, "Caught invalid territory";
throws_ok { $locale = Locale::CLDR->new('en_wibb') } qr/Invalid script/, "Caught invalid script";
