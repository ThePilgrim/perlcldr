#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.18;
use strict;
use warnings;
use utf8;
use feature 'unicode_strings';

use Test::More tests => 8;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en');

ok($locale->is_exemplar_character("A"), 'Is Exemplar Character');
ok(!$locale->is_exemplar_character('@'), 'Is not Exemplar Character');
ok($locale->is_exemplar_character('auxiliary', "\N{U+00EA}"), 'Is Auxiliary Exemplar Character');
ok(!$locale->is_exemplar_character('auxiliary','@'), 'Is not Auxiliary Exemplar Character');
ok($locale->is_exemplar_character('punctuation', "!"), 'Is Punctiation Exemplar Character');
ok(!$locale->is_exemplar_character('punctuation', 'a'), 'Is not Punctiation Exemplar Character');
is("@{$locale->index_characters()}", 'A B C D E F G H I J K L M N O P Q R S T U V W X Y Z', 'Index Characters');
