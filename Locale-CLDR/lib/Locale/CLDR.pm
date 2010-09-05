package Locale::CLDR v1.8.1;
use 5.012;
use encoding 'utf8';
use feature 'unicode_strings';
use open ':encoding(utf8)';

use Moose;
with 'Locale::CLDR::ValidCodes';

=head1 NAME

Locale::CLDR - Main Class for CLDR Locals

=head1 VERSION

Version 1.8.0 To match the CLDR Version

=cut

use List::Util qw(first);
use Unicode::Set qw(parse);


=head1 SYNOPSIS

This module handles Local Data from the CLDR

=head1 Attributes

=cut

has 'language' => (
	is			=> 'ro',
	isa			=> 'Str',
	required	=> 1,
);

# language aliases
around 'language' => sub {
	my ($orig, $self) = @_;
	my $value = $self->$orig;
	return $self->language_aliases->{$value} // $value;
};

has 'script' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_script',
);

has 'territory' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_territory',
);

# territory aliases
around 'territory' => sub {
	my ($orig, $self) = @_;
	my $value = $self->$orig;
	return $value if defined $value;
	my $alias = $self->territory_aliases->{$value};
	return (split /\s+/, $alias)[0];
};

has 'variant' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_variant',
);

has 'extentions' => (
	is			=> 'ro',
	isa			=> 'Undef|HashRef',
	default		=> undef
);

has 'modules' => (
	is			=> 'ro',
	isa			=> 'ArrayRef[Object]',
	default		=> 'Root',
	writer		=> '_set_modules',
	init_arg	=> undef,
	auto_deref	=> 1,
	lazy		=> 1,
);

has 'method_cache' => (
	is			=> 'rw',
	isa			=> 'HashRef[ArrayRef[Object]]',
	init_arg	=> undef,
	default		=> sub { return {}},
);

has '_no_fallback' => (
	is			=> 'ro',
	isa			=> 'Bool',
	default		=> 0,
	lazy		=> 1,
);

has 'break_grapheme_cluster' => (
	is => 'ro',
	isa => 'ArrayRef',
	init_arg => undef(),
	lazy => 1,
	default => sub {shift->_build_break('GraphemeClusterBreak')},
);

has 'break_word' => (
	is => 'ro',
	isa => 'ArrayRef',
	init_arg => undef(),
	lazy => 1,
	default => sub {shift->_build_break('WordBreak')},
);

has 'break_line' => (
	is => 'ro',
	isa => 'ArrayRef',
	init_arg => undef(),
	lazy => 1,
	default => sub {shift->_build_break('LineBreak')},
);

has 'break_sentence' => (
	is => 'ro',
	isa => 'ArrayRef',
	init_arg => undef(),
	lazy => 1,
	default => sub {shift->_build_break('SentenceBreak')},
);

sub _build_break {
	my ($self, $what) = @_;

	my $vars = $self->_build_break_vars($what);
	my $rules = $self->_build_break_rules($vars, $what);
	return $rules;
}

sub _build_break_vars {
	my ($self, $what) = @_;

	my $name = "${what}_variables";
	my @bundles = $self->_find_bundle($name);
	my @vars;
	foreach my $bundle (reverse @bundles) {
		push @vars, @{$bundle->$name};
	}

	my %vars = ();
	while (my ($name, $value) = (shift @vars, shift @vars)) {
		last unless defined $name;
		if (! defined $value) {
			delete $vars{$name};
			next;
		}

		$value =~ s{ ( \$ \p{ID_START} \p{ID_CONTINUE}* ) }{$vars{$1}}msxeg;
		$vars{$name} = $value;
	}

	return \%vars;
}

sub _build_break_rules {
	my ($self, $vars, $what) = @_;

	my $name = "${what}_rules";
	my @bundles = $self->_find_bundle($name);

	my %rules;
	foreach my $bundle (reverse @bundles) {
		%rules = (%rules, %{$bundle->$name});
	}

	my @rules;
	foreach my $rule_number ( sort { $a <=> $b } keys %rules ) {
		# Test for deleted rules
		next unless defined $rules{$rule_number};

		$rules{$rule_number} =~ s{ ( \$ \p{ID_START} \p{ID_CONTINUE}* ) }{$vars->{$1}}msxeg;
		my ($first, $opp, $second) = split /(×|÷)/, $rules{$rule_number};

		foreach my $opperand ($first, $second) {
			if ($opperand =~ m{ \S }msx) {
				$opperand = parse($opperand);
			}
			else {
				$opperand = '.';
			}
		}

		push @rules, [qr{$first}msx, qr{$second}msx, ($opp eq '×' ? 1 : 0)];
	}

	push @rules, [ '.', '.', 0 ];

	return \@rules;
}

sub BUILDARGS {
	my $self = shift;
	my %args;

	# Used for arguments when we call new from our own code
	my %internal_args = ();
	if (@_ > 1 && ref $_[-1] eq 'HASH') {
		%internal_args = %{pop @_};
	}

	if (1 == @_ && ! ref $_[0]) {
		my ($language, $script, $territory, $variant, $extentions)
		 	= $_[0]=~/^
				([a-zA-Z]+)
				(?:[-_]([a-zA-Z]{4}))?
				(?:[-_]([a-zA-Z]{2,3}))?
				(?:[-_]([a-zA-Z0-9]+))?
				(?:[-_]u[_-](.+))?
			$/x;

		foreach ($language, $script, $territory, $variant) {
			$_ = '' unless defined $_;
		}
			
		%args = (
			language	=> $language,
			script		=> $script,
			territory	=> $territory,
			variant		=> $variant,
			extentions	=> $extentions,
		);
	}

	if (! %args ) {
		%args = ref $_[0]
			? %{$_[0]}
			: @_
	}

	# Split up the extentions
	if ( defined $args{extentions} && ! ref $args{extentions} ) {
		$args{extentions} = {
			map {lc}
			split /[_-]/, $args{extentions}
		};
	}

	# Fix casing of args
	$args{language}		= lc $args{language}		if defined $args{language};
	$args{script}		= ucfirst lc $args{script}	if defined $args{script};
	$args{territory}	= uc $args{territory}		if defined $args{territory};

	$self->SUPER::BUILDARGS(%args, %internal_args);
}

sub BUILD {
	my ($self, $args) = @_;

	# Check that the args are valid
	# also check for aliases
	$args->{language} = $self->language_aliases->{$args->{language}}
		// $args->{language};
	die "Invalid language" unless first { $args->{language} eq $_ } $self->valid_languages;

	die "Invalid script" if $args->{script} 
		&& ! first { ucfirst lc $args->{script} eq $_ } $self->valid_scripts;

	die "Invalid territory" if $args->{territory} 
		&&  ( !  ( first { uc $args->{territory} eq $_ } $self->valid_territories )
			&& ( ! $self->territory_aliases->{$self->{territory}} )
		);
    
	die "Invalid variant" if $args->{variant}
		&&  ( !  ( first { uc $args->{variant} eq $_ } $self->valid_variants )
			&& ( ! $self->variant_aliases->{lc $self->{variant}} )
	);

	if ($args->{extention}) {
		my %valid_keys = $self->valid_keys;
		foreach my $key ( keys %{$args->{extention}} ) {
			my %key_aliases = $self->key_aliases;
			$key = $key_aliases{$key} if exists $key_aliases{$key};
			die "Invalid extention name" unless exists $valid_keys{$key};
			die "Invalid extention value" unless 
				first { $_ eq $args->{extention}{$key} } @{$valid_keys{$key}};
		}
	}
		
	# Check for variant aliases
	if ($args->{variant} && (my $variant_alias = $self->variant_aliases->{lc $self->variant})) {
		delete $args->{variant};
		my ($what) = keys %{$variant_alias};
		my ($value) = values %{$variant_alias};
		$args->{$what} = $value;
	}

	# Create the new path
	my @path;
	my $path = join '::',
		map { ucfirst lc }
		map { $_ ? $_ : 'Any' } (
			$args->{language},
			$args->{script},
			$args->{territory},
			$args->{variant}
		);

	while ($path) {
		push @path, $path;
		$path=~s/(?:::)?[^:]+$//;
	}

	push @path, 'Root' 
		unless $path[-1] eq 'Root';

	# Now we go through the path loading each module
	# And calling new on it. With each module we call
	# fallback to expand the module with it's fallbacks
	my @modules;
	foreach my $module (@path) {
		$module = "Locale::CLDR::$module";
		eval "require $module";
		next if $@;
		my $locale_package = $module->new;
		push @modules, 
			$locale_package, 
			$self->_no_fallback 
				? ()
				: map {Locale::CLDR->new($_, {_no_fallback => 1})} $locale_package->fallback;
	}

	# If we only have the root module then we have a problem as
	# none of the language specific data is in the root. So we
	# fall back to the en module
	if (1 == @modules ) {
		require Locale::CLDR::En;
		push @modules, Locale::CLDR::En->new
	}

	$self->_set_modules(\@modules);
}

use overload 
  'bool'	=> sub { 1 },
  '""'		=> \&stringify;

sub stringify {
	my $self = shift;
	my $string = lc $self->language;

	if ($self->script) {
		$string.= '_' . ucfirst lc $self->script;
	}

	if ($self->territory) {
		$string.= '_' . uc $self->territory;
	}

	if ($self->variant) {
		$string.= '_' . uc $self->variant;
	}

	if (defined $self->extentions) {
		$string.= '_u';
		foreach my $key (sort keys %{$self->extentions}) {
			my $value = $self->extentions->{$key};
			$string .= "_${key}_$value";
		}
		chop $string;
	}

	return $string;
}

# Method to locate the resource bundle with the required data
sub _find_bundle {
	my ($self, $method_name) = @_;
	if ($self->method_cache->{$method_name}) {
		return wantarray
			? @{$self->method_cache->{$method_name}}
			: $self->method_cache->{$method_name}[0];
	}

	foreach my $module ($self->modules) {
		if ($module->can($method_name)) {
			push @{$self->method_cache->{$method_name}}, $module;
		}
	}

	return unless $self->method_cache->{$method_name};
	return wantarray
		? @{$self->method_cache->{$method_name}}
		: $self->method_cache->{$method_name}[0];
}

# Method to return the given local name in the current locals format
sub locale_name {
	my ($self, $name) = @_;
	$name //= $self;

	my $code = ref $name
		? join ('_', $name->language, $name->territory)
		: $name;
	
	my @bundles = $self->_find_bundle('display_name_language');

	foreach my $bundle (@bundles) {
		my $display_name = $bundle->display_name_language->{$code};
		return $display_name if defined $display_name;
	}

	# $name can be a string or a Locale::CLDR::*
	if (! ref $name) {
		$name = Locale::CLDR->new($name);
	}

	# Now we have to process each individual element
	# to pass to the display name pattern
	my $language = $self->language_name($name);
	my $script = $self->script_name($name);
	my $territory = $self->territory_name($name);
	my $variant = $self->variant_name($name);

	my $bundle = $self->_find_bundle('display_name_pattern');
	return $bundle
		->display_name_pattern($language, $territory, $script, $variant);
}

sub language_name {
	my ($self, $name) = @_;

	$name //= $self;

	my $code = ref $name
		? $name->language
		: eval { Locale::CLDR->new(language => $name)->language };

	my $language = undef;
	my @bundles = $self->_find_bundle('display_name_language');
	if ($code) {
		foreach my $bundle (@bundles) {
			my $display_name = $bundle->display_name_language->{$code};
			if (defined $display_name) {
				$language = $display_name;
				last;
			}
		}
	}
	# If we don't have a display name for the language we try again
	# with the und tag
	if (! defined $language ) {
		foreach my $bundle (@bundles) {
			my $display_name = $bundle->display_name_language->{'und'};
			if (defined $display_name) {
				$language = $display_name;
				last;
			}
		}
	}

	return $language;
}

sub script_name {
	my ($self, $name) = @_;
	$name //= $self;

	if (! ref $name ) {
		$name = eval {__PACKAGE__->new(language => 'und', script => $name)};
	}

	if ( ref $name && ! $name->script ) {
		return '';
	}

	my $script = undef;
	my @bundles = $self->_find_bundle('display_name_script');
	if ($name) {
		foreach my $bundle (@bundles) {
			$script = $bundle->display_name_script->{$name->script};
			if (defined $script) {
				last;
			}
		}
	}

	if (! $script) {
		foreach my $bundle (@bundles) {
			$script = $bundle->display_name_script->{'Zzzz'};
			if (defined $script) {
				last;
			}
		}
	}

	return $script;
}

sub territory_name {
	my ($self, $name) = @_;
	$name //= $self;

	if (! ref $name ) {
		$name = eval { __PACKAGE__->new(language => 'und', territory => $name); };
	}

	if ( ref $name && ! $name->territory) {
		return '';
	}

	my $territory = undef;
	my @bundles = $self->_find_bundle('display_name_territory');
	if ($name) {
		foreach my $bundle (@bundles) {
			$territory = $bundle->display_name_territory->{$name->territory};
			if (defined $territory) {
				last;
			}
		}
	}

	if (! defined $territory) {
		foreach my $bundle (@bundles) {
			$territory = $bundle->display_name_territory->{'ZZ'};
			if (defined $territory) {
				last;
			}
		}
	}

	return $territory;
}

sub variant_name {
	my ($self, $name) = @_;
	$name //= $self;

	if (! ref $name ) {
		$name = __PACKAGE__->new(language=> 'und', variant => $name);
	}

	return '' unless $name->variant;
	my $variant = undef;
	if ($name->has_variant) {
		my @bundles = $self->_find_bundle('display_name_variant');
		foreach my $bundle (@bundles) {
			$variant= $bundle->display_name_variant->{$name->variant};
			if (defined $variant) {
				last;
			}
		}
	}

	return $variant // '';
}

sub key_name {
	my ($self, $name) = @_;

	$name = lc $name;
	my %key_aliases = $self->key_aliases;
	my %key_names	= $self->key_names;
	my %valid_keys	= $self->valid_keys;

	$name = $key_aliases{$name} if exists $key_aliases{$name};

	return '' unless exists $valid_keys{$name};
	my @bundles = $self->_find_bundle('display_name_key');
	foreach my $bundle (@bundles) {
		my $key = $bundle->display_name_key->{$name};
		return $key if length $key;
	}

	return ucfirst ($key_names{$name} || $name);
}

sub type_name {
	my ($self, $key, $type) = @_;

	$key	= lc $key;
	$type	= lc $type;

	my %key_aliases = $self->key_aliases;
	my %valid_keys	= $self->valid_keys;
	my %key_names	= $self->key_names;

	$key = $key_aliases{$key} if exists $key_aliases{$key};

	return '' unless exists $valid_keys{$key};
	return '' unless first { $_ eq $type } @{$valid_keys{$key}};

	my @bundles = $self->_find_bundle('display_name_type');
	foreach my $bundle (@bundles) {
		my $type = $bundle->display_name_type->{$key_names{$key}}{$type};
		return $type if defined $type;
	}

	return '';
}
	
sub measurement_system_name {
	my ($self, $name) = @_;

	# Fix case of code
	$name = uc $name;
	$name = 'metric' if $name eq 'METRIC';

	# Check valid values
	return '' unless $name=~m{ \A (?: US | metric ) \z }xms;

	my @bundles = $self->_find_bundle('display_name_measurement_system');
	foreach my $bundle (@bundles) {
		my $system = $bundle->display_name_measurement_system->{$name};
		return $system if defined $system;
	}

	return '';
}

sub code_pattern {
	my ($self, $type, $locale) = @_;
	$type = lc $type;

	# If locale isnot passed in then we are using ourself
	$locale //= $self;

	# If locale is not an object then inflate it
	$locale = __PACKAGE__->new($locale) unless blessed $locale;

	return '' unless $type =~ m{ \A (?: language | script | territory ) \z }xms;

	my $method = $type . '_name';
	my $substute = $locale->$method;

	my @bundles = $self->_find_bundle('display_name_code_patterns');
	foreach my $bundle (@bundles) {
		my $text = $bundle->display_name_code_patterns->{$type};
		next unless defined $text;
		my $match = qr{ \{ 0 \} }xms;
		$text=~ s{ $match }{$substute}gxms;
		return $text;
	}

	return '';
}

sub text_orientation {
	my $self = shift;
	my $type = shift;

	my @bundles = $self->_find_bundle('text_orientation');
	foreach my $bundle (@bundles) {
		my $orientation = $bundle->text_orientation;
		next unless defined $orientation;
		return $orientation->{$type};
	}

	return;
}

# Correctly case $list_entry
sub in_list {
	my ($self, $list_entry) = @_; 

	my @bundles = $self->_find_bundle('in_list');
	foreach my $bundle (@bundles) {
		my $casing = $bundle->in_list;
		next unless defined $casing;
		return $self->_set_casing($casing, $list_entry);
	}

	return $list_entry;
}

sub _set_casing {
	my ($self, $casing, $string) = @_;

	my @words = $self->split_words($string);

	if ($casing eq 'titlecase-firstword') {
		# Check to see wether $words[0] is whitspace or not
		my $firstword_location = 0;
 		if ($words[0] =~ m{ \A \s }msx) {
			$firstword_location = 1;
		}

		$words[$firstword_location] = ucfirst $words[$firstword_location];
	}
	elsif($casing eq 'titlecase-words') {
		@words = map{ ucfirst } @words;
	}

	return join '', @words;
}

# Split a string at various points
sub split_words {
	my ($self, $string) = @_;

	my $rules = $self->break_word;
	my @words = $self->_split($rules, $string);

	return @words;
}

sub _split {
	my ($self, $rules, $string) = @_;

	my @split = ();

	$string =~ s{ \A ( \X ) }{}msx;

	my $first = $1;
	my $capture = $first;

	while ( $string =~ s{ \A ( \X ) }{}msx ) {
		my $second = $1;

		foreach my $rule (@$rules) {
			next unless $first =~ $rule->[0] && $second =~ $rule->[1];
			if ($rule->[2]) {
				# Can't split here
				$capture .= $second;
			}
			else {
				push @split, $capture;
				$capture = $second;
			}

			$first = $second;
			last;
		}
	}
	# End of rules
	push @split, $capture;

	# Naïve splitting for now
#	@split = split /\b/, $string;
	return @split;
}

=head1 AUTHOR

John Imrie, C<< <j dot imrie at virginemail.com> >>

=head1 BUGS

Please report any bugs or feture requests to me at the above email adddress 
and ignore the CPAN stuff below for the present

Please report any bugs or feature requests to C<bug-locale-cldr at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Locale-CLDR>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Locale::CLDR


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Locale-CLDR>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Locale-CLDR>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Locale-CLDR>

=item * Search CPAN

L<http://search.cpan.org/dist/Locale-CLDR/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 John Imrie.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Locale::CLDR
