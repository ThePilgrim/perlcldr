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

REGEX_TERM:        "'" STRING_TYPE(s?) "'" { $return = join '', @{$item[2]}; }
|                  "(" REGEX_TERM(s) ")" REGEX_OP(?) { $return = join '', @{$item[2]}, $item[4][0]; }
|                  PROPERTY REGEX_OP(?) { $return = "$item[1]$item[2][0]"; }
|                  SET REGEX_OP(?) { $return = "$item[1]$item[2][0]"; }
|                  PERL_PROPERTY REGEX_OP(?) { $return = "$item[1]$item[2][0]"; }
|                  CHARACTER_TYPE REGEX_OP(?) { $return = "$item[1]$item[2][0]"; }

STRING_TYPE:       CHARACTER_TYPE_EXCLUDE["'"] { $return = $item[1]; }

SET:               <skip:''> SET_EXPRESSION
{ 
  $return = __PACKAGE__->parse_set($item{SET_EXPRESSION});
}

SET_EXPRESSION:    PROPERTY { $return = $item[1] }
|                  /\s*/ '[' NEGATE(?) /\s*/ SET_EXPRESSION /\s*/ ']' { $return = "[" . ($item[3][0] ? '^' : '' ) . " $item{SET_EXPRESSION} ]" }
|                  /\s*/ '[' NEGATE(?) /\s*/ SET_INTERSECTION /\s*/ ']' { $return = "[" . ($item[3][0] ? '^' : '' ) . " $item{SET_INTERSECTION} ]" }
|                  /\s*/ '[' NEGATE(?) /\s*/ SET_DIFFERENCE /\s*/ ']' { $return = "[" . ($item[3][0] ? '^' : '' ) . " $item{SET_DIFFERENCE} ]" }
|                  /\s*/ '[' NEGATE(?) /\s*/ SET_UNION(s) /\s*/ ']' { $return = join '', "[" , ($item[3][0] ? '^ ' : ' ' ) ,  @{$item[5]}, " ]" }

SET_INTERSECTION:  <leftop: SET_UNION /(\s*&&?\s*)/ SET_UNION>
{ $return = join '', @{$item[1]} }

SET_DIFFERENCE:    <leftop: SET_UNION /(\s*--?\s*)/ SET_UNION>
{ $return = join '', @{$item[1]} }

SET_UNION:         NEGATE SET_UNION { $return = "^$item[2]"}
|                  PROPERTY {$return = $item[1]}
|                  PERL_PROPERTY {$return = $item[1] }
|                  SET_EXPRESSION {$return = $item[1]}
|                  EXPOSED_RANGE {$return = $item[1]}
|                  SET_UNION_TYPE_LIST {$return = $item[1] }
|                  /\s+/ {$return = $item[1] }
|                  CHARACTER_TYPE_EXCLUDE['[\[\]\|\-& ]'](s) {$return = join '', @{$item[1]} }
|                  '|' .../\S/ { $return = '|'; }

SET_UNION_TYPE_LIST: <leftop: SET_UNION_TYPE /\s+\|\|?\s+/ SET_UNION_TYPE>
{
  $return = join ' | ', @{$item[1]};
}

SET_UNION_TYPE:     PROPERTY {$return = $item[1] }
|                   /\s*/ '[' NEGATE(?) /\s*/ SET_EXPRESSION /\s*/ ']' { $return = "[" . ($item{NEGATE}[0] ? '^' : '' ) . " $item{SET_EXPRESSION} ]" }
|                   /\s*/ '[' NEGATE(?) /\s*/ SET_UNION /\s*/ ']' { $return = "[" . ($item{NEGATE}[0] ? '^' : '' ) . " $item{SET_UNION} ]" }
|                   EXPOSED_RANGE {$return = $item[1] }
|                   CHARACTER_TYPE_EXCLUDE['[\[\]\| ]'](s) {$return = join '',   @{$item[1]} }

CHARACTER_TYPE_EXCLUDE: ESCAPE_CHR { $return = $item[1] }
|                       CHARACTER_TYPE <reject: $item[1] =~ /$arg[0]/>
{ $return = $item[1] }

EXPOSED_RANGE:     CHARACTER_TYPE "-" CHARACTER_TYPE 
{ $return = "$item[1]-$item[3]"; }


PROPERTY:          /\s*/ /\^?/ "[:" NEGATE(?) CHARACTER_TYPE_EXCLUDE[':'](s) ":]" 
{ 
  my $property = $item[2] || $item[4][0] ? 'P' : 'p' ;
  my $name = join'', @{$item[5]};
  $name = ucfirst $name;
  $name = 'XDigit' if $name eq 'Xdigit';
  # \p{ccc=\d+} is currently borked so use this workaround
  $name =~s/^Ccc=(\d+)$/ccc$1/ unless 'a'=~/\p{ccc=NR}/;
  $return = $item[1] . "\\${property}{" . $name ."}";
}

ESCAPE_CHR:        HEX_CODE_POINT {$return = $item[1]}
|                  ESCAPE CODE_POINT { $return = "\\$item[2]"; }

GRAPHEME_CLUSTER:  "{" CHARACTER_TYPE(s) "}" 
{ $return = bless $item[2], 'Unicode::Rgex::Parse::GraphemeCluster'; }

CHARACTER_TYPE:    HEX_CODE_POINT { $return = $item[1]; }
|                  CODE_POINT { $return = $item[1]; }

HEX_CODE_POINT:    ESCAPE /u/i /\p{IsXDigit}+/ 
{ $return = "\\x{$item[3]}"; }

PERL_PROPERTY:     ESCAPE /[pP]\{[^\}]+\}/ 
{ $return = "\\$item[2]" ; }

REGEX_OP:          ZERO_OR_MORE { $return = $item[1]; }
|                  ZERO_OR_ONE { $return = $item[1]; }
|                  ONE_OR_MORE { $return = $item[1]; }

CODE_POINT:        /[\x{0000}-\x{10FFFF}]/
ESCAPE:            '\\'
NEGATE:            /\^\s*/
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
