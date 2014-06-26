#!/usr/bin/perl
use Test::More tests => 10;

use ok 'Locale::CLDR';
use ok 'Locale::CLDR::Collator';

my $collation = Locale::CLDR::Collator->new();

is_deeply([$collation->sort(qw( 1 £ ৴ ))], [qw(1 ৴ £)], 'Using CLDR root collation');
is_deeply([$collation->sort(qw(John john Fred Fréd))], [qw(Fréd Fred john John)], 'Collation with longer words');
is_deeply([$collation->sort(qw(John J Joh Jo))], [qw(J Jo Joh John)], 'Collation with sub strings');
is_deeply([$collation->sort(qw(áe Aé))], [qw(Aé áe)], 'Case and accents');

# level handling
my @sorted = (
	undef,
	['ae', 'Ae', 'a e', 'A e', 'áe', 'Áe', 'á e', 'Á e'],
	['ae', 'Ae', 'a e', 'A e', 'Áe', 'áe', 'Á e', 'á e'],
	['ae', 'Ae', 'a e', 'A e', 'Áe', 'áe', 'Á e', 'á e'],
	['ae', 'Ae', 'a e', 'A e', 'Áe', 'Á e', 'áe', 'á e']
);
foreach my $level ( 1 .. 4) {
	$collation = Locale::CLDR::Collator->new(strength => $level);
	is_deeply([$collation->sort('ae', 'Ae', 'a e', 'A e', 'áe', 'Áe', 'á e', 'Á e')], $sorted[$level], "Sorted at level $level");
}
	