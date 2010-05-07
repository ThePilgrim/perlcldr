package Locale::CLDR;

use Moose;
with 'Locale::CLDR::ValidCodes';

=head1 NAME

Locale::CLDR - Main Class for CLDR Locals

=head1 VERSION

Version 1.8.0 To match the CLDR Version

=cut

use version; our $VERSION = qv("1.8.0");
use List::Util qw(first);


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

has 'valid_keys' => (
	is			=> 'ro',
	isa			=> 'ArrayRef[Str]',
	init_arg		=> undef,
	auto_deref		=> 1,
	default		=> sub {
		return [ qw( colation calendar currency numbers timezone ) ];
	},
);

has '_no_fallback' => (
	is			=> 'ro',
	isa			=> 'Bool',
	default		=> 0,
	lazy		=> 1,
);

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

=head1 AUTHOR

John Imrie, C<< <john.imrie at vodafoneemail.co.uk> >>

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
