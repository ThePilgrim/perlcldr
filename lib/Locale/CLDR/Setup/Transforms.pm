package Locale::CLDR::Setup::Transforms;
use base 'Locale::CLDR::Setup::Base';

use File::Path;
use File::Basename;
use Parse::RecDescent;
use Unicode::Regex::Parser;
our @Transform_List = ();

sub _calculate_file_names {
  my $self = shift;

  my $filename = [ File::Spec->catfile('Transform',$self->{transforms}[0]{from},$self->{transforms}[0]{to}) ];
  if ($self->{transforms}[0]{direction} eq 'both') {
    push @$filename, File::Spec->catfile('Transform',$self->{transforms}[0]{to},$self->{transforms}[0]{from});
  }
  if (defined $self->{transforms}[0]{variant}) {
    foreach (@$filename) {
      $_=File::Spec->catfile($_,$self->{transforms}[0]{variant});
    }
  }
  # Fix for CLDR bug 2043
  if (
    (
      $self->{transforms}[0]{from} eq 'Thaana'
      && $self->{transforms}[0]{to} eq 'Latin'
    )
    ||
    (
      $self->{transforms}[0]{from} eq 'Aboriginal'
      && $self->{transforms}[0]{to} eq 'Latin'
    )
  ) {
    @$filename = reverse @$filename;
  }
  $self->{__cache__}{filenames} = $filename;
  return $self->{__cache__}{filenames};
}

sub create_files {
  my $self = shift;
  my $count = 0;
  foreach my $filename ($self->get_file_name) {
    $self->current_file_name($filename);
    $self->create_file({backwards => $count++});
  }
  $self->create_list_file(\@Transform_List);
}

sub get_package_name {
  my $self = shift;
  my $package = join '::', map {ucfirst lc $_} File::Spec->splitdir((fileparse($self->current_file_name()))[1]);
  $package.= fileparse($self->current_file_name());
  return "Local::CLDR::$package";
}

sub add_data_to_file {
  {
    no warnings 'once';
    %::Variables = ();
  }
  our $transformGrammar ||= <<'EOGRAMMAR';
Transforms: TRANSFORM(s) { $return = join "\n", @{$item[1]}; }

TRANSFORM: FORWARD_FILTER(?) RULES REVERSE_FILTER(?)
{
  $return = join "\n", $item[1][0], $item[2], $item[3][0];
}

FORWARD_FILTER: /::\s*/ UNICODE_SET ';' COMMENT(?)
{
  $return = "sub filter_re { return qr($item{UNICODE_SET}) }\n";
}

REVERSE_FILTER: /::\s*/ '(' UNICODE_SET ')' ';' COMMENT(?)
{
  $return = "";
}

UNICODE_PROPERTY: 
{
$return = Unicode::Regex::Parser::parser->PROPERTY(\$text);
}

UNICODE_SET: 
{
$return = Unicode::Regex::Parser::parser->SET(\$text);
}

COMMENT: '#' <resync>

RULES: RULE(s) { $return = join "\n", @{$item[1]}; }

RULE:  '::' '(' '[' <commit> <reject>
|      TRANSFORM_RULE ';' COMMENT(?) { $return = $item[1]; }
|      VARIABLE_DEFINITION_RULE ';' COMMENT(?) { $return = $item[1]; }
|      CONVERSION_RULE ';' COMMENT(?) { $return = $item[1]; }

TRANSFORM_RULE: TRANSFORM_RULE_INVERSE { $return = $item[1]; }
|               TRANSFORM_RULE_NORMAL { $return = $item[1]; }
|               TRANSFORM_RULE_BOTH { $return = $item[1]; }
|               TRANSFORM_RULE_SAME { $return = $item[1]; }

TRANSFORM_RULE_INVERSE: '::' '(' TRANSFORM_RULE_NAME ')'
{
  $return= '';
}

TRANSFORM_RULE_NORMAL:  '::' TRANSFORM_RULE_NAME '()'
{
  my ($filter, $from, $to) = ($item{TRANSFORM_RULE_NAME}[0], split /-/, $item{TRANSFORM_RULE_NAME}[1]);
  unless(defined $to) {
    $to = $from;
    $from = 'Any';
  }
  foreach ($from, $to) {
    $_ = ucfirst lc;
  }
  if (defined $filter) {
    $filter = "filter => '$filter',"
  }
  else {
    $filter = '';
  }
  $from = 'Any' if $from eq 'Und';
  $return = "push \@rules, sub {
  my (\$self, \$string) = \@_;
  return \$self->Transform($filter from => '$from', to => '$to', string => \$string);
};
push \@rules,[];
"
}

TRANSFORM_RULE_BOTH:    '::' TRANSFORM_RULE_NAME '(' TRANSFORM_RULE_NAME ')'
{
  my ($filter, $from, $to) = ($item[2][0],split /-/, $item[2][1]);
  unless(defined $to) {
    $to = $from;
    $from = 'Any';
  }
  foreach ($from, $to) {
    $_ = ucfirst lc;
  }
  if (defined $filter) {
    $filter = "filter => '$filter',"
  }
  else {
    $filter = '';
  }
  $from = 'Any' if $from = 'Und';
  $return = "push \@rules, sub {
  my (\$self, \$string) = \@_;
  return \$self->Transform($filter from => '$from', to => '$to', string => \$string);
};
push \@rules,[];
";
}

TRANSFORM_RULE_SAME:  '::' TRANSFORM_RULE_NAME 
{
  my ($filter, $from, $to) = ($item{TRANSFORM_RULE_NAME}[0], split /-/, $item{TRANSFORM_RULE_NAME}[1]);
  unless(defined $to) {
    $to = $from;
    $from = 'Any';
  }
  foreach ($from, $to) {
    $_ = ucfirst lc;
  }
  $from = 'Any' if $from eq 'Und';
  if (defined $filter) {
    $filter = "filter => '$filter',"
  }
  else {
    $filter = '';
  }
  $return = "push \@rules, sub {
  my (\$self, \$string) = \@_;
  return \$self->Transform($filter from => '$from', to => '$to', string => \$string);
};
push \@rules,[];
"
}

FILTER:  UNICODE_PROPERTY   { $return = $item[1] }
|        UNICODE_SET        { $return = $item[1] }

TRANSFORM_RULE_NAME: FILTER(?) CHARACTER_TYPE_EXCLUDE['(;)'](s)
{
  $return = [$item[1][0], join '', @{$item[2]}];
}

CONVERSION_RULE: FORWARD_CONVERSION_RULE { $return = $item[1]; }
|                BACKWARD_CONVERSION_RULE { $return = $item[1]; }
|                DUAL_CONVERSION_RULE { $return = $item[1]; }

FORWARD_CONVERSION_RULE: BEFORE_CONTEXT(?) TEXT_TO_REPLACE(?) AFTER_CONTEXT(?) '→' COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) 
{
  my ($before, $replace, $after, $compleated, $revisit) = @item[1 .. 3, 5,6 ];
  my ($from, $offset) = ('',0);
  foreach my $string ($before->[0], $replace->[0], $after->[0], $compleated->[0], $revisit->[0]) {
    $string =~s/(\$\p{IDStart}\p{IDContinue}*)/exists $::Variables{$1} ? $::Variables{$1} : "\\$1"/eg;
    $string =~s/\$(\d+)/\\\$$1/g;
    $string=~s/^\s*(.*?)\s*$/$1/;
    my $set = $string;
    $string = Unicode::Regex::Parser::parser->Regex(\$set) || $string;
  }

  if (length $before->[0]) {
    $before = "before => qr($before->[0]\\G)x,";
  }
  else {
    $before = '';
  }

  $replace->[0] = '' unless defined $replace->[0];
  $from.="\\G$replace->[0]";
  if (length $after->[0]) {
    $from.="(?=$after->[0])";
  }

  if(length $revisit->[0]) {
    $offset = "- length(\"$revisit->[0]\")";
    $revisit->[0] =~s/^\@+//;
    $compleated->[0].=$revisit->[0];
  }

  $return = "push \@{\$rules[-1]}, { $before from => qr($from)x, to => \"$compleated->[0]\", offset => '$offset' };\n";
}

BACKWARD_CONVERSION_RULE: COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) '←' BEFORE_CONTEXT(?) TEXT_TO_REPLACE(?) AFTER_CONTEXT(?)
{
  $return = ''; 1;
}

DUAL_CONVERSION_RULE: BEFORE_CONTEXT(?) COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) AFTER_CONTEXT(?) '↔' BEFORE_CONTEXT(?) COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) AFTER_CONTEXT(?)
{
  my ($before, $replace, $continue, $after, $compleated, $revisit) = @item[1 .. 4, 7, 8 ];
  my ($from, $offset) = ('',0);
  $replace->[0] .= $continue->[0];
  foreach my $string ($before->[0], $replace->[0], $after->[0], $compleated->[0], $revisit->[0]) {
    $string=~s/^\s*(.*?)\s*$/$1/;
    $string =~s/(\$\p{IDStart}\p{IDContinue}*)/exists $::Variables{$1} ? $::Variables{$1} : "\\$1"/eg;
    $string =~s/\$(\d+)/\\\$$1/g;
    my $set = $string;
    $string = Unicode::Regex::Parser::parser->Regex(\$set);
  }
  if (length $before->[0]) {
    $before = "before => qr($before->[0]\\G)x,";
  }
  else {
    $before = '';
  }
  $from.="\\G$replace->[0]";
  if (length $after->[0]) {
    $from.="(?=$after->[0])";
  }

  if(length $revisit->[0]) {
    $offset = "- length(\"$revisit->[0]\")";
    $revisit->[0] =~s/^\@+//;
    $compleated->[0].=$revisit->[0];
  }

  $return = "push \@{\$rules[-1]}, { $before from => qr($from)x, to => \"$compleated->[0]\", offset => '$offset' };\n";
}

BEFORE_CONTEXT: <skip:''> CHARACTER_TYPE_EXCLUDE["{;←↔→\x{ff5b}"](s) /[\x{ff5b}{]/
{
  pop @{$item[2]} while $item[2][-1]=~/\s/;
  $return = join '', @{$item[2]};
}

COMPLEATED_RESULT: <skip:''> CHARACTER_TYPE_EXCLUDE["}|;←↔→\x{ffd}"](s)
{
  pop @{$item[2]} while $item[2][-1]=~/\s/;
  $return = join '', @{$item[2]};
}

RESULT_TO_REVIST: '|' TEXT_TO_REPLACE
{
  $return = $item[2];
}

TEXT_TO_REPLACE: <skip:''> CHARACTER_TYPE_EXCLUDE[";}↔←→\x{FF5D}"](s)
{
  pop @{$item[2]} while $item[2][-1]=~/\s/;
  $return = join '', @{$item[2]};
}

AFTER_CONTEXT: /[\x{ff5d}}]/ <skip:''> CHARACTER_TYPE_EXCLUDE[';←↔→'](s)
{
  pop @{$item[3]} while $item[3][-1]=~/\s/;
  $return = join '', @{$item[3]};
}

VARIABLE_DEFINITION_RULE: /\$\p{IDStart}\p{IDContinue}*/ /=\s*/ <skip:''> CHARACTER_TYPE_EXCLUDE[';'](s)
{
  $::Variables{$item[1]} = join ('', @{$item[4]});
  $::Variables{$item[1]} =~s/(\$\p{IDStart}\p{IDContinue}*)/exists $::Variables{$1} ? $::Variables{$1} : $1/eg;
  chop $::Variables{$item[1]} while $::Variables{$item[1]}=~/\s$/;
  $return = '';
}

CHARACTER_STRING:       ESCAPE_CHR { $return = $item[1] }
|                       CHARACTER_TYPE <reject: $item[1] eq "'">
{ $return = $item[1] }

CHARACTER_TYPE_EXCLUDE: ESCAPE_CHR { $return = $item[1] }
|                       STRING { $return = $item[1] }
|                       CHARACTER_TYPE {$arg[0]=quotemeta $arg[0]} <reject: $item[1] =~ /[$arg[0]]/>
{ $return = $item[1] }

ESCAPE_CHR: HEX_CODE_POINT {$return=$item[1]}
|           ESCAPE CODE_POINT {$return = "\\$item[2]" }

CHARACTER_TYPE:    HEX_CODE_POINT { $return = $item[1]; }
|                  CODE_POINT { $return = $item[1]; }

HEX_CODE_POINT:    ESCAPE /u/i /\p{IsXDigit}+/ 
{ $return = "\\x{$item[3]}"; }

STRING: <skip:''> "'" CHARACTER_STRING(s?) "'"
{
  $return = join '', "'", @{$item[3]}, "'";
  $return = "\\'" if $return eq "''";
}

CODE_POINT:        /[\x{0000}-\x{10FFFF}]/
ESCAPE:            '\\'

EOGRAMMAR

  our $transformParserForwards ||= Parse::RecDescent->new($transformGrammar);
  our $transformParserBackwards ||= Parse::RecDescent->new($transformGrammar);

  # Fixup the reverse transformation
  $transformParserBackwards->Replace(<<'EOGRAMMAR');
RULES: RULE(s) { $return = join "\n", reverse @{$item[1]}; }

FORWARD_FILTER: /::\s*/ UNICODE_SET ';' COMMENT(?)
{
  $return = "";
}

REVERSE_FILTER: /::\s*/ '(' UNICODE_SET ')' ';' COMMENT(?)
{
  $return = "sub filter_re { return qr($item[3]) }\n";
}

TRANSFORM_RULE_INVERSE: '::' '(' TRANSFORM_RULE_NAME ')'
{
  my ($filter, $from, $to) = ($item{TRANSFORM_RULE_NAME}[0], split /-/, $item{TRANSFORM_RULE_NAME}[1]);
  unless(defined $to) {
    $to = $from;
    $from = 'Any';
  }
  foreach ($from, $to) {
    $_ = ucfirst lc;
  }
  if (defined $filter) {
    $filter = "filter => '$filter',"
  }
  else {
    $filter = '';
  }
  $from = 'Any' if $from eq 'Und';
  $return = "push \@rules, sub {
  my (\$self, \$string) = \@_;
  return \$self->Transform($filter from=> '$from', to=> '$to', string => \$string);
};
push \@rules,[];
"
}

TRANSFORM_RULE_NORMAL:  '::' TRANSFORM_RULE_NAME '()'
{
  $return= '';
}

TRANSFORM_RULE_BOTH:    '::' TRANSFORM_RULE_NAME '(' TRANSFORM_RULE_NAME ')'
{
  my ($filter, $from, $to) = ($item[4][0], split /-/, $item[4][1]);
  unless(defined $to) {
    $to = $from;
    $from = 'Any';
  }
  foreach ($from, $to) {
    $_ = ucfirst lc;
  }
  if (defined $filter) {
    $filter = "filter => '$filter',"
  }
  else {
    $filter = '';
  }
  $from = 'Any' if $from = 'Und';
  $return = "push \@rules, sub {
  my (\$self, \$string) = \@_;
  return \$self->Transform($filter from => '$from', to => '$to', string => \$string);
};
"
}

FORWARD_CONVERSION_RULE: BEFORE_CONTEXT(?) TEXT_TO_REPLACE(?) AFTER_CONTEXT(?) '→' COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) 
{
  $return = '';
}

BACKWARD_CONVERSION_RULE: COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) '←' BEFORE_CONTEXT(?) TEXT_TO_REPLACE(?) AFTER_CONTEXT(?)
{
  use Data::Dumper;
  my ($before, $replace, $after, $compleated, $revisit) = @item[4 .. 6, 1,2 ];
  my ($from, $offset) = ('',0);
  foreach my $string ($before->[0], $replace->[0], $after->[0], $compleated->[0], $revisit->[0]) {
    $string=~s/^\s*(.*?)\s*$/$1/;
    $string =~s/(\$\p{IDStart}\p{IDContinue}*)/exists $::Variables{$1} ? $::Variables{$1} : "\\$1"/eg;
    $string =~s/\$(\d+)/\\\$$1/g;
    my $set = $string;
    $string = Unicode::Regex::Parser::parser->Regex(\$set);
  }
  if (length $before->[0]) {
    $before = "before => qr($before->[0]\\G)x,";
  }
  else {
    $before = '';
  }
  $replace->[0] ='' unless defined $replace->[0];
  $from.="\\G$replace->[0]";
  if (length $after->[0]) {
    $from.="(?=$after->[0])";
  }

  if(length $revisit->[0]) {
    $offset = "- length(\"$revisit->[0]\")";
    $revisit->[0] =~s/^\@+//;
    $compleated->[0].=$revisit->[0];
  }

  # Fixup $ at end of 'to' string
  $compleated->[0]=~s/\$$/\\\$/;
  $return = "push \@{\$rules[-1]}, { $before from => qr($from)x, to => \"$compleated->[0]\", offset => '$offset' };\n";
}

DUAL_CONVERSION_RULE: BEFORE_CONTEXT(?) COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) AFTER_CONTEXT(?) '↔' BEFORE_CONTEXT(?) COMPLEATED_RESULT(?) RESULT_TO_REVIST(?) AFTER_CONTEXT(?)
{
  my ($before, $replace, $continue, $after, $compleated, $revisit) = @item[6 .. 9, 2, 3 ];
  my ($from, $offset) = ('',0);
  $replace->[0] .= $continue->[0];
  foreach my $string ($before->[0], $replace->[0], $after->[0], $compleated->[0], $revisit->[0]) {
    $string=~s/^\s*(.*?)\s*$/$1/;
    $string =~s/(\$\p{IDStart}\p{IDContinue}*)/exists $::Variables{$1} ? $::Variables{$1} : "\\$1"/eg;
    $string =~s/\$(\d+)/\\\$$1/g;
    my $set = $string;
    $string = Unicode::Regex::Parser::parser->Regex(\$set);
  }
  if (length $before->[0]) {
    $before = "before => qr($before->[0]\\G)x,";
  }
  else {
    $before = '';
  }
  $from.="\\G$replace->[0]";
  if (length $after->[0]) {
    $from.="(?=$after->[0])";
  }

  if(length $revisit->[0]) {
    $offset = "- length(\"$revisit->[0]\")";
    $revisit->[0] =~s/^\@+//;
    $compleated->[0].=$revisit->[0];
  }

  $return = "push \@{\$rules[-1]}, { $before from => qr($from)x, to => \"$compleated->[0]\", offset => '$offset' };\n";
}

EOGRAMMAR

  my ($self, $file, $additional_paramaters) = @_;
  my $direction = $additional_paramaters->{backwards} ? 'backwards' : 'forwards';
  my $count = 0;

  print STDERR "From: $self->{file_name}; Direction: $direction\n" if $verbose;
  print $file <<'EOT';
use Unicode::Normalize;
use base 'Locale::CLDR::Transform';

our @rules;
push @rules, [];

EOT
  foreach my $transformation (@{$self->{transforms}}) {

    # Preprocess the rules so that we pass in a rule with no
    # white space or escaped characters. Also a rule can span 
    # multiple tRule elements so we need to check for that.

    my @rules = @{$transformation->{rules}};

    for (my $count = 0; $count < @rules; $count++) {
      while ($rules[$count]=~s/\\\s*$//) {
        $rules[$count+1]="$rules[$count]$rules[$count+1]";
	$rules[$count] = undef;
	$count++;
      }
    }
    
    @{$transformation->{rules}} = grep {defined} @rules;

    # $rules[$count] now contains the rule on one line
#    $::RD_TRACE=1;
    print $file (
      $direction eq   'backwards'
        ? $transformParserBackwards
	: $transformParserForwards
    )->Transforms(join "\n", @{$transformation->{rules}});
  }
  push @Transform_List,
    [$self->get_package_name()=~/^Local::CLDR::Transform::(.*?)::(.*?)(?:::(.*))?$/]
    unless (defined $self->{transforms}[0]{visibility}
      && $self->{transforms}[0]{visibility} eq 'internal');
}

sub create_list_file {
  my ($self, $list) = @_;
  open my $file, '>', 'Transform/List.pl' or die $!;
  my $time = gmtime;
  print $file <<EOT;
#Local::CLDR::Transform::List generated on $time GMT
#by $0 from data in the CLDR Version $::VERSION.
#This file contains all the public facing transformations

return <<EOT;
EOT
  foreach my $transform_pair (sort {$a->[0] cmp $b->[0]} @{$list}) {
    print $file join('=>', grep {defined} @{$transform_pair}), "\n";
  }
  print $file "EOT\n";
}

1;
