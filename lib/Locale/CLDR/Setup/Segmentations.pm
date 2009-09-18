package Locale::CLDR::Setup::Segmentations;
use base 'Locale::CLDR::Setup::Base';

sub add_data_to_file {
  my ($self, $file) = @_;
  print $file "use base 'Locale::CLDR::Segmentations';\n# Segmentations\n";
  my $segment_nodes = $self->{xpath}->find('/ldml/segmentations');
  foreach my $context ($segment_nodes->get_nodelist) {
    my $segment_nodes = $self->{xpath}->findnodes('segmentation/@type',$context);
    foreach my $segment ( map { $_->getNodeValue } $segment_nodes->get_nodelist) {
      print $file <<EOT;
sub ${segment}_variables {
  my \$self = shift();

  my \$variables = [
EOT
      my $variable_node = $self->{xpath}->findnodes("segmentation[\@type='$segment']/variables", $context);
      foreach my $context ($variable_node->get_nodelist) {
        my $variable_nodes = $self->{xpath}->findnodes('variable',$context);
        foreach my $variable ( map { [$_->getAttribute('id'), $_->getChildNode(1)->toString] } $variable_nodes->get_nodelist ) {
          print $file "    '$variable->[0]' => '$variable->[1]',\n";
        }
      }
      print $file <<EOT;
  ];
  return \$variables;
}

sub ${segment}_rules {
  my \$self = shift();

  my \$rules = {
EOT
      my $rule_node = $self->{xpath}->findnodes("segmentation[\@type='$segment']/segmentRules", $context);
      foreach my $context ($rule_node->get_nodelist) {
        my $rule_nodes = $self->{xpath}->findnodes('rule/@id', $context);
        foreach my $rule ( map {$_->getNodeValue } $rule_nodes->get_nodelist ) {
          print $file "    '$rule' => '", $self->{xpath}->find("rule[\@id='$rule']", $context)->string_value, "',\n";
        }
      }
      print $file <<EOT;
  };
  return \$rules;
}

EOT
    }
  }
}

1;
