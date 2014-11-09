#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 558;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en');

#                   0    1   2   3   4         5 .. 8       9       10 .. 19,            20    21  22 23   24      25 .. 28       29   30 .. 69
my @results = ((((qw( other one two few few ), ('other') x 4, 'few'), ('other') x 10), (qw( other one two few few ), ('other') x 4, 'few') x 5,
#         70 .. 79         80   81  82  83  84         85 .. 88     89       90 .. 99   100 .. 199
      ('other') x 10, qw( other one two few few ), ('other') x 4, 'few', ('other') x 10 ) x  2);

for (my $count = 0; $count < @results; $count++) {
	is ($locale->plural($count), $results[$count], "Plural for $count in en");
}

$locale = Locale::CLDR->new('ar');

#                   0    1   2   3   4   5   6   7   8   9   10      11 .. 99        100    101   102  103 104 105 106 107 108 109 110     111     199
@results = (qw( zero one two few few few few few few few few ), ('many') x 89, qw(other other other few few few few few few few few), ('many') x 88);

for (my $count = 0; $count < @results; $count++) {
	is ($locale->plural($count), $results[$count], "Plural for $count in ar");
}

@results = (qw(other zero zero few many), ('other') x 4, (qw(few many), ('other') x 4) x 4, qw(few many other));
my $count = 0;
foreach my $start (qw(zero one two few many other)) {
	foreach my $end (qw(zero one two few many other)) {
		is ($locale->plural_range($start, $end), $results[$count++], "Plural range $start - $end in ar");
	}
}

@results = (qw(other zero zero), ('few') x 8, (('other') x 3, ('few') x 8) x 10 );
$count = 0;
foreach my $start (0 .. 10) {
	foreach my $end (0 .. 10) {
		is ($locale->plural_range($start, $end), $results[$count++], "Plural range $start - $end in ar");
	}
}

is ($locale->plural_range(2.73, 6.43), 'few', "Plural range 2.73 - 6.43 in ar");