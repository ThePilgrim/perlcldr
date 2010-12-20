use Test;
use strict;
use warnings;
BEGIN {
	plan tests => 43;
};

use  Unicode::Set qw(unicode_to_perl);

use vars qw(@char $digit $upper $lower $space $punct);

$digit = join '', "0".."9";
$upper = join '', "A".."Z";
$lower = join '', "a".."z";
$space = "\n\r\t\f\ ";
$punct = '!"#$%&\'()*+,-./:;<=>?@[\]^_`{|}~';


@char = split //, "$digit$upper$lower$space$punct";

sub testregex {
    my $pat = unicode_to_perl(shift);
    join '', grep /^$pat\z/, @char;
}

ok(testregex('[A-Z]'),
	 $upper);

ok(testregex('[A-Z xyz]'),
	 $upper.'xyz');

ok(testregex('[A&G]'),
	 'AG&');

ok(testregex('[A-Z&a-z]'),
	 "$upper$lower&");

ok(testregex('[[A-Z] & [PERL]]'),
	 'ELPR');

ok(testregex('[[A-Z] & [xyz]]'),
	 '');

ok(testregex('[[A-Z] & [C-S] & [K-V]]'),
	 'KLMNOPQRS');

ok(testregex('[[A-Z] - [C-S] - [K-V]]'),
	 'ABWXYZ');

ok(testregex('[[[A-Z] & [B-L]] - [[C-S] - [K-V]]]'),
	 'BKL');

ok(testregex('[[[A-Z] & [D-LPERL]] - [[C-S] - [K-V]]]'),
	 'KLPR');

ok(testregex('[[A-Z] & [ABCL-Q] & [[K-S] - [QRS]]]'),
	 'LMNOP');

ok(testregex('[[\p{Upper} & [PERLperl]] | [abc]]'),
	 'ELPRabc');

ok(testregex('[[\p{Latin} & PERLperl] - [abcdef]]'),
	 'ELPRlpr');

ok(testregex('[\p{Latin} & PERLperl [abcde]]'),
	 'ELPRabcdelpr');

ok(testregex('[\p{Latin} & PERLperl | [cde]]'),
	 'ELPRcdelpr');

ok(testregex('[^ A-Z]'),
	 "$digit$lower$space$punct");

ok(testregex('[[A-Z] - [^ PERL]]'),
	 'ELPR');

ok(testregex('[[A-Z] & [^JUNK]]'),
	 'ABCDEFGHILMOPQRSTVWXYZ');

ok(testregex('[^[[B-Z] & [A-D]]]'),
	 $digit.'AEFGHIJKLMNOPQRSTUVWXYZ'."$lower$space$punct");

ok(testregex('[ \^\-\[ ]'),
	 '-[^');

ok(testregex('[^A-Z a-z]'),
	 "$digit$space$punct");

ok(testregex('[^ [A-Z a-z]]'),
	 "$digit$space$punct");

ok(testregex('[ [^A-Z] PERL]'),
	 $digit."ELPR"."$lower$space$punct");

ok(testregex('[ [^A-Z] [^a-z]]'),
	 "$digit$upper$lower$space$punct");

ok(testregex('[[A-Z] & [^TEST]]'),
	 'ABCDFGHIJKLMNOPQRUVWXYZ');

ok(testregex('[[0-9] [-TEST]]'),
	 '0123456789EST-');

ok(testregex('[[0-] [TEST]]'),
	 '0EST-');

ok(testregex('[9\- TEST]'),
	 '9EST-');

ok(testregex('[0-9 T\	\ E^S-T]'), # TAB, SPACE, HAT, range
	 '0123456789EST	 ^');

ok(testregex('[0-9 T\	\ E^S\-T]'), # TAB, SPACE, HAT, range
	 '0123456789EST	 -^');

ok(testregex('[A-Z [^[:alnum:]]]'),
	 "$upper$space$punct");

ok(testregex('[A-Z [^[:alnum:]]]'),
	 "$upper$space$punct");

ok(testregex('[A-Z [:^alnum:]]'),
	 "$upper$space$punct");

ok(testregex('[A-Z [^\p{Latin}]]'),
	 "$digit$upper$space$punct");

ok(testregex('[A-Z [^\p{Latin}]]'),
	 "$digit$upper$space$punct");

ok(testregex('[A-Z \p{^Latin}]'),
	 "$digit$upper$space$punct");

ok(testregex('[REGEX\P{Latin}]'),
	 $digit."EGRX$space$punct");

ok(testregex('[[A-Z] - [[:alnum:]]]'),
	 "");

ok(testregex('[[:alnum:]]'),
	 "$digit$upper$lower");

ok(testregex('[[:alnum:] - 0123]'),
	 "456789$upper$lower");

ok(testregex('[[[ace][bdf]] - [[abc][def]]]'),
	 "");

ok(testregex('[[[ace][bdf]] - [[abc][df]]]'),
	 "e");

my $pat = unicode_to_perl('[a-c{ch}]');
ok(join ('', grep /^$pat\z/, @char, 'ch') eq 'abcch');
