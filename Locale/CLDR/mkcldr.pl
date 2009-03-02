)#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use 5.008;
use utf8;
use lib '../..';

use XML::Parser;
use File::Spec;
use File::Path;
use File::Basename;
use Unicode::Regex::Parser;

use constant {
  START => 1,
  STOP  => 2,
};

binmode STDERR, ':utf8';
binmode $DB::OUT, ':utf8' if defined $DB::OUT;

my $verbose = '';
if (grep /-v/, @ARGV) {
  $verbose = 1;
}

# Match version to CLDR version
our $VERSION = '1.6.1';

# Get the directories to parse
my @directories;
my $dir;
if (opendir($dir, 'Data')) {
  foreach my $file (readdir($dir)) {
    next unless -d File::Spec->catdir("Data",$file); # Skip none directories
    next if $file=~/^\./;                           # Skip hidden files
    push @directories, File::Spec->catdir("Data",$file);
  }
}
else {
  die $!;
}

foreach my $directory (@directories) {
  my $dir;
  if(opendir($dir, $directory)) {
    foreach my $filename (readdir $dir) {
      my $fullname = File::Spec->catfile($directory,$filename);
      next unless -f $fullname;       # Skip anything that is not a regular file
      next if $filename=~/^\./;        # Skip hidden files
      next unless $filename=~/\.xml$/i; # Skip anything without an .xml extention
      process_file($fullname);
    }
  }
  else {
    warn "Unable to process directory $directory: $!, skipping\n";
  }
}

sub process_file {
  my $filename = shift;

  print STDERR "Processing $filename\n" if $verbose;
  
  my $parser = XML::Parser->new(
    Handlers => {
      Init  => \&do_init,
      Final => \&do_final,
      Start => \&do_start,
      End   => \&do_end,
      Char  => \&do_char,
    }
  );

  return $parser->parsefile($filename);
}

{
  my %data;
  sub do_init {
    my ($expat) = @_;
    %data=(
      stack     => [],
      file_name => $expat->base(),
      version   => $VERSION,
    );
  }

  sub do_final {
    my ($expat) = @_;
    process_data(\%data);
    return 1;
  }

  sub do_start {
    my ($expat, $element, %attributes) = @_;
    if (defined &$element) {
      no strict 'refs';
      $element->(START, \%data, \%attributes);
    }
    else {
      die "Elelment $element not defined\n";
    }
    push @{$data{stack}},$element;
  }
  
  sub do_end {
    my ($expat, $element) = @_;
    if (defined &$element) {
      no strict 'refs';
      $element->(STOP, \%data);
    }
    pop @{$data{stack}};
    delete $data{"@{$data{stack}}"};
  }
  
  sub do_char {
    my ($expat, $string) = @_;
    $data{"@{$data{stack}}"}{_characters} .= "$string ";
  }
}

sub process_data {
  my $data = shift;
  (undef, $data->{_section_}) = File::Spec->splitdir($data->{file_name});
  bless $data,_get_class($data);
  $data->create_file_path;
  $data->create_files;
}

# elements described here
sub ldml {
  my ($type, $data, $attributes) = @_;
}

sub identity {
  my ($type, $data, $attributes) = @_;
  #/ldml
}

sub version {
  my ($type, $data, $attributes) = @_;
  #/ldml/identity
  if ($type == START) {
    $data->{version} = $attributes->{number};
    $data->{version}=~s/^\$Revision: ([^ ]+) \$$/$1/;
  }
}

sub generation {
  my ($type, $data, $attributes) = @_;
  #/ldml/identity
  if ($type == START) {
    $data->{generation} = $attributes->{date};
    $data->{generation}=~s/^\$Date: (.+) \$$/$1/;
  }
}

sub language {
  my ($type, $data, $attributes) = @_;
  if ($type == START) {
    #/ldml/identity
    if ($data->{stack}[-1] eq 'identity') {
      $data->{language} = $attributes->{type};
    }
    #/ldml/localeDisplayNames/languages
    elsif ($data->{stack}[-1] eq 'languages'){
      die;
    }
    else {
      use Data::Dumper;
      die Dumper($data);
    }
  }
}

sub territory {
  my ($type, $data, $attributes) = @_;
  #/ldml/identity
  if ($type == START) {
    $data->{territory} = $attributes->{type};
  }
}

sub variant {
  my ($type, $data, $attributes) = @_;
  #/ldml/identity
  if ($type == START) {
    $data->{variant} = $attributes->{type};
  }
}

sub segmentations {
  my ($type, $data, $attributes) = @_;
  #/ldml
}

sub segmentation {
  my ($type, $data, $attributes) = @_;
  #/ldml/segmentations
  if ($type == START) {
    $data->{segmentations}{segmentation}{$attributes->{type}}={};
    $data->{segmentations}{current}=
      $data->{segmentations}{segmentation}{$attributes->{type}};
  }
}

sub variables {
  my ($type, $data, $attributes) = @_;
  #/ldml/segmentations/segmentation
}

sub variable {
  my ($type, $data, $attributes) = @_;
  #/ldml/segmentations/segmentation/variables
  if ($type == START) {
    $data->{segmentations}{current}{variables}{current} = $attributes->{id};
  }
  else {
    # Strip pre and post white space
    $data->{"@{$data->{stack}}"}{_characters}=~s/^\s*(.*?)\s*$/$1/;

    $data->{"@{$data->{stack}}"}{_characters}=~s/(\$\p{ID_Start}\p{ID_Continue}*)/$data->{segmentations}{current}{variables}{variable}{$1} || $1/eg;
    $data->{segmentations}{current}{variables}{variable}{$data->{segmentations}{current}{variables}{current}} =
      $data->{"@{$data->{stack}}"}{_characters};
   $data->{"@{$data->{stack}}"}{_characters}='';
  }
}

sub segmentRules {
  my ($type, $data, $attributes) = @_;
  #/ldml/segmentations/segmentation
}

sub rule {
  my ($type, $data, $attributes) = @_;
  #/ldml/segmentations/segmentation/segmentRules
  if ($type == START) {
    push @{$data->{segmentations}{current}{segmentRules}{_order_}},$attributes->{id};
    $data->{segmentations}{current}{segmentRules}{rule}{$attributes->{id}}='';
    $data->{segmentations}{current}{segmentRules}{current}=
      \$data->{segmentations}{current}{segmentRules}{rule}{$attributes->{id}};
  }
  else {
   ${$data->{segmentations}{current}{segmentRules}{current}}=
    $data->{"@{$data->{stack}}"}{_characters};
   $data->{"@{$data->{stack}}"}{_characters}='';
  }
}

sub supplementalData {
  my ($type, $data, $attributes) = @_;
  $data->{version} = $attributes->{version}
    if defined $attributes->{version};
}

sub transforms {
  my ($type, $data, $attributes) = @_;
  #/supplementalData
}

sub transform {
  my ($type, $data, $attributes) = @_;
  #/supplementalData/transforms
  if ($type == START ) {
    push @{$data->{transforms}}, {
      from       => $attributes->{source},
      to         => $attributes->{target},
      direction  => $attributes->{direction},
      variant    => $attributes->{variant},
      visibility => $attributes->{visibility},
      rules     => [],
    };
  }
}

sub tRule {
  my ($type, $data, $attributes) = @_;
  #/supplementalData/transforms/transform
  if ($type == STOP) {

    push @{$data->{transforms}[-1]{rules}},
      $data->{"@{$data->{stack}}"}{_characters};
    $data->{"@{$data->{stack}}"}{_characters} = '';
  }
}

sub comment {}

sub localeDisplayNames {
  my ($type, $data, $attributes) = @_;
  #/ldml
}

sub languages {
  my ($type, $data, $attributes) = @_;
  #/ldml/localeDisplayNames
  if ($type == START) {
    $data->{localDisplayNames}{languages} = [];
  }
}

sub _get_class {
  my $data = shift;
  return 'CLDR::Create::Segmentations' if $data->{segmentations};
  return 'CLDR::Create::Transforms'    if $data->{transforms};
  die "Unknown Class";
}

package CLDR::Create::Base;
use File::Basename;
use File::Path;

# None standard modules
use Unicode::Regex::Parser;

sub create_file_path {
  my $self = shift;
  foreach my $filename ($self->get_file_name()) {
    unless (-e "${filename}.pm") {
      my $dir  = dirname($filename);
      mkpath $dir;
    }
  }
}

sub get_file_name {
  my $self = shift;
  my $filenames = $self->{__cache__}{filenames};
  if (! $filenames) {
    $filenames = $self->_calculate_file_names();
  }
  return wantarray ? @$filenames : $filenames->[0];
}

sub current_file_name {
  my $self = shift;
  if (@_) {
    $self->{__cache__}{current_file_name} = $_[0];
  }
  return $self->{__cache__}{current_file_name};
}

sub _calculate_file_names {
  my $self = shift;
  $self->{__cache__}{filenames} = [File::Spec->catfile(map {defined($_) ? $_ : 'any'} @$self{qw{_section_ language script territory variant}})];
  tr[-][_] foreach @{$self->{__cache__}{filenames}};
  return $self->{__cache__}{filenames};
}

sub create_files {
  my $self = shift;
  foreach my $filename ($self->get_file_name) {
    $self->current_file_name($filename);
    $self->create_file();
  }
}

sub create_file {
  my ($self, $additional_paramaters) = @_;
  my $filename = $self->current_file_name;
  open my $file, '>:utf8', "$filename.pm" or die "Can't open $filename: $!";
  print $file $self->file_header;
  $self->add_data_to_file($file, $additional_paramaters);
  print $file "1;\n";
  close $file;
}

sub version {
  my $self = shift;
  if (@_) {
    $self->{version} = $_[0];
  }
  return $self->{version};
}

sub generation_date {
  my $self = shift;
  if (@_) {
    $self->{generation} = $_[0];
  }
  return $self->{generation} || 'unknown date';
}

sub get_package_name {
  my $self = shift;
  my $package = join '::', map {defined($_) ? ucfirst lc $_ : 'Any' } (qw(Locale CLDR), @$self{qw{_section_ language script territory variant}});
  return $package;
}

sub file_header {
  my $self = shift();

  my $file_name = $self->{file_name};
  my $version   = $self->version;
  my $date      = $self->generation_date;
  my $package   = $self->get_package_name($file_name);
  my $now = gmtime() . ' GMT';
  return <<EOT;
# This file was autogenerated by $0 on $now
# from the CLDR data file: $file_name generated on $date
# Do NOT Normailze this file. It will break

package $package;
use strict;
use warnings;
use utf8;
our \$VERSION = $version;

EOT
}

sub process_unicode_re {
  my ($self, $re) = @_;
  my $parsed_re = Unicode::Regex::Parser::parse($re);
  return $parsed_re;
}

package CLDR::Create::Segmentations;
BEGIN {
  our @ISA = ('CLDR::Create::Base');
}

sub add_data_to_file {
  my ($self, $file) = @_;
  print $file "# Segmentations\n";
  foreach my $segment (keys %{$self->{segmentations}{segmentation}}) {
    print $file <<EOT;
sub segmentation_${segment}_variables {
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

sub segmentation_${segment}_rules {
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

package CLDR::Create::Transforms;
use File::Path;
use File::Basename;
BEGIN {
  our @ISA = ('CLDR::Create::Base');
}
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

FORWARD_FILTER: '::' UNICODE_SET ';' COMMENT(?)
{
  $return = "sub filter_re { return qr($item[2]) }\n";
}

REVERSE_FILTER: '::' '(' UNICODE_SET ')' ';' COMMENT(?)
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

BEFORE_CONTEXT: <skip:''> CHARACTER_TYPE_EXCLUDE["{;←↔→\x{ff5b}"](s) /[\x{{{ff5b}{]/
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
  $return = "# $item[1] = $::Variables{$item[1]}\n";
}

CHARACTER_STRING:       ESCAPE_CHR { $return = $item[1] }
|                       CHARACTER_TYPE <reject: $item[1] eq "'">
{ $return = $item[1] }

CHARACTER_TYPE_EXCLUDE: ESCAPE_CHR { $return = $item[1] }
|                       STRING { $return = $item[1] }
|                       CHARACTER_TYPE <reject: $item[1] =~ /[\Q$arg[0]\E]/>
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

FORWARD_FILTER: '::' UNICODE_SET ';' COMMENT(?)
{
  $return = "";
}

REVERSE_FILTER: '::' '(' UNICODE_SET ')' ';' COMMENT(?)
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
use if 'a' !~/\p{ccc=NR}/, 'Unicode::Regex::CCC';

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
