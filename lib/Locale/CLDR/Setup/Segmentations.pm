package Locale::CLDR::Setup::Segmentations;
use base 'Locale::CLDR::Setup::Base';

sub add_data_to_file {
  my ($self, $file) = @_;
  print $file "use base 'Locale::CLDR::Segmentations';\n# Segmentations\n";
  foreach my $segment (keys %{$self->{segmentations}{segmentation}}) {
    print $file <<EOT;
sub ${segment}_variables {
  my \$self = shift();

  my \$variables = [
EOT
    foreach my $variable (keys %{$self->{segmentations}{segmentation}{$segment}{variables}{variable}}) {
      print $file "    '$variable' => '", $self->{segmentations}{segmentation}{$segment}{variables}{variable}{$variable}, "',\n";
    }
  print $file <<EOT;
  ];
  return \$variables;
}

sub ${segment}_rules {
  my \$self = shift();

  my \$rules = {
EOT
    foreach my $rule (@{$self->{segmentations}{segmentation}{$segment}{segmentRules}{_order_}}) {
      print $file "    '$rule' => '", $self->{segmentations}{segmentation}{$segment}{segmentRules}{rule}{$rule}, "',\n";
    }
  print $file <<EOT;
  };
  return \$rules;
}

EOT
  }
}

1;
