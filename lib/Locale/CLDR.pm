# Module to format data depending on Local
# Uses the Comon Local Data Repositery http://unicode.org/cldr/ for its 
# local database
package Locale::CLDR;
use File::Spec;

use 5.010; # Need at least this for unicode version 5 support
use File::Spec;

# User subs follow

#Constructor

sub new {
  my ($class, $locale) = @_;
  my @params = $class->_process($locale);
  return bless {@params}, $class;
}

# Transliteration

sub Transliterate {
  my ($self, $from, $to, $string, $variation) = @_;

  foreach ($from, $to, defined $variation ? $variation : ()) {
    $_=ucfirst lc
  }

  my $class = "Local::CLDR::Transform::${from}::${to}";
  $class .= "::$variation" if defined $variation;
  eval "require $class";
  if ($@) {
    die "Can not load transform data '$class' $@\n";
  }

  # re-bless the CLDR object into a transliteration object
  my $transliterationObject = $self;
  bless $transliterationObject, $class;

  $string = $transliterationObject->Convert($string);

  return $string;
}

sub get_transliteration_list {
  # Returns a list of from, to, variation 
  my $list = do "Local::CLDR::Transform::List";
  my @list = map {[split /=>/, $_]} 
             split /\n/, $list;
  return \@list;
}

# Segmentations
sub Segment {
  my ($self, $to, $string) = @_;
  my $class= $self->_find_class('Segments');
  eval "require $class";
  if ($@) {
    die "Can not load segment data '$class' $@\n";
  }

  # re-bless the CLDR object into a segmentation object
  my $segmentationObject = $self;
  bless $segmentationObject, $class;

  my @segments = $segmentationObject->Split($to, $string);

  return @segments;
}

# Locale
sub DisplayLocale {}
sub DisplayLanguage {}
sub DisplayScript {}
sub DisplayTerritory {}
sub DisplayVariant {}
sub DisplayKey {}
sub DisplayType {}
sub DisplayMeasuremntSystem {}
sub DisplayCodePattern {}
sub ExamplarCaharacters {}

# Private methods

sub _process {
  my ($self, $locale) = @_;
  die "Trying to copy from somthing that is not a Locale\n"
    if (ref $locale && ! locale->isa('Locale::CLDR');

  my ($language, $script, $region, $variant, $extention);
  if (ref $locale) {
    ($language, $script, $region, $variant) =
      @locale{qw(Language Script Region Variant)};
    $extention = { %{$locale->{Extention}} };

    return ( 
      Language  => $language,
      Script    => $script,
      Region    => $region,
      Variant   => $variant,
      Extention => $extention,
    );
  }
  else {
    ($language, $script, $region, $variant, $extention) =
      $locale=~/^
        ([a-zA-Z]{2})          # Language
        (?:[-_]([a-zA-Z]{4}))? # Script
        (?:[-_]([a-zA-Z]{2}))? # Region
        (?:[-_]([a-zA-Z]+))?   # Variant
        (?:\@(.*))?            # Extention
      $/x;

    foreach my $type ($language, $script, $region, $variant, $extention) {
      if (defined $type) {
        $type = ucfirst lc $type;
      }
      else {
        $type = 'Any';
      }
    }
  }

  return ( 
    Language  => $language,
    Script    => $script,
    Region    => $region,
    Variant   => $variant,
    Extention => {
      map { split '=', $_, 2 }
      split ';', $extention
    },
  );
}

sub _find_class {
  my ($self, $section) = @_;

  my @parts=@{$self}{ qw( Language Script Region ) };
  
  my $base = $INC{'Locale/CLDR.pm'};
  $base=~s/\.pm$//;

  # check directories
  for (my $count = 0; $count < 3; $count++) {
    if(! -d File::Spec->catdir($base, $section, @parts[0 .. $count])) {
      $parts[$count] = 'Any';
    }
  }

  # Check final file
  if ( -e File::Spec->catfile($base, $section, @parts, "$self->{Variant}.pm")) {
    return join '::', 'Locale::CLDR', $section, @parts, $self->{Variant};
  }

  # Check for 'Any' Variant
  if ( -e File::Spec->catfile($base, $section, @parts, "$self->{Variant}.pm")) {
    return join '::', 'Locale::CLDR', $section, @parts, 'Any';
  }

  # The class does not exist so return the root class
  return "Locale::CLDR::${section}::Root::Any::Any::Any";
}

1;

__END__

=head1 NAME

Locale::CLDR -Module to access Locale data from the Unicode CLDR database

=head1 SYNOPSIS

use Locale::CLDR
my $locale = Locale::CLDR->new('en_GB');
print 'My locale is ', $locale->DisplayLocale(), "\n"

=head1 DESCRIPTION

The Unicode Consortium publishes the Common Locale Database as a set of
XML files. This module allows access to this data via a Locale::CLDR object.

The object holds the current Locale and the methods allow formatting of
various asects of Locale data for the Locale of the object.

=head1 METHODS

=head2 Constructor

 my $locale = Locale::CLDR->new('en_GB');
 my $copyLocale = Locale::CLDR->new($locale);

The constructor new() takes either a string description of a locale or
an existing locale object and creates a new locale object from it.

=head2 Transliterate

 my $transliteratedString = $locale->Transliterate->('Latin', 'Greek', $strin);

The Transliterate() method tansliterates $string in the first script to the
second script. For some translitteration pairs there is more than one
way to handle the transliteration the diffrent variations can be 
given as an optional 4th paramater to the method

=head2 get_transliteration_list

 my @list = $locale->get_transliteration_list()
 foreach (@list) {
   print "From: $_->[0] To: $_->[1]";
   print " $_->[2]" if defined $_->[2];
   print "\n";
 }

get_transliteration_list() returns a list of aray refs of transliteration
data the elements in the aray ref are; from, to, variation. Variation will
nly be defined if a validvariation for the transliteration pair exists.
The list is generated from data stored in Locale::CLDR::Transform::List

=head2 Segment

  use Locale::CLDR::Constants ':segments';
  my @sentence_split_points = $locale->Segment(SEGMENT_SENTENCE, $string);

The Segment() method takes a string in the locales script and splits it 
into chunks depending on the constant iven as the 1st paramater.

The constants and what they do are

=over 4

=item SEGMENT_GRAPHEME_CLUSTER

Splits the string into grapheme clusters

=item SEGMENT_LINE

Splits the string at every point a line can end. You will have to 
work out after which of the returned chunks you wish to split the
line yourself.

=item SEGMENT_SENTENCE

Splits the string on sentence boundries

=item SEGMENT_WORD

Splits the string on word bundries

=back

In no case is whitespace lost.

=head2 DisplayLocale

 my $localeName         = $locale->DisplayLocal();
 my $GermanName         = $locale->DisplayLocale('de_AT');
 my $GermanName         = $locale->DisplayLocale('de');
 my $otherLocaleName    = $locale->DisplayLocale($otherLocale);

DisplayLocale() returns a locale name formatted for the current locale.
Without any paramaters it returns the locales name formatted for the locale.
The other 3 versions allow you to get the name of a diffrent locale 
formatted for the current locale.

=head2 DisplayLanguage

 my $localeLanguageName      = $locale->DisplayLanguage();
 my $austrianLanguageName    = $locale->DisplayLanguage('de_AT');
 my $austrianLanguageName    = $locale->DisplayLanguage('AT');
 my $otherLocaleLanguageName = $locale->DisplayLanguage($otherLocale);

DispalayLanguage() returns a language name formatted for the current locale
Without any paramaters it returns the locales language name formatted for
the locale.
The other 3 versions allow you to get the name of a language for a diffrent
locale formatted for the current locale.

=head2 DisplayScript

 my $localeScriptName      = $locale->DisplayScript();
 my $austrianScriptName    = $locale->DisplayScript('de_latin_AT');
 my $ScriptName            = $locale->DisplayScript('latin');
 my $otherLocaleScriptName = $locale->DisplayScript($otherLocale);

DispalayScript() returns a script name formatted for the current locale
Without any paramaters it returns the locales script name formatted for
the locale.
The other 3 versions allow you to get the name of a script for a diffrent
locale formatted for the current locale.

=head2 DisplayTerritory

 my $localeTerritoryName      = $locale->DisplayTerritory();
 my $austrianTerritoryName    = $locale->DisplayTerritory('de_AT');
 my $TerritoryName            = $locale->DisplayTerritory('AT');
 my $otherLocaleTerritoryName = $locale->DisplayTerritory($otherLocale);

DispalayTeritorry() returns a teritory name formatted for the current
locale. Without any paramaters it returns the locales teritory name
formatted for the locale.
The other 3 versions allow you to get the name of a teritory for a diffrent
locale formatted for the current locale.

=head2 DisplayVariant

 my $localeVariantName      = $locale->DisplayVariant();
 my $PosixVariantName       = $locale->DisplayVariant('en_us_POSIX');
 my $VariantName            = $locale->DisplayVariant('POSIX');
 my $otherLocaleVariantName = $locale->DisplayVariant($otherLocale);

DispalayVariant() returns a variant name formatted for the current
locale. Without any paramaters it returns the locales variant name
formatted for the locale.
The other 3 versions allow you to get the name of a variant for a diffrent
locale formatted for the current locale.

=head2 DisplayKey

 use Local::CLDR::Constants ':key';
 my $KeyName = $locale->DisplayKey(KEY_COLLATION);

DispalayKey() returns a tanslation for the key elements in the extention
part of a locale name. The value of the paramater must be one of

=over 4

=item KEY_CALENDAR

=item KEY_COLLATION

=item KEY_CURRENCY

=back

these can be imported from Locale::CLDR::Constants useing the C<:key> tag

=head2 DisplayType

 use Locale:CLDR::Constants (':type', ':key');
 my $translatedTypeName =  $locale->DisplayType(KEY_CALENDAR, TYPE_JAPANESE);

DispalayType() returns a tanslation for the type elements in the extention
part of a locale name. The value of the first paramater must be one of  

=over 4

=item KEY_CALENDAR

=item KEY_COLLATION

=item KEY_CURRENCY

=back

The value of the second paamater must be a type constant corrisponding to the given key

=head2 DisplayMeasurementSystem

 use Locale::CLDR::Constants(':measurement');
 $translatedMeasurementName = $locale->DisplayMeasurementSystem(MEASUREMENT_UK);

DisplayMeasurementSystem() returns the translated name for the given Measurement system. The Value of the paramater must be one of

=over 4

=item MEASUREMENT_METRIC

=item MEASUREMENT_UK

=item MEASUREMENT_US

=back
