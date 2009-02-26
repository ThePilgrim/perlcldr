package Unicode::Regex::CCC;
use strict;
use warnings;

# Fixup for borked ccc unicode property

use base 'Exporter';
our @EXPORT;

my %class;

my $current0 = 0;

my @list = split /\n/, do 'unicore/CombiningClass.pl';

#  make use of the fact that the data file is in code point order
foreach my $entry (@list) {
  my ($begin, $end, $number) = split /\s+/, $entry;

  # fixup range
  if (! defined $number ) {
    $number = $end;
    $end   = $begin;
  }

  # Fixup level 0
  if (hex($begin) > $current0 +1) {
    add_range(\%class, 0, $current0, hex($begin)-1);
  }

  add_range(\%class, $number, hex($begin), hex($end));
  $current0 = hex $end;
}

# create a sub for the set of ranges and push
# it onto the EXPORT list
foreach my $key ( keys %class ) {
  push @EXPORT, "ccc$key";
  my $return = join "\n", map {join ' ', @{$_}} @{$class{$key}};
  no strict 'refs';
  *{"ccc$key"} = sub {return $return};
}

sub add_range {
  my ($list, $number, $begin, $end) = @_;
  $begin = "\cI" if $begin == $end;
  push @{$list->{$number}}, [map {$_ eq "\cI" ? $_ : sprintf '%x', $_ } ($begin, $end)];
}

1;
