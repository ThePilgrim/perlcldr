package Locale::CLDR::Transform;
use utf8;
use Unicode::Normalize;
use base 'Local::CLDR';

# Base clas for Transformations

# Returning the null string from filter_re causes the filter sub
# to return the entire string. This will be overridden by those
# transformations that require a filter
sub filter_re {
  return '';
}

# Split a string into chunks useing the filter regex
# The returned array is (don't change, change, ...)
sub filter {
  my ($self, $string, $re) = @_;
  
  return ('',[$string]) unless defined $re && length $re;
  my @char = split //, $string;
  @chr = map {[ $_, /$re/ ? 1 : 0 ]} @chr;

  my @string;
  my $ok = 0;
  foreach my $chr (@chr) {
    if ($chr->[1] == $ok) {
      $string[-1].=chr->[0];
    }
    else {
      $ok = $ok ? 0 : 1;
      push @string, $chr->[0];
    }
  }
  return @string;
}

# Set up standard transformation rules
my %transformationRules = (
  Nfc => sub {
    return NFC(@_);
  },
  Nfd => sub {
    return NFD(@_);
  },
  Nfkd => sub {
    return NFKD(@_);
  },
  Nfkc => sub {
    return NFKC(@_);
  },
  Lower => sub {
    return lc @_;
  },
  Upper => sub {
    return uc @_;
  },
  Title => sub {
    return ucfirst @_;
  },
  Null => sub {
    return @_;
  },
  Remove => sub {
    return '';
  },
);

sub Transform {
  my ($self, $from, $to, $string) = @_;

  # Normalise the from and to data
  foreach ($from, $to) {
    $_ = ucfirst lc;
  }

  my @strings = $self->filter($string, $self->filter_re());

  pos($string) = 0;

  my $convert=1;
  foreach my $sub_string (@strings) {
    $convert = ! $convert;
    next if ! $convert;
    
    if (my $sub = $transformationRules{$to}) {
      $sub_string = $sub->($sub_string);
    }
    else {
      $sub_string = $self->Transliterate($from, $to, $sub_string);
    }
  }

  return join '', @strings;
}

# This method is the starting point for the Tranformation
sub Convert {
  my ($self, $string) = @_;
  my $class = ref $self;
  my @rules;

  {
    no strict 'refs';
    @rules = @{"${class}::rules"};
  }

  foreach my $rule (@rules){
    pos($string)=0;
    while(pos($string) < length($string)) {
      if (ref $rule eq 'ARRAY') {
        foreach my $transformation (@$rule) {
	  if ($transformation->{before} && $string=~/$transformation->{before}/) {
	    if ($string=~s/$transformation->{from}/$transformation->{to}/) {
	      pos($string)+=$transformation->{offset};
	      last;
	    }
	  }
	  pos($string)++;
	}
      }
      else {
        $string = $rule->($transliterationObject, $string);
      }
    }
  }
}

1;
