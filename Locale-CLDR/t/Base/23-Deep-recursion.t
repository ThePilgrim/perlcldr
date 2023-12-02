use v5.024;
use strict;
use warnings;

use Locale::CLDR;

# deep recursion
my $locale = Locale::CLDR->new(language_id => 'und', region_id => 'AQ');
#my $locale = Locale::CLDR->new(language_id => 'und', region_id => 'BV');
#my $locale = Locale::CLDR->new(language_id => 'und', region_id => 'CP');
#my $locale = Locale::CLDR->new(language_id => 'und', region_id => 'GS');
#my $locale = Locale::CLDR->new(language_id => 'und', region_id => 'HM');

# works
#my $locale = Locale::CLDR->new(language_id => 'und', region_id => 'AG');

say $locale->region_name;