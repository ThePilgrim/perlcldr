#!perl

use Test::More tests => 12;

use ok 'Locale::CLDR';

my $local = Locale::CLDR->new(language => 'en');
is("$local", 'en', 'Set Language explicitly');

$local = Locale::CLDR->new('en');
is("$local", 'en', 'Set Language implicitly');

my $local = Locale::CLDR->new(language => 'en', region => 'gb');
is("$local", 'en_GB', 'Set Language and Region explicitly');

$local = Locale::CLDR->new('en-gb');
is("$local", 'en_GB', 'Set Language and Region implicitly');

my $local = Locale::CLDR->new(language => 'en', script => 'latn');
is("$local", 'en_Latn', 'Set Language and Script explicitly');

$local = Locale::CLDR->new('en-latn');
is("$local", 'en_Latn', 'Set Language and Script implicitly');

my $local = Locale::CLDR->new(language => 'en', region => 'gb', script => 'latn');
is("$local", 'en_Latn_GB', 'Set Language, Region and Script explicitly');

$local = Locale::CLDR->new('en-latn-gb');
is("$local", 'en_Latn_GB', 'Set Language, Region and Script implicitly');

my $local = Locale::CLDR->new(language => 'en', variant => 'BOKMAL');
is("$local", 'en_BOKMAL', 'Set Language and Variant from string explicitly');

$local = Locale::CLDR->new('en_BOKMAL');
is("$local", 'en_BOKMAL', 'Set Language and variant implicitly');

$local = Locale::CLDR->new('en_latn_gb_BOKMAL');
is("$local", 'en_Latn_GB_BOKMAL', 'Set Language, Region, Script and variant implicitly');
