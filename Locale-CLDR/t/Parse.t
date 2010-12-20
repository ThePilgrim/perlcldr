use Test::More;
use strict;
use warnings;
use charnames ':full';

use ok 'Unicode::Set', qw(unicode_to_perl);

ok(unicode_to_perl('[A-Z]'),
	 '' . qr'[A-Z]'msx);

ok(unicode_to_perl('[a-z A-Z]'),
	 '' . qr'[a-zA-Z]'msx);

ok(unicode_to_perl('[[a-z] | [A-Z]]'),
	 '' . qr'(?:[a-z]|[A-Z])'msx);

ok(unicode_to_perl('[a-z A-Z 0-9]'),
	 '' . qr'[a-zA-Z0-9]'msx);

ok(unicode_to_perl('[[a-z] | [A-Z] | [0-9]]'),
	 '' . qr'(?:[a-z]|[A-Z]|[0-9])'msx);

ok(unicode_to_perl('[[a-z  A-Z] | [0-9]]'),
	 '' . qr'(?:[a-zA-Z]|[0-9])'msx);

ok(unicode_to_perl('[[a-z] [[A-Z]] [0-9]]'),
	 '' . qr'(?:[a-z]|[A-Z]|[0-9])'msx);

ok(unicode_to_perl('[[a-z] - [A-Z]]'),
	 '' . qr'(?:(?![A-Z])[a-z])'msx);

ok(unicode_to_perl('[[a-z] - [A-Z \r \n]]'),
	 '' . qr'(?:(?![A-Z\r\n])[a-z])'msx);

ok(unicode_to_perl('[[a-z] - [A-Z] - [\r] - [\n]]'),
	 '' . qr'(?:(?![A-Z]|[\r]|[\n])[a-z])'msx);

ok(unicode_to_perl('[[a-z xyz0-9] - [A-Z] - [\r\n]]'),
	'' . qr'(?:(?![A-Z]|[\r\n])[a-zxyz0-9])'msx);

ok(unicode_to_perl('[\p{Latin} - [[A-Z] - [AEIOUaeiou]]]'),
	'' . qr'(?:(?!(?:(?![AEIOUaeiou])[A-Z]))\p{Latin})'msx);

ok(unicode_to_perl('[[A-Z] & \p{Latin}]'),
	'' . qr'(?:(?=\p{Latin})[A-Z])'msx);

ok(unicode_to_perl('[[A-Z] & \p{Latin} 0-9]'),
	'' . qr'(?:(?=(?:\p{Latin}|[0-9]))[A-Z])'msx);

ok(unicode_to_perl('[[A-Z] & [C-Q] & [K-S]]'),
	'' . qr'(?:(?=[C-Q])(?=[K-S])[A-Z])'msx);

ok(unicode_to_perl('[\p{L} [\p{Zs} A-Z] - \p{Nd} \p{Pi}]'),
	'' . qr'(?:\p{L}|(?:(?!(?:\p{Nd}|\p{Pi}))(?:\p{Zs}|[A-Z])))'msx);

ok(unicode_to_perl('[[A-Z] & [ABC L-Q] & [[K-S] - [QRS]]]'),
	'' . qr'(?:(?=[ABCL-Q])(?=(?:(?![QRS])[K-S]))[A-Z])'msx);

ok(unicode_to_perl('[\p{Latin} & \p{L&} - \p{ASCII}]'),
	'' . qr'(?:(?=(?:(?!\p{ASCII})\p{L&}))\p{Latin})'msx);

ok(unicode_to_perl('[ [\[-\]] & [abc\ xyz] ]'),
	'' . qr'(?:(?=[abc\ xyz])[\[-\]])'msx);

ok(unicode_to_perl('[^ A-Z]'),
	'' . qr'(?:(?![A-Z])(?s:.))'msx);

ok(unicode_to_perl('[ ^A-Z PERL]'),
	'' . qr'[^A-ZPERL]'msx);

ok(unicode_to_perl('[^ a-z A-Z 0-9]'),
	'' . qr'(?:(?![a-zA-Z0-9])(?s:.))'msx);

ok(unicode_to_perl('[^A-Z a-z 0-9]'),
	'' . qr'(?:(?![A-Za-z0-9])(?s:.))'msx);

ok(unicode_to_perl('[^[A-Z a-z 0-9]]'),
	'' .qr'(?:(?![A-Za-z0-9])(?s:.))'msx);

ok(unicode_to_perl('[^[B-Z] & [A-D]]'),
	'' .qr'(?:(?!(?:(?=[A-D])[B-Z]))(?s:.))'msx);

ok(unicode_to_perl('[^[A-Z] - [PERL]]'),
	'' .qr'(?:(?!(?:(?![PERL])[A-Z]))(?s:.))'msx);

ok(unicode_to_perl('[[A-Z] - [^ PERL]]'),
	'' .qr'(?:(?!(?:(?![PERL])(?s:.)))[A-Z])'msx);

ok(unicode_to_perl('[[A-Z] & [^JUNK]]'),
	'' . qr'(?:(?=(?:(?![JUNK])(?s:.)))[A-Z])'msx);

ok(unicode_to_perl('[^ [A-Z] - [^pqr] ]'),
	'' . qr'(?:(?!(?:(?!(?:(?![pqr])(?s:.)))[A-Z]))(?s:.))'msx);

ok(unicode_to_perl('[\] \-\ 	 ]'),
	 '' . qr'[\]\-\ ]'msx);

ok(unicode_to_perl('[\p{letter} \p{decimal number}]'),
	'' . qr'(?:\p{letter}|\p{decimal number})'msx);

ok(unicode_to_perl('[\p{alnum} - \P{decimal number}]'),
	'' . qr'(?:(?!\P{decimal number})\p{alnum})'msx);

my $qr = '(?:(?![' . "\x{3B1}" . '])\p{Greek})';
ok(unicode_to_perl("[\\p{Greek} - [\N{GREEK SMALL LETTER ALPHA}]]"),
	'' . qr/$qr/msx);

ok(unicode_to_perl('[\p{Assigned} - \p{Decimal Digit Number} - [a-f A-F]]'),
	'' . qr'(?:(?!\p{Decimal Digit Number}|[a-fA-F])\p{Assigned})'msx);

ok(unicode_to_perl('[[\x00-\x7F] - [^\p{Latin}]]'),
	'' . qr'(?:(?!(?:(?!\p{Latin})(?s:.)))[\x00-\x7F])'msx);

ok(unicode_to_perl('[[\x00-\x7F][^\p{Latin}]]'),
	'' . qr'(?:[\x00-\x7F]|(?:(?!\p{Latin})(?s:.)))'msx);

ok(unicode_to_perl('[[\x00-\x7F][^[:alpha:]]]'),
	'' . qr'(?:[\x00-\x7F]|(?:(?![\p{L&}])(?s:.)))'msx);

ok(unicode_to_perl('[[\x00-\x7F] [-A-Z]]'),
	'' . qr'(?:[\x00-\x7F]|[-A-Z])'msx);

ok(unicode_to_perl('[[0-9] [-TEST]]'),
	'' . qr'(?:[0-9]|[-TEST])'msx);

ok(unicode_to_perl('[[0-] [TEST]]'),
	'' . qr'(?:[0-]|[TEST])'msx);

ok(unicode_to_perl('[0\- TEST]'),
	'' . qr'[0\-TEST]'msx);

ok(unicode_to_perl('[0\c[]'),
	'' . qr'[0\c[]'msx);

ok(unicode_to_perl('[\c]\c\]'),
	'' .qr'[\c]\c\]'msx);

ok(unicode_to_perl('[a-z{ch}]'),
	'' . qr'(?:ch|[a-z])'msx);

done_testing;
