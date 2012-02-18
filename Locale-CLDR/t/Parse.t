use Test::More;
use strict;
use warnings;
use charnames ':full';

use ok 'Unicode::Set', qw(unicode_to_perl);

is(unicode_to_perl('[A-Z]'),
	 '' . qr'[A-Z]'umsx);

is(unicode_to_perl('[a-z A-Z]'),
	 '' . qr'[a-zA-Z]'umsx);

is(unicode_to_perl('[[a-z] | [A-Z]]'),
	 '' . qr'(?:[a-z]|[A-Z])'umsx);

is(unicode_to_perl('[a-z A-Z 0-9]'),
	 '' . qr'[a-zA-Z0-9]'umsx);

is(unicode_to_perl('[[a-z] | [A-Z] | [0-9]]'),
	 '' . qr'(?:[a-z]|[A-Z]|[0-9])'umsx);

is(unicode_to_perl('[[a-z  A-Z] | [0-9]]'),
	 '' . qr'(?:[a-zA-Z]|[0-9])'umsx);

is(unicode_to_perl('[[a-z] [[A-Z]] [0-9]]'),
	 '' . qr'(?:[a-z]|[A-Z]|[0-9])'umsx);

is(unicode_to_perl('[[a-z] - [A-Z]]'),
	 '' . qr'(?:(?![A-Z])[a-z])'umsx);

is(unicode_to_perl('[[a-z] - [A-Z \r \n]]'),
	 '' . qr'(?:(?![A-Z\r\n])[a-z])'umsx);

is(unicode_to_perl('[[a-z] - [A-Z] - [\r] - [\n]]'),
	 '' . qr'(?:(?![A-Z]|[\r]|[\n])[a-z])'umsx);

is(unicode_to_perl('[[a-z xyz0-9] - [A-Z] - [\r\n]]'),
	'' . qr'(?:(?![A-Z]|[\r\n])[a-zxyz0-9])'umsx);

is(unicode_to_perl('[\p{Latin} - [[A-Z] - [AEIOUaeiou]]]'),
	'' . qr'(?:(?!(?:(?![AEIOUaeiou])[A-Z]))\p{Latin})'umsx);

is(unicode_to_perl('[[A-Z] & \p{Latin}]'),
	'' . qr'(?:(?=\p{Latin})[A-Z])'umsx);

is(unicode_to_perl('[[A-Z] & \p{Latin} 0-9]'),
	'' . qr'(?:(?=(?:\p{Latin}|[0-9]))[A-Z])'umsx);

is(unicode_to_perl('[[A-Z] & [C-Q] & [K-S]]'),
	'' . qr'(?:(?=[C-Q])(?=[K-S])[A-Z])'umsx);

is(unicode_to_perl('[\p{L} [\p{Zs} A-Z] - \p{Nd} \p{Pi}]'),
	'' . qr'(?:\p{L}|(?:(?!(?:\p{Nd}|\p{Pi}))(?:\p{Zs}|[A-Z])))'umsx);

is(unicode_to_perl('[[A-Z] & [ABC L-Q] & [[K-S] - [QRS]]]'),
	'' . qr'(?:(?=[ABCL-Q])(?=(?:(?![QRS])[K-S]))[A-Z])'umsx);

is(unicode_to_perl('[\p{Latin} & \p{L&} - \p{ASCII}]'),
	'' . qr'(?:(?=(?:(?!\p{ASCII})\p{L&}))\p{Latin})'umsx);

is(unicode_to_perl('[ [\[-\]] & [abc\ xyz] ]'),
	'' . qr'(?:(?=[abc\ xyz])[\[-\]])'umsx);

is(unicode_to_perl('[^ A-Z]'),
	'' . qr'(?:(?![A-Z])(?s:.))'umsx);

is(unicode_to_perl('[ ^A-Z PERL]'),
	'' . qr'[^A-ZPERL]'umsx);

is(unicode_to_perl('[^ a-z A-Z 0-9]'),
	'' . qr'(?:(?![a-zA-Z0-9])(?s:.))'umsx);

is(unicode_to_perl('[^A-Z a-z 0-9]'),
	'' . qr'(?:(?![A-Za-z0-9])(?s:.))'umsx);

is(unicode_to_perl('[^[A-Z a-z 0-9]]'),
	'' .qr'(?:(?![A-Za-z0-9])(?s:.))'umsx);

is(unicode_to_perl('[^[B-Z] & [A-D]]'),
	'' .qr'(?:(?!(?:(?=[A-D])[B-Z]))(?s:.))'umsx);

is(unicode_to_perl('[^[A-Z] - [PERL]]'),
	'' .qr'(?:(?!(?:(?![PERL])[A-Z]))(?s:.))'umsx);

is(unicode_to_perl('[[A-Z] - [^ PERL]]'),
	'' .qr'(?:(?!(?:(?![PERL])(?s:.)))[A-Z])'umsx);

is(unicode_to_perl('[[A-Z] & [^JUNK]]'),
	'' . qr'(?:(?=(?:(?![JUNK])(?s:.)))[A-Z])'umsx);

is(unicode_to_perl('[^ [A-Z] - [^pqr] ]'),
	'' . qr'(?:(?!(?:(?!(?:(?![pqr])(?s:.)))[A-Z]))(?s:.))'umsx);

is(unicode_to_perl('[\] \-\ 	 ]'),
	 '' . qr'[\]\-\ ]'umsx);

is(unicode_to_perl('[\p{letter} \p{decimal number}]'),
	'' . qr'(?:\p{letter}|\p{decimal number})'umsx);

is(unicode_to_perl('[\p{alnum} - \P{decimal number}]'),
	'' . qr'(?:(?!\P{decimal number})\p{alnum})'umsx);

my $qr = '(?:(?![' . "\x{3B1}" . '])\p{Greek})';
is(unicode_to_perl("[\\p{Greek} - [\N{GREEK SMALL LETTER ALPHA}]]"),
	'' . qr/$qr/umsx);

is(unicode_to_perl('[\p{Assigned} - \p{Decimal Digit Number} - [a-f A-F]]'),
	'' . qr'(?:(?!\p{Decimal Digit Number}|[a-fA-F])\p{Assigned})'umsx);

is(unicode_to_perl('[[\x00-\x7F] - [^\p{Latin}]]'),
	'' . qr'(?:(?!(?:(?!\p{Latin})(?s:.)))[\x00-\x7F])'umsx);

is(unicode_to_perl('[[\x00-\x7F][^\p{Latin}]]'),
	'' . qr'(?:[\x00-\x7F]|(?:(?!\p{Latin})(?s:.)))'umsx);

is(unicode_to_perl('[[\x00-\x7F][^[:alpha:]]]'),
	'' . qr'(?:[\x00-\x7F]|(?:(?![\p{L&}])(?s:.)))'umsx);

is(unicode_to_perl('[[\x00-\x7F] [-A-Z]]'),
	'' . qr'(?:[\x00-\x7F]|[-A-Z])'umsx);

is(unicode_to_perl('[[0-9] [-TEST]]'),
	'' . qr'(?:[0-9]|[-TEST])'umsx);

is(unicode_to_perl('[[0-] [TEST]]'),
	'' . qr'(?:[0-]|[TEST])'umsx);

is(unicode_to_perl('[0\- TEST]'),
	'' . qr'[0\-TEST]'umsx);

is(unicode_to_perl('[0\c[]'),
	'' . qr'[0\c[]'umsx);

is(unicode_to_perl('[\c]\c\]'),
	'' .qr'[\c]\c\]'umsx);

is(unicode_to_perl('[a-z{ch}]'),
	'' . qr'(?:ch|[a-z])'umsx);

is(unicode_to_perl('[a-z{ch\u21}]'),
	'' . qr'(?:ch!|[a-z])'umsx);

is(unicode_to_perl('[a-c{ch}]'),
	'' . qr'(?:ch|[a-c])'umsx);

my $dot = chr(0x307);
is(unicode_to_perl('[a {i\\u0307} b]'),
	'' . qr"(?:i$dot|[ab])"umsx);

is(unicode_to_perl('[a b c ç d e ə f g ğ h x ı i {i\\u0307} j k q l m n o ö p r s ş t u ü v y z]'),
	'' . qr"(?:i$dot|[abcçdeəfgğhxıijkqlmnoöprsştuüvyz])"umsx);

is(unicode_to_perl('[]'),
	'' . qr/[ ]/umsx);
done_testing;
