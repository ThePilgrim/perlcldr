# Base package for Segmentations
package Locale::CLDR::Segmentations;
use strict;
use warnings;
use utf8;
use base 'Locale::CLDR';
use Unicode::Regex::Parser;

sub Split {
  my ($self, $what, $string) = @_;

  # Work out the rules and then cache them
  if (! $self->{segmentation_rules}) {
    $self->_generate_rules();
  }

  my @constants2names = (
    '',
    'GraphemeClusterBreak',
    'LineBreak',
    'SentenceBreak',
    'WordBreak',
  );

  my @rules = @{$self->{segmentation_rules}{$constants2names[$what]}};
  # we now have a set of preprocessed rules of [$before, $type, $after]
  
  my @segments;
  my $count = 0;
  while ($count < length $string) {
    pos($string) = $count;
    foreach my $rule (@rules) {
      if ($string=~/$rule->[0]/) {
        if ($rule->[1] eq '÷') {
	  push @segments, substr $string,0,$count,'';
	  $count = 0;
	}
	last;
      }
    }
    $count++;
  }
  push @segments, $string if length $string;

  return @segments;
}

sub _generate_rules {
  my $self = shift;

  my $class = ref $self;

  my $base = $INC{'Locale/CLDR.pm'};
  $base =~s/\.pm$//;

  my $root = 'Locale::CLDR::Segments::Root::Any::Any::Any';
  my @available_children = split '::', $class;
  shift @available_children;
  shift @available_children;
  my @found_children;
  my $have_root = 0;
  for (my $count = 0; $count < @available_children; $count++) {
    my $file = File::Spec->catfile($base, 'Locale', 'CLDR', @available_children[0 .. $count]) . '.pm';
    if (do $file) {
      push @found_children, $file;
      $have_root = 1 if $file eq $root;
    }
  }
  @available_children = (($have_root ? () : $root), @found_children);
  # Now we need to build up all the variables and rules lists
  foreach my $type (qw( GraphemeClusterBreak LineBreak SentenceBreak WordBreak)) {
    my (@vars, @rules, %rules, %vars);
    foreach my $class (@available_children) {
      if ($class->can("${type}_variables")) {
        push @vars, @{$class->${\"${type}_variables"}};
      }
      if ($class->can("${type}_rules")) {
        %rules = (%rules, %{$class->${\"${type}_rules"}});
      }
    }

    # Fixup the Variables
    while (@vars) {
      my $name  = shift @vars;
      my $value = shift @vars;
      $value =~s/(\$\p{ID_START}\p{ID_CONTINUE}*)/exists $vars{$1} ? $vars{$1} : $1/eg;
      $vars{$name}=$value;
    }

    # Fixup the Rules
    foreach my $rule (sort {$a <=> $b} keys %rules) {
      my ($before, $mark, $after) = $rules{$rule}=~/^(.*?)([÷×])(.*)$/;
      foreach ($before, $after) {
        s/(\$\p{ID_START}\p{ID_CONTINUE}*)/exists $vars{$1} ? $vars{$1} : $1/eg;
	if (! defined || ! /\S/ ) {
	  $_ = '';
	  next;
	}
        $_ = Unicode::Regex::Parser::parse($_);
      }
      push @rules , [ qr/$before\G$after/, $mark ];
    }
    $self->{segmentation_rules}{$type} = \@rules;
  }
}

1;
