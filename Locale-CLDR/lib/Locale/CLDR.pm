package Locale::CLDR v0.0.1;

=encoding utf8

=head1 NAME

Locale::CLDR - Main Class for CLDR Locals

=head1 VERSION

Version 0.0.1

=head1 SYNOPSIS

This module handles Locale Data from the CLDR.

=head1 USAGE

 my $locale = Locale::CLDR->new('en_GB');

or

 my $locale = Locale::CLDR->new(language_id => 'en', territory_id => 'gb');

=cut

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
use List::Util qw(first);
use Class::MOP;
use DateTime::Locale;
use Unicode::Normalize();

=head1 ATTRIBUTES

These can be passed into the constructor and all are optional.

=over 4

=item language_id

A valid language or language alias id, such as C<en>

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

=item script_id

A valid script id, such as C<latn> or C<Ctcl>. The code will pick a likely script
depending on the given language if non is provided.

=cut

has 'script_id' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_script',
);

=item territory_id

A valid territory id or territory alias such as C<GB>

=cut

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

=item variant_id

A valid variant id. The code currently ignores this

=cut

has 'variant_id' => (
	is			=> 'ro',
	isa			=> 'Str',
	default		=> '',
	predicate	=> 'has_variant',
);

=item extensions 

A Hashref of extension names and values. This is currently ignored but future releases
will use it to override various assumptions such as calendar type and number type

=cut

has 'extensions' => (
	is			=> 'ro',
	isa			=> 'Undef|HashRef',
	default		=> undef,
	writer		=> '_set_extensions',
);

=back

=head1 Methods

The following methods can be called on the locale object

=over 4

=item id()

The local identifier. This is what you get if you attempt to
stringify a locale object.

=item likely_language()

Given a locale with no language passed in or with the explicit language
code of C<und>, this method attempts to use the script and territory
data to guess the locales language.

=cut

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

=item likely_script()

Given a locale with no script passed in this method attempts to use the
language and territory data to guess the locales script.

=cut

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

=item likely_territory()

Given a locale with no territory passed in this method attempts to use the
language and script data to guess the locales territory.

=back

=cut

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

=head2 Meta Data

The following methods return, in English, the names if the various 
id's passed into the locales constructor. I.e. if you passed 
C<language => 'fr'> to the constructor you would get back C<French>
for the language.

=over 4

=item name

The locales name. This is usually built up out of the language, 
script, territory and variant of the locale

=item language

The name of the locales language

=item script

The name of the locales script

=item territory

The name of the locales territory

=item variant

The name of the locales variant

=back

=head2 Native Meta Data

Like Meta Data above this provides the names of the various id's 
passed into the locales constructor. However in this case the
names are formatted to match the locale. I.e. if you passed 
C<language => 'fr'> to the constructor you would get back 
C<français> for the language.

=over 4

=item native_name

The locales name. This is usually built up out of the language, 
script, territory and variant of the locale. Returned in the locales
language and script

=item native_language

The name of the locales language in the locales language and script.

=item native_script

The name of the locales script in the locales language and script.

=item native_territory

The name of the locales territory in the locales language and script.

=item native_variant

The name of the locales variant in the locales language and script.

=back

=cut

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

=head2 Calenders

The Calendar data is built to hook into L<DateTime::Locale> so that 
all Locale::CLDR objects can be used as replacements for DateTime::Locale's 
locale data

=over 4

=item month_format_wide 

=item month_format_abbreviated 

=item month_format_narrow

=item month_stand_alone_wide

=item month_stand_alone_abbreviated

=item month_stand_alone_narrow

All the above return an arrayref of month names in the requested style.

=item day_format_wide 

=item day_format_abbreviated 

=item day_format_narrow

=item day_stand_alone_wide

=item day_stand_alone_abbreviated

=item day_stand_alone_narrow

All the above return an array ref of day names in the requested style.

=item quarter_format_wide 

=item quarter_format_abbreviated 

=item quarter_format_narrow

=item quarter_stand_alone_wide

=item quarter_stand_alone_abbreviated

=item quarter_stand_alone_narrow

All the above return an arrayref of quarter names in the requested style.

=item am_pm_wide

=item am_pm_abbreviated

=item am_pm_narrow

All the above return the date period name for AM and PM
in the requested style

=item era_wide

=item era_abbreviated

=item era_narrow

All the above return an array ref of era names. Note that these 
return the first two eras which is what you normally want for 
BC and AD etc. but won't work correctly for Japanese calendars.

=back

=cut

foreach my $property (qw( 
	month_format_wide month_format_abbreviated month_format_narrow
	month_stand_alone_wide month_stand_alone_abbreviated month_stand_alone_narrow
	day_format_wide day_format_abbreviated day_format_narrow
	day_stand_alone_wide day_stand_alone_abbreviated day_stand_alone_narrow
	quarter_format_wide quarter_format_abbreviated quarter_format_narrow
	quarter_stand_alone_wide quarter_stand_alone_abbreviated quarter_stand_alone_narrow
	am_pm_wide am_pm_abbreviated am_pm_narrow
	era_wide era_abbreviated era_narrow
	era_format_wide era_format_abbreviated era_format_narrow
	era_stand_alone_wide era_stand_alone_abbreviated era_stand_alone_narrow
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

=pod

The next set of methods are not used by DateTime::Locale but CLDR provide
the data and you might want it

=over 4

=item am_pm_format_wide 

=item am_pm_format_abbreviated

=item am_pm_format_narrow

=item am_pm_stand_alone_wide

=item am_pm_stand_alone_abbreviated

=item am_pm_stand_alone_narrow

All the above return a hashref keyed on date period
with the value being the value for that date period

The get_day_period() method will calculate the correct
period for a given time and return the period name in
the Locales language and script

=item era_format_wide 

=item era_format_abbreviated 

=item era_format_narrow
	
=item era_stand_alone_wide 

=item era_stand_alone_abbreviated 

=item era_stand_alone_narrow

All the above return an array ref with I<all> the era data for the
locale formatted to the requested width

=cut

foreach my $property (qw( 
	am_pm_format_wide am_pm_format_abbreviated am_pm_format_narrow
	am_pm_stand_alone_wide am_pm_stand_alone_abbreviated am_pm_stand_alone_narrow
)) {
	has $property => (
		is => 'ro',
		isa => 'HashRef',
		init_arg => undef,
		lazy => 1,
		builder => "_build_$property",
		clearer => "_clear_$property",
	);
}

=item date_format_full 

=item date_format_long 

=item date_format_medium 

=item date_format_short
	
=item time_format_full

=item time_format_long

=item time_format_medium

=item time_format_short
	
=item datetime_format_full

=item datetime_format_long
	
=item datetime_format_medium

=item datetime_format_short

All the above return the CLDR I<date format pattern> for the given 
element and width

=cut

foreach my $property (qw(
	id
	date_format_full date_format_long 
	date_format_medium date_format_short
	time_format_full time_format_long
	time_format_medium time_format_short
	datetime_format_full datetime_format_long
	datetime_format_medium datetime_format_short
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

=item prefers_24_hour_time()

Returns a boolean value, true if the locale has a preference
for 24 hour time over 12 hour

=cut

has 'prefers_24_hour_time' => (
	is => 'ro',
	isa => 'Bool',
	init_arg => undef,
	lazy => 1,
	builder => "_build_prefers_24_hour_time",
);

=item first_day_of_week()

Returns the numeric representation of the first day of the week
With 0 = Saturday

=cut

has 'first_day_of_week' => (
	is => 'ro',
	isa => 'Int',
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
		my ($language, $script, $territory, $variant, $extensions)
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
			extensions	=> $extensions,
		);
	}

	if (! keys %args ) {
		%args = ref $_[0]
			? %{$_[0]}
			: @_
	}

	# Split up the extensions
	if ( defined $args{extensions} && ! ref $args{extensions} ) {
		$args{extensions} = {
			map {lc}
			split /[_-]/, $args{extensions}
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
	
	if ($args->{extensions}) {
		my %valid_keys = $self->valid_keys;
		my %key_aliases = $self->key_aliases;
		my @keys = keys %{$args->{extensions}};

		foreach my $key ( @keys ) {
			my $canonical_key = $key_aliases{$key} if exists $key_aliases{$key};
			$canonical_key //= $key;
			if ($canonical_key ne $key) {
				$args->{extensions}{$canonical_key} = delete $args->{extensions}{$key};
			}

			$key = $canonical_key;
			die "Invalid extension name" unless exists $valid_keys{$key};
			die "Invalid extension value" unless 
				first { $_ eq $args->{extensions}{$key} } @{$valid_keys{$key}};

			$self->_set_extensions($args->{extensions})
		}
	}

	# Check for variant aliases
	if ($args->{variant_id} && (my $variant_alias = $self->variant_aliases->{lc $self->variant_id})) {
		delete $args->{variant_id};
		my ($what) = keys %{$variant_alias};
		my ($value) = values %{$variant_alias};
		$args->{$what} = $value;
	}
	
	# Now set up the module
	$self->_build_module;
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

	if (defined $self->extensions) {
		$string.= '_u';
		foreach my $key (sort keys %{$self->extensions}) {
			my $value = $self->extensions->{$key};
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

=item locale_name($name)

Returns the given locale name in the current locales format. The name can be
a locale id or a locale object or non existent. If a name is not passed in
then the name of the current locale is returned.

=cut

sub locale_name {
	my ($self, $name) = @_;
	$name //= $self;

	my $code = ref $name
		? join ( '_', $name->language_id, $name->territory_id ? $name->territory_id : () )
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

=item language_name($language)

Returns the language name in the current locales format. The name can be
a locale language id or a locale object or non existent. If a name is not
passed in then the language name of the current locale is returned.

=cut

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

=item all_languages()

Returns a hash ref keyed on language id of all the languages the system 
knows about. The values are the language names for the corresponding id's 

=cut

sub all_languages {
	my $self = shift;

	my @bundles = $self->_find_bundle('display_name_language');
	my %languages;
	foreach my $bundle (@bundles) {
		my $languages = $bundle->display_name_language->();

		# Remove existing languages
		delete @{$languages}{keys %languages};

		# Assign new ones to the hash
		@languages{keys %$languages} = values %$languages;
	}

	return \%languages;
}

=item script_name($script)

Returns the script name in the current locales format. The script can be
a locale script id or a locale object or non existent. If a script is not
passed in then the script name of the current locale is returned.

=cut

sub script_name {
	my ($self, $name) = @_;
	$name //= $self;

	if (! ref $name ) {
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

=item all_scripts()

Returns a hash ref keyed on script id of all the scripts the system 
knows about. The values are the script names for the corresponding id's 

=cut

sub all_scripts {
	my $self = shift;

	my @bundles = $self->_find_bundle('display_name_script');
	my %scripts;
	foreach my $bundle (@bundles) {
		my $scripts = $bundle->display_name_script->();

		# Remove existing scripts
		delete @{$scripts}{keys %scripts};

		# Assign new ones to the hash
		@scripts{keys %$scripts} = values %$scripts;
	}

	return \%scripts;
}

=item territory_name($territory)

Returns the territory name in the current locales format. The territory can be
a locale territory id or a locale object or non existent. If a territory is not
passed in then the territory name of the current locale is returned.

=cut

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

=item all_territories

Returns a hash ref keyed on territory id of all the territory the system 
knows about. The values are the territory names for the corresponding id's 

=cut

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

=item variant_name($variant)

Returns the variant name in the current locales format. The variant can be
a locale variant id or a locale object or non existent. If a variant is not
passed in then the variant name of the current locale is returned.

=cut

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

=item key_name($key)

Returns the key name in the current locales format. The key must be
a locale key id as a string

=cut

sub key_name {
	my ($self, $name) = @_;

	$name = lc $name;
	my %key_aliases = $self->key_aliases;
	my %key_names	= $self->key_names;
	my %valid_keys	= $self->valid_keys;

	my $alias = $key_aliases{$name} if exists $key_aliases{$name};

	return '' unless exists $valid_keys{$name} || exists $valid_keys{$alias};
	my @bundles = $self->_find_bundle('display_name_key');
	foreach my $bundle (@bundles) {
		my $key = $bundle->display_name_key->{$name} // $alias ? $bundle->display_name_key->{$alias} : '';
		return $key if length $key;
	}

	return ucfirst ($key_names{$name} || $name);
}

=item type_name($key, $type)

Returns the type name in the current locales format. The key and type must be
a locale key id and type id as a string

=cut

sub type_name {
	my ($self, $key, $type) = @_;

	$key	= lc $key;
	$type	= lc $type;

	my %key_aliases = $self->key_aliases;
	my %valid_keys	= $self->valid_keys;
	my %key_names	= $self->key_names;

	my $alias = $key_aliases{$key} if exists $key_aliases{$key};

	return '' unless exists $valid_keys{$key} || $valid_keys{$alias};
	return '' unless first { $_ eq $type } @{$valid_keys{$key} || $valid_keys{$alias} || []};

	my @bundles = $self->_find_bundle('display_name_type');
	foreach my $bundle (@bundles) {
		next unless my $types = $bundle->display_name_type->{$key_names{$key} || ($alias ? $key_names{$alias} : '')};
		my $type = $types->{$type};
		return $type if defined $type;
	}

	return '';
}
	
=item measurement_system_name($measurement_system)

Returns the measurement system name in the current locales format. The measurement system must be
a measurement system id as a string

=cut
	
sub measurement_system_name {
	my ($self, $name) = @_;

	# Fix case of code
	$name = uc $name;
	$name = 'metric' if $name eq 'METRIC';

	my @bundles = $self->_find_bundle('display_name_measurement_system');
	foreach my $bundle (@bundles) {
		my $system = $bundle->display_name_measurement_system->{$name};
		return $system if defined $system;
	}

	return '';
}

=item transform_name($measurement_system)

Returns the transform (transliteration) name in the current locales format. The transform must be
a transform id as a string

=cut

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

	# If locale is not passed in then we are using ourself
	$locale //= $self;

	# If locale is not an object then inflate it
	$locale = __PACKAGE__->new($locale) unless blessed $locale;

	return '' unless $type =~ m{ \A (?: language | script | territory ) \z }xms;

	my $method = $type . '_name';
	my $substitute = $self->$method($locale);

	my @bundles = $self->_find_bundle('display_name_code_patterns');
	foreach my $bundle (@bundles) {
		my $text = $bundle->display_name_code_patterns->{$type};
		next unless defined $text;
		my $match = qr{ \{ 0 \} }xms;
		$text=~ s{ $match }{$substitute}gxms;
		return $text;
	}

	return '';
}

=item text_orientation($type)

Gets the text orientation for the locale. Type must be one of 
C<lines> or C<characters>

=cut

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

=item split_grapheme_clusters($string)

Splits a string on grapheme clusters using the locals segmentation rules.
Returns a list of grapheme clusters.

=cut

sub split_grapheme_clusters {
	my ($self, $string) = @_;

	my $rules = $self->break_grapheme_cluster;
	my @clusters = $self->_split($rules, $string, 1);

	return @clusters;
}

=item split_words($string)

Splits a string on word boundaries using the locals segmentation rules.
Returns a list of words.

=cut

sub split_words {
	my ($self, $string) = @_;

	my $rules = $self->break_word;
	my @words = $self->_split($rules, $string);

	return @words;
}

=item split_sentences($string)

Splits a string on on all points where a sentence could
end using the locals segmentation rules. Returns a list
the end of each list element is the point where a sentence
could end.

=cut

sub split_sentences {
	my ($self, $string) = @_;

	my $rules = $self->break_sentence;
	my @sentences = $self->_split($rules, $string);

	return @sentences;
}

=item split_lines($string)

Splits a string on on all points where a line could
end using the locals segmentation rules. Returns a list
the end of each list element is the point where a line
could end.

=cut

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

=item is_exemplar_character( $type, $character)

=item is_exemplar_character($character)

Tests if the given character is used in the locale. There are 
three possible types; c<main>, C<auxiliary> and c<punctuation>.
If no type is given C<main> is assumed.

=cut

sub is_exemplar_character {
	my ($self, @parameters) = @_;
	unshift @parameters, 'main' if @parameters == 1;

	my @bundles = $self->_find_bundle('characters');
	foreach my $bundle (@bundles) {
		my $characters = $bundle->characters->{lc $parameters[0]};
		next unless defined $characters;
		return 1 if fc($parameters[1])=~$characters;
	}

	return;
}

=item index_characters()

Returns an array ref of characters normally used when creating 
an index.

=cut

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

=item truncated_beginning($string)

Adds the locale specific marking to show that the 
string has been truncated at the beginning.

=cut

sub truncated_beginning {
	shift->_truncated(initial => @_);
}

=item truncated_between($string, $string)

Adds the locale specific marking to show that something 
has been truncated between the two strings. Returns a
string comprising of the concatenation of the first string,
the mark and the second string

=cut

sub truncated_between {
	shift->_truncated(medial => @_);
}

=item truncated_end($string)

Adds the locale specific marking to show that the 
string has been truncated at the end.

=cut

sub truncated_end {
	shift->_truncated(final => @_);
}

=item truncated_word_beginning($string)

Adds the locale specific marking to show that the 
string has been truncated at the beginning. This
should be used in preference to C<truncated_beginning>
when the truncation occurs on a word boundary.

=cut

sub truncated_word_beginning {
	shift->_truncated('word-initial' => @_);
}

=item truncated_word_between($string, $string)

Adds the locale specific marking to show that something 
has been truncated between the two strings. Returns a
string comprising of the concatenation of the first string,
the mark and the second string. This should be used in
preference to C<truncated_between> when the truncation
occurs on a word boundary.

=cut

sub truncated_word_between {
	shift->_truncated('word-medial' => @_);
}

=item truncated_word_end($string)

Adds the locale specific marking to show that the 
string has been truncated at the end. This should be
used in preference to C<truncated_end> when the
truncation occurs on a word boundary.

=cut

sub truncated_word_end {
	shift->_truncated('word-final' => @_);
}

=item more_information()

The more information string is one that can be displayed
in an interface to indicate that more information is
available.

=cut

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

=item quote($string)

Adds the locales primary quotation marks to the ends of the string.
Also scans the string for paired primary and auxiliary quotation
marks and flips them.

eg passing C<z “abc” z> to this method for the C<en_GB> locale
gives C<“z ‘abc’ z”>

=cut

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

=item measurement()

Returns the measurement type for the locale

=cut

sub measurement {
	my $self = shift;
	
	my $measurement_data = $self->measurement_system;
	my $territory = $self->territory_id // '001';
	
	return $measurement_data->{$territory} // $measurement_data->{'001'};
}

=item paper()

Returns the paper type for the locale

=cut

sub paper {
	my $self = shift;
	
	my $paper_size = $self->paper_size;
	my $territory = $self->territory_id // '001';
	
	return $paper_size->{$territory} // $paper_size->{'001'};
}

=item all_units()

Returns a list of all the unit identifiers for the locale

=cut

sub all_units {
	my $self = shift;
	my @bundles = $self->_find_bundle('units');
	
	my %units;
	foreach my $bundle (reverse @bundles) {
		%units = %units, $bundle->units;
	}
	
	return keys %units;
}

=item unit($number, $unit, $width)

Returns the localised string for the given number and unit formatted for the 
required width. The number must not be the localized version of the number.
The returned string will be in the locales format, including the number.

=cut

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

=item duration_unit($format, @data)

This method formats a duration. The format must be one of
C<hm>, C<hms> or C<ms> corresponding to C<hour minuet>, 
C<hour minuet second> and C<minuet second> respectively.
The data must correspond to the given format. 

=cut

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

=item is_yes($string)

Returns true if the passed in string matches the locales 
idea of a string designating yes. Note that under POSIX
rules unless the locales word for no starts with C<Y>
(U+0079) then a single 'y' will also be accepted as yes.
The string will be matched case insensitive.

=cut

sub is_yes {
	my ($self, $test_str) = @_;
	
	my $bundle = $self->_find_bundle('yesstr');
	return $test_str =~ $bundle->yesstr ? 1 : 0;
}

=item is_no($string)

Returns true if the passed in string matches the locales 
idea of a string designating no. Note that under POSIX
rules unless the locales word for yes starts with C<n>
(U+006E) then a single 'n' will also be accepted as no
The string will be matched case insensitive.

=cut

sub is_no {
	my ($self, $test_str) = @_;
	
	my $bundle = $self->_find_bundle('nostr');
	return $test_str =~ $bundle->nostr ? 1 : 0;
}

=item transform(from => $from, to => $to, variant => $variant, text => $text)

This method returns the transliterated string of C<text> from script C<from>
to script C<to> using variant C<variant>. If c<from> is not given then the 
current locales script is used. If C<text> is not given then it defaults to an
empty string. The C<variant> is optional.

=cut

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

=item list(@data)

Returns C<data> as a string formatted by the locales idea of producing a list
of elements. What is returned can be effected by the locale and the number
of items in C<data>. Note that C<data> can contain 0 or more items.

=cut

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
		am_pm_wide am_pm_abbreviated am_pm_narrow am_pm_format_wide 
		am_pm_format_abbreviated am_pm_format_narrow am_pm_stand_alone_wide 
		am_pm_stand_alone_abbreviated am_pm_stand_alone_narrow era_wide 
		era_abbreviated era_narrow date_format_full date_format_long date_format_medium
		date_format_short time_format_full
		time_format_long time_format_medium time_format_short
		datetime_format_full datetime_format_long
		datetime_format_medium datetime_format_short
		available_formats format_data
	)) {
		my $method = "_clear_$property";
		$self->$method;
	}
}

sub _build_any_month {
	my ($self, $type, $width) = @_;
	my $default_calendar = $self->default_calendar();
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

sub _build_month_format_wide {
	my $self = shift;
	my ($type, $width) = (qw(format wide));
	
	return $self->_build_any_month($type, $width);
}

sub _build_month_format_abbreviated {
	my $self = shift;
	my ($type, $width) = (qw(format abbreviated));
	
	return $self->_build_any_month($type, $width);
}

sub _build_month_format_narrow {
	my $self = shift;
	my ($type, $width) = (qw(format narrow));
	
	return $self->_build_any_month($type, $width);
}

sub _build_month_stand_alone_wide {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'wide');
	
	return $self->_build_any_month($type, $width);
}

sub _build_month_stand_alone_abbreviated {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'abbreviated');
	
	return $self->_build_any_month($type, $width);
}

sub _build_month_stand_alone_narrow {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'narrow');
	
	return $self->_build_any_month($type, $width);
}

sub _build_any_day {
	my ($self, $type, $width) = @_;
	
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_days');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $days= $bundle->calendar_days;
			
			if (exists $days->{$default_calendar}{alias}) {
				$default_calendar = $days->{$default_calendar}{alias};
				redo BUNDLES;
			}

			if (exists $days->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$days->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			my $result = $days->{$default_calendar}{$type}{$width};
			return [ @{$result}{qw( mon tue wed thu fri sat sun )} ] if keys %$result;
		}
	}

	return [];
}

sub _build_day_format_wide {
	my $self = shift;
	my ($type, $width) = (qw(format wide));
	
	return $self->_build_any_day($type, $width);
}

sub _build_day_format_abbreviated {
	my $self = shift;
	my ($type, $width) = (qw(format abbreviated));
	
	return $self->_build_any_day($type, $width);
}

sub _build_day_format_narrow {
	my $self = shift;
	my ($type, $width) = (qw(format narrow));
	
	return $self->_build_any_day($type, $width);
}

sub _build_day_stand_alone_wide {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'wide');
	
	return $self->_build_any_day($type, $width);
}

sub _build_day_stand_alone_abbreviated {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'abbreviated');

	return $self->_build_any_day($type, $width);
}

sub _build_day_stand_alone_narrow {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'narrow');
	
	return $self->_build_any_day($type, $width);
}

sub _build_any_quarter {
	my ($self, $type, $width) = @_;
	
	my $default_calendar = $self->default_calendar();

	my @bundles = $self->_find_bundle('calendar_quarters');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $quarters= $bundle->calendar_quarters;
			
			if (exists $quarters->{$default_calendar}{alias}) {
				$default_calendar = $quarters->{$default_calendar}{alias};
				redo BUNDLES;
			}

			if (exists $quarters->{$default_calendar}{$type}{$width}{alias}) {
				($type, $width) = @{$quarters->{$default_calendar}{$type}{$width}{alias}}{qw(context type)};
				redo BUNDLES;
			}
			
			my $result = $quarters->{$default_calendar}{$type}{$width};
			return [ @{$result}{qw( 0 1 2 3 )} ] if keys %$result;
		}
	}

	return [];
}

sub _build_quarter_format_wide {
	my $self = shift;
	my ($type, $width) = (qw( format wide ));
	
	return $self->_build_any_quarter($type, $width);
}

sub _build_quarter_format_abbreviated {
	my $self = shift;
	my ($type, $width) = (qw(format abbreviated));

	return $self->_build_any_quarter($type, $width);
}

sub _build_quarter_format_narrow {
	my $self = shift;
	my ($type, $width) = (qw(format narrow));

	return $self->_build_any_quarter($type, $width);
}

sub _build_quarter_stand_alone_wide {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'wide');

	return $self->_build_any_quarter($type, $width);
}

sub _build_quarter_stand_alone_abbreviated {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'abbreviated');
	
	return $self->_build_any_quarter($type, $width);
}

sub _build_quarter_stand_alone_narrow {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'narrow');

	return $self->_build_any_quarter($type, $width);
}

sub get_day_period {
	# Time in hhmm
	my ($self, $time) = @_;
	
	my $default_calendar = $self->default_calendar();
	
	my $bundle = $self->_find_bundle('day_period_data');
	
	my $day_period = $bundle->day_period_data;
	$day_period = $self->$day_period($default_calendar, $time);
	
	my $am_pm = $self->am_pm_format_abbreviated;
	
	return $am_pm->{$day_period};
}

sub _build_any_am_pm {
	my ($self, $type, $width) = @_;

	my $default_calendar = $self->default_calendar();
	my @result;
	my @bundles = $self->_find_bundle('day_periods');

	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $am_pm = $bundle->day_periods;
	
			if (exists $am_pm->{$default_calendar}{alias}) {
				$default_calendar = $am_pm->{$default_calendar}{alias};
				redo BUNDLES;
			}

			if (exists $am_pm->{$default_calendar}{$type}{alias}) {
				$type = $am_pm->{$default_calendar}{$type}{alias};
				redo BUNDLES;
			}
			
			if (exists $am_pm->{$default_calendar}{$type}{$width}{alias}) {
				$width = $am_pm->{$default_calendar}{$type}{$width}{alias};
				redo BUNDLES;
			}
			
			my $result = $am_pm->{$default_calendar}{$type}{$width};
			
			return $result if keys %$result;
		}
	}

	return {};
}

# The first 3 are to link in with Date::Time::Locale
sub _build_am_pm_wide {
	my $self = shift;
	my ($type, $width) = (qw( format wide ));
	
	my $result = $self->_build_any_am_pm($type, $width);
	
	return [ @$result{qw( am pm )} ];
}

sub _build_am_pm_abbreviated {
	my $self = shift;
	my ($type, $width) = (qw( format abbreviated ));

	my $result = $self->_build_any_am_pm($type, $width);
	
	return [ @$result{qw( am pm )} ];
}

sub _build_am_pm_narrow {
	my $self = shift;
	my ($type, $width) = (qw( format narrow ));
	
	my $result = $self->_build_any_am_pm($type, $width);
	
	return [ @$result{qw( am pm )} ];
}

# Now we do the full set of data
sub _build_am_pm_format_wide {
	my $self = shift;
	my ($type, $width) = (qw( format wide ));
	
	return $self->_build_any_am_pm($type, $width);
}

sub _build_am_pm_format_abbreviated {
	my $self = shift;
	my ($type, $width) = (qw( format abbreviated ));

	return $self->_build_any_am_pm($type, $width);
}

sub _build_am_pm_format_narrow {
	my $self = shift;
	my ($type, $width) = (qw( format narrow ));
	
	return $self->_build_any_am_pm($type, $width);
}

sub _build_am_pm_stand_alone_wide {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'wide');
	
	return $self->_build_any_am_pm($type, $width);
}

sub _build_am_pm_stand_alone_abbreviated {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'abbreviated');

	return $self->_build_any_am_pm($type, $width);
}

sub _build_am_pm_stand_alone_narrow {
	my $self = shift;
	my ($type, $width) = ('stand-alone', 'narrow');
	
	return $self->_build_any_am_pm($type, $width);
}

sub _build_any_era {
	my ($self, $width) = @_;

	my $default_calendar = $self->default_calendar();
	my @bundles = $self->_find_bundle('eras');
	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $eras = $bundle->eras;
	
			if (exists $eras->{$default_calendar}{alias}) {
				$default_calendar = $eras->{$default_calendar}{alias};
				redo BUNDLES;
			}

			if (exists $eras->{$default_calendar}{$width}{alias}) {
				$width = $eras->{$default_calendar}{$width}{alias};
				redo BUNDLES;
			}
						
			my $result = $eras->{$default_calendar}{$width};
			
			my @result = map {$result->{$_}} sort { $a <=> $b } keys %$result;
			
			return \@result if keys %$result;
		}
	}

	return [];
}
	
# The next three are for DateDime::Locale
sub _build_era_wide {
	my $self = shift;
	my ($width) = (qw( wide ));

	my $result = $self->_build_any_era($width);
	
	return [@$result[0, 1]];
}

sub _build_era_abbreviated {
	my $self = shift;
	my ($width) = (qw( abbreviated ));

	my $result = $self->_build_any_era($width);
	
	return [@$result[0, 1]];
}

sub _build_era_narrow {
	my $self = shift;
	my ($width) = (qw( narrow ));

	my $result = $self->_build_any_era($width);
	
	return [@$result[0, 1]];
}

# Now get all the era data
sub _build_era_format_wide {
	my $self = shift;
	my ($width) = (qw( wide ));

	return $self->_build_any_era($width);
}

sub _build_era_format_abbreviated {
	my $self = shift;
	my ($width) = (qw( abbreviated ));

	return $self->_build_any_era($width);
}

sub _build_era_format_narrow {
	my $self = shift;
	my ($type, $width) = (qw( narrow ));

	return $self->_build_any_era($type, $width);
}

*_build_era_stand_alone_wide = \&_build_era_format_wide;
*_build_era_stand_alone_abbreviated = \&_build_era_format_abbreviated;
*_build_era_stand_alone_narrow = \&_build_era_format_narrow;

sub _build_any_date_formats {
	my ($self, $width) = @_;
	my $default_calendar = $self->default_calendar();
	
	my @bundles = $self->_find_bundle('date_formats');

	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $date_formats = $bundle->date_formats;
			if (exists $date_formats->{alias}) {
				$default_calendar = $date_formats->{alias};
				redo BUNDLES;
			}
			
			my $result = $date_formats->{$default_calendar}{$width};
			return $result if $result;
		}
	}
	return '';
}

sub _build_date_format_full {
	my $self = shift;
	
	my ($width) = ('full');
	return $self->_build_any_date_formats($width);
}

sub _build_date_format_long {
	my $self = shift;
	
	my ($width) = ('long');
	return $self->_build_any_date_formats($width);
}

sub _build_date_format_medium {
	my $self = shift;
	
	my ($width) = ('medium');
	return $self->_build_any_date_formats($width);
}

sub _build_date_format_short {
	my $self = shift;
	
	my ($width) = ('short');
	return $self->_build_any_date_formats($width);
}

sub _build_any_time_format {
	my ($self, $width) = @_;
	my $default_calendar = $self->default_calendar();
	
	my @bundles = $self->_find_bundle('time_formats');

	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $time_formats = $bundle->time_formats;
			if (exists $time_formats->{alias}) {
				$default_calendar = $time_formats->{alias};
				redo BUNDLES;
			}
			
			my $result = $time_formats->{$default_calendar}{$width};
			return $result if $result;
		}
	}
	return '';
}

sub _build_time_format_full {
	my $self = shift;
	my $width = 'full';
	
	return $self->_build_any_time_format($width);
}

sub _build_time_format_long {
	my $self = shift;
	
	my $width = 'long';
	return $self->_build_any_time_format($width);
}

sub _build_time_format_medium {
	my $self = shift;
	
	my $width = 'medium';
	return $self->_build_any_time_format($width);
}

sub _build_time_format_short {
	my $self = shift;
	
	my $width = 'short';
	return $self->_build_any_time_format($width);
}

sub _build_any_datetime_format {
	my ($self, $width) = @_;
	my $default_calendar = $self->default_calendar();
	
	my @bundles = $self->_find_bundle('datetime_formats');

	BUNDLES: {
		foreach my $bundle (@bundles) {
			my $datetime_formats = $bundle->datetime_formats;
			if (exists $datetime_formats->{alias}) {
				$default_calendar = $datetime_formats->{alias};
				redo BUNDLES;
			}
			
			my $result = $datetime_formats->{$default_calendar}{$width};
			return $result if $result;
		}
	}
	
	return '';
}	

sub _build_datetime_format_full {
	my $self = shift;
	
	my $width = 'full';
	$self->_build_any_datetime_format($width);
}

sub _build_datetime_format_long {
	my $self = shift;
		
	my $width = 'long';
	$self->_build_any_datetime_format($width);
}

sub _build_datetime_format_medium {
	my $self = shift;
	
	my $width = 'medium';
	$self->_build_any_datetime_format($width);
}

sub _build_datetime_format_short {
	my $self = shift;
	
	my $width = 'short';
	$self->_build_any_datetime_format($width);
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
						(?:\\\\)*+	# One or more pairs of \ without back tracking
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
		\s* 					# Possible white space
		\[  					# Opening set
		^?  					# Possible negation
		(?:           			# One of
			[^\[\]]++			# Not an open or close set 
			|					# Or
			(?<=\\)[\[\]]       # An open or close set preceded by \
			|                   # Or
			(?:
				\s*      		# Possible white space
				(?&posix)		# A posix class
				(?!         	# Not followed by
					\s*			# Possible white space
					[&-]    	# A Unicode regex op
					\s*     	# Possible white space
					\[      	# A set opener
				)
			)
		)+
		\] 						# Close the set
		\s*						# Possible white space
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

John Imrie, C<< <j dot imrie1 at virginmedia.com> >>

=head1 BUGS

Please report any bugs or feature requests to me at the above email address 
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

Copyright 2009-2014 John Imrie.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Locale::CLDR
