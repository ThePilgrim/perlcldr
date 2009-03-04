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

sub _process {
  my ($self, $locale) = @_;
  my ($language, $script, $region, $variant, $extention) =
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

# Private methods
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
