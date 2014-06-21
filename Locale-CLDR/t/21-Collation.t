#!/usr/bin/perl
use Test::More tests => 2;

use ok 'Locale::CLDR';

my $locale_de = Locale::CLDR->new('de');

my $collation = $locale_de->collation();

is_deeply([$collation->sort(qw(10 a b c d e 1 2 3 4 5))], [qw(1 10 2 3 4 5 a b c d e)], 'Basic sort');