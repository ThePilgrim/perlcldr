package Locale::CLDR::Transform;
use utf8;
use Unicode::Normalize;
use base 'Local::CLDR';

# Base clas for Transformations

sub filter {
  my ($self, $string, $re) = @_;
  
  my @char = split //, $string;
  return ('',[@chr]) unless defined $re && length $re;
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
  NFC => sub {
    return NFC(@_);
  },
  NFD => sub {
    return NFD(@_);
  },
  NFKD => sub {
    return NFKD(@_);
  },
  NFKC => sub {
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
  Null => {
    return @_;
  },
  Remove => {
    return '';
  },
);

sub Transform {
  my ($self, $from, $to, $string) = @_;

  foreach ($from, $to) {
    $_ = ucfirst lc;
  }

  my @strings = $self->filter($string, $self->filter_re());

  pos($string) = 0;

  my $convert=1;
  foreach my $sub_string (@strings) {
    $convert = ! $convert;
    next if ! $convert
    
    if (my $sub = $transformationRules{$to}) {
      $sub_string = $sub->($sub_string);
    }
    else {
      $sub_string = $self->Transliterate($from, $to, $sub_string);
    }
  }

  return join '', @strings;
}

1;
