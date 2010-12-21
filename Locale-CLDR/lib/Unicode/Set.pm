package Unicode::Set;
use 5.010;
use strict;
use warnings;

use List::Util qw(first);
use List::MoreUtils qw(zip);
use Sub::Exporter -setup => {
	exports => [ qw(unicode_to_perl) ]
};

use Regexp::Grammars;

use Readonly;
Readonly my %POSIX_TO_UNICODE => (
	alnum	=> '\p{L&}\p{Nd}',
	alpha	=> '\p{L&}',
	ascii	=> '\p{InBasicLatin}',
	blank	=> "\\p{Zs}\t",
	cntrl	=> '\p{Cc}',
	digit	=> '\p{Nd}',
	graph	=> '[^\p{Z}\p{C}]',
	lower	=> '\p{Ll}',
	print	=> '\p{C}',
	punct	=> '[\p{P}\p{S}]',
	space	=> '\s',
	uppse	=> '\p{Lu}',
	word	=> '\w',
	xdigit	=> '[A-Fa-f0-9]',
);

my $gramma = qr{
	<gramma>
	<rule: gramma>
		(?: <pre=not_set>? <[unicode_set]>* )
		<MATCH=(?{
			my $regex = ( $MATCH{pre} // '' )
				. join ' ', @{$MATCH{unicode_set} // []};
			qr/$regex/msx; 
		})>

	<rule: not_set>
		(?: [^\[]+ )

	<rule: unicode_set>
		(?: <.neg_open> <set=negative_set> \] | \[ <set> \] ) <not_set>?
		<MATCH=(?{
			stringify($MATCH{set}) . ( $MATCH{not_set} // '' ); 
	})>

	<token: neg_open>
		\[\^

	<rule: negative_set>
		(?: <[expression]> ** <[op]>  | <[expression]>+ )
		<MATCH=(?{
			mktree(1, $MATCH{expression}, $MATCH{op}) 
		})>

	<rule: set>
		(?: <[expression]> ** <[op]>  | <[expression]>+ )
		<MATCH=(?{
			mktree(0, $MATCH{expression}, $MATCH{op})
		})>

	<token: negation>
		[\^]

	<rule: op>
		(?: & | \| | - | )

	<rule: expression>
		(?: <property> | (?: <.neg_open> <[set=negative_set]> \] | \[ <[set]>+ \] ) | <[list]>+ )
		<MATCH=(?{
			my (@list, @cluster) = ();
			if ($MATCH{list}) {
				foreach my $test (@{$MATCH{list}}) {
					if (index($test, "{") == 0) { 
						chop $test;
						$test = reverse $test;
						chop $test;
						$test = reverse $test;
						push @cluster, $test;
					}
					else {
						push @list, $test;
					}
				} 
			}

			my $ret = defined $MATCH{set}
				? mktree ($MATCH{set}, [('|') x (@{$MATCH{set}} - 1)]) 
				: defined $MATCH{property} 
					? $MATCH{property} 
					: @list
						? '[' . join( '', @list) . ']'
						: '';
			
			if (@cluster) {
				$ret = "(?:" . join('|', @cluster) . "|$ret)"
			}

			'}' && $ret;
		})>

	<rule: property>
		(?: <perl_property> | <unicode_property> )
		<MATCH=(?{
			defined $MATCH{perl_property}
				? $MATCH{perl_property}
				: $MATCH{unicode_property}
		})>

	<rule: perl_property>
		\\ [pP] \{ .*? \}

	<rule: unicode_property>
		\[: <negation>? <[litteral]>+? :\]
		<MATCH=(?{
			$MATCH{negation} 
				? '[^' . $POSIX_TO_UNICODE{lc join ('', @{$MATCH{litteral}})} . ']'
				: '[' . $POSIX_TO_UNICODE{lc join ('', @{$MATCH{litteral}})} . ']'
		})>
	
	<token: hyphon_minus>
		-

	<rule: list>
		(?:
			(?: <hyphon_range> | <hyphon_minus> )? 
			(?: <range> | <[grapheme_litteral]>+? )
			<end_hyphon=hyphon_minus>? 
		)
		<MATCH=(?{
			defined $MATCH{range} 
				? join '', (( $MATCH{hyphon_minus} // ()), $MATCH{range}) 
				: join '', (( $MATCH{hyphon_range} // ()), ( $MATCH{hyphon_minus} // () ), @{$MATCH{grapheme_litteral}}, ( $MATCH{end_hyphon} // () )) 
		})>

	<rule: hyphon_range>
		<from=hyphon_minus> - <to=litteral>
		<MATCH=(?{
			"$MATCH{from}-$MATCH{to}"
		})>

	<rule: range>
		<from=litteral> - <to=litteral>
		<MATCH=(?{
			"$MATCH{from}-$MATCH{to}"
		})>

	<rule: grapheme_litteral>
		(?: <grapheme> | <litteral> )
		<MATCH=(?{ $MATCH{grapheme} // $MATCH{litteral} })>

	<rule: grapheme>
		\{ <grapheme_chars> \} 
		<MATCH=(?{ '{' . $MATCH{grapheme_chars} . '}' })>

	<rule: grapheme_chars>
		<[grapheme_char]>+
		<MATCH=(?{ join '', @{$MATCH{grapheme_char}} })>

	<rule: grapheme_char>
		(?: <char=escape_u> | <char=escape_c> | <char=escapped> | <char=not_meta> ) 
		<MATCH=(?{
			$MATCH{char}
		})>

	<rule: litteral>
		(?: <char=escape_u> | <char=escape_c> | <char=escape_p> | <char=escapped> | <char=not_meta> )
		<MATCH=(?{
			$MATCH{char}
		})>

	<rule: escape_u>
		(?: \\ u <cp=hexDigits> )
		<MATCH=(?{
			chr hex $MATCH{cp}
		})>

	<token: hexDigits>
		\p{hexDigit}{1,6}

	<token: escape_c>
		\\ c [@-_]

	<token: escape_p>
		\\ [pP] \{

	<token: escapped>
		\\ \p{Any}

	<token: not_meta>
		[^\[\]-]
}x;

sub unicode_to_perl {
	my $set = shift;
	$set=~$gramma;
	my %ret = %/;
	return $ret{gramma};
}

sub mktree {
	my ($negation, $terms, $ops);
	if (@_ == 3 ) {
		($negation, $terms, $ops) = @_;
	}
	else {
		($terms, $ops) = @_;
	}

	my $tree = {};
	$ops //= [];
	$negation //= 0;

	$tree->{negation} = $negation;
	# No ops return $terms->[0]
	unless (@$ops) {
		$tree->{children} = [$terms->[0]];
		return $tree;
	}

	my ($first, $second) = (shift @$terms, shift @$terms);
	my $op = shift @$ops;
	
	$tree->{op}=$op;
	$tree->{children} = [$first, $second];

	while (@$ops && $ops->[0] eq $op) {
		push @{$tree->{children}}, shift @$terms;
		shift @$ops;
	}

	if (@$ops) {
		$tree->{children}[-1] = mktree([$second, @$terms], $ops);
	}

	return $tree;
}

sub stringify {
	my ($tree) = @_;

    for (@{ $tree->{children} }) {
		next  if !ref($_);
		die __PACKAGE__ . " panic" if ref($_) ne 'HASH';
		$_ = stringify($_); # recursive
    }

    my $ret;
    my $op   = $tree->{op} || '|';
    my $kids = $tree->{children};

    if ($op eq '&') {
		my $base = shift @$kids;
		my $pre  = join '', map "(?=$_)", @$kids;
		$ret = "(?:$pre$base)";
    }
    elsif ($op eq '-') {
		my $base = shift @$kids;
		my $pre  = join('|', @$kids);
		$ret = "(?:(?!$pre)$base)";
    }
    else {
		$ret = @$kids > 1 ? "(?:".join('|', @$kids).")" : $kids->[0];
    }

    return $tree->{negation} ? "(?:(?!$ret)(?s:.))" : $ret;
}
