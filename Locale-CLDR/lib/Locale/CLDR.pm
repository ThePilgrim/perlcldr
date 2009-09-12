package Locale::CLDR;

use Moose;

=head1 NAME

Locale::CLDR - Main Class for CLDR Locals

=head1 VERSION

Version 1.7.1 To match the CLDR Version

=cut

use version; our $VERSION = qv("1.7.1");


=head1 SYNOPSIS

This module handles Local Data from the CLDR

=head1 Attributes

=cut

has 'language' => (
	is			=> 'ro',
	isa			=> 'Str',
	required	=> 1,
);

has 'script' => (
	is			=> 'ro',
	isa			=> 'Str|Undef',
	default		=> undef
);

has 'region' => (
	is			=> 'ro',
	isa			=> 'Str|Undef',
	default		=> undef
);

has 'variant' => (
	is			=> 'ro',
	isa			=> 'Str|Undef',
	default		=> undef
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
);

has 'method_cashe' => (
	isa			=> 'HashRef[ArrayRef[Object]]',
	init_arg	=> undef,
);

sub BUILDARGS {
	my $self = shift;
	my %args;
	if (1 == @_ && ! ref $_[0]) {
		my ($language, $script, $region, $variant, $extentions)
		 	= $_[0]=~/^([a-zA-Z]+)(?:[-_]([a-zA-Z]{4}))?(?:[-_]([a-zA-Z]{2,3}))?(?:[-_]([a-zA-Z]+))?(?:\@(.+))?$/;
		%args = (
			language	=> $language,
			script		=> $script,
			region		=> $region,
			variant		=> $variant,
			extentions	=> $extentions,
		);
	}

	if (! %args ) {
		%args = ref $_[0]
			? %{$_[0]}
			: @_
	}

	# Split up the variant
	if ( defined $args{extentions} && ! ref $args{extentions} ) {
		$args{extentions} = {
			map { split /=/ }
			split /;/, $args{extentions}
		};
	}

	$self->SUPER::BUILDARGS(%args);
}

sub BUILD {
	my ($self, $args) = @_;

	# Create the new path
	my @path;
	my $path = join '::',
		map { ucfirst lc }
		grep { defined } (
			$args->{language},
			$args->{script},
			$args->{region},
			$args->{variant}
		);

	while ($path) {
		push @path, $path;
		$path=~s/(?:::)?[^:]+$//;
	}

	# Fixup language_region if we have a script and a region
	if (defined $args->{script} && defined $args->{region}) {
		pop @path;
		$path = join '::',
			map { ucfirst lc }
			grep { defined } (
				$args->{language},
				$args->{region},
				$args->{variant}
			);

		while ($path) {
			push (@path, $path);
			$path=~s/(?:::)?[^:]+$//;
		}
	}

	push @path, 'Root' 
		unless $path[-1] eq 'Root';

	# Now we go through the path loading each module
	# And calling new on it. With each module we call
	# fallback to expand the module with it's fallbacks
	my @modules;
	foreach my $module (@path) {
		$module = "Local::CLDR::$module";
		eval "require $module";
		next if $@;
		my $local_package = $module->new;
		push @modules, 
			$local_package, 
			map {Local::CLDR->new($_)->modules} $local_package->fallback;
	}

	# If we only have the root module then we have a problem as
	# none of the language specific data is in the root. So we
	# fall back to the en module
	if (1 == @modules ) {
		require Local::CLDR::En;
		push @modules, Local::CLDR::En->new
	}
	;
	$self->_set_modules(\@modules);
}

use overload 
  'bool'	=> sub { 1 },
  '""'		=> \&stringify;

sub stringify {
	my $self = shift;
	my $string = lc $self->language;

	if (defined $self->script) {
		$string.= '_' . ucfirst lc $self->script;
	}

	if (defined $self->region) {
		$string.= '_' . uc $self->region;
	}

	if (defined $self->variant) {
		$string.= '_' . uc $self->variant;
	}

	if (defined $self->extentions) {
		$string.= '@';
		foreach my $key (sort keys %{$self->extentions}) {
			my $value = $self->extentions->{$key};
			$string .= "$key=$value;";
		}
		chop $string;
	}

	return $string;
}

# Method to locate the resource bundle with the required data
sub _find_bundle {
	my ($self, $method_name) = @_;
	return $self->method_cashe->{$method_name}
		if $self->method_cashe->{$method_name};

	foreach my $module ($self->modules) {
		if ($module->can($method_name)) {
			push @{$self->method_cashe->{$method_name}}, $module;
		}
	}

	return wantarray
		? @{$self->method_cashe->{$method_name}}
		: $self->method_cashe->{$method_name}[0];
}

# Method to return the given local name in the current locals format
sub local_name {
	my ($self, $name) = @_;
	$name //= $self;

	my $code = ref $name
		? join ('_', $name->language, $name->region)
		: $name;
	
	my @bundles = $self->_find_bundle('displayNameLanguage');

	foreach my $bundle (@bundles) {
		my $display_name = $bundel->displayNameLanguage->{$code};
		return $display_name if defined $display_name;
	}

	# $name can be a string or a Local::CLDR::*
	if (! ref $name) {
		$name = Local::CLDR->new($name);
	}

	# Now we have to process each individual element
	# to pass to the display name pattern
	my $language = $self->language_name($name);
	my $script = $self->script_name($name);
	my $territory = $self->territory_name($name);
	my $variant = $self->variant_name($name);

	$bundle = $self->_find_bundle('displayNamePattern');
	return $bundel->displayNamePattern($name, $territory, $script, $variant);
}

sub language_name {
	my ($self, $name) = @_;

	$name //= $self;

	my $code = ref $name
		? $name->language
		: $name;

	my $language = undef;
	foreach my $bundle (@bundles) {
		my $display_name = $bundel->displayNameLanguage->{$code};
		if (defined $display_name) {
			$language = $display_name;
			last;
		}
	}

	# If we don't have a display name for the language we try again
	# with the und tag
	if (! defined $language ) {
		foreach my $bundle (@bundles) {
			my $display_name = $bundel->displayNameLanguage->{'und'};
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

	if ( ref $name && ! $name->has_script ) {
		return undef;
	}

	if (! ref $name ) {
		$name = __PACKAGE__->new(language => 'und', script => $name);
	}

	my $script = undef;
	@bundles = $self->_find_bundle('displayNameScript');
	foreach my $bundle (@bundles) {
		$script = $bundel->displayNameScript->{$name->script};
		if (defined $script) {
			last;
		}
	}

	if (! defined $script) {
		foreach my $bundle (@bundles) {
			$script = $bundel->displayNameScript->{'Zzzz'};
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

	if ( ref $name && ! $name->has_territory) {
		return undef;
	}

	if (! ref $name ) {
		$name = __PACKAGE__->new(languge => 'und', territory => $name);
	}

	my $territory = undef;
	@bundles = $self->_find_bundle('displayNameTerritory');
	foreach my $bundle (@bundles) {
		$territory = $bundel->displayNameTerritory->{$name->territory};
		if (defined $territory) {
			last;
		}
	}

	if (! defined $territory) {
		foreach my $bundle (@bundles) {
			$territory = $bundel->displayNameTerritory->{'ZZ'};
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

	my $variant = undef;
	if ($name->has_variant) {
		@bundles = $self->_find_bundle('displayNameVariant');
		foreach my $bundle (@bundles) {
			$variant= $bundel->displayNameVariant->{$name->variant};
			if (defined $variant) {
				last;
			}
		}
	}

	return $variant;
}

=head1 AUTHOR

John Imrie, C<< <john.imrie at vodafoeemail.co.uk> >>

=head1 BUGS

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

#vim:tabstop=4:
