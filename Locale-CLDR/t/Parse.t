use Test;
use strict;
use warnings;
use charnames ':full';

BEGIN { plan tests => 46 };

use Unicode::Set qw(parse);
ok(1); # If we made it this far, we're ok.

ok(parse('[A-Z]'),
	 '' . qr'[A-Z]');

ok(parse('[a-z A-Z]'),
	 '' . qr'[a-zA-Z]');

ok(parse('[[a-z] | [A-Z]]'),
	 '' . qr'(?:[a-z]|[A-Z])');

ok(parse('[a-z A-Z 0-9]'),
	 '' . qr'[a-zA-Z0-9]');

ok(parse('[[a-z] | [A-Z] | [0-9]]'),
	 '' . qr'(?:[a-z]|[A-Z]|[0-9])');

ok(parse('[[a-z  A-Z] | [0-9]]'),
	 '' . qr'(?:[a-zA-Z]|[0-9])');

ok(parse('[[a-z] [[A-Z]] [0-9]]'),
	 '' . qr'(?:[a-z]|[A-Z]|[0-9])');

ok(parse('[[a-z] - [A-Z]]'),
	 '' . qr'(?:(?![A-Z])[a-z])');

ok(parse('[[a-z] - [A-Z \r \n]]'),
	 '' . qr'(?:(?![A-Z\r\n])[a-z])');

ok(parse('[[a-z] - [A-Z] - [\r] - [\n]]'),
	 '' . qr'(?:(?![A-Z]|[\r]|[\n])[a-z])');

ok(parse('[[a-z xyz0-9] - [A-Z] - [\r\n]]'),
	'' . qr'(?:(?![A-Z]|[\r\n])[a-zxyz0-9])');

ok(parse('[\p{Latin} - [[A-Z] - [AEIOUaeiou]]]'),
	'' . qr'(?:(?!(?:(?![AEIOUaeiou])[A-Z]))\p{Latin})');

ok(parse('[[A-Z] & \p{Latin}]'),
	'' . qr'(?:(?=\p{Latin})[A-Z])');

ok(parse('[[A-Z] & \p{Latin} 0-9]'),
	'' . qr'(?:(?=(?:\p{Latin}|[0-9]))[A-Z])');

ok(parse('[[A-Z] & [C-Q] & [K-S]]'),
	'' . qr'(?:(?=[C-Q])(?=[K-S])[A-Z])');

ok(parse('[\p{L} [\p{Zs} A-Z] - \p{Nd} \p{Pi}]'),
	'' . qr'(?:\p{L}|(?:(?!(?:\p{Nd}|\p{Pi}))(?:\p{Zs}|[A-Z])))');

ok(parse('[[A-Z] & [ABC L-Q] & [[K-S] - [QRS]]]'),
	'' . qr'(?:(?=[ABCL-Q])(?=(?:(?![QRS])[K-S]))[A-Z])');

ok(parse('[\p{Latin} & \p{L&} - \p{ASCII}]'),
	'' . qr'(?:(?=(?:(?!\p{ASCII})\p{L&}))\p{Latin})');

ok(parse('[ [\[-\]] & [abc\ xyz] ]'),
	'' . qr'(?:(?=[abc\ xyz])[\[-\]])');

ok(parse('[^ A-Z]'),
	'' . qr'(?:(?![A-Z])(?s:.))');

ok(parse('[ ^A-Z PERL]'),
	'' . qr'[^A-ZPERL]');

ok(parse('[^ a-z A-Z 0-9]'),
	'' . qr'(?:(?![a-zA-Z0-9])(?s:.))');

ok(parse('[^A-Z a-z 0-9]'),
	'' . qr'(?:(?![A-Za-z0-9])(?s:.))');

ok(parse('[^[A-Z a-z 0-9]]'),
	'' .qr'(?:(?![A-Za-z0-9])(?s:.))');

ok(parse('[^[B-Z] & [A-D]]'),
	'' .qr'(?:(?!(?:(?=[A-D])[B-Z]))(?s:.))');

ok(parse('[^[A-Z] - [PERL]]'),
	'' .qr'(?:(?!(?:(?![PERL])[A-Z]))(?s:.))');

ok(parse('[[A-Z] - [^ PERL]]'),
	'' .qr'(?:(?!(?:(?![PERL])(?s:.)))[A-Z])');

ok(parse('[[A-Z] & [^JUNK]]'),
	'' . qr'(?:(?=(?:(?![JUNK])(?s:.)))[A-Z])');

ok(parse('[^ [A-Z] - [^pqr] ]'),
	'' . qr'(?:(?!(?:(?!(?:(?![pqr])(?s:.)))[A-Z]))(?s:.))');

ok(parse('[\] \-\ 	 ]'),
	 '' . qr'[\]\-\ ]');

ok(parse('[\p{letter} \p{decimal number}]'),
	'' . qr'(?:\p{letter}|\p{decimal number})');

ok(parse('[\p{alnum} - \P{decimal number}]'),
	'' . qr'(?:(?!\P{decimal number})\p{alnum})');

my $qr = '(?:(?![' . "\x{3B1}" . '])\p{Greek})';
ok(parse("[\\p{Greek} - [\N{GREEK SMALL LETTER ALPHA}]]"),
	'' . qr/$qr/);

ok(parse('[\p{Assigned} - \p{Decimal Digit Number} - [a-f A-F]]'),
	'' . qr'(?:(?!\p{Decimal Digit Number}|[a-fA-F])\p{Assigned})');

ok(parse('[[\x00-\x7F] - [^\p{Latin}]]'),
	'' . qr'(?:(?!(?:(?!\p{Latin})(?s:.)))[\x00-\x7F])');

ok(parse('[[\x00-\x7F][^\p{Latin}]]'),
	'' . qr'(?:[\x00-\x7F]|(?:(?!\p{Latin})(?s:.)))');

ok(parse('[[\x00-\x7F][^[:alpha:]]]'),
	'' . qr'(?:[\x00-\x7F]|(?:(?![\p{L&}])(?s:.)))');

ok(parse('[[\x00-\x7F] [-A-Z]]'),
	'' . qr'(?:[\x00-\x7F]|[-A-Z])');

ok(parse('[[0-9] [-TEST]]'),
	'' . qr'(?:[0-9]|[-TEST])');

ok(parse('[[0-] [TEST]]'),
	'' . qr'(?:[0-]|[TEST])');

ok(parse('[0\- TEST]'),
	'' . qr'[0\-TEST]');

ok(parse('[0\c[]'),
	'' . qr'[0\c[]');

ok(parse('[\c]\c\]'),
	'' .qr'[\c]\c\]');

