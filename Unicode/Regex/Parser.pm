package Unicode::Regex::Parser;
use 5.008;

use Parse::RecDescent;
use Unicode::Regex::Set;

use base 'Exporter';
our @EXPORT_OK = qw(parse parser);

# Set up the RecDescent Gramma
my $grammar = <<'EOGRAMMAR';
Regex:             REGEX_TERM(s) 
{ $return = join '', @{$item[1]}; }

REGEX_TERM:        STRING { $return = $item[1]; }
|                  PROPERTY_OP { $return = $item[1]; }
|                  SET_OP { $return = $item[1]; }
|                  GROUP_OP { $return = $item[1]; }
|                  PERL_PROPERTY_OP { $return = $item[1]; }
|                  CHARACTER_TYPE_OP { $return = $item[1]; }

PROPERTY_OP:       PROPERTY REGEX_OP(?)
{ $return = "$item[1]$item[2][0]"; }

SET_OP:            SET REGEX_OP(?)
{ $return = "$item[1]$item[2][0]"; }

GROUP_OP:          GROUP REGEX_OP(?)
{ $return = "$item[1]$item[2][0]"; }

PERL_PROPERTY_OP:  PERL_PROPERTY REGEX_OP(?)
{ $return = "$item[1]$item[2][0]"; }

CHARACTER_TYPE_OP: CHARACTER_TYPE REGEX_OP(?)
{ $return = "$item[1]$item[2][0]"; }

STRING:            "'" STRING_TYPE(s?) "'" 
{ $return = join '', @{$item[2]}; }

STRING_TYPE:       ESCAPE_CHR["'"] { $return = $item[1]; }
|                  CHARACTER_TYPE <reject: $item[1] eq "'"> { $return = $item[1]; }

SET:               <skip:''> SET_EXPRESSION
{ 
  $return = __PACKAGE__->parse_set($item[2]);
}

SET_EXPRESSION:    PROPERTY { $return = $item[1] }
|                  SET_EXPRESSION_BLOCK { $return = $item[1] }
|                  SET_INTERSECTION_BLOCK { $return = $item[1] }
|                  SET_DIFFERENCE_BLOCK { $return = $item[1] }
|                  SET_UNION_BLOCK { $return = $item[1] }

SET_EXPRESSION_BLOCK: SET_EXPRESSION_BLOCK_N { $return = $item[1]; }
|                     SET_EXPRESSION_BLOCK_P { $return = $item[1]; }

SET_EXPRESSION_BLOCK_N: /\s*\[\^\s*/ SET_EXPRESSION /\s*\]/
{ 
  $return = "[^ $item[2] ]"
}

SET_EXPRESSION_BLOCK_P: /\s*\[\s*/ SET_EXPRESSION /\s*\]/
{ 
  $return = "[ $item[2] ]"
}

SET_INTERSECTION_BLOCK: SET_INTERSECTION_BLOCK_N { $return = $item[1]; }
|                       SET_INTERSECTION_BLOCK_P { $return = $item[1]; }

SET_INTERSECTION_BLOCK_N: /\s*\[\^\s*/ SET_INTERSECTION /\s*\]/
{
  $return = "[^ $item[2] ]"
}

SET_INTERSECTION_BLOCK_P: /\s*\[\s*/ SET_INTERSECTION /\s*\]/
{
  $return = "[ $item[2] ]"
}

SET_DIFFERENCE_BLOCK: SET_DIFFERENCE_BLOCK_N { $return = $item[1] }
|                     SET_DIFFERENCE_BLOCK_P { $return = $item[1] }

SET_DIFFERENCE_BLOCK_N: /\s*\[\^\s*/ SET_DIFFERENCE /\s*\]/
{
  $return = "[^ $item[2] ]" 
}

SET_DIFFERENCE_BLOCK_P: /\s*\[\s*/ SET_DIFFERENCE /\s*\]/
{
  $return = "[ $item[2] ]" 
}

SET_UNION_BLOCK:   SET_UNION_BLOCK_N { $return = $item[1]; }
|                  SET_UNION_BLOCK_P { $return = $item[1]; }

SET_UNION_BLOCK_N: /\s*\[\^\s*/ SET_UNION(s) /\s*\]/
{
  $return = join '', '[^ ', @{$item[2]}, " ]"
}

SET_UNION_BLOCK_P: /\s*\[\s*/ SET_UNION(s) /\s*\]/
{
  $return = join '', '[ ', @{$item[2]}, " ]"
}

SET_INTERSECTION:  <leftop: SET_UNION /\s+&&?\s+/ SET_UNION>
{ $return = join ' & ', @{$item[1]} }

SET_DIFFERENCE:    <leftop: SET_UNION /\s+--?\s+/ SET_UNION>
{ $return = join ' - ', @{$item[1]} }

SET_UNION:         PROPERTY {$return = $item[1]}
|                  SET_EXPRESSION {$return = $item[1]}
|                  EXPOSED_RANGE {$return = $item[1]}
|                  SET_UNION_TYPE_LIST {$return = $item[1] }
|                  PERL_PROPERTY {$return = $item[1] }
|                  /\s+/ {$return = $item[1] }
|                  CHARACTER_TYPE_EXCLUDE['[\]\|\-& ]'](s) {$return = join '', @{$item[1]} }

SET_UNION_TYPE_LIST: <leftop: SET_UNION_TYPE /\s+\|\|?\s+/ SET_UNION_TYPE>
{
  $return = join ' | ', @{$item[1]};
}

SET_UNION_TYPE:     PROPERTY {$return = $item[1] }
|                   SET_EXPRESSION_BLOCK {$return = $item[1] }
|                   SET_UNION_BLOCK {$return = $item[1] }
|                   EXPOSED_RANGE {$return = $item[1] }
|                   CHARACTER_TYPE_EXCLUDE['[\]\| ]'](s) {$return = join '',   @{$item[1]} }

CHARACTER_TYPE_EXCLUDE: ESCAPE_CHR[$arg[0]] { $return = $item[1] }
|                       CHARACTER_TYPE <reject: $item[1] =~ /$arg[0]/>
{ $return = $item[1] }

RANGE:             EXPOSED_RANGE
{ $return = "[$item[1]]"; }

EXPOSED_RANGE:     CHARACTER_TYPE "-" CHARACTER_TYPE 
{ $return = "$item[1]-$item[3]"; }

GROUP:             "(" REGEX_TERM(s) ")" 
{ $return = join '', '(', @{$item[2]}, ')'; print "GROUP: $return\n" }

PROPERTY:          /\s*/ /\^?/ "[:" NEGATE(?) CHARACTER_TYPE_EXCLUDE[':'](s) ":]" 
{ $return = ' ' . ($item[2] ? '^' : '') . '[:' . ($item[4][0] ? '^' : '') . join '', @{$item[5]}, ':] '; }

ESCAPE_CHR:        ESCAPE "$arg[0]" 
{ $return = $arg[0]; }

GRAPHEME_CLUSTER:  "{" CHARACTER_TYPE(s) "}" 
{ $return = bless $item[2], 'Unicode::Rgex::Parse::GraphemeCluster'; }

CHARACTER_TYPE:    HEX_CODE_POINT { $return = $item[1]; }
|                  CODE_POINT { $return = $item[1]; }

HEX_CODE_POINT:    ESCAPE /u/i /\p{IsXDigit}+/ 
{ $return = chr hex $item[3]; }

PERL_PROPERTY:     ESCAPE /[pP]\{[^\}]+\}/ 
{ $return = "\\$item[2]" ; }

REGEX_OP:          ZERO_OR_MORE { $return = $item[1]; }
|                  ZERO_OR_ONE { $return = $item[1]; }
|                  ONE_OR_MORE { $return = $item[1]; }

CODE_POINT:        /[\x{0000}-\x{10FFFF}]/
ESCAPE:            '\\'
NEGATE:            /^\s*/
ZERO_OR_MORE:      "*"
ZERO_OR_ONE:       "?"
ONE_OR_MORE:       "+"
EOGRAMMAR

sub Parse::RecDescent::parse_set {
  my $self = shift;
  my $set  = shift;

  my $return = Unicode::Regex::Set::parse($set);
  return $return;
}

my $parser = new Parse::RecDescent($grammar);

sub parse {
  # Takes a string containing the unicode regex to parse
  # Oprional hashref or key / value list of variables
  # returns a perl regex ref

  my ($UnicodeRegex, @vars) = @_;
  my %Vars;
  if (@vars) { # test for a kv list or hash ref
    if (ref $vars[0] eq 'HASH') {
      %Vars = %$vars;
    }
    else {
      %Vars = @vars;
    }
  }
  return $parser->Regex($UnicodeRegex);
}

sub parser {
  return $parser;
}

1;
