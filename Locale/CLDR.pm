# Module to format data depending on Local
# Uses the Comon Local Data Repositery http://unicode.org/cldr/ for its 
# local database
package Locale::CLDR;

use 5.008_008; # Need at least this for correct unicode support


# Low level subs
sub process_segmentation_variables {
  my ($self, $type) = @_;

  my $method = "segmentation_${type}_variables";

  if ($self->can($method)) {
    my %variables;
    my @variables = $self->$method;
    while(@variables) {
      my $key   = shift @variables;
      my $value = shift @variables;
      $value =~s/\$(\w+)/$variables{$1}/eg;
      $key =~ s/^\$//;
      $value = qr/$value/x;
      $variables{$key} = $value;
    }
    return \%variables;
  }
  else {
    die "Invalid segment type $type\n";
  }
}

sub process_segmentation_rules {
  my ($self, $type) = @_;

  my $method = "segmentation_${type}_rules";

  if ($self->can($method)) {
    my %rules;
    my @rules = $self->$method;
    while(@rules) {
      my $key   = shift @rules;
      my $value = shift @rules;
      $value =~s/\$(\w+)/$rules{$1}/eg;
      $key =~ s/^\$//;
      $value = qr/$value/x;
      $rules{$key} = $value;
    }
    return [@rules{sort {$a <=> $b} keys %rules}];
  }
  else {
    die "Invalid segment type $type\n";
  }
}

sub Transliterate {
  my ($self, $from, $to, $string) = @_;

  foreach ($from, $to) {
    $_=ucfirst lc
  }

  my $class = "Local::CLDR::Transform::${from}::${to}";
  eval "require $class";
  if ($@) {
    die "Can not load transform data for '$from::$to' $@\n";
  }

  # re-bless the CLDR object into a transliteration object
  my $transliterationObject = bless $self, $class;

  $string = $transliterationObject->Convert($string);

  return $string;
}
    
1;
