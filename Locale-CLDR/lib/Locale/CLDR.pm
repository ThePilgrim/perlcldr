package Locale::CLDR v2.0.2;
use v5.18;
use open ':encoding(utf8)';
use utf8;
use Moose;
use MooseX::ClassAttribute;
with 'Locale::CLDR::ValidCodes', 'Locale::CLDR::EraBoundries', 'Locale::CLDR::WeekData', 
	'Locale::CLDR::MeasurementSystem', 'Locale::CLDR::LikelySubtags', 'Locale::CLDR::NumberingSystems',
	'Locale::CLDR::NumberFormatter', 'Locale::CLDR::TerritoryContainment', 'Locale::CLDR::CalendarPreferences';
	
use Class::Load;

use namespace::autoclean;

=head1 NAME

Locale::CLDR - Main Class for CLDR Locals

=head1 VERSION

Version 1.8.0 To match the CLDR Version

=cut

use List::Util qw(first);
use Class::MOP;
use DateTime::Locale;
use Unicode::Normalize();

=head1 SYNOPSIS

This module handles Local Data from the CLDR

=head1 Attributes

=cut

has 'language_id' => (
	is			=> 'ro',
	isa			=> 'Str',
	required	=> 1,
);

# language aliases
around 'language_id' => sub {
	my ($orig, $self) = @_;
	my $value = $self->$orig;
	return $self->language_aliases->{$value} // $value;
};

has 'script_id' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_script',
);

has 'territory_id' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_territory',
);

# territory aliases
around 'territory_id' => sub {
	my ($orig, $self) = @_;
	my $value = $self->$orig;
	return $value if defined $value;
	my $alias = $self->territory_aliases->{$value};
	return (split /\s+/, $alias)[0];
};

has 'variant_id' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_variant',
);

has 'extentions' => (
	is			=> 'ro',
	isa			=> 'Undef|HashRef',
	default		=> undef,
	writer		=> '_set_extentions',
);

has 'likely_language' => (
	is			=> 'ro',
	isa			=> 'Str',
	init_arg	=> undef,
	lazy		=> 1,
	builder		=> '_build_likely_language',
);

sub _build_likely_language {
	my $self = shift;
	
	my $language = $self->language();
	
	return $language unless $language eq 'und';
	
	return $self->likely_subtag->language;
}

has 'likely_script' => (
	is			=> 'ro',
	isa			=> 'Str',
	init_arg	=> undef,
	lazy		=> 1,
	builder		=> '_build_likely_script',
);

sub _build_likely_script {
	my $self = shift;
	
	my $script = $self->script();
	
	return $script if $script;
	
	return $self->likely_subtag->script || '';
}

has 'likely_territory' => (
	is			=> 'ro',
	isa			=> 'Str',
	init_arg	=> undef,
	lazy		=> 1,
	builder		=> '_build_likely_territory',
);

sub _build_likely_territory {
	my $self = shift;
	
	my $territory = $self->territory();
	
	return $territory if $territory;
	
	return $self->likely_subtag->territory || '';
}

has 'module' => (
	is			=> 'ro',
	isa			=> 'Object',
	init_arg	=> undef,
	lazy		=> 1,
	builder		=> '_build_module',
);

sub _build_module {
	# Create the new path
	my $self = shift;
	
	my @path = map { ucfirst lc }
		map { $_ ? $_ : 'Any' } (
			$self->language_id,
			$self->script_id,
			$self->territory_id,
		);

	my @likely_path = 
		map { ucfirst lc } (
			$self->has_likely_subtag ? $self->likely_subtag->language_id : 'Any',
			$self->has_likely_subtag ? $self->likely_subtag->script_id : 'Any',
			$self->has_likely_subtag ? $self->likely_subtag->territory_id : 'Any',
		);
	
	for (my $i = 0; $i < @path; $i++) {
		$likely_path[$i] = $path[$i] unless $path[$i] eq 'und' or $path[$i] eq 'Any';
	}
	
	# Note the order we push these onto the stack is important
	@path = join '::', @likely_path;
	push @path, join '::', $likely_path[0], 'Any', $likely_path[2];
	push @path, join '::', @likely_path[0 .. 1], 'Any';
	push @path, join '::', $likely_path[0], 'Any', 'Any';
	
	# Now we go through the path loading each module
	# And calling new on it. 
	my $module;
	foreach my $module_name (@path) {
		$module_name = "Locale::CLDR::$module_name";
		eval { Class::Load::load_class($module_name); };
		next if $@;
		$module = $module_name->new;
		last;
	}

	# If we only have the root module then we have a problem as
	# none of the language specific data is in the root. So we
	# fall back to the en module
	if (! $module || ref $module eq 'Locale::CLDR::Root') {
		Class::Load::load_class('Locale::CLDR::En');
		$module = Locale::CLDR::En->new
	}

	return $module;
}

class_has 'method_cache' => (
	is			=> 'rw',
	isa			=> 'HashRef[HashRef[ArrayRef[Object]]]',
	init_arg	=> undef,
	default		=> sub { return {}},
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

foreach my $property (qw( name language script territory variant)) {
	has $property => (
		is => 'ro',
		isa => 'Str',
		init_arg => undef,
		lazy => 1,
		builder => "_build_$property",
	);

	no strict 'refs';
	*{"native_$property"} = sub {
		my ($self, $for) = @_;
		
		$for //= $self;
		my $build = "_build_native_$property";
		return $self->$build($for);
	};
}

#DateTime::Local
foreach my $property (qw( 
	month_format_wide month_format_abbreviated month_format_narrow
	month_stand_alone_wide month_stand_alone_abbreviated month_stand_alone_narrow
	day_format_wide day_format_abbreviated day_format_narrow
	day_stand_alone_wide day_stand_alone_abreviated day_stand_alone_narrow
	quater_format_wide quater_format_abbreviated quater_format_narrow
	quater_stand_alone_wide quater_stand_alone_abreviated quater_stand_alone_narrow
	am_pm_wide am_pm_abbreviated am_pm_narrow
	era_wide era_abbreviated era_narrow
)) {
	has $property => (
		is => 'ro',
		isa => 'ArrayRef',
		init_arg => undef,
		lazy => 1,
		builder => "_build_$property",
		clearer => "_clear_$property",
	);
}
	
foreach my $property (qw(
	id
	date_format_full date_formart_long 
	date_format_medium date_format_short date_format_default
	time_format_full time_formart_long
	time_format_medium time_format_short timeformat_default
	datetime_format_full datetime_formart_long
	datetime_format_medium datetime_format_short datetimeformat_default
)) {
	has $property => (
		is => 'ro',
		isa => 'Str',
		init_arg => undef,
		lazy => 1,
		builder => "_build_$property",
		clearer => "_clear_$property",
	);
}

has '_available_formats' => (
	traits => ['Array'],
	is => 'ro',
	isa => 'ArrayRef',
	init_arg => undef,
	lazy => 1,
	builder => "_build_available_formats",
	clearer => "_clear_available_formats",
	handles => {
		available_formats => 'elements',
	},
);

has 'format_data' => (
	is => 'ro',
	isa => 'HashRef',
	init_arg => undef,
	lazy => 1,
	builder => "_build_format_data",
	clearer => "_clear_format_data",
);

# default_calendar
foreach my $property (qw(
	default_date_format_length default_time_format_length
)) {
	has $property => (
		is => 'ro',
		isa => 'Str',
		init_arg => undef,
		lazy => 1,
		builder => "_build_$property",
		writer => "set_$property" 
	);
}

has 'prefers_24_hour_time' => (
	is => 'ro',
	isa => 'Bool',
	init_arg => undef,
	lazy => 1,
	builder => "_build_prefers_24_hour_time",
);

has 'first_day_of_week' => (
	is => 'ro',
	isa => 'Bool',
	init_arg => undef,
	lazy => 1,
	builder => "_build_first_day_of_week",
);

has 'likely_subtag' => (
	is => 'ro',
	isa => __PACKAGE__,
	init_arg => undef,
	writer => '_set_likely_subtag',
	predicate => 'has_likely_subtag',
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

		foreach my $operand ($first, $second) {
			if ($operand =~ m{ \S }msx) {
				$operand = unicode_to_perl($operand);
			}
			else {
				$operand = '.';
			}
		}
		
		no warnings 'deprecated';
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
			language_id	=> $language,
			script_id		=> $script,
			territory_id	=> $territory,
			variant_id		=> $variant,
			extentions	=> $extentions,
		);
	}

	if (! keys %args ) {
		%args = ref $_[0]
			? %{$_[0]}
			: @_
	}

	# Split up the extensions
	if ( defined $args{extentions} && ! ref $args{extentions} ) {
		$args{extentions} = {
			map {lc}
			split /[_-]/, $args{extentions}
		};
	}

	# Fix casing of args
	$args{language_id}		= lc $args{language_id}		if defined $args{language_id};
	$args{script_id}		= ucfirst lc $args{script_id}	if defined $args{script_id};
	$args{territory_id}	= uc $args{territory_id}		if defined $args{territory_id};
	$args{variant_id}	= uc $args{variant_id}		if defined $args{variant_id};
	
	# Set up undefined language
	$args{language_id} //= 'und';

	$self->SUPER::BUILDARGS(%args, %internal_args);
}

sub BUILD {
	my ($self, $args) = @_;

	# Check that the args are valid
	# also check for aliases
	$args->{language_id} = $self->language_aliases->{$args->{language_id}}
		// $args->{language_id};
		
	die "Invalid language" if $args->{language_id}
		&& ! first { $args->{language_id} eq $_ } $self->valid_languages;

	die "Invalid script" if $args->{script_id} 
		&& ! first { ucfirst lc $args->{script_id} eq $_ } $self->valid_scripts;

	die "Invalid territory" if $args->{territory_id} 
		&&  ( !  ( first { uc $args->{territory_id} eq $_ } $self->valid_territories )
			&& ( ! $self->territory_aliases->{$self->{territory_id}} )
		);
    
	die "Invalid variant" if $args->{variant_id}
		&&  ( !  ( first { uc $args->{variant_id} eq $_ } $self->valid_variants )
			&& ( ! $self->variant_aliases->{lc $self->{variant_id}} )
	);
	
	if ($args->{extentions}) {
		my %valid_keys = $self->valid_keys;
		my %key_aliases = $self->key_aliases;
		my @keys = keys %{$args->{extentions}};

		foreach my $key ( @keys ) {
			my $canonical_key = $key_aliases{$key} if exists $key_aliases{$key};
			$canonical_key //= $key;
			if ($canonical_key ne $key) {
				$args->{extentions}{$canonical_key} = delete $args->{extentions}{$key};
			}

			$key = $canonical_key;
			die "Invalid extention name" unless exists $valid_keys{$key};
			die "Invalid extention value" unless 
				first { $_ eq $args->{extentions}{$key} } @{$valid_keys{$key}};

			$self->_set_extentions($args->{extentions})
		}
	}

	# Check for variant aliases
	if ($args->{variant_id} && (my $variant_alias = $self->variant_aliases->{lc $self->variant_id})) {
		delete $args->{variant_id};
		my ($what) = keys %{$variant_alias};
		my ($value) = values %{$variant_alias};
		$args->{$what} = $value;
	}
}

after 'BUILD' => sub {

	my $self = shift;
	
	# Fix up likely sub tags
	
	my $likely_subtags = $self->likely_subtags;
	my $likely_subtag;
	my ($language_id, $script_id, $territory_id) = ($self->language_id, $self->script_id, $self->territory_id);
	
	unless ($language_id ne 'und' && $script_id && $territory_id ) {
		$likely_subtag = $likely_subtags->{join '_', $language_id, $script_id, $territory_id};
		
		if (! $likely_subtag ) {
			$likely_subtag = $likely_subtags->{join '_', $language_id, $territory_id};
		}
	
		if (! $likely_subtag ) {
			$likely_subtag = $likely_subtags->{join '_', $language_id, $script_id};
		}
	
		if (! $likely_subtag ) { 
			$likely_subtag = $likely_subtags->{$language_id};
		}
	
		if (! $likely_subtag ) {
			$likely_subtag = $likely_subtags->{join '_', 'und', $script_id};
		}
	}
		
	if ($likely_subtag) {
		$self->_set_likely_subtag(__PACKAGE__->new($likely_subtag));
	}
	
	# Register with DateTime::Locale
	DateTime::Locale->register(
		id 	    => $self->id,
		en_language => $self->language,
		class   => __PACKAGE__,
		replace => 1,
	);
};

use overload 
  'bool'	=> sub { 1 },
  '""'		=> sub {shift->id};

sub _build_id {
	my $self = shift;
	my $string = lc $self->language_id;

	if ($self->script_id) {
		$string.= '_' . ucfirst lc $self->script_id;
	}

	if ($self->territory_id) {
		$string.= '_' . uc $self->territory_id;
	}

	if ($self->variant_id) {
		$string.= '_' . uc $self->variant_id;
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

sub _get_english {
	my $self = shift;
	my $english;
	if ($self->language_id eq 'en') {
		$english = $self;
	}
	else {
		$english = Locale::CLDR->new('en_Latn_US');
	}

	return $english;
}

sub _build_name {
	my $self = shift;

	return $self->_get_english->native_name($self);
}

sub _build_native_name {
	my ($self, $for) = @_;

	return $self->locale_name($for);
}

sub _build_language {
	my $self = shift;

	return $self->_get_english->native_language($self);
}

sub _build_native_language {
	my ($self, $for) = @_;

	return $self->language_name($for) // '';
}

sub _build_script {
	my $self = shift;

	return $self->_get_english->native_script($self);
}

sub _build_native_script {
	my ($self, $for) = @_;

	return $self->script_name($for);
}

sub _build_territory {
	my $self = shift;

	return $self->_get_english->native_territory($self);
}

sub _build_native_territory {
	my ($self, $for) = @_;

	return $self->territory_name($for);
}

sub _build_variant {
	my $self = shift;

	return $self->_get_english->native_variant($self);
}

sub _build_native_variant {
	my ($self, $for) = @_;

	return $self->variant_name($for);
}

# Method to locate the resource bundle with the required data
sub _find_bundle {
	my ($self, $method_name) = @_;
	my $id = $self->has_likely_subtag()
		? $self->likely_subtag()->id()
		: $self->id(); 
	if ($self->method_cache->{$id}{$method_name}) {
		return wantarray
			? @{$self->method_cache->{$id}{$method_name}}
			: $self->method_cache->{$id}{$method_name}[0];
	}

	foreach my $module ($self->module->meta->linearized_isa) {
		last if $module eq 'Moose::Object';
		if ($module->meta->has_method($method_name)) {
			push @{$self->method_cache->{$id}{$method_name}}, $module->new;
		}
	}

	return unless $self->method_cache->{$id}{$method_name};
	return wantarray
		? @{$self->method_cache->{$id}{$method_name}}
		: $self->method_cache->{$id}{$method_name}[0];
}

# Method to return the given locale name in the current locales format
sub locale_name {
	my ($self, $name) = @_;
	$name //= $self;

	my $code = ref $name
		? join ('_', $name->language_id, $name->territory_id)
		: $name;
	
	my @bundles = $self->_find_bundle('display_name_language');

	foreach my $bundle (@bundles) {
		my $display_name = $bundle->display_name_language->($code);
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

	my $code = ref $name ? $name->language_id : eval { Locale::CLDR->new(language_id => $name)->language_id };

	my $language = undef;
	my @bundles = $self->_find_bundle('display_name_language');
	if ($code) {
		foreach my $bundle (@bundles) {
			my $display_name = $bundle->display_name_language->($code);
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
			my $display_name = $bundle->display_name_language->('und');
			if (defined $display_name) {
				$language = $display_name;
				last;
			}
		}
	}

	return $language;
}

sub all_languages {
	my $self = shift;

	my @bundles = $self->_find_bundle('display_name_language');
	my %languages;
	foreach my $bundle (@bundles) {
		my $languages = $bundle->display_name_language;

		# Remove existing languages
		delete @{$languages}{keys %languages};

		# Assign new ones to the hash
		@languages{keys %$languages} = values %$languages;
	}

	return \%languages;
}

sub script_name {
	my ($self, $name) = @_;
	$name //= $self;

	if (! ref $name ) {
#		$name = eval {__PACKAGE__->new(language_id => 'und', script_id => $name)};
		$name = eval {__PACKAGE__->new(script_id => $name)};
	}

	if ( ref $name && ! $name->script_id ) {
		return '';
	}

	my $script = undef;
	my @bundles = $self->_find_bundle('display_name_script');
	if ($name) {
		foreach my $bundle (@bundles) {
			$script = $bundle->display_name_script->($name->script_id);
			if (defined $script) {
				last;
			}
		}
	}

	if (! $script) {
		foreach my $bundle (@bundles) {
			$script = $bundle->display_name_script->('Zzzz');
			if (defined $script) {
				last;
			}
		}
	}

	return $script;
}

sub all_scripts {
	my $self = shift;

	my @bundles = $self->_find_bundle('display_name_script');
	my %scripts;
	foreach my $bundle (@bundles) {
		my $scripts = $bundle->display_name_script;

		# Remove existing scripts
		delete @{$scripts}{keys %scripts};

		# Assign new ones to the hash
		@scripts{keys %$scripts} = values %$scripts;
	}

	return \%scripts;
}

sub territory_name {
	my ($self, $name) = @_;
	$name //= $self;

	if (! ref $name ) {
		$name = eval { __PACKAGE__->new(language_id => 'und', territory_id => $name); };
	}

	if ( ref $name && ! $name->territory_id) {
		return '';
	}

	my $territory = undef;
	my @bundles = $self->_find_bundle('display_name_territory');
	if ($name) {
		foreach my $bundle (@bundles) {
			$territory = $bundle->display_name_territory->{$name->territory_id};
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

sub all_territories {
	my $self = shift;

	my @bundles = $self->_find_bundle('display_name_territory');
	my %territories;
	foreach my $bundle (@bundles) {
		my $territories = $bundle->display_name_territory;

		# Remove existing territories
		delete @{$territories}{keys %territories};

		# Assign new ones to the hash
		@territories{keys %$territories} = values %$territories;
	}

	return \%territories;
}

sub variant_name {
	my ($self, $name) = @_;
	$name //= $self;

	if (! ref $name ) {
		$name = __PACKAGE__->new(language_id=> 'und', variant_id => $name);
	}

	return '' unless $name->variant_id;
	my $variant = undef;
	if ($name->has_variant) {
		my @bundles = $self->_find_bundle('display_name_variant');
		foreach my $bundle (@bundles) {
			$variant= $bundle->display_name_variant->{$name->variant_id};
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

sub transform_name {
	my ($self, $name) = @_;

	$name = lc $name;

	my @bundles = $self->_find_bundle('display_name_transform_name');
	foreach my $bundle (@bundles) {
		my $key = $bundle->display_name_transform_name->{$name};
		return $key if length $key;
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
	my $substute = $self->$method($locale);

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

sub _set_casing {
	my ($self, $casing, $string) = @_;

	my @words = $self->split_words($string);

	if ($casing eq 'titlecase-firstword') {
		# Check to see whether $words[0] is white space or not
		my $firstword_location = 0;
 		if ($words[0] =~ m{ \A \s }msx) {
			$firstword_location = 1;
		}

		$words[$firstword_location] = ucfirst $words[$firstword_location];
	}
	elsif ($casing eq 'titlecase-words') {
		@words = map{ ucfirst } @words;
	}
	elsif ($casing eq 'lowercase-words') {
		@words = map{ lc } @words;
	}

	return join '', @words;
}

# Split a string at various points
sub split_grapheme_clusters {
	my ($self, $string) = @_;

	my $rules = $self->break_grapheme_cluster;
	my @clusters = $self->_split($rules, $string, 1);

	return @clusters;
}

sub split_words {
	my ($self, $string) = @_;

	my $rules = $self->break_word;
	my @words = $self->_split($rules, $string);

	return @words;
}

sub split_sentences {
	my ($self, $string) = @_;

	my $rules = $self->break_sentence;
	my @sentences = $self->_split($rules, $string);

	return @sentences;
}

sub split_lines {
	my ($self, $string) = @_;

	my $rules = $self->break_line;
	my @lines = $self->_split($rules, $string);

	return @lines;
}

sub _split {
	my ($self, $rules, $string, $grapheme_split) = @_;

	my @split = (scalar @$rules) x (length($string) - 1);

	pos($string)=0;
	# The Unicode Consortium has deprecated LB=Surrogate but the CLDR still
	# uses it, at last in this version.
	no warnings 'deprecated';
	while (length($string) -1 != pos $string) {
		my $rule_number = 0;
		foreach my $rule (@$rules) {
			unless( $string =~ m{
				\G
				(?<first> $rule->[0] )
				(?<second> $rule->[1] )
			}msx) {
				$rule_number++;
				next;
			}
			my $location = pos($string) + length($+{first}) -1;
			$split[$location] = $rule_number;
			
			# If the left hand side was part of a grapheme cluster 
			# we have to jump past the entire cluster
			my $length = length $+{first};
			my ($gc) = $string =~ /\G(\X)/;
			$length = (! $grapheme_split && length($gc)) > $length ? length($gc) : $length;
			pos($string)+= $length;
			last;
		}
	}

	push @$rules,[undef,undef,1];
	@split = map {$rules->[$_][2] ? 1 : 0} @split;
	my $count = 0;
	my @sections = ('.');
	foreach my $split (@split) {
		$count++ unless $split;
		$sections[$count] .= '.';
	}
	
	my $regex = '(' . join(')(', @sections) . ')';
	$regex = qr{ \A $regex \z}msx;
	@split = $string =~ $regex;

	return @split;
}

#Exemplar characters
sub is_exemplar_character {
	my ($self, @parameters) = @_;
	unshift @parameters, 'main' if @parameters == 1;

	my @bundles = $self->_find_bundle('characters');
	foreach my $bundle (@bundles) {
		my $characters = $bundle->characters->{$parameters[0]};
		next unless defined $characters;
		return 1 if fc($parameters[1])=~$characters;
	}

	return;
}

sub index_characters {
	my $self = shift;

	my @bundles = $self->_find_bundle('characters');
	foreach my $bundle (@bundles) {
		my $characters = $bundle->characters->{index};
		next unless defined $characters;
		return $characters;
	}
	return [];
}

sub _truncated {
	my ($self, $type, @params) = @_;

	my @bundles = $self->_find_bundle('ellipsis');
	foreach my $bundle (@bundles) {
		my $ellipsis = $bundle->ellipsis->{$type};
		next unless defined $ellipsis;
		$ellipsis=~s{ \{ 0 \} }{$params[0]}msx;
		$ellipsis=~s{ \{ 1 \} }{$params[1]}msx;
		return $ellipsis;
	}
}

sub truncated_beginning {
	shift->_truncated(initial => @_);
}

sub truncated_between {
	shift->_truncated(medial => @_);
}

sub truncated_end {
	shift->_truncated(final => @_);
}

sub truncated_word_beginning {
	shift->_truncated('word-initial' => @_);
}

sub truncated_word_between {
	shift->_truncated('word-medial' => @_);
}

sub truncated_word_end {
	shift->_truncated('word-final' => @_);
}


sub more_information {
	my $self = shift;

	my @bundles = $self->_find_bundle('more_information');
	foreach my $bundle (@bundles) {
		my $info = $bundle->more_information;
		next unless defined $info;
		return $info;
	}
	return '';
}

sub quote {
	my ($self, $text) = @_;

	my %quote;
	my @bundles = $self->_find_bundle('quote_start');
	foreach my $bundle (@bundles) {
		my $quote = $bundle->quote_start;
		next unless defined $quote;
		$quote{start} = $quote;
		last;
	}

	@bundles = $self->_find_bundle('quote_end');
	foreach my $bundle (@bundles) {
		my $quote = $bundle->quote_end;
		next unless defined $quote;
		$quote{end} = $quote;
		last;
	}

	@bundles = $self->_find_bundle('alternate_quote_start');
	foreach my $bundle (@bundles) {
		my $quote = $bundle->alternate_quote_start;
		next unless defined $quote;
		$quote{alternate_start} = $quote;
		last;
	}

	@bundles = $self->_find_bundle('alternate_quote_end');
	foreach my $bundle (@bundles) {
		my $quote = $bundle->alternate_quote_end;
		next unless defined $quote;
		$quote{alternate_end} = $quote;
		last;
	}

	# Check to see if we need to switch quotes
	foreach (qw( start end alternate_start alternate_end)) {
		$quote{$_} //= '';
	}

	my $from = join ' | ', map {quotemeta} @quote{qw( start end alternate_start alternate_end)};
	my %to;
	@to{@quote{qw( start end alternate_start alternate_end)}}
		= @quote{qw( alternate_start alternate_end start end)};

	my $outer = index($text, $quote{start});
	my $inner = index($text, $quote{alternate_start});

	if ($inner == -1 || ($outer > -1 && $inner > -1 && $outer < $inner)) {
		$text =~ s{ ( $from ) }{ $to{$1} }msxeg;
	}

	return "$quote{start}$text$quote{end}";
}

# Measurement data
sub measurement {
	my $self = shift;
	
	my $measurement_data = $self->measurement_system;
	my $territory = $self->territory_id // '001';
	
	return $measurement_data->{$territory} // $measurement_data->{'001'};
}

sub paper {
	my $self = shift;
	
	my $paper_size = $self->paper_size;
	my $territory = $self->territory_id // '001';
	
	return $paper_size->{$territory} // $paper_size->{'001'};
}

# Units
sub all_units {
	my $self = shift;
	my @bundles = $self->_find_bundle('units');
	
	my %units;
	foreach my $bundle (reverse @bundles) {
		%units = %units, $bundle->units;
	}
	
	return keys %units;
}

sub unit {
	my ($self, $number, $what, $type) = @_;
	$type //= 'long';
	
	my $plural = $self->plural($number);
	
	my @bundles = $self->_find_bundle('units');
	my $format;
	foreach my $bundle (@bundles) {
		if (exists $bundle->units()->{$type}{$what}{$plural}) {
			$format = $bundle->units()->{$type}{$what}{$plural};
			last;
		}
			
		if (exists $bundle->units()->{$type}{$what}{other}) {
			$format = $bundle->units()->{$type}{$what}{other};
			last;
		}
	}
	
	# Check for aliases
	unless ($format) {
		my $original_type = $type;
		my @aliases = $self->_find_bundle('unit_alias');
		foreach my $alias (@aliases) {
			$type = $alias->unit_alias()->{$original_type};
			next unless $type;
			foreach my $bundle (@bundles) {
				if (exists $bundle->units()->{$type}{$what}{$plural}) {
					$format = $bundle->units()->{$type}{$what}{$plural};
					last;
				}
			
				if (exists $bundle->units()->{$type}{$what}{other}) {
					$format = $bundle->units()->{$type}{$what}{other};
					last;
				}
			}
		}
		$type = $original_type;
	}
	
	# Check for a compound unit that we don't specifically have
	if (! $format && (my ($dividend, $divisor) = $what =~ /^(.+)-per-(.+)$/)) {
		return $self->unit_compound($number, $dividend, $divisor, $type);
	}
	
	$number = $self->format_number($number);
	return $number unless $format;
	
	return $format =~ s/\{0\}/$number/gr;
}

sub unit_compound {
	my ($self, $number, $dividend_what, $divisor_what, $type) = @_;
	
	$type //= 'long';
	
	my $dividend = $self->unit($number, $dividend_what, $type);
	my $divisor = $self->unit(1, $divisor_what, $type);
	
	my $one = $self->format_number(1);
	$divisor =~ s/\s*$one\s*//;

	my @bundles = $self->_find_bundle('units');
	my $format;
	foreach my $bundle (@bundles) {
		if (exists $bundle->units()->{$type}{per}{other}) {
			$format = $bundle->units()->{$type}{per}{other};
			last;
		}
	}

	# Check for aliases
	unless ($format) {
		my $original_type = $type;
		my @aliases = $self->_find_bundle('unit_alias');
		foreach my $alias (@aliases) {
			$type = $alias->unit_alias()->{$original_type};
			foreach my $bundle (@bundles) {
				if (exists $bundle->units()->{$type}{per}{other}) {
					$format = $bundle->units()->{$type}{per}{other};
					last;
				}
			}
		}
	}
	
	$format =~ s/\{0\}/$dividend/g;
	return $format =~ s/\{1\}/$divisor/gr;
}

sub duration_unit {
	# data in hh,mm; hh,mm,ss or mm,ss 
	my ($self, $format, @data) = @_;
	
	my $bundle = $self->_find_bundle('duration_units');
	my $parsed = $bundle->duration_units()->{$format};
	
	my $num_format = '#';
	foreach my $entry ( qr/(hh?)/, qr/(mm?)/, qr/(ss?)/) {
		$num_format = '00' if $parsed =~ s/$entry/$self->format_number(shift(@data), $num_format)/e;
	}
	
	return $parsed;
}

sub is_yes {
	my ($self, $test_str) = @_;
	
	my $bundle = $self->_find_bundle('yesstr');
	return $test_str =~ $bundle->yesstr ? 1 : 0;
}

sub is_no {
	my ($self, $test_str) = @_;
	
	my $bundle = $self->_find_bundle('nostr');
	return $test_str =~ $bundle->nostr ? 1 : 0;
}

# Transformations 
sub transform {
	my ($self, %params) = @_;
	
	my $from 	= $params{from} // $self;
	my $to 		= $params{to}; 
	my $variant	= $params{variant} // 'Any';
	my $text	= $params{text} // '';
	
	($from, $to) = map {ref $_ ? $_->likely_script() : $_} ($from, $to);
	$_ = ucfirst(lc $_) foreach ($from, $to, $variant);
	
	my $package = __PACKAGE__ . "::Transformations::${variant}::${from}::${to}";
	eval { Class::Load::load_class($package); };
	warn $@ if $@;
	return $text if $@; # Can't load transform module so return original text
	use feature 'state';
	state $transforms;
	$transforms->{$variant}{$from}{$to} //= $package->new();
	my $rules = $transforms->{$variant}{$from}{$to}->transforms();
	
	# First get the filter rule
	my $filter = $rules->[0];
		
	# Break up the input on the filter
	my @text;
	pos($text) = 0;
	while (pos($text) < length($text)) {
		my $characters = '';
		while (my ($char) = $text =~ /($filter)/) {
			$characters .= $char;
			pos($text) = pos($text) + length $char;
		}
		push @text, $characters;
		last unless pos($text) < length $text;
		
		$characters = '';
		while ($text !~ /$filter/) {
			my ($char) = $text =~ /\G(\X)/;
			$characters .= $char;
			pos($text) = pos($text) + length $char;
		}
		push @text, $characters;
	}
	
	my $to_transform = 1;
	
	foreach my $characters (@text) {
		if ($to_transform) {
			foreach my $rule (@$rules[1 .. @$rules -1 ]) {
				if ($rule->{type} eq 'transform') {
					$characters = $self->_transformation_transform($characters, $rule->{data}, $variant);
				}
				else {
					$characters = $self->_transform_convert($characters, $rule->{data});
				}
			}
		}
		$to_transform = ! $to_transform;
	}
	
	return join '', @text;
}

sub _transformation_transform {
	my ($self, $text, $rules, $variant) = @_;
	
	use feature 'switch';
	no warnings 'experimental';
	
	foreach my $rule (@$rules) {
		given (lc $rule->{to}) {
			when ('nfc') {
				$text = Unicode::Normalize::NFC($text);
			}
			when ('nfd') {
				$text = Unicode::Normalize::NFD($text);
			}
			when ('nfkd') {
				$text = Unicode::Normalize::NFKD($text);
			}
			when ('nfkc') {
				$text = Unicode::Normalize::NFKC($text);
			}
			when ('lower') {
				$text = lc($text);
			}
			when ('upper') {
				$text = uc($text);
			}
			when ('title') {
				$text =~ s/(\X)/\u$1/g;
			}
			when ('null') {
			}
			when ('remove') {
				$text = '';
			}
			default {
				$text = $self->transform($text, $variant, $rule->{from}, $rule->to);
			}
		}
	}
	return $text;
}		

sub _transform_convert {
	my ($self, $text, $rules) = @_;
	
	pos($text) = 0; # Make sure we start scanning at the beginning of the text
		
	CHARACTER: while (pos($text) < length($text)) {
		foreach my $rule (@$rules) {
			next if length $rule->{before} && $text !~ /$rule->{before}\G/;
			my $regex = $rule->{replace};
			$regex .= '(' . $rule->{after} . ')' if length $rule->{after};
			my $result = 'q(' . $rule->{result} . ')';
			$result .= '. $1' if length $rule->{after};
			if ($text =~ s/\G$regex/eval $result/e) {
				pos($text) += length($rule->{result}) - $rule->{revisit};
				next CHARACTER;
			}
		}
		
		pos($text)++;
	}
	
	return $text;
}

sub list {
	my ($self, @data) = @_;
	
	# Short circuit on 0 or 1 entries
	return '' unless @data;
	return $data[0] if 1 == @data;
	
	my @bundles = $self->_find_bundle('listPatterns');
	
	my %list_data;
	foreach my $bundle (reverse @bundles) {
		%list_data = %{$bundle->listPatterns};
	}
	
	if (my $pattern = $list_data{scalar @data}) {
		return $pattern=~s/\{([0-9]+)\}/$data[$1]/egr;
	}
	
	my ($start, $middle, $end) = @list_data{qw( start middle end )};
	
	# First do the end
	my $pattern = $end;
	$pattern=~s/\{1\}/pop @data/e;
	$pattern=~s/\{0\}/pop @data/e;
	
	# If there is any data left do the middle
	while (@data > 1) {
		my $current = $pattern;
		$pattern = $middle;
		$pattern=~s/\{1\}/$current/;
		$pattern=~s/\{0\}/pop @data/e;
	}
	
	# Now do the start
	my $current = $pattern;
	$pattern = $start;
	$pattern=~s/\{1\}/$current/;
	$pattern=~s/\{0\}/pop @data/e;
	
	return $pattern;
}
	
# Stubs until I get onto numbers
sub plural {
	return 'one' if $_[1] =~ /1$/;
	return 'other';
}

sub _clear_calendar_data {
	my $self = shift;

	foreach my $property (qw(
		month_format_wide month_format_abbreviated month_format_narrow
		month_stand_alone_wide month_stand_alone_abbreviated
		month_stand_alone_narrow day_format_wide day_format_abbreviated
		day_format_narrow day_stand_alone_wide day_stand_alone_abreviated
		day_stand_alone_narrow quater_format_wide quater_format_abbreviated
		quater_format_narrow quater_stand_alone_wide
		quater_stand_alone_abreviated quater_stand_alone_narrow
		am_pm_wide am_pm_abbreviated am_pm_narrow era_wide era_abbreviated
		era_narrow date_format_full date_formart_long date_format_medium
		date_format_short date_format_default time_format_full
		time_formart_long time_format_medium time_format_short
		timeformat_default datetime_format_full datetime_formart_long
		datetime_format_medium datetime_format_short datetimeformat_default
		available_formats format_data
	)) {
		my $method = "_clear_$property";
		$self->$method;
	}
}

sub _build_month_format_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();
	my ($type, $width) = (qw(format wide));
	my @bundles = $self->_find_bundle('calendar_months');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $months = $bundle->calendar_months;
			if (exists $months->{$default_calendar}{alias}) {
				$default_calendar = $months->{$default_calendar}{alias};
				redo BUNDLES;
			}

			if (exists $months->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$months->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			
			my $result = $months->{$default_calendar}{$type}{$width}{nonleap};
			return $result if defined $result;
		}
	}
	
	return [];
}

sub _build_month_format_abbreviated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();
	my ($type, $width) = (qw(format abbreviated));
	my @bundles = $self->_find_bundle('calendar_months');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $months = $bundle->calendar_months;
			if (exists $months->{$default_calendar}{alias}) {
				$default_calendar = $months->{$default_calendar}{alias};
				redo BUNDLES;
			}
			
			if (exists $months->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$months->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			
			my $result = $months->{$default_calendar}{$type}{$width}{nonleap};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_month_format_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();
	my ($type, $width) = (qw(format narrow));
	my @bundles = $self->_find_bundle('calendar_months');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $months = $bundle->calendar_months;
			if (exists $months->{$default_calendar}{alias}) {
				$default_calendar = $months->{$default_calendar}{alias};
				redo BUNDLES;
			}
			
			if (exists $months->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$months->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			
			my $result = $months->{$default_calendar}{$type}{$width}{nonleap};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_month_stand_alone_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();
	my ($type, $width) = ('stand-alone', 'wide');
	my @bundles = $self->_find_bundle('calendar_months');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $months = $bundle->calendar_months;
			if (exists $months->{$default_calendar}{alias}) {
				$default_calendar = $months->{$default_calendar}{alias};
				redo BUNDLES;
			}
			
			if (exists $months->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$months->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			
			my $result = $months->{$default_calendar}{$type}{$width}{nonleap};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_month_stand_alone_abbreviated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();
	my ($type, $width) = ('stand-alone', 'abbreviated');
	my @bundles = $self->_find_bundle('calendar_months');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $months = $bundle->calendar_months;
			if (exists $months->{$default_calendar}{alias}) {
				$default_calendar = $months->{$default_calendar}{alias};
				redo BUNDLES;
			}
			
			if (exists $months->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$months->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			
			my $result = $months->{$default_calendar}{$type}{$width}{nonleap};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_month_stand_alone_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();
	my ($type, $width) = ('stand-alone', 'narrow');
	my @bundles = $self->_find_bundle('calendar_months');
	
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $months = $bundle->calendar_months;
			if (exists $months->{$default_calendar}{alias}) {
				$default_calendar = $months->{$default_calendar}{alias};
				redo BUNDLES;
			}
			
			if (exists $months->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$months->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			
			my $result = $months->{$default_calendar}{$type}{$width}{nonleap};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_day_format_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_days');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $days = $bundle->calendar_days;
			my $result = $days->{$calendar}{format}{wide};
			return [@$result{qw( mon tue wed thu fri sat sun )}] if defined $result;
		}
	}

	return [];
}

sub _build_day_format_abbreviated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_days');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $days= $bundle->calendar_days;
			my $result = $days->{$calendar}{format}{abbreviated};
			return @{$result}{qw( mon tue wed thu fri sat sun )} if defined $result;
		}
	}

	return [];
}

sub _build_day_format_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_days');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $days = $bundle->calendar_days;
			my $result = $days->{$calendar}{format}{narrow};
			return @{$result}{qw( mon tue wed thu fri sat sun )} if defined $result;
		}
	}

	return [];
}

sub _build_day_stand_alone_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_days');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $days= $bundle->calendar_days;
			my $result = $days->{$calendar}{'stand-alone'}{wide};
			return @{$result}{qw( mon tue wed thu fri sat sun )} if defined $result;
		}
	}

	return [];
}

sub _build_day_stand_alone_abbreviated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_days');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $days= $bundle->calendar_days;
			my $result = $days->{$calendar}{'stand-alone'}{abbreviated};
			return @{$result}{qw( mon tue wed thu fri sat sun )} if defined $result;
		}
	}

	return [];
}

sub _build_day_stand_alone_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_days');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $days= $bundle->calendar_days;
			my $result = $days->{$calendar}{'stand-alone'}{narrow};
			return @{$result}{qw( mon tue wed thu fri sat sun )} if defined $result;
		}
	}

	return [];
}

sub _build_quarter_format_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_quarters');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $quarters = $bundle->calendar_quarters;
			my $result = $quarters->{$calendar}{format}{wide};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_quarter_format_abbreviated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_quarters');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $quarters = $bundle->calendar_quarters;
			my $result = $quarters->{$calendar}{format}{abbreviated};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_quarter_format_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_quarters');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $quarters = $bundle->calendar_quarters;
			my $result = $quarters->{$calendar}{format}{narrow};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_quarter_stand_alone_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_quarters');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $quarters = $bundle->calendar_quarters;
			my $result = $quarters->{$calendar}{'stand-alone'}{wide};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_quarter_stand_alone_abbreviated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_quarters');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $quarters = $bundle->calendar_quarters;
			my $result = $quarters->{$calendar}{'stand-alone'}{abbreviated};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_quarter_stand_alone_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_quarters');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $quarters= $bundle->calendar_quarters;
			my $result = $quarters->{$calendar}{'stand-alone'}{narrow};
			return $result if defined $result;
		}
	}

	return [];
}

sub _build_am_pm_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @result;
	my @bundles = $self->_find_bundle('day_periods');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $am_pm = $bundle->day_periods;
			my $result = $am_pm->{$calendar}{format}{wide};
			$result[0] //= $result->{am};
			$result[1] //= $result->{pm};
			return \@result if ((map {defined} @result) == 2);
		}
	}

	return [];
}

sub _build_am_pm_abbrivated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @result;
	my @bundles = $self->_find_bundle('day_periods');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $am_pm = $bundle->day_periods;
			my $result = $am_pm->{$calendar}{format}{abbrivated} ;
			$result[0] //= $result->{am};
			$result[1] //= $result->{pm};
			return \@result if ((map {defined} @result) == 2);
		}
	}

	return [];
}

sub _build_am_pm_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @result;
	my @bundles = $self->_find_bundle('day_periods');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $am_pm = $bundle->day_periods;
			my $result = $am_pm->{$calendar}{format}{narrow};
			$result[0] //= $result->{am};
			$result[1] //= $result->{pm};
			return \@result if ((map {defined} @result) == 2);
		}
	}

	return [];
}

sub _build_era_wide {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('eras');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $eras = $bundle->eras;
			my $result = $eras->{$calendar}{wide};
			return $result if $result;
		}
	}

	return 0;
}

sub _build_era_abbrivated {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('eras');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $eras = $bundle->eras;
			my $result = $eras->{$calendar}{abbrivated} ;
			return $result if $result;
		}
	}

	return 0;
}

sub _build_era_narrow {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('eras');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $eras = $bundle->day_periods;
			my $result = $eras->{$calendar}{narrow};
			return $result if $result;
		}
	}

	return 0;
}

sub _build_date_format_full {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('date_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $date_formats = $bundle->date_formats;
			my $result = $date_formats->{$calendar}{full};
			return $result if $result;
		}
	}

	return '';
}

sub _build_date_format_long {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('date_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $date_formats = $bundle->date_formats;
			my $result = $date_formats->{$calendar}{long};
			return $result if $result;
		}
	}

	return '';
}

sub _build_date_format_medium {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('date_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $date_formats = $bundle->date_formats;
			my $result = $date_formats->{$calendar}{medium};
			return $result if $result;
		}
	}

	return '';
}

sub _build_date_format_short {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('date_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $date_formats = $bundle->date_formats;
			my $result = $date_formats->{$calendar}{short};
			return $result if $result;
		}
	}

	return '';
}

sub _build_date_format_default {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('date_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $date_formats = $bundle->date_formats;
			my $result = $date_formats->{$calendar}{default};
			return $result if $result;
		}
	}

	return '';
}

sub _build_time_format_full {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('time_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $time_formats = $bundle->time_formats;
			my $result = $time_formats->{$calendar}{full};
			return $result if $result;
		}
	}

	return '';
}

sub _build_time_format_long {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('time_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $time_formats = $bundle->time_formats;
			my $result = $time_formats->{$calendar}{long};
			return $result if $result;
		}
	}

	return '';
}

sub _build_time_format_medium {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('time_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $time_formats = $bundle->time_formats;
			my $result = $time_formats->{$calendar}{medium};
			return $result if $result;
		}
	}

	return '';
}

sub _build_time_format_short {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('time_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $time_formats = $bundle->time_formats;
			my $result = $time_formats->{$calendar}{short};
			return $result if $result;
		}
	}

	return '';
}

sub _build_time_format_default {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('time_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $time_formats = $bundle->time_formats;
			my $result = $time_formats->{$calendar}{default};
			return $result if $result;
		}
	}

	return '';
}

sub _build_datetime_format_full {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('datetime_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $datetime_formats = $bundle->datetime_formats;
			my $result = $datetime_formats->{$calendar}{full};
			next unless $result;
			my $date_format_full = $self->date_format_full;
			my $time_format_full = $self->time_format_full;
			$result =~ s/ \{ 0 \} /$time_format_full/gx;
			$result =~ s/ \{ 1 \} /$date_format_full/gx;
		}
	}

	return '';
}

sub _build_datetime_format_long {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('datetime_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $datetime_formats = $bundle->datetime_formats;
			my $result = $datetime_formats->{$calendar}{long};
			next unless $result;
			my $date_format_long = $self->date_format_long;
			my $time_format_long = $self->time_format_long;
			$result =~ s/ \{ 0 \} /$time_format_long/gx;
			$result =~ s/ \{ 1 \} /$date_format_long/gx;
		}
	}

	return '';
}

sub _build_datetime_format_medium {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('datetime_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $datetime_formats = $bundle->datetime_formats;
			my $result = $datetime_formats->{$calendar}{medium};
			next unless $result;
			my $date_format_medium = $self->date_format_medium;
			my $time_format_medium = $self->time_format_medium;
			$result =~ s/ \{ 0 \} /$time_format_medium/gx;
			$result =~ s/ \{ 1 \} /$date_format_medium/gx;
		}
	}

	return '';
}

sub _build_datetime_format_short {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('datetime_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $datetime_formats = $bundle->datetime_formats;
			my $result = $datetime_formats->{$calendar}{short};
			next unless $result;
			my $date_format_short = $self->date_format_short;
			my $time_format_short = $self->time_format_short;
			$result =~ s/ \{ 0 \} /$time_format_short/gx;
			$result =~ s/ \{ 1 \} /$date_format_short/gx;
		}
	}

	return '';
}

sub _build_datetime_format_default {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('datetime_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $datetime_formats = $bundle->datetime_formats;
			my $result = $datetime_formats->{$calendar}{default};
			return $result if $result;
		}
	}

	return '';
}

sub _build_format_data {
	my $self = shift;
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('datetime_formats_available_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $datetime_formats_available_formats = $bundle->datetime_formats_available_formats;
			my $result = $datetime_formats_available_formats->{$calendar};
			return $result if $result;
		}
	}

	return {};
}

sub format_for {
	my ($self, $format) = @_;

	my $format_data = $self->format_data;

	return $format_data->{$format} // '';
}

sub _build_available_formats {
	my $self = shift;

	my $format_data = $self->format_data;

	return [keys %$format_data];
}

sub _build_default_date_format_length {
	my $self = shift;
	
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('date_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $date_formats = $bundle->date_formats;
			my $result = $date_formats->{$calendar}{default};
			return $result if $result;
		}
	}
}

sub _build_default_time_format_length {
	my $self = shift;
	
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('time_formats');
	foreach my $calendar ($default_calendar, 'gregorian') {
		foreach my $bundle (@bundles) {
			my $time_formats = $bundle->time_formats;
			my $result = $time_formats->{$calendar}{default};
			return $result if $result;
		}
	}
}

sub _build_prefers_24_hour_time {
	my $self = shift;

	return $self->time_format_short() =~ /h|K/ ? 0 : 1;
}

{
	my %days_2_number = (
		mon => 1,
		tue => 2,
		wen => 3,
		thu => 4,
		fri => 5,
		sat => 6,
		sun => 7,
	);

	sub _build_first_day_of_week {

		my $self = shift;

		my $territory_id = $self->territory_id || '001';

		my $first_day_hash = $self->week_data_first_day;
		my $first_day = $first_day_hash->{$territory_id}
			|| $first_day_hash->{'001'};

		return $days_2_number{$first_day};
	}
}

# Sub to mangle Unicode regex to Perl regex
sub unicode_to_perl {
	my $regex = shift;

	return '' unless length $regex;
	$regex =~ s/
		(?:\\\\)*+               	# Pairs of \
		(?!\\)                   	# Not followed by \
		\K                       	# But we don't want to keep that
		(?<set>                     # Capture this
			\[                      # Start a set
				(?:
					[^\[\]\\]+     	# One or more of not []\
					|               # or
					(?:
						(?:\\\\)*+	# One or more pairs of \ witout back tracking
						\\.         # Followed by an escaped character
					)
					|				# or
					(?&set)			# An inner set
				)++                 # Do the inside set stuff one or more times without backtracking
			\]						# End the set
		)
	/ convert($1) /xeg;
	no warnings "experimental::regex_sets";
	no warnings "deprecated"; # Because CLDR uses surrogates
	return qr/$regex/x;
}

sub convert {
	my $set = shift;
	
	# Some definitions
	my $posix = qr/(?(DEFINE)
		(?<posix> (?> \[: .+? :\] ) )
		)/x;
	
	# Convert Unicode escapes \u1234 to characters
	$set =~ s/\\u(\p{Ahex}+)/chr(hex($1))/egx;
	
	# Check to see if this is a normal character set
	my $normal = 0;
	
	$normal = 1 if $set =~ /^
		\s* 					# Possible whitespace
		\[  					# Opening set
		^?  					# Possible negation
		(?:           			# One of
			[^\[\]]++			# Not an open or close set 
			|					# Or
			(?<=\\)[\[\]]       # An open or close set preceded by \
			|                   # Or
			(?:
				\s*      		# Posible Whitespace
				(?&posix)		# A posix class
				(?!         	# Not followd by
					\s*			# Possible whitespace
					[&-]    	# A unicode regex op
					\s*     	# Posible whitespace
					\[      	# A set opener
				)
			)
		)+
		\] 						# Close the set
		\s*						# Possible whitespace
		$
		$posix
	/x;
	
	# Convert posix to perl
	$set =~ s/\[:(.*?):\]/\\p{$1}/g;
	
	if ($normal) {
		return "$set";
	}
	
	# Fix up [abc[de]] to [[abc][de]]
	$set =~ s/\[ ( (?>\^? \s*) [^\]]+? ) \s* \[/[[$1][/gx;
	
	# Fix up [[ab]cde] to [[ab][cde]]
	$set =~ s/\[ \^?+ \s* \[ [^\]]+? \] \K \s* ( [^\[]+ ) \]/[$1]]/gx;
	
	# Unicode uses ^ to compliment the set where as Perl uses !
	$set =~ s/\[ \^ \s*/[!/gx;
	
	# The above can leave us with empty sets. Strip them out
	$set =~ s/\[\]//g;
	
	# Fixup inner sets with no operator
	1 while $set =~ s/ \] \s* \[ /] + [/gx;
	1 while $set =~ s/ \] \s * (\\p\{.*?\}) /] + $1/xg;
	1 while $set =~ s/ \\p\{.*?\} \s* \K \[ / + [/xg;
	1 while $set =~ s/ \\p\{.*?\} \s* \K (\\p\{.*?\}) / + $1/xg;
	
	# Unicode uses [] for grouping as well as starting an inner set
	# Perl uses ( ) So fix that up now
	
	$set =~ s/. \K \[ (?> (!?) \s*) \[ /($1\[/gx;
	$set =~ s/ \] \s* \] (.) /])$1/gx;
	
	return "(?$set)";
}

=head1 AUTHOR

John Imrie, C<< <j dot imrie1 at virginemail.com> >>

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

Copyright 2009-2011 John Imrie.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Locale::CLDR
