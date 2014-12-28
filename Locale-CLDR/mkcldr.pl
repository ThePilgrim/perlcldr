#!/usr/bin/perl

use v5.18;
use strict;
use warnings 'FATAL';
use open ':encoding(utf8)', ':std';

use FindBin;
use File::Spec;
use File::Path qw(make_path);
use File::Copy qw(copy);
use XML::XPath; 
use XML::XPath::Node::Text;
use LWP::UserAgent;
use Archive::Extract;
use DateTime;
use XML::Parser;
use Text::ParseWords;
use List::MoreUtils qw( any );
use Unicode::UCD qw(charinfo);
no warnings "experimental::regex_sets";

my $start_time = time();

our $verbose = 0;
$verbose = 1 if grep /-v/, @ARGV;
@ARGV = grep !/-v/, @ARGV;

use version;
my $API_VERSION = 0;
my $CLDR_VERSION = 26;
my $REVISION = 6;
our $VERSION = version->parse(join '.', $API_VERSION, $CLDR_VERSION, $REVISION);
my $CLDR_PATH = $CLDR_VERSION;
my $RELEASE_STATUS = 'unstable';

chdir $FindBin::Bin;
my $data_directory            = File::Spec->catdir($FindBin::Bin, 'Data');
my $core_filename             = File::Spec->catfile($data_directory, 'core.zip');
my $base_directory            = File::Spec->catdir($data_directory, 'common'); 
my $transform_directory       = File::Spec->catdir($base_directory, 'transforms');
my $lib_directory             = File::Spec->catdir($FindBin::Bin, 'lib', 'Locale', 'CLDR');
my $locales_directory         = File::Spec->catdir($lib_directory, 'Locales');
my $transformations_directory = File::Spec->catdir($lib_directory, 'Transformations');
my $distributions_directory   = File::Spec->catdir($FindBin::Bin, 'Distributions');
my $tests_directory           = File::Spec->catdir($FindBin::Bin, 't');
my $build_directory           = File::Spec->catdir($FindBin::Bin, 'lib');

# Check if we have a Data directory
if (! -d $data_directory ) {
    mkdir $data_directory
        or die "Can not create $data_directory: $!";
}

# Check the lib directory
if(! -d $lib_directory) {
    make_path($lib_directory);
}

# Get the data file from the Unicode Consortium
if (! -e $core_filename ) {
    say "Getting data file from the Unicode Consortium"
        if $verbose;

    my $ua = LWP::UserAgent->new(
        agent => "perl Locale::CLDR/$VERSION (Written by john.imrie1\@gmail.com)",
    );
    my $response = $ua->get("http://unicode.org/Public/cldr/$CLDR_PATH/core.zip",
        ':content_file' => $core_filename
    );

    if (! $response->is_success) {
        die "Can not access http://unicode.org/Public/cldr/$CLDR_VERSION/core.zip' "
             . $response->status_line;
    }
}

# Now uncompress the file
if (! -d $base_directory) {
    say "Extracting Data" if $verbose;
    my $zip = Archive::Extract->new(archive => $core_filename);
    $zip->extract(to => $data_directory)
        or die $zip->error;
}

# Now check that we have a 'common' directory
die <<EOM
I successfully unzipped the core.zip file but don't have a 'common' 
directory. Is this version $CLDR_VERSION of the Unicode core.zip file?
EOM

    unless -d File::Spec->catdir($base_directory);

# We look at the supplemental data file to get the cldr version number
my $xml_parser = XML::Parser->new(
    NoLWP => 1,
    ErrorContext => 2,
    ParseParamEnt => 1,
);

my $vf = XML::XPath->new(
    parser => $xml_parser,
    filename => File::Spec->catfile($base_directory, 
    'main',
    'root.xml'),
);

say "Checking CLDR version" if $verbose;
my $cldrVersion = $vf->findnodes('/ldml/identity/version')
    ->get_node
    ->getAttribute('cldrVersion');

die "Incorrect CLDR Version found $cldrVersion. It should be $CLDR_VERSION"
    unless version->parse("$cldrVersion") == $CLDR_VERSION;

say "Processing files"
    if $verbose;

my $file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'likelySubtags.xml'
);

my $xml = XML::XPath->new(
    File::Spec->catfile($file_name)
);

# Number Formatter
open my $file, '>', File::Spec->catfile($lib_directory, 'NumberFormatter.pm');
write_out_number_formatter($file);
close $file;

# Collator

=for comment

open my $file, '>', File::Spec->catfile($lib_directory, 'Collator.pm');
write_out_collator($file);
close $file;

=end

=cut

# Likely sub-tags
open $file, '>', File::Spec->catfile($lib_directory, 'LikelySubtags.pm');

say "Processing file $file_name" if $verbose;

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::LikelySubtags', $CLDR_VERSION, $xml, $file_name, 1);
process_likely_subtags($file, $xml);
process_footer($file, 1);
close $file;

# Numbering Systems
$file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'numberingSystems.xml'
);

$xml = XML::XPath->new(
    File::Spec->catfile($file_name));

open $file, '>', File::Spec->catfile($lib_directory, 'NumberingSystems.pm');

say "Processing file $file_name" if $verbose;

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::NumberingSystems', $CLDR_VERSION, $xml, $file_name, 1);
process_numbering_systems($file, $xml);
process_footer($file, 1);
close $file;

#Plaural rules
$file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'plurals.xml'
);

my $plural_xml = XML::XPath->new(
    File::Spec->catfile($file_name));
	
$file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'ordinals.xml'
);

my $ordanal_xml = XML::XPath->new(
    File::Spec->catfile($file_name));

open $file, '>', File::Spec->catfile($lib_directory, 'Plurals.pm');

say "Processing file $file_name" if $verbose;

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::Plurals', $CLDR_VERSION, $xml, $file_name, 1);
process_plurals($file, $plural_xml, $ordanal_xml);

$file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'pluralRanges.xml'
);

my $plural_ranges_xml = XML::XPath->new(
    File::Spec->catfile($file_name));

process_plural_ranges($file, $plural_ranges_xml);
process_footer($file, 1);
close $file;

# The supplemental/supplementalMetaData.xml file contains a list of all valid
# locale codes
$xml = XML::XPath->new(
    File::Spec->catfile($base_directory,
        'supplemental',
        'supplementalMetadata.xml',
    )
);

open $file, '>', File::Spec->catfile($lib_directory, 'ValidCodes.pm');

$file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'supplementalMetadata.xml'
);

say "Processing file $file_name" if $verbose;

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::ValidCodes', $CLDR_VERSION, $xml, $file_name, 1);
process_valid_languages($file, $xml);
process_valid_scripts($file, $xml);
process_valid_territories($file, $xml);
process_valid_variants($file, $xml);
process_valid_keys($file, $base_directory);
process_valid_language_aliases($file,$xml);
process_valid_territory_aliases($file,$xml);
process_valid_variant_aliases($file,$xml);
process_footer($file, 1);
close $file;

# File for era boundaries
$xml = XML::XPath->new(
    File::Spec->catfile($base_directory,
        'supplemental',
        'supplementalData.xml',
    )
);

open $file, '>', File::Spec->catfile($lib_directory, 'EraBoundries.pm');

$file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'supplementalData.xml'
);

say "Processing file $file_name" if $verbose;


# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::EraBoundries', $CLDR_VERSION, $xml, $file_name, 1);
process_era_boundries($file, $xml);
process_footer($file, 1);
close $file;

# Currency defaults
open $file, '>', File::Spec->catfile($lib_directory, 'Currencies.pm');
process_header($file, 'Locale::CLDR::Currencies', $CLDR_VERSION, $xml, $file_name, 1);
process_currency_data($file, $xml);
process_footer($file, 1);
close $file;

# Territory Containment
open $file, '>', File::Spec->catfile($lib_directory, 'TerritoryContainment.pm');
process_header($file, 'Locale::CLDR::TerritoryContainment', $CLDR_VERSION, $xml, $file_name, 1);
process_territory_containment_data($file, $xml);
process_footer($file, 1);
close $file;


# Calendar Preferences
open $file, '>', File::Spec->catfile($lib_directory, 'CalendarPreferences.pm');

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::CalendarPreferences', $CLDR_VERSION, $xml, $file_name, 1);
process_calendar_preferences($file, $xml);
process_footer($file, 1);
close $file;

#Week data
open $file, '>', File::Spec->catfile($lib_directory, 'WeekData.pm');

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::WeekData', $CLDR_VERSION, $xml, $file_name, 1);
process_week_data($file, $xml);
process_footer($file, 1);
close $file;

# Measurement System Data
open $file, '>', File::Spec->catfile($lib_directory, 'MeasurementSystem.pm');

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::MeasurementSystem', $CLDR_VERSION, $xml, $file_name, 1);
process_measurement_system_data($file, $xml);
process_footer($file, 1);
close $file;

# Transformations
make_path($transformations_directory) unless -d $transformations_directory;
opendir (my $dir, $transform_directory);
my $num_files = grep { -f File::Spec->catfile($transform_directory,$_)} readdir $dir;
my $count_files = 0;
rewinddir $dir;
my @transformation_list;

foreach my $file_name ( sort grep /^[^.]/, readdir($dir) ) {
    my $percent = ++$count_files / $num_files * 100;
    my $full_file_name = File::Spec->catfile($transform_directory, $file_name);
    say sprintf("Processing Transformation File %s: $count_files of $num_files, %.2f%% done", $full_file_name, $percent) if $verbose;
	$xml = XML::XPath->new($full_file_name);
    process_transforms($transformations_directory, $xml, $full_file_name);
}

=for comment

#Collation
# First convert the base collation file into a moose role
say "Copying base collation file" if $verbose;
open (my $Allkeys_in, '<', File::Spec->catfile($base_directory, 'uca', 'FractionalUCA.txt'));
open (my $Allkeys_out, '>', File::Spec->catfile($lib_directory, 'CollatorBase.pm'));
process_header($Allkeys_out, 'Locale::CLDR::CollatorBase', $CLDR_VERSION, undef, File::Spec->catfile($base_directory, 'uca', 'allkeys_CLDR.txt'), 1);
process_collation_base($Allkeys_in, $Allkeys_out);
process_footer($Allkeys_out,1);
close $Allkeys_in;
close $Allkeys_out;

=end

=cut

# Main directory
my $main_directory = File::Spec->catdir($base_directory, 'main');
opendir ( $dir, $main_directory);

# Count the number of files
$num_files = grep { -f File::Spec->catfile($main_directory,$_)} readdir $dir;
$count_files = 0;
rewinddir $dir;

my $segmentation_directory = File::Spec->catdir($base_directory, 'segments');
my $rbnf_directory = File::Spec->catdir($base_directory, 'rbnf');

my %territory_to_package;
# Sort files ASCIIbetically
my $en;
my $languages;
foreach my $file_name ( 'root.xml', 'en.xml', 'en_US.xml', sort grep /^[^.]/, readdir($dir) ) {
    if (@ARGV) {
        next unless grep {$file_name eq $_} @ARGV;
    }
    $xml = XML::XPath->new(
        File::Spec->catfile($main_directory, $file_name)
    );

    my $segment_xml = undef;
    if (-f File::Spec->catfile($segmentation_directory, $file_name)) {
        $segment_xml = XML::XPath->new(
            File::Spec->catfile($segmentation_directory, $file_name)
        );
    }

	my $rbnf_xml = undef;
	if (-f File::Spec->catfile($rbnf_directory, $file_name)) {
        $rbnf_xml = XML::XPath->new(
            File::Spec->catfile($rbnf_directory, $file_name)
        );
    }

    my @output_file_parts = output_file_name($xml);
    my $current_locale = lc $output_file_parts[0];

    my $package = join '::', @output_file_parts;
	
    $output_file_parts[-1] .= '.pm';

    my $out_directory = File::Spec->catdir(
        $locales_directory, 
        @output_file_parts[0 .. $#output_file_parts - 1]
    );

    make_path($out_directory) unless -d $out_directory;

	if (defined( my $t = $output_file_parts[2])) {
		$t =~ s/\.pm$//;
		push @{$territory_to_package{lc $t}}, join('::','Locale::CLDR',@output_file_parts[0,1],$t);
	}
	
	my $has_en = -e File::Spec->catfile($locales_directory, 'En', 'Any', 'Us.pm');
	if ($has_en && ! $en) {
		require lib;
		lib::import(undef,File::Spec->catdir($FindBin::Bin, 'lib'));
		require Locale::CLDR;
		$en = Locale::CLDR->new('en');
		$languages = $en->all_languages;
	}

    open $file, '>', File::Spec->catfile($locales_directory, @output_file_parts);

    my $full_file_name = File::Spec->catfile($base_directory, 'main', $file_name);
    my $percent = ++$count_files / $num_files * 100;
    say sprintf("Processing File %s: $count_files of $num_files, %.2f%% done", $full_file_name, $percent) if $verbose;

    # Note: The order of these calls is important
    process_class_any($locales_directory, @output_file_parts[0 .. $#output_file_parts -1]);
	
    process_header($file, "Locale::CLDR::Locales::$package", $CLDR_VERSION, $xml, $full_file_name, 0, $languages->{$current_locale});
    process_segments($file, $segment_xml) if $segment_xml;
	process_rbnf($file, $rbnf_xml) if $rbnf_xml;
    process_display_pattern($file, $xml);
    process_display_language($file, $xml);
    process_display_script($file, $xml);
    process_display_territory($file, $xml);
    process_display_variant($file, $xml);
    process_display_key($file, $xml);
    process_display_type($file,$xml);
    process_display_measurement_system_name($file, $xml);
    process_display_transform_name($file,$xml);
    process_code_patterns($file, $xml);
    process_orientation($file, $xml);
    process_exemplar_characters($file, $xml);
    process_ellipsis($file, $xml);
    process_more_information($file, $xml);
    process_delimiters($file, $xml);
	process_units($file, $xml);
    process_posix($file, $xml);
	process_list_patterns($file, $xml);
	process_context_transforms($file, $xml);
	process_numbers($file, $xml);
    process_calendars($file, $xml, $current_locale);
    process_time_zone_names($file, $xml);
    process_footer($file);

    close $file;
}

# Build Bundles and Distributions

my $out_directory = File::Spec->catdir($lib_directory, '..', '..', 'Bundle', 'Locale','CLDR');
make_path($out_directory) unless -d $out_directory;

# Territory bundles
my $territory_contains = $en->territory_contains();
my $territory_names = $en->all_territories();

foreach my $territory (keys %$territory_names) {
	$territory_names->{$territory} = ucfirst( lc $territory ) . '.pm' unless exists $territory_contains->{$territory};
}

foreach my $territory (sort keys %$territory_contains) {
	my $name = lc $territory_names->{$territory};
	$name=~tr/a-z0-9//cs;
	build_bundle($out_directory, $territory_contains->{$territory}, $name, $territory_names);
}

# Language bundles
foreach my $language (sort keys %$languages) {
	next if $language =~ /[_@]/;
	my @files = get_language_bundle_data(ucfirst lc $language);
	next unless @files;
	push @files, get_language_bundle_data(ucfirst lc "${language}.pm");
	my @packages = convert_files_to_packages(\@files);
	build_bundle($out_directory, \@packages, $language );
}

sub convert_files_to_packages {
	my $files = shift;
	my @packages;
	
	foreach my $file_name (@$files) {
		open my $file, $file_name or die "Bang $file_name: $!";
		my $package;
		($package) = (<$file> =~ /^package (.+);$/)
			until $package;

		close $file;
		push @packages, $package;
	}

	return @packages;
}

sub get_language_bundle_data {
	my ($language, $directory_name) = @_;
	
	$directory_name //= $locales_directory;
	
	my @packages;
	if ( -d (my $new_dir = File::Spec->catdir($directory_name, $language)) ) {
		opendir $dir, $new_dir;
		my @files = grep { ! /^\./ } readdir $dir;
		foreach my $file (@files) {
			push @packages, get_language_bundle_data($file, $new_dir);
		}
	}
	else {
		push @packages, File::Spec->catfile($directory_name, $language)
			if -f File::Spec->catfile($directory_name, $language);
	}
	return @packages;
}

# Transformation bundle
build_bundle($out_directory, \@transformation_list, 'Transformations');

# Base bundle
my @base_bundle = (
	'Locale::CLDR',
	'Locale::CLDR::CalendarPreferences',
	'Locale::CLDR::Currencies',
	'Locale::CLDR::EraBoundries',
	'Locale::CLDR::LikelySubtags',
	'Locale::CLDR::MeasurementSystem',
	'Locale::CLDR::NumberFormatter',
	'Locale::CLDR::NumberingSystems',
	'Locale::CLDR::Plurals',
	'Locale::CLDR::TerritoryContainment',
	'Locale::CLDR::ValidCodes',
	'Locale::CLDR::WeekData',
	'Locale::CLDR::Locales::En',
	'Locale::CLDR::Locales::En::Any',
	'Locale::CLDR::Locales::En::Any::Us',
	'Locale::CLDR::Locales::Root',
);

build_bundle($out_directory, \@base_bundle, 'Base');

# All Bundle
my @all_bundle = (
	'Locale::CLDR::Locales::World',
	'Locale::CLDR::Transformations',
);

build_bundle($out_directory, \@all_bundle, 'Everything');

# Now split everything into distributions

build_distributions();

my $duration = time() - $start_time;
my @duration;
$duration[2] = $duration % 60;
$duration = int($duration/60);
$duration[1] = $duration % 60;
$duration[0] = int($duration/60);

say "Duration: ", sprintf "%02i:%02i:%02i", @duration if $verbose;

# This sub looks for nodes along an xpath.
sub findnodes {
    my ($xpath, $path ) = @_;
    my $nodes = $xpath->findnodes($path);

    return $nodes;
}

# Calculate the output file name
sub output_file_name {
    my $xpath = shift;
    my @nodes;
    foreach my $name (qw( language script territory variant )) {
        my $nodes = findnodes($xpath, "/ldml/identity/$name");
        if ($nodes->size) {;
            push @nodes, $nodes->get_node->getAttribute('type');
        }
        else {
            push @nodes, 'Any';
        }
    };

    # Strip off Any's from end of list
    pop @nodes while $nodes[-1] eq 'Any';

    return map {ucfirst lc} @nodes;
}

# Fill in any missing script or territory with the pseudo class Any
sub process_class_any {
    my ($lib_path, @path_parts) = @_;
    
    my $package = 'Locale::CLDR::Locales';
    foreach my $path (@path_parts) {
        my $parent = $package;
        $parent = 'Locale::CLDR::Locales::Root' if $parent eq 'Locale::CLDR::Locales';
        $package .= "::$path";
        $lib_path = File::Spec->catfile($lib_path, $path);

        next unless $path eq 'Any';

        my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');
        open my $file, '>:utf8', "$lib_path.pm";
        print $file <<EOT;
package $package;

# This file auto generated
#\ton $now GMT

use version;

our \$VERSION = version->declare('v$VERSION');

use v5.10;
use mro 'c3';
use if \$^V ge v5.12.0, feature => 'unicode_strings';

use Moose;

extends('$parent');

no Moose;
__PACKAGE__->meta->make_immutable;
EOT
        close $file;
    }
}

# Process the elements of the file note
sub process_header {
    my ($file, $class, $version, $xpath, $xml_name, $isRole, $language) = @_;
    say "Processing Header" if $verbose;

    $isRole = $isRole ? '::Role' : '';

    $xml_name =~s/^.*(Data.*)$/$1/;
    my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');
    my $xml_generated = $xpath
		? ( findnodes($xpath, '/ldml/identity/generation')
			|| findnodes($xpath, '/supplementalData/generation')
			)->get_node->getAttribute('date')
		: '';

    $xml_generated=~s/^\$Date: (.*) \$$/$1/;
	$xml_generated = "# XML file generated $xml_generated" if $xml_generated;

	my $header = '';
	if ($language) {
		print $file <<EOT;
=head1

$class - Package for language $language

=cut

EOT
	}
	
	print $file <<EOT;
package $class;
# This file auto generated from $xml_name
#\ton $now GMT
$xml_generated

use version;

our \$VERSION = version->declare('v$VERSION');

use v5.10;
use mro 'c3';
use utf8;
use if \$^V ge v5.12.0, feature => 'unicode_strings';

use Moose$isRole;

EOT
    print $file $header;
	if (!$isRole && $class =~ /^Locale::CLDR::Locales::...?(?:::|$)/) {
		my ($parent) = $class =~ /^(.+)::/;
		$parent = 'Locale::CLDR::Locales::Root' if $parent eq 'Locale::CLDR::Locales';
		
		say $file "extends('$parent');" unless $isRole;
	}
}

=for comment

sub process_collation_base {
	my ($Allkeys_in, $Allkeys_out) = @_;

	print $Allkeys_out <<EOT;
has 'collation_base' => (
	is			=> 'ro',
	isa			=> 'HashRef',
	init_arg	=> undef,
	traits 		=> ['Hash'],
	handles		=> {
		_set_ce	=> 'set',
		get_collation_element	=> 'get',
	},
	default		=> sub {
		{
EOT
	
	my @character_sequences;
	my %top_bytes = ();
	my %ce = ();
	my ($max_variable, $min_variable);
	
	while (<$Allkeys_in>) {
		next if /^#/;
		next if /^$/;
		
		#Top Byte
		if (my ($top_byte, $category) = /^\[top_byte\t(\p{AHex}{2})\t([A-Za-z ]+)(?:\tCOMPRESS)? \]) {
			my @category = split / /, $category;
			@top_byte{@category} = (hex $top_byte) x @category;
		}
		# CE
		elsif (my ($character, $primary, $secondary, $tertiary) = /^((?:\p{AHex}{4,6}[| ]?)+; \[([^U+,]*),([^,]*),(.*?)\]/) {
			foreach ($primary, $secondary, $tertiary) {
				s/\s+//;
				my @bytes = map {chr hex} /(..)/g;
				$_ = join '', @bytes;
			}
			
			@character = split /[| ]+/, $character;
			$character = join '', map {chr hex} @character;
			
			push @character_sequences, $character if @character > 1;
			
			$primary .= "\0" x 3 - length $primary;
			$secondary .= "\0" x 2 - length $secondary;
			$tertiary .= "\0" x 2 - length $tertiary;
			$ce{$character} = [$primary, $secondary, $tertiary];
		}
		elsif (my ($character, $primary, $secondary, $tertiary) = /^((?:\p{AHex}{4,6}[| ]?)+; \[U+(\p{AHex}+)(,[^,]+)?(,(.*?)\]/) {
			my $same = $ce{chr hex $primary};
			foreach ($secondary, $tertiary) {
				next unless defined;
				s/\s+//;
				my @bytes = map {chr hex} /(..)/g;
				$_ = join '', @bytes;
			}
			
			if (defined $tertiary) {
				$same=~s/^(...)..../$1$secondary$tertiary/;
			}
			elsif (defined $secondary) {
				$same=~s/^(.....)../$1$secondary/;
			}
			
			$ce{$character} = $same;
		}
		
	my $character_sequences = join "','", 
		map {$_->[0]} 
		sort {$b->[1] <=> $a->[1]}
		map {[$_ => length $_]}
		@character_sequences;
	
	print $Allkeys_out <<EOT;
		}
	}
);

has min_variable => (
	is => 'ro',
	isa => 'Str',
	init_arg => undef,
	default => '$min_variable'
);

has max_variable => (
	is => 'ro',
	isa => 'Str',
	init_arg => undef,
	default => '$max_variable'
);

has '_sort_digraphs' => (
	is => 'ro',
	isa => 'ArrayRef',
	init_arg => undef,
	default => sub {['$character_sequences']},
	writer => '_set_sort_digraphs',
	reader => '_get_sort_digraphs',
);

EOT
}

=end

=cut

sub process_valid_languages {
    my ($file, $xpath) = @_;
    say "Processing Valid Languages"
        if $verbose;

    my $languages = findnodes($xpath,'/supplementalData/metadata/validity/variable[@id="$language"]');
    
    my @languages = map {"$_\n"} split /\s+/, $languages->get_node->string_value;

    print $file <<EOT
has 'valid_languages' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'ArrayRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tdefault\t=> sub {[qw( @languages \t)]},
);

EOT
}

sub process_valid_scripts {
    my ($file, $xpath) = @_;

    say "Processing Valid Scripts"
        if $verbose;

    my $scripts = findnodes($xpath, '/supplementalData/metadata/validity/variable[@id="$script"');

    my @scripts = map {"$_\n"} split /\s+/, $scripts->get_node->string_value;
    
    print $file <<EOT
has 'valid_scripts' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'ArrayRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tdefault\t=> sub {[qw( @scripts \t)]},
);

EOT
}

sub process_valid_territories {
    my ($file, $xpath) = @_;

    say "Processing Valid Territories"
        if $verbose;

    my $territories = findnodes($xpath, '/supplementalData/metadata/validity/variable[@id="$territory"');

    my @territories = map {"$_\n"} split /\s+/, $territories->get_node->string_value;

    print $file <<EOT
has 'valid_territories' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'ArrayRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tdefault\t=> sub {[qw( @territories \t)]},
);

EOT
}

sub process_valid_variants {
    my ($file, $xpath) = @_;

    say "Processing Valid Variants"
        if $verbose;

    my $variants = findnodes($xpath, '/supplementalData/metadata/validity/variable[@id="$variant"');

    my @variants = map {"$_\n" } split /\s+/, $variants->get_node->string_value;

    print $file <<EOT
has 'valid_variants' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'ArrayRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tdefault\t=> sub {[qw( @variants \t)]},
);

EOT
}

sub process_valid_keys {
    my ($file, $base_directory) = @_;

    say "Processing Valid Keys"
        if $verbose;

    opendir (my $dir, File::Spec->catdir($base_directory, 'bcp47'))
        || die "Can't open directory: $!";

    my @files = map {File::Spec->catfile($base_directory, 'bcp47', $_)}
        grep /\.xml \z/xms, readdir $dir;

    closedir $dir;
    my %keys;
    foreach my $file_name (@files) {
        my $xml = XML::XPath->new(
            $file_name
        );

        my @keys = findnodes($xml, '/ldmlBCP47/keyword/key')->get_nodelist;
        foreach my $key (@keys) {
            my ($name, $alias) = ($key->getAttribute('name'), $key->getAttribute('alias'));
            $keys{$name}{alias} = $alias;
            my @types = findnodes($xml,qq(/ldmlBCP47/keyword/key[\@name="$name"]/type))->get_nodelist;
            foreach my $type (@types) {
                push @{$keys{$name}{type}}, $type->getAttribute('name');
                push @{$keys{$name}{type}}, $type->getAttribute('alias')
                    if length $type->getAttribute('alias');
            }
        }
    }

    print $file <<EOT;
has 'key_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tdefault\t=> sub { return {
EOT
    foreach my $key (sort keys %keys) {
        my $alias = lc $keys{$key}{alias};
        next unless $alias;
        say $file "\t\t'$key' => '$alias',";
    }
    print $file <<EOT;
\t}},
);

has 'key_names' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tlazy\t\t=> 1,
\tdefault\t=> sub { return { reverse shift()->key_aliases }; },
);

has 'valid_keys' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tdefault\t=> sub { return {
EOT
    
    foreach my $key (sort keys %keys) {
        my @types = @{$keys{$key}{type} // []};
        say $file "\t\t$key\t=> [";
        print $file map {"\t\t\t'$_',\n"} @types;
        say $file "\t\t],";
    }

    print $file <<EOT;
\t}},
);

EOT
}

sub process_valid_language_aliases {
    my ($file, $xpath) = @_;

    say "Processing Valid Language Aliases"
        if $verbose;

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/languageAlias');
    print $file <<EOT;
has 'language_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { return {
EOT
    foreach my $node ($aliases->get_nodelist) {
        my $from = $node->getAttribute('type');
        my $to = $node->getAttribute('replacement');
        say $file "\t'$from' => '$to',";
    }
    print $file <<EOT;
\t}},
);
EOT
}

sub process_valid_territory_aliases {
    my ($file, $xpath) = @_;

    say "Processing Valid Territory Aliases"
        if $verbose;

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/territoryAlias');
    print $file <<EOT;
has 'territory_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { return {
EOT
    foreach my $node ($aliases->get_nodelist) {
        my $from = $node->getAttribute('type');
        my $to = $node->getAttribute('replacement');
        say $file "\t'$from' => [qw($to)],";
    }
    print $file <<EOT;
\t}},
);
EOT

}

sub process_valid_variant_aliases {
    my ($file, $xpath) = @_;

    say "Processing Valid Variant Aliases"
        if $verbose;

    print $file <<EOT;
has 'variant_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { return {
\t\tbokmal\t\t=> { language\t=> 'nb' },
\t\tnynorsk\t\t=> { language\t=> 'nn' },
\t\taaland\t\t=> { territory\t=> 'AX' },
\t\tpolytoni\t=> { variant\t=> 'POLYTON' },
\t\tsaaho\t\t=> { language\t=> 'ssy' },
\t}},
);
EOT
}

sub process_likely_subtags {
	my ($file, $xpath) = @_;
	
	my $subtags = findnodes($xpath,
        q(/supplementalData/likelySubtags/likelySubtag));
		
	print $file <<EOT;
has 'likely_subtags' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { return {
EOT

foreach my $subtag ($subtags->get_nodelist) {
	my $from = $subtag->getAttribute('from');
	my $to = $subtag->getAttribute('to');
	
	print $file "\t\t'$from'\t=> '$to',\n";
}

print $file <<EOT;
\t}},
);

EOT
}

sub process_numbering_systems {
	my ($file, $xpath) = @_;
	
	my $systems = findnodes($xpath,
        q(/supplementalData/numberingSystems/numberingSystem));
		
	print $file <<EOT;
has 'numbering_system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { return {
EOT

foreach my $system ($systems->get_nodelist) {
	my $id = $system->getAttribute('id');
	my $type = $system->getAttribute('type');
	my $data;
	if ($type eq 'numeric') {
		$data = '[qw(' . join(' ', split //, $system->getAttribute('digits')) . ')]';
	}
	else {
		$data = "'" . $system->getAttribute('rules') . "'";
	}
	
	print $file <<EOT;
\t\t'$id'\t=> {
\t\t\ttype\t=> '$type',
\t\t\tdata\t=> $data,
\t\t},
EOT
}

print $file <<EOT;
\t}},
);

has '_default_numbering_system' => ( 
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t=> '',
\ttraits\t=> ['String'],
\thandles\t=> {
\t\t_set_default_nu\t\t=> 'append',
\t\t_clear_default_nu\t=> 'clear',
\t\t_test_default_nu\t=> 'length',
\t},
);

sub default_numbering_system {
	my \$self = shift;
	
	if(\$self->_test_default_nu) {
		return \$self->_default_numbering_system;
	}
	else {
		my \$numbering_system = \$self->_find_bundle('default_numbering_system')->default_numbering_system;
		\$self->_set_default_nu(\$numbering_system);
		return \$numbering_system
	}
}

EOT
}

sub process_era_boundries {
    my ($file, $xpath) = @_;

    say "Processing Era Boundries"
        if $verbose;
    
    my $calendars = findnodes($xpath,
        q(/supplementalData/calendarData/calendar));
    
    print $file <<EOT;
has '_era_boundry' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'CodeRef',
\ttraits\t\t=> ['Code'],
\thandles\t\t=> { era_boundry => 'execute_method' },
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { sub {
\t\tmy (\$self, \$type, \$date) = \@_;
\t\t# \$date in yyyymmdd format
\t\tmy \$return = -1;
\t\tSWITCH:
\t\tfor (\$type) {
EOT
    foreach my $calendar ($calendars->get_nodelist) {
        my $type = $calendar->getAttribute('type');
        say $file "\t\t\tif (\$_ eq '$type') {";
        my $eras = findnodes($xpath,
            qq(/supplementalData/calendarData/calendar[\@type="$type"]/eras/era)
        );
        foreach my $era ($eras->get_nodelist) {
            my ($type, $start, $end) = (
                $era->getAttribute('type'),
                $era->getAttribute('start'),
                $era->getAttribute('end'),
            );
            if (length $start) {
                my ($y, $m, $d) = split /-/, $start;
				die $start unless length "$y$m$d";
                $m //= 0;
                $d //= 0;
				$y //= 0;
                $start = sprintf('%d%0.2d%0.2d',$y,$m,$d);
				$start =~ s/^0+//;
                say $file "\t\t\t\t\$return = $type if \$date >= $start;";
            }
            if (length $end) {
                my ($y, $m, $d) = split /-/, $end;
                $m //= '0';
                $d //= '0';
                $end = sprintf('%d%0.2d%0.2d',$y,$m,$d);
				$end =~ s/^0+//;
                say $file "\t\t\t\t\$return = $type if \$date <= $end;";
            }
        }
        say $file "\t\t\tlast SWITCH";
        say $file "\t\t\t}";
    }
    print $file <<EOT;
\t\t} return \$return; }
\t}
);

EOT
}

sub process_week_data {
    my ($file, $xpath) = @_;

    say "Processing Week Data"
        if $verbose;
    
    my $week_data_min_days = findnodes($xpath, 
        q(/supplementalData/weekData/minDays));
    
    print $file <<EOT;
has '_week_data_min_days' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_min_days->get_nodelist) {
        my @territories = split /\s+/,$node->getAttribute('territories');
		shift @territories if $territories[0] eq '';
        my $count = $node->getAttribute('count');
        foreach my $territory (@territories) {
            say $file "\t\t'$territory' => $count,";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
    
    my $week_data_first_day = findnodes($xpath,
        q(/supplementalData/weekData/firstDay));

    print $file <<EOT;
has '_week_data_first_day' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_first_day->get_nodelist) {
        my @territories = split /\s+/,$node->getAttribute('territories');
		shift @territories if $territories[0] eq '';
        my $day = $node->getAttribute('day');
        foreach my $territory (@territories) {
            say $file "\t\t'$territory' => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
    
    my $week_data_weekend_start= findnodes($xpath,
        q(/supplementalData/weekData/weekendStart));

    print $file <<EOT;
has '_week_data_weekend_start' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_weekend_start->get_nodelist) {
        my @territories = split /\s+/,$node->getAttribute('territories');
		shift @territories if $territories[0] eq '';
        my $day = $node->getAttribute('day');
        foreach my $territory (@territories) {
            say $file "\t\t'$territory' => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
    
    my $week_data_weekend_end = findnodes($xpath,
        q(/supplementalData/weekData/weekendEnd));

    print $file <<EOT;
has '_week_data_weekend_end' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_weekend_end->get_nodelist) {
        my @territories = split /\s+/,$node->getAttribute('territories');
        my $day = $node->getAttribute('day');
        foreach my $territory (@territories) {
            say $file "\t\t'$territory' => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
    
}

sub process_calendar_preferences {
    my ($file, $xpath) = @_;

    say "Processing Calendar Preferences"
        if $verbose;
    
    my $calendar_preferences = findnodes($xpath, 
        q(/supplementalData/calendarPreferenceData/calendarPreference));
    
    print $file <<EOT;
has 'calendar_preferences' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($calendar_preferences->get_nodelist) {
        my @territories = split / /,$node->getAttribute('territories');
        my @ordering = split / /, $node->getAttribute('ordering');
        foreach my $territory (@territories) {
            say $file "\t\t'$territory' => ['", join("','", @ordering), "'],";
        }
    }
    print $file <<EOT;
\t}},
);

has '_default_calendar' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { { } },
\ttraits\t=> ['Hash'],
\thandles\t=> {
\t\t_set_default_ca  => 'set',
\t\t_get_default_ca  => 'get',
\t\t_test_default_ca => 'exists',
\t},
);

sub default_calendar {
\tmy (\$self, \$territory) = \@_;

\t\$territory //= ( \$self->territory_id() || \$self->likely_subtag->territory_id );
\tif (\$self->_test_default_ca(\$territory)) {
\t\treturn \$self->_get_default_ca(\$territory);
\t}

\tmy \$calendar_preferences = \$self->calendar_preferences();

\tmy \$default;

\tmy \$current_territory = \$territory;

\twhile (! \$default) {
\t\t\$default = \$calendar_preferences->{\$current_territory};
\t\tif (\$default) {
\t\t\t\$default = \$default->[0];
\t\t}
\t\telse {
\t\t\t\$current_territory = \$self->territory_contained_by()->{\$current_territory}
\t\t}
\t}

\t\$self->_set_default_ca(\$territory => \$default);

\treturn \$default;
}
EOT
}

sub process_valid_timezone_aliases {
    my ($file, $xpath) = @_;

    say "Processing Valid Time Zone Aliases"
        if $verbose;

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/zoneAlias');
    print $file <<EOT;
has 'zone_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($aliases->get_nodelist) {
        my $from = $node->getAttribute('type');
        my $to = $node->getAttribute('replacement');
        say $file "\t'$from' => '$to',";
    }
    print $file <<EOT;
\t}},
);
EOT

}

sub process_display_pattern {
    my ($file, $xpath) = @_;

    say "Processing Display Pattern"
        if $verbose;

    my $display_pattern = 
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localePattern');
    return unless $display_pattern->size;
    $display_pattern = $display_pattern->get_node->string_value;

    my $display_seperator = 
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localeSeparator');
    $display_seperator = $display_seperator->size ? $display_seperator->get_node->string_value : '';

    my $display_key_type = 
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localeKeyTypePattern');
    $display_key_type = $display_key_type->size ? $display_key_type->get_node->string_value : '';

    return unless defined $display_pattern;
    foreach ($display_pattern, $display_seperator, $display_key_type) {
        s/\//\/\//g;
        s/'/\\'/g;
    }

    print $file <<EOT;
# Need to add code for Key type pattern
sub display_name_pattern {
\tmy (\$self, \$name, \$territory, \$script, \$variant) = \@_;

\tmy \$display_pattern = '$display_pattern';
\t\$display_pattern =~s/\\\{0\\\}/\$name/g;
\tmy \$subtags = join '$display_seperator', grep {\$_} (
\t\t\$territory,
\t\t\$script,
\t\t\$variant,
\t);

\t\$display_pattern =~s/\\\{1\\\}/\$subtags/g;
\treturn \$display_pattern;
}

EOT
}

sub process_display_language {
    my ($file, $xpath) = @_;
    say "Processing Display Language"
        if $verbose;

    my $languages = findnodes($xpath,'/ldml/localeDisplayNames/languages/language');

    return unless $languages->size;
    my @languages = $languages->get_nodelist;
    foreach my $language (@languages) {
        my $type = $language->getAttribute('type');
        my $variant = $language->getAttribute('alt');
        if ($variant) {
            $type .= "\@alt=$variant";
        }
        my $name = $language->getChildNode(1);
        next unless $name;
        $name = $name->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $language = "\t\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display_name_language' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'CodeRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t sub {
\t\t\t my %languages = (
@languages
\t\t\t);
\t\t\tif (\@_) {
\t\t\t\treturn \$languages{\$_[0]};
\t\t\t}
\t\t\treturn \\%languages;
\t\t}
\t},
);

EOT
}

sub process_display_script {
    my ($file, $xpath) = @_;

    say "Processing Display Script"
        if $verbose;

    my $scripts = findnodes($xpath, '/ldml/localeDisplayNames/scripts/script');

    return unless $scripts->size;
    my @scripts = $scripts->get_nodelist;
    foreach my $script (@scripts) {
        my $type = $script->getAttribute('type');
        my $variant = $script->getAttribute('alt');
        if ($variant) {
            $type .= "\@alt=$variant";
        }
        my $name = $script->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $script = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display_name_script' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'CodeRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub {
\t\tsub {
\t\t\tmy %scripts = (
@scripts
\t\t\t);
\t\t\tif ( \@_ ) {
\t\t\t\treturn \$scripts{\$_[0]};
\t\t\t}
\t\t\treturn \\%scripts;
\t\t}
\t}
);

EOT
}

sub process_display_territory {
    my ($file, $xpath) = @_;

    say "Processing Display Territory"
        if $verbose;

    my $territories = findnodes($xpath, '/ldml/localeDisplayNames/territories/territory');

    return unless $territories->size;
    my @territories = $territories->get_nodelist;
    foreach my $territory (@territories) {
        my $type = $territory->getAttribute('type');
        my $variant = $territory->getAttribute('alt');
        if ($variant) {
            $type .= "\@alt=$variant";
        }

        my $node = $territory->getChildNode(1);
        my $name = $node ? $node->getValue : '';
        $name =~s/\\/\/\\/g;
        $name =~s/'/\\'/g;
        $territory = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display_name_territory' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@territories
\t\t}
\t},
);

EOT
}

sub process_display_variant {
    my ($file, $xpath) = @_;

    say "Processing Display Variant"
        if $verbose;

    my $variants= findnodes($xpath, '/ldml/localeDisplayNames/variants/variant');

    return unless $variants->size;
    my @variants = $variants->get_nodelist;
    foreach my $variant (@variants) {
        my $type = $variant->getAttribute('type');
        my $variant_attr = $variant->getAttribute('alt');
        if ($variant_attr) {
            $type .= "\@alt=$variant_attr";
        }
        my $name = $variant->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $variant = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display_name_variant' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@variants
\t\t}
\t},
);

EOT
}

sub process_display_key {
    my ($file, $xpath) = @_;

    say "Processing Display Key"
        if $verbose;

    my $keys= findnodes($xpath, '/ldml/localeDisplayNames/keys/key');

    return unless $keys->size;
    my @keys = $keys->get_nodelist;
    foreach my $key (@keys) {
        my $type = lc $key->getAttribute('type');
        my $name = $key->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $key = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display_name_key' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@keys
\t\t}
\t},
);

EOT
}

sub process_display_type {
    my ($file, $xpath) = @_;

    say "Processing Display Type"
        if $verbose;

    my $types = findnodes($xpath, '/ldml/localeDisplayNames/types/type');
    return unless $types->size;

    my @types = $types->get_nodelist;
    my %values;
    foreach my $type_node (@types) {
        my $type = lc $type_node->getAttribute('type');
        my $key  = lc $type_node->getAttribute('key');
        my $value = $type_node->getChildNode(1)->getValue;
        $type //= 'default';
        $values{$key}{$type} = $value;
    }
    @types = ();
    foreach my $key (sort keys %values) {
        push @types, "\t\t\t'$key' => {\n";
        foreach my $type (sort keys %{$values{$key}}) {
            push @types, "\t\t\t\t'$type' => q{$values{$key}{$type}},\n";
        }
        push @types, "\t\t\t},\n";
    }

    print $file <<EOT;
has 'display_name_type' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[HashRef[Str]]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@types
\t\t}
\t},
);

EOT
}

sub process_display_measurement_system_name {
    my ($file, $xpath) = @_;

    say "Processing Display Mesurement System"
        if $verbose;

    my $names = findnodes($xpath, '/ldml/localeDisplayNames/measurementSystemNames/measurementSystemName');
    return unless $names->size;

    my @names = $names->get_nodelist;
    foreach my $name (@names) {
        my $type = $name->getAttribute('type');
        my $value = $name->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $name = "\t\t\t'$type' => q{$value},\n";
    }

    print $file <<EOT;
has 'display_name_measurement_system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@names
\t\t}
\t},
);

EOT
}

sub process_display_transform_name {
    my ($file, $xpath) = @_;

    say "Processing Display Transform Names"
        if $verbose;

    my $names = findnodes($xpath, '/ldml/localeDisplayNames/transformNames/transformName');
    return unless $names->size;

    my @names = $names->get_nodelist;
    foreach my $name (@names) {
        my $type = lc $name->getAttribute('type');
        my $value = $name->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $name = "\t\t\t'$type' => '$value',\n";
    }

    print $file <<EOT;
has 'display_name_transform_name' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@names
\t\t}
\t},
);

EOT
}

sub process_code_patterns {
    my ($file, $xpath) = @_;
    say "Processing Code Patterns"
        if $verbose;

    my $patterns = findnodes($xpath, '/ldml/localeDisplayNames/codePatterns/codePattern');
    return unless $patterns->size;

    my @patterns = $patterns->get_nodelist;
    foreach my $pattern (@patterns) {
        my $type = $pattern->getAttribute('type');
        my $value = $pattern->getChildNode(1)->getValue;
        $pattern =~s/\\/\\\\/g;
        $pattern =~s/'/\\'/g;
        $pattern = "\t\t\t'$type' => '$value',\n";
    }

    print $file <<EOT;
has 'display_name_code_patterns' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@patterns
\t\t}
\t},
);

EOT
}

sub process_orientation {
    my ($file, $xpath) = @_;

    say "Processing Orientation" if $verbose;
    my $character_orientation = findnodes($xpath, '/ldml/layout/orientation/characterOrder');
    my $line_orientation = findnodes($xpath, '/ldml/layout/orientation/lineOrder');
    return unless $character_orientation->size 
        || $line_orientation->size;

    my ($lines) = $line_orientation->get_nodelist;
        $lines = ($lines && $lines->getChildNode(1)->getValue) || '';
    my ($characters) = $character_orientation->get_nodelist;
        $characters = ($characters && $characters->getChildNode(1)->getValue) || '';

    print $file <<EOT;
has 'text_orientation' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { return {
\t\t\tlines => '$lines',
\t\t\tcharacters => '$characters',
\t\t}}
);

EOT
}

sub process_exemplar_characters {
    my ($file, $xpath) = @_;

    say "Processing Exemplar Characters" if $verbose;
    my $characters = findnodes($xpath, '/ldml/characters/exemplarCharacters');
    return unless $characters->size;

    my @characters = $characters->get_nodelist;
    my %data;
    foreach my $node (@characters) {
        my $regex = $node->getChildNode(1)->getValue;
		next if $regex =~ /^\[\s*\]/;
        my $type = $node->getAttribute('type');
        $type ||= 'main';
        if ($type eq 'index') {
            my ($entries) = $regex =~ m{\A \s* \[ (.*) \] \s* \z}msx;
            $entries = join "', '", split( /\s+/, $entries);
            $entries =~ s{\{\}}{}g;
            $data{index} = "['$entries'],";
        }
        else {
		    $regex = unicode_to_perl($regex);
            $data{$type} = "qr{$regex},";
        }
    }
    print $file <<EOT;
has 'characters' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> \$^V ge v5.18.0
\t? eval <<'EOT'
\tsub {
\t\tno warnings 'experimental::regex_sets';
\t\treturn {
EOT
    foreach my $type (sort keys %data) {
        say $file "\t\t\t$type => $data{$type}";
    }
    print $file <<EOFILE;
\t\t};
\t},
EOT
: sub {
EOFILE
if ($data{index}) {
	say $file "\t\treturn { index => $data{index} };"
}
else {
	say $file "\t\treturn {};";
}

say $file <<EOFILE
},
);

EOFILE
}

sub process_ellipsis {
    my ($file, $xpath) = @_;

    say "Processing Ellipsis" if $verbose;
    my $ellipsis = findnodes($xpath, '/ldml/characters/ellipsis');
    return unless $ellipsis->size;
    my @ellipsis = $ellipsis->get_nodelist;
    my %data;
    foreach my $node (@ellipsis) {
        my $pattern = $node->getChildNode(1)->getValue;
        my $type = $node->getAttribute('type');
        $data{$type} = $pattern;
    }
    print $file <<EOT;
has 'ellipsis' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub {
\t\treturn {
EOT
    foreach my $type (sort keys %data) {
        say $file "\t\t\t'$type' => '$data{$type}',";
    }
    print $file <<EOT;
\t\t};
\t},
);

EOT
}

sub process_more_information {
    my ($file, $xpath) = @_;

    say 'Processing More Information' if $verbose;
    my $info = findnodes($xpath, '/ldml/characters/moreInformation');
    return unless $info->size;
    my @info = $info->get_nodelist;
    $info = $info[0]->getChildNode(1)->getValue;

    print $file <<EOT;
has 'more_information' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> qq{$info},
);

EOT
}

sub process_delimiters {
    my ($file, $xpath) = @_;

    say 'Processing Delimiters' if $verbose;
    my %quote;
    $quote{quote_start}             = findnodes($xpath, '/ldml/delimiters/quotationStart');
    $quote{quote_end}               = findnodes($xpath, '/ldml/delimiters/quotationEnd');
    $quote{alternate_quote_start}   = findnodes($xpath, '/ldml/delimiters/alternateQuotationStart');
    $quote{alternate_quote_end}     = findnodes($xpath, '/ldml/delimiters/alternateQuotationEnd');

    return unless $quote{quote_start}->size 
        || $quote{quote_end}->size 
        || $quote{alternate_quote_start}->size
        || $quote{alternate_quote_end}->size;

    foreach my $quote (qw(quote_start quote_end alternate_quote_start alternate_quote_end)) {
        next unless ($quote{$quote}->size);
        
        my @quote = $quote{$quote}->get_nodelist;
        my $value = $quote[0]->getChildNode(1)->getValue;
        
        print $file <<EOT;
has '$quote' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> qq{$value},
);

EOT
    }
}

sub process_measurement_system_data {
	my ($file, $xpath) = @_;
	
	say 'Processing Measurement System Data' if $verbose;
	my $measurementData = findnodes($xpath, '/supplementalData/measurementData/*');
	return unless $measurementData->size;
	
	my @measurementSystem;
	my @paperSize;
	
	foreach my $measurement ($measurementData->get_nodelist) {
		my $what = $measurement->getLocalName;
		my $type = $measurement->getAttribute('type');
		my $territories = $measurement->getAttribute('territories');
		
		push @{$what eq 'measurementSystem' ? \@measurementSystem : \@paperSize },
			[$type, $territories ];
	}
	
	print $file <<EOT;
has 'measurement_system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $measurement ( @measurementSystem ) {
		foreach my $territory (split /\s+/, $measurement->[1]) {
			say $file "\t\t\t\t'$territory'\t=> '$measurement->[0]',";
		}
	}
	
	print $file <<EOT;
\t\t\t} },
);

EOT
	
	print $file <<EOT;
has 'paper_size' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $paper_size ( @paperSize) {
		foreach my $territory (split /\s+/, $paper_size->[1]) {
			say $file "\t\t\t\t'$territory'\t=> '$paper_size->[0]',";
		}
	}
	
	print $file <<EOT;
\t\t\t} },
);

EOT
}

sub process_units {
    my ($file, $xpath) = @_;

    say 'Processing Units' if $verbose;
	my $units = findnodes($xpath, '/ldml/units/*');
    return unless $units->size;
	
    my (%units, %aliases, %duration_units);
    foreach my $length_node ($units->get_nodelist) {
		my $length = $length_node->getAttribute('type');
		my $units = findnodes($xpath, qq(/ldml/units/unitLength[\@type="$length"]/*));
		my $duration_units = findnodes($xpath, qq(/ldml/units/durationUnit[\@type="$length"]/durationUnitPattern));
		
		foreach my $duration_unit ($duration_units->get_nodelist) {
			my $patten = $duration_unit->getChildNode(1)->getValue;
			$duration_units{$length} = $patten;
		}
			
		my $unit_alias = findnodes($xpath, qq(/ldml/units/unitLength[\@type="$length"]/alias));
		if ($unit_alias->size) {
			my ($node) = $unit_alias->get_nodelist;
			my $path = $node->getAttribute('path');
			my ($type) = $path =~ /\[\@type=['"](.*)['"]\]/;
			$aliases{$length} = $type;
		}
		
		foreach my $unit_type ($units->get_nodelist) {
			my $unit_type_name = $unit_type->getAttribute('type');
			$unit_type_name =~ s/^[^\-]+-//;
			foreach my $unit_pattern ($unit_type->getChildNodes) {
				next if $unit_pattern->isTextNode;
				my $count = $unit_pattern->getAttribute('count') // 1;
				my $pattern = $unit_pattern->getChildNode(1)->getValue;
				$units{$length}{$unit_type_name}{$count} = $pattern;
			}
		}
    }
    
	if (keys %duration_units) {
		print $file <<EOT;
has 'duration_units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $type (sort keys %duration_units) {
			say $file "\t\t\t\t$type => '$duration_units{$type}',";
		}
	
		print $file <<EOT;
\t\t\t} }
);

EOT
	}
	
	if (keys %aliases) {
		print $file <<EOT;
has 'unit_alias' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $from (sort keys %aliases) {
			say $file "\t\t\t\t$from => '$aliases{$from}',";
		}
	
		print $file <<EOT;
\t\t\t} }
);

EOT
	}
	
    print $file <<EOT;
has 'units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[HashRef[HashRef[Str]]]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
    foreach my $length (sort keys %units) {
        say $file "\t\t\t\t'",$length,"' => {";
        foreach my $type (sort keys %{$units{$length}}) {
            say $file "\t\t\t\t\t'$type' => {";
                foreach my $count (sort keys %{$units{$length}{$type}}) {
                    say $file "\t\t\t\t\t\t'$count' => q(",
                        $units{$length}{$type}{$count},
                        "),";
                }
            say $file "\t\t\t\t\t},";
        }
        say $file "\t\t\t\t},";
    }
    print $file <<EOT;
\t\t\t} }
);

EOT
}

sub process_posix {
    my ($file, $xpath) = @_;

    say 'Processing Posix' if $verbose;
    my $yes = findnodes($xpath, '/ldml/posix/messages/yesstr/text()');
    my $no  = findnodes($xpath, '/ldml/posix/messages/nostr/text()');
    return unless $yes->size || $no->size;
    $yes = $yes->size
      ? ($yes->get_nodelist)[0]->getValue()
      : '';

    $no = $no->size
      ? ($no->get_nodelist)[0]->getValue()
      : '';
        
    $yes .= ':yes:y' unless (grep /^y/i, split /:/, "$yes:$no");
    $no  .= ':no:n'  unless (grep /^n/i, split /:/, "$yes:$no");

    s/:/|/g foreach ($yes, $no);

    print $file <<EOT if defined $yes;
has 'yesstr' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'RegexpRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { qr'^(?i:$yes)\$' }
);

EOT

    print $file <<EOT if defined $no;
has 'nostr' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'RegexpRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { qr'^(?i:$no)\$' }
);

EOT
}

# List patterns
#/ldml/listPatterns/
sub process_list_patterns {
	my ($file, $xpath) = @_;
	
	say "Processing List Patterns" if $verbose;
	
	my $patterns = findnodes($xpath, '/ldml/listPatterns/listPattern/listPatternPart');
	
	return unless $patterns->size;
	
	my %patterns;
	foreach my $pattern ($patterns->get_nodelist) {
		my $type = $pattern->getAttribute('type');
		my $text = $pattern->getChildNode(1)->getValue;
		$patterns{$type} = $text;
	}
	
	print $file <<EOT;
has 'listPatterns' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
	my %sort_lookup = (start => 0, middle => 1, end => 2, 2 => 3, 3 => 4);
	no warnings;
	foreach my $type ( sort { 
		(($a + 0) <=> ($b + 0)) 
		|| ( $sort_lookup{$a} <=> $sort_lookup{$b}) 
	} keys %patterns ) {
		say $file "\t\t\t\t$type => q($patterns{$type}),"
	}
	
	print $file <<EOT;
\t\t} }
);

EOT

}

#/ldml/contextTransforms
sub process_context_transforms {
	my ($file, $xpath) = @_;
	# TODO fix this up
}

#/ldml/numbers
sub process_numbers {
	my ($file, $xpath) = @_;
	
	say "Processing Numbers" if $verbose;

	my $default_numbering_system = '';
	my $nodes = findnodes($xpath, '/ldml/numbers/defaultNumberingSystem/text()');
	if ($nodes->size) {
		$default_numbering_system = ($nodes->get_nodelist)[0]->getValue;
	}
	
	# Other Numbering systems
	my %other_numbering_systems;
	$other_numbering_systems{native} = '';
	$nodes = findnodes($xpath, '/ldml/numbers/otherNumberingSystems/native/text()');
	if ($nodes->size) {
		$other_numbering_systems{native} = ($nodes->get_nodelist)[0]->getValue;
	}
	
	$other_numbering_systems{traditional} =  '';
	$nodes = findnodes($xpath, '/ldml/numbers/otherNumberingSystems/traditional/text()');
	if ($nodes->size) {
		$other_numbering_systems{traditional} =  ($nodes->get_nodelist)[0]->getValue;
	}
	
	$other_numbering_systems{finance} =  '';
	$nodes = findnodes($xpath, '/ldml/numbers/otherNumberingSystems/finance/text()');
	if ($nodes->size) {
		$other_numbering_systems{finance} = ($nodes->get_nodelist)[0]->getValue;
	}
	
	# Symbols
	my %symbols;
	my $symbols_nodes = findnodes($xpath, '/ldml/numbers/symbols');
	foreach my $symbols ($symbols_nodes->get_nodelist) {
		my $type = $symbols->getAttribute('numberSystem');
		foreach my $symbol ( qw( alias decimal group list percentSign minusSign plusSign exponential superscriptingExponent perMille infinity nan ) ) {
			if ($symbol eq 'alias') {
				my $nodes = findnodes($xpath, qq(/ldml/numbers/symbols[\@numberSystem="$type"]/$symbol/\@path));
				next unless $nodes->size;
				my ($alias) = ($nodes->get_nodelist)[0]->getValue =~ /\[\@numberSystem='(.*?)'\]/;
				$symbols{$type}{alias} = $alias;
			}
			else {
				my $nodes = findnodes($xpath, qq(/ldml/numbers/symbols[\@numberSystem="$type"]/$symbol/text()));
				next unless $nodes->size;
				$symbols{$type}{$symbol} = ($nodes->get_nodelist)[0]->getValue;
			}
		}
	}
	
	# Formats
	my %formats;
	foreach my $format_type ( qw( decimalFormat percentFormat scientificFormat ) ) {
		my $format_nodes = findnodes($xpath, qq(/ldml/numbers/${format_type}s));
		foreach my $format_node ($format_nodes->get_nodelist) {
			my $number_system = $format_node->getAttribute('numberSystem');
			my $format_xpath = qq(/ldml/numbers/${format_type}s[\@numberSystem="$number_system"]);
			$format_xpath = qq(/ldml/numbers/${format_type}s[not(\@numberSystem)]) unless $number_system;
			my $format_alias_nodes = findnodes($xpath, "$format_xpath/alias");
			if ($format_alias_nodes->size) {
				my ($alias) = ($format_alias_nodes->get_nodelist)[0]->getAttribute('path') =~ /\[\@numberSystem='(.*?)'\]/;
				$formats{$number_system || 'default'}{alias} = $alias;
			}
			else {
				my $format_nodes_length = findnodes($xpath, "/ldml/numbers/${format_type}s/${format_type}Length");
				foreach my $format_node ( $format_nodes_length->get_nodelist ) { 
					my $length_type = $format_node->getAttribute('type');
					my $attribute = $length_type ? qq([\@type="$length_type"]) : '';
					my $nodes = findnodes($xpath, "/ldml/numbers/${format_type}s/${format_type}Length$attribute/$format_type/alias/\@path");
					if ($nodes->size) {
						my $alias = ($nodes->get_nodelist)[0]->getValue =~ /${format_type}Length\[\@type='(.*?)'\]/;
						$formats{$format_type}{$length_type || 'default'}{alias} = $alias;
					}
					else { 
						my $pattern_nodes = findnodes($xpath, "/ldml/numbers/${format_type}s/${format_type}Length$attribute/$format_type/pattern");
						foreach my $pattern ($pattern_nodes->get_nodelist) {
							my $pattern_type = $pattern->getAttribute('type') || 0;
							my $pattern_count = $pattern->getAttribute('count') // 'default';
							my $pattern_text = $pattern->getChildNode(1)->getValue();
							$formats{$format_type}{$length_type || 'default'}{$pattern_type}{$pattern_count} = $pattern_text;
						}
					}
				}
			}
		}
	}
	
	# Currency Formats
	my %currency_formats;
	my $currency_format_nodes = findnodes($xpath, "/ldml/numbers/currencyFormats");
	foreach my $currency_format_node ($currency_format_nodes->get_nodelist) {
		my $number_system = $currency_format_node->getAttribute('numberSystem') // 'latn';
		
		# Check for alias
		my $alias_nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number_system"]/alias));
		if ($alias_nodes->size) {
			my $alias_node = ($alias_nodes->get_nodelist)[0];
			my ($alias) = $alias_node->getAttribute('path') =~ /currencyFormats\[\@numberSystem='(.*?)'\]/;
			$currency_formats{$number_system}{alias} = $alias;
		}
		else {
			foreach my $location (qw( beforeCurrency afterCurrency )) {
				foreach my $data (qw( currencyMatch surroundingMatch insertBetween ) ) {
					my $nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number_system"]/currencySpacing/$location/$data/text()));
					next unless $nodes->size;
					my $text = ($nodes->get_nodelist)[0]->getValue;
					$currency_formats{$number_system}{position}{$location}{$data} = $text;
				}
			}
			
			foreach my $currency_format_type (qw( standard accounting )) {
				my $length_nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number_system"]/currencyFormatLength));
				foreach my $length_node ($length_nodes->get_nodelist) {
					my $length_node_type = $length_node->getAttribute('type') // '';
					my $length_node_type_text = $length_node_type ? qq([type="$length_node_type"]) : '';

					foreach my $currency_type (qw( standard accounting )) {
						# Check for aliases
						my $alias_nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number_system"]/currencyFormatLength$length_node_type_text/currencyFormat[\@type="$currency_type"]/alias));
						if ($alias_nodes->size) {
							my ($alias) = ($alias_nodes->get_nodelist)[0]->getAttribute('path') =~ /currencyFormat\[\@type='(.*?)'\]/;
							$currency_formats{$number_system}{pattern}{$length_node_type || 'default'}{$currency_type}{alias} = $alias;
						}
						else {
							my $pattern_nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number_system"]/currencyFormatLength$length_node_type_text/currencyFormat[\@type="$currency_type"]/pattern/text()));
							next unless $pattern_nodes->size;
							my $pattern = ($pattern_nodes->get_nodelist)[0]->getValue;
							my ($positive, $negative) = split /;/, $pattern;
							$negative //= $positive;
							$currency_formats{$number_system}{pattern}{$length_node_type || 'default'}{$currency_type}{positive} = $positive;
							$currency_formats{$number_system}{pattern}{$length_node_type || 'default'}{$currency_type}{negative} = $negative;
						}
					}
				}
			}
		}
	}
	
	# Currencies
	my %currencies;
	my $currency_nodes = findnodes($xpath, "/ldml/numbers/currencies/currency");
	foreach my $currency_node ($currency_nodes->get_nodelist) {
		my $currency_code = $currency_node->getAttribute('type');
		my $currency_symbol_nodes = findnodes($xpath, "/ldml/numbers/currencies/currency[\@type='$currency_code']/symbol/text()");
		if ($currency_symbol_nodes->size) {
			$currencies{$currency_code}{currency_symbol} = ($currency_symbol_nodes->get_nodelist)[0]->getValue;
		}
		my $display_name_nodes = findnodes($xpath, "/ldml/numbers/currencies/currency[\@type='$currency_code']/displayName");
		foreach my $display_name_node ($display_name_nodes->get_nodelist) {
			my $count = $display_name_node->getAttribute('count') || 'currency';
			my $name = $display_name_node->getChildNode(1)->getValue();
			$currencies{$currency_code}{display_name}{$count} = $name;
		}
	}
	
	# Write out data
	print $file <<EOT if $default_numbering_system;
has 'default_numbering_system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> '$default_numbering_system',
);

EOT

	foreach my $numbering_system (qw( native traditional finance )) {
		if ($other_numbering_systems{$numbering_system}) {
			print $file <<EOT;
has ${numbering_system}_numbering_system => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> '$other_numbering_systems{$numbering_system}',
);

EOT
		}
	}

	if (keys %symbols) {
		print $file <<EOT;
has 'number_symbols' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $number_system (sort keys %symbols) {
			if (exists $symbols{$number_system}{alias}) {
				say $file "\t\t'$number_system' => { 'alias' => '$symbols{$number_system}{alias}' },"
			}
			else {
				say $file "\t\t'$number_system' => {";
				foreach my $symbol (sort keys %{$symbols{$number_system}}) {
					say $file "\t\t\t'$symbol' => q($symbols{$number_system}{$symbol}),";
				}
				say $file "\t\t},";
			}
		}
		print $file <<EOT;
\t} }
);

EOT
	}
	
	if (keys %formats) {
		print $file <<EOT;
has 'number_formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $number_system (sort keys %formats) {
			say $file "\t\t$number_system => {";
			foreach my $length ( sort keys %{$formats{$number_system}} ) {
				if ($length eq 'alias') {
					say $file "\t\t\t'alias' => '$formats{$number_system}{alias}',";
				}
				else {
					say $file "\t\t\t'$length' => {";
					foreach my $pattern_type (sort keys %{$formats{$number_system}{$length}}) {
						if ($pattern_type eq 'alias') {
							say $file "\t\t\t\t'alias' => '$formats{$number_system}{$length}{alias}',";
						}
						else {
							say $file "\t\t\t\t'$pattern_type' => {";
							foreach my $count (sort keys %{$formats{$number_system}{$length}{$pattern_type}}) {
								say $file "\t\t\t\t\t'$count' => '$formats{$number_system}{$length}{$pattern_type}{$count}',";
							}
							say $file "\t\t\t\t},";
						}
					}
					say $file "\t\t\t},";
				}
			}
			say $file "\t\t},";
		}
		print  $file <<EOT;
} },
);

EOT
	}
	
	if (keys %currency_formats) {
		print $file <<EOT;
has 'number_currency_formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $number_system (sort keys %currency_formats ) {
			say $file "\t\t'$number_system' => {";
			foreach my $type (sort keys %{$currency_formats{$number_system}}) {
				if ($type eq 'alias') {
					say $file "\t\t\t'alias' => '$currency_formats{$number_system}{alias}',";
				}
				elsif ($type eq 'position') {
					say $file "\t\t\t'possion' => {";
					foreach my $location (sort keys %{$currency_formats{$number_system}{position}}) {
						say $file "\t\t\t\t'$location' => {";
						foreach my $data (sort keys %{$currency_formats{$number_system}{position}{$location}}) {
							say $file "\t\t\t\t\t'$data' => '$currency_formats{$number_system}{position}{$location}{$data}',";
						}
						say $file "\t\t\t\t},";
					}
					say $file "\t\t\t},";
				}
				else {
					say $file "\t\t\t'pattern' => {";
					foreach my $length (sort keys %{$currency_formats{$number_system}{pattern}}) {
						say $file "\t\t\t\t'$length' => {";
						foreach my $currency_type (sort keys %{$currency_formats{$number_system}{pattern}{$length}} ) {
							say $file "\t\t\t\t\t'$currency_type' => {";
							foreach my $p_n_a (sort keys %{$currency_formats{$number_system}{pattern}{$length}{$currency_type}}) {
								say $file "\t\t\t\t\t\t'$p_n_a' => '$currency_formats{$number_system}{pattern}{$length}{$currency_type}{$p_n_a}',";
							}
							say $file "\t\t\t\t\t},";
						}
						say $file "\t\t\t\t},";
					}
					say $file "\t\t\t},";
				}
			}
			say $file "\t\t},";
		}
		print  $file <<EOT;
} },
);

EOT
	}
	
	if (keys %currencies) {
		print $file <<EOT;
has 'curriencies' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $currency (sort keys %currencies) {
			say $file "\t\t'$currency' => {";
			say $file "\t\t\tsymbol => '$currencies{$currency}{currency_symbol}'," 
				if exists $currencies{$currency}{currency_symbol};

			if ( exists $currencies{$currency}{display_name} ) {
				say $file "\t\t\tdisplay_name => {";
				foreach my $count (sort keys %{$currencies{$currency}{display_name}}) {
					my $display_name = $currencies{$currency}{display_name}{$count};
					$display_name = $display_name =~ s/\(/\\(/gr =~ s/\)/\\)/gr;
					say $file "\t\t\t\t'$count' => q($display_name),";
				}
				say $file "\t\t\t},";
			}
			say $file "\t\t},";
		}

		say $file <<EOT;
\t} },
);

EOT
	}
}

# Default currency data
sub process_currency_data {
	my ($file, $xml) = @_;
	
	say "Processing currency data" if $verbose;
	
	# Do fraction data
	my $fractions = findnodes($xml, '/supplementalData/currencyData/fractions/info');
	my %fractions;
	foreach my $node ($fractions->get_nodelist) {
		$fractions{$node->getAttribute('iso4217')} = {
			digits			=> $node->getAttribute('digits'),
			rounding		=> $node->getAttribute('rounding'),
			cashrounding	=> $node->getAttribute('cashRounding') 	|| $node->getAttribute('rounding'),
			cashdigits		=> $node->getAttribute('cashDigits') 	|| $node->getAttribute('digits'),
		};
	}
	
	# Do default Currency data
	# The data set provides historical data which I'm ignoring for now
	my %default_currency;
	my $default_currencies = findnodes($xml, '/supplementalData/currencyData/region');
	foreach my $node ( $default_currencies->get_nodelist ) {
		my $region = $node->getAttribute('iso3166');
		
		my $currencies = findnodes($xml, qq(/supplementalData/currencyData/region[\@iso3166="$region"]/currency[not(\@to)]));
		
		next unless $currencies->size;
		
		my ($currency) = $currencies->get_nodelist;
		$currency = $currency->getAttribute('iso4217');
		$default_currency{$region} = $currency;
	}
	
	say $file <<EOT;
has '_currency_fractions' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $fraction (sort keys %fractions) {
		say $file "\t\t$fraction => {";
		foreach my $type ( qw(digits rounding cashdigits cashrounding ) ) {
			say $file "\t\t\t'$type' => '$fractions{$fraction}{$type}',";
		}
		say $file "\t\t},";
	}
	
	say $file <<'EOT';
	} },
);

sub currency_fractions {
	my ($self, $currency) = @_;
	
	my $currency_data = $self->_currency_fractions()->{$currency};
	
	$currency_data = {
		digits 			=> 2,
		cashdigits 		=> 2,
		rounding 		=> 0,
		cashrounding	=> 0,
	} unless $currency_data;
	
	return $currency_data;
}

has '_default_currency' => (
	is			=> 'ro',
	isa			=> 'HashRef',
	init_arg	=> undef,
	default		=> sub { {
EOT
	
	foreach my $territory (sort keys %default_currency) {
		say $file "\t\t\t\t'$territory' => '$default_currency{$territory}',";
	}
	
	say $file <<EOT;
\t } },
);

EOT
}


# Territory Containment data
sub process_territory_containment_data {
	my ($file, $xpath) = @_;
	
	my $data = findnodes($xpath, '/supplementalData/territoryContainment/group');
	
	my %contains;
	my %contained_by;
	foreach my $node ($data->get_nodelist) {
		my $base = $node->getAttribute('type');
		my @contains = split /\s+/, $node->getAttribute('contains');
		push @{$contains{$base}}, @contains;
		@contained_by{@contains} = ($base) x @contains;
	}
	
	say $file <<EOT;
has 'territory_contains' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $territory ( sort { $a <=> $b || $a cmp $b } keys %contains ) {
		say $file "\t\t'$territory' => [ qw( @{$contains{$territory}} ) ], ";
	}
	
	say $file <<EOT;
\t} }
);

has 'territory_contained_by' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $territory ( sort { $a <=> $b || $a cmp $b } keys %contained_by ) {
		say $file "\t\t'$territory' => '$contained_by{$territory}', ";
	}
	
	say $file <<EOT;
\t} }
);

EOT
}

# Dates
#/ldml/dates/calendars/
sub process_calendars {
    my ($file, $xpath, $local) = @_;

    say "Processing Calendars" if $verbose;
    
    my $calendars = findnodes($xpath, '/ldml/dates/calendars/calendar');

    return unless $calendars->size;

    my %calendars;
    foreach my $calendar ($calendars->get_nodelist) {
        my $type = $calendar->getAttribute('type');
        my ($months) = process_months($xpath, $type);
        $calendars{months}{$type} = $months if $months;
        my ($days) = process_days($xpath, $type);
        $calendars{days}{$type} = $days if $days;
        my $quarters = process_quarters($xpath, $type);
        $calendars{quarters}{$type} = $quarters if $quarters;
        my $day_periods = process_day_periods($xpath, $type);
        $calendars{day_periods}{$type} = $day_periods if $day_periods;
        my $eras = process_eras($xpath, $type);
        $calendars{eras}{$type} = $eras if $eras;
        my $day_period_data = process_day_period_data($local);
        $calendars{day_period_data}{$type} = $day_period_data if $day_period_data;
        my $date_formats = process_date_formats($xpath, $type);
        $calendars{date_formats}{$type} = $date_formats if $date_formats;
        my $time_formats = process_time_formats($xpath, $type);
        $calendars{time_formats}{$type} = $time_formats if $time_formats;
        my $datetime_formats = process_datetime_formats($xpath, $type);
        $calendars{datetime_formats}{$type} = $datetime_formats if $datetime_formats;
    }

    # Got all the data now write it out to the file;
    if (keys %{$calendars{months}}) {
        print $file <<EOT;
has 'calendar_months' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $type (sort keys %{$calendars{months}}) {
			
            say $file "\t\t\t'$type' => {";
            foreach my $context ( sort keys %{$calendars{months}{$type}} ) {
                if ($context eq 'alias') {
					say $file "\t\t\t\t'alias' => '$calendars{months}{$type}{alias}',";
					next;
				}
				
                say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{months}{$type}{$context}}) {
                    if (exists $calendars{months}{$type}{$context}{$width}{alias}) {
						say $file "\t\t\t\t\t'$width' => {";
                        say $file "\t\t\t\t\t\t'alias' => {";
						say $file "\t\t\t\t\t\t\tcontext\t=> q{$calendars{months}{$type}{$context}{$width}{alias}{context}},";
						say $file "\t\t\t\t\t\t\ttype\t=> q{$calendars{months}{$type}{$context}{$width}{alias}{type}},";
						say $file "\t\t\t\t\t\t},";
						say $file "\t\t\t\t\t},";
                        next;
                    }

                    print $file "\t\t\t\t\t$width => {\n\t\t\t\t\t\tnonleap => [\n\t\t\t\t\t\t\t";
                    
                    say $file join ",\n\t\t\t\t\t\t\t",
                        map {
                            my $month = $_;
                            $month =~ s/'/\\'/;
                            $month = "'$month'";
                        } @{$calendars{months}{$type}{$context}{$width}{nonleap}};
                    print $file "\t\t\t\t\t\t],\n\t\t\t\t\t\tleap => [\n\t\t\t\t\t\t\t";

                    say $file join ",\n\t\t\t\t\t\t\t",
                        map {
                            my $month = $_ // '';
                            $month =~ s/'/\\'/;
                            $month = "'$month'";
                        } @{$calendars{months}{$type}{$context}{$width}{leap}};
                    say $file "\t\t\t\t\t\t],";
                    say $file "\t\t\t\t\t},";
                }
                say $file "\t\t\t\t},";
            }
            say $file "\t\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

   my %days = (
        mon => 0,
        tue => 1,
        wed => 2,
        thu => 3,
        fri => 4,
        sat => 5,
        sun => 6,
    );

    if (keys %{$calendars{days}}) {
        print $file <<EOT;
has 'calendar_days' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $type (sort keys %{$calendars{days}}) {
            say $file "\t\t\t'$type' => {";
            foreach my $context ( sort keys %{$calendars{days}{$type}} ) {
                if ($context eq 'alias') {
                    say $file "\t\t\t\t'alias' => q{$calendars{days}{$type}{alias}},";
                    next;
                }

                say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{days}{$type}{$context}}) {
                    if (exists $calendars{days}{$type}{$context}{$width}{alias}) {
						say $file "\t\t\t\t\t'$width' => {";
                        say $file "\t\t\t\t\t\t'alias' => {";
						say $file "\t\t\t\t\t\t\tcontext\t=> q{$calendars{days}{$type}{$context}{$width}{alias}{context}},";
						say $file "\t\t\t\t\t\t\ttype\t=> q{$calendars{days}{$type}{$context}{$width}{alias}{type}},";
						say $file "\t\t\t\t\t\t},";
						say $file "\t\t\t\t\t},";
                        next;
                    }

                    say $file "\t\t\t\t\t$width => {";
                    print $file "\t\t\t\t\t\t";
                    my @days  = sort {$days{$a} <=> $days{$b}}
                        keys %{$calendars{days}{$type}{$context}{$width}};

                    say $file join ",\n\t\t\t\t\t\t",
                        map {
                            my $day = $calendars{days}{$type}{$context}{$width}{$_};
                            my $key = $_;
                            $day =~ s/'/\\'/;
                            $day = "'$day'";
                            "$key => $day";
                        } @days;
                    say $file "\t\t\t\t\t},";
                }
                say $file "\t\t\t\t},";
            }
            say $file "\t\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{quarters}}) {
        print $file <<EOT;
has 'calendar_quarters' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $type (sort keys %{$calendars{quarters}}) {
            say $file "\t\t\t'$type' => {";
            foreach my $context ( sort keys %{$calendars{quarters}{$type}} ) {
                if ($context eq 'alias') {
                    say $file "\t\t\t\t'alias' => q{$calendars{quarters}{$type}{alias}},";
                    next;
                }
				
				say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{quarters}{$type}{$context}}) {
					if (exists $calendars{quarters}{$type}{$context}{$width}{alias}) {
						say $file "\t\t\t\t\t'$width' => {";
                        say $file "\t\t\t\t\t\t'alias' => {";
						say $file "\t\t\t\t\t\t\tcontext\t=> q{$calendars{quarters}{$type}{$context}{$width}{alias}{context}},";
						say $file "\t\t\t\t\t\t\ttype\t=> q{$calendars{quarters}{$type}{$context}{$width}{alias}{type}},";
						say $file "\t\t\t\t\t\t},";
						say $file "\t\t\t\t\t},";
                        next;
                    }
					
                    print $file "\t\t\t\t\t$width => {";
                    say $file join ",\n\t\t\t\t\t\t",
                        map {
                            my $quarter = $calendars{quarters}{$type}{$context}{$width}{$_};
                            $quarter =~ s/'/\\'/;
                            $quarter = "'$quarter'";
							"$_ => $quarter";
                        } sort { $a <=> $b } keys %{$calendars{quarters}{$type}{$context}{$width}};
                    say $file "\t\t\t\t\t},";
                }
                say $file "\t\t\t\t},";
            }
            say $file "\t\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
        
    }

    if (keys %{$calendars{day_period_data}}) {
        print $file <<EOT;
has 'day_period_data' => (
\ttraits\t\t=> ['Code'],
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'CodeRef',
\tinit_arg\t=> undef,
\thandles\t\t=> { call => 'execute_method' },
\tdefault\t\t=> sub { sub {
\t\t# Time in hhmm format
\t\tmy (\$self, \$type, \$time) = \@_;
\t\tSWITCH:
\t\tfor (\$type) {
EOT
        foreach my $ctype (keys  %{$calendars{day_period_data}}) {
            say $file "\t\t\tif (\$_ eq '$ctype') {";
            foreach my $type (keys  %{$calendars{day_period_data}{$ctype}}) {
                my %boundries = map {@$_} @{$calendars{day_period_data}{$ctype}{$type}};
                if (exists $boundries{at}) {
                    my ($hm) = $boundries{at};
                    $hm =~ s/://;
                    say $file "\t\t\t\treturn '$type' if \$time == $hm;";
                    next;
                }

                my $start = exists $boundries{from} ? '>=' : '>';
                my $end   = exists $boundries{to}   ? '<=' : '<';

                my $stime = $boundries{from} // $boundries{after};
                my $etime = $boundries{to}   // $boundries{before};

                s/:// foreach ($stime, $etime);

                say $file "\t\t\t\treturn '$type' if \$time $start $stime";
                say $file "\t\t\t\t\t&& \$time $end $etime;";
            }
            say $file "\t\t\tlast SWITCH;";
            say $file "\t\t\t}"
        }
        print $file <<EOT;
\t\t}
\t} },
);

EOT
    }

    if (keys %{$calendars{day_periods}}) {
        print $file <<EOT;
has 'day_periods' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        
		foreach my $ctype (sort keys %{$calendars{day_periods}}) {
            say $file "\t\t'$ctype' => {";
			if (exists $calendars{day_periods}{$ctype}{alias}) {
				say $file "\t\t\t'alias' => '$calendars{day_periods}{$ctype}{alias}',";
				say $file "\t\t},";
				next;
			}
			
            foreach my $type (sort keys %{$calendars{day_periods}{$ctype}}) {
				say $file "\t\t\t'$type' => {";
				if (exists $calendars{day_periods}{$ctype}{$type}{alias}) {
					say $file "\t\t\t\t'alias' => '$calendars{day_periods}{$ctype}{$type}{alias}',";
					say $file "\t\t\t},";
					next;
				}
				
                foreach my $width (keys %{$calendars{day_periods}{$ctype}{$type}}) {
                    say $file "\t\t\t\t'$width' => {";
					if (exists $calendars{day_periods}{$ctype}{$type}{$width}{alias}) {
						say $file "\t\t\t\t\t'alias' => '$calendars{day_periods}{$ctype}{$type}{$width}{alias}',";
						say $file "\t\t\t\t},";
						next;
					}
				
                    foreach my $period (keys %{$calendars{day_periods}{$ctype}{$type}{$width}}) {
                        say $file "\t\t\t\t\t'$period' => q{$calendars{day_periods}{$ctype}{$type}{$width}{$period}},"
                    }
                    say $file "\t\t\t\t},";
                }
                say $file "\t\t\t},";
            }
            say $file "\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{eras}}) {
        print $file <<EOT;
has 'eras' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{eras}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $type (sort keys %{$calendars{eras}{$ctype}}) {
				if ($type eq 'alias') {
					say $file "\t\t\t'alias' => '$calendars{eras}{$ctype}{alias}',";
					next;
				}
                
				say $file "\t\t\t$type => {";
                print $file "\t\t\t\t";
                print $file join ",\n\t\t\t\t", map {
                    my $name = $calendars{eras}{$ctype}{$type}{$_};
                    $name =~ s/'/\\'/;
                    "'$_' => '$name'";
                } sort { $a <=> $b } keys %{$calendars{eras}{$ctype}{$type}};
                say $file "\n\t\t\t},";
            }
            say $file "\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{date_formats}}) {
        print $file <<EOT;
has 'date_formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{date_formats}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $width (sort keys %{$calendars{date_formats}{$ctype}}) {
                say $file "\t\t\t'$width' => q{$calendars{date_formats}{$ctype}{$width}},";
            }
            say $file "\t\t},";
        }

        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{time_formats}}) {
        print $file <<EOT;
has 'time_formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{time_formats}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $width (sort keys %{$calendars{time_formats}{$ctype}}) {
                say $file "\t\t\t'$width' => q{$calendars{time_formats}{$ctype}{$width}},";
            }
            say $file "\t\t},";
        }

        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{datetime_formats}}) {
        print $file <<EOT;
has 'datetime_formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{datetime_formats}}) {
            say $file "\t\t'$ctype' => {";
			if (exists $calendars{datetime_formats}{$ctype}{alias}) {
			    say $file "\t\t\t'alias' => q{$calendars{datetime_formats}{$ctype}{alias}},";
			}
			else {
				foreach my $length (sort keys %{$calendars{datetime_formats}{$ctype}{formats}}) {
					say $file "\t\t\t'$length' => q{$calendars{datetime_formats}{$ctype}{formats}{$length}},";
				}
			}
			say $file "\t\t},";
        }

        print $file <<EOT;
\t} },
);

has 'datetime_formats_available_formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (keys %{$calendars{datetime_formats}}) {
			if (exists $calendars{datetime_formats}{$ctype}{alias}) {
				say $file "\t\t'$ctype' => {";
				say $file "\t\t\t'alias' => q{$calendars{datetime_formats}{$ctype}{alias}},";
				say $file "\t\t},";
			}
			else {
				if (exists $calendars{datetime_formats}{$ctype}{available_formats}) {
					say $file "\t\t'$ctype' => {";
					foreach my $type (sort keys %{$calendars{datetime_formats}{$ctype}{available_formats}}) {
						say $file "\t\t\t$type => q{$calendars{datetime_formats}{$ctype}{available_formats}{$type}},";
					}
					say $file "\t\t},";
				}
            }
        }
        print $file <<EOT;
\t} },
);

has 'datetime_formats_append_item' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

        foreach my $ctype (keys %{$calendars{datetime_formats}}) {
			if (exists $calendars{datetime_formats}{$ctype}{alias}) {
				say $file "\t\t'$ctype' => {";
				say $file "\t\t\t'alias' => q{$calendars{datetime_formats}{$ctype}{alias}},";
				say $file "\t\t},";
			}
			else {
				if (exists $calendars{datetime_formats}{$ctype}{appendItem}) {
					say $file "\t\t'$ctype' => {";
					foreach my $type (sort keys %{$calendars{datetime_formats}{$ctype}{appendItem}}) {
						say $file "\t\t\t'$type' => '$calendars{datetime_formats}{$ctype}{appendItem}{$type}',";
					}
					say $file "\t\t},";
				}
			}
        }
        print $file <<EOT;
\t} },
);

has 'datetime_formats_interval' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

        foreach my $ctype (keys %{$calendars{datetime_formats}}) {
			if (exists $calendars{datetime_formats}{$ctype}{alias}) {
				say $file "\t\t'$ctype' => {";
				say $file "\t\t\t'alias' => q{$calendars{datetime_formats}{$ctype}{alias}},";
				say $file "\t\t},";
			}
			else {
				if (exists $calendars{datetime_formats}{$ctype}{interval}) {
					say $file "\t\t'$ctype' => {";
					foreach my $format_id ( sort keys %{$calendars{datetime_formats}{$ctype}{interval}}) {
						if ($format_id eq 'fallback') {
							say $file "\t\t\tfallback => '$calendars{datetime_formats}{$ctype}{interval}{fallback}',";
							next;
						}
						say $file "\t\t\t$format_id => {";
						foreach my $greatest_difference (sort keys %{$calendars{datetime_formats}{$ctype}{interval}{$format_id}}) {
							say $file "\t\t\t\t$greatest_difference => q{$calendars{datetime_formats}{$ctype}{interval}{$format_id}{$greatest_difference}},";
						}
						say $file "\t\t\t},";
					}
					say $file "\t\t},";
				}
			}
        }
        print $file <<EOT;
\t} },
);

EOT
    }
}

#/ldml/dates/calendars/calendar/months/
sub process_months {
    my ($xpath, $type) = @_;

    say "Processing Months ($type)" if $verbose;

    my (%months);
    my $months_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/alias));
    if ($months_alias->size) {
        my $path = ($months_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$months{alias} = $alias;
    }
    else {
        my $months_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext));

        return 0 unless $months_nodes->size;

        foreach my $context_node ($months_nodes->get_nodelist) {
            my $context_type = $context_node->getAttribute('type');

            my $width = findnodes($xpath,
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context_type"]/monthWidth));

            foreach my $width_node ($width->get_nodelist) {
                my $width_type = $width_node->getAttribute('type');
				
				my $width_alias_nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context_type"]/monthWidth[\@type="$width_type"]/alias)
				);
				
				if ($width_alias_nodes->size) {
                    my $path = ($width_alias_nodes->get_nodelist)[0]->getAttribute('path');
                    my ($new_width_context) = $path =~ /monthContext\[\@type='([^']+)'\]/;
                    $new_width_context //= $context_type;
                    my ($new_width_type) = $path =~ /monthWidth\[\@type='([^']+)'\]/;
					$months{$context_type}{$width_type}{alias} = {
						context	=> $new_width_context,
						type	=> $new_width_type,
					};
					next;
                }
                my $month_nodes = findnodes($xpath, 
                    qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context_type"]/monthWidth[\@type="$width_type"]/month));
                foreach my $month ($month_nodes->get_nodelist) {
                    my $month_type = $month->getAttribute('type') -1;
                    my $year_type = $month->getAttribute('yeartype') || 'nonleap';
                    $months{$context_type}{$width_type}{$year_type}[$month_type] = 
                        $month->getChildNode(1)->getValue();
                }
            }
        }
    }
    return \%months;
}

#/ldml/dates/calendars/calendar/days/
sub process_days {
    my ($xpath, $type) = @_;

    say "Processing Days ($type)" if $verbose;

    my (%days);
    my $days_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/alias));
    if ($days_alias->size) {
        my $path = ($days_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$days{alias} = $alias;
    }
	else {
		my $days_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext));
		return 0 unless $days_nodes->size;

		foreach my $context_node ($days_nodes->get_nodelist) {
			my $context_type = $context_node->getAttribute('type');

			my $width = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context_type"]/dayWidth));
        
			foreach my $width_node ($width->get_nodelist) {
				my $width_type = $width_node->getAttribute('type');
				
				my $width_alias_nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context_type"]/dayWidth[\@type="$width_type"]/alias)
				);
				
				if ($width_alias_nodes->size) {
                    my $path = ($width_alias_nodes->get_nodelist)[0]->getAttribute('path');
                    my ($new_width_context) = $path =~ /dayContext\[\@type='([^']+)'\]/;
                    $new_width_context //= $context_type;
                    my ($new_width_type) = $path =~ /dayWidth\[\@type='([^']+)'\]/;
					$days{$context_type}{$width_type}{alias} = {
						context	=> $new_width_context,
						type	=> $new_width_type,
					};
					next;
                }
                
                my $day_nodes = findnodes($xpath, 
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context_type"]/dayWidth[\@type="$width_type"]/day));
				
				foreach my $day ($day_nodes->get_nodelist) {
					my $day_type = $day->getAttribute('type');
					$days{$context_type}{$width_type}{$day_type} = 
						$day->getChildNode(1)->getValue();
				}
            }
		}
    }
    return \%days;
}

#/ldml/dates/calendars/calendar/quarters/
sub process_quarters {
    my ($xpath, $type) = @_;

    say "Processing Quarters ($type)" if $verbose;

    my %quarters;
    my $quarters_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/alias));
    if ($quarters_alias->size) {
        my $path = ($quarters_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$quarters{alias} = $alias;
    }
	else {
		my $quarters_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext));
		return 0 unless $quarters_nodes->size;

		foreach my $context_node ($quarters_nodes->get_nodelist) {
			my $context_type = $context_node->getAttribute('type');
			
			my $width = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context_type"]/quarterWidth));
        
			foreach my $width_node ($width->get_nodelist) {
				my $width_type = $width_node->getAttribute('type');
				
				my $width_alias_nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context_type"]/quarterWidth[\@type="$width_type"]/alias)
				);
			
				if ($width_alias_nodes->size) {
                    my $path = ($width_alias_nodes->get_nodelist)[0]->getAttribute('path');
                    my ($new_width_context) = $path =~ /quarterContext\[\@type='([^']+)'\]/;
                    $new_width_context //= $context_type;
                    my ($new_width_type) = $path =~ /quarterWidth\[\@type='([^']+)'\]/;
					$quarters{$context_type}{$width_type}{alias} = {
						context	=> $new_width_context,
						type	=> $new_width_type,
					};
					next;
                }
                
				my $quarter_nodes = findnodes($xpath, 
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context_type"]/quarterWidth[\@type="$width_type"]/quarter));
            
				foreach my $quarter ($quarter_nodes->get_nodelist) {
					my $quarter_type = $quarter->getAttribute('type') -1;
					$quarters{$context_type}{$width_type}{$quarter_type} = 
						$quarter->getChildNode(1)->getValue();
				}
			}
		}
	}
    
	return \%quarters;
}

sub process_day_period_data {
    my $locale = shift;

	use feature 'state';
	state %day_period_data;	

    unless (keys %day_period_data) {

	# The supplemental/dayPeriods.xml file contains a list of all valid
	# day periods
        my $xml = XML::XPath->new(
            File::Spec->catfile(
				$base_directory,
				'supplemental',
				'dayPeriods.xml',
			)
        );

        my $dayPeriodRules = findnodes($xml, 
            q(/supplementalData/dayPeriodRuleSet/dayPeriodRules)
        );

        foreach my $day_period_rule ($dayPeriodRules->get_nodelist) {
            my $locales = $day_period_rule->getAttribute('locales');
            my %data;
            my $day_periods = findnodes($xml, 
                qq(/supplementalData/dayPeriodRuleSet/dayPeriodRules[\@locales="$locales"]/dayPeriodRule)
            );

            foreach my $day_period ($day_periods->get_nodelist) {
                my $type;
                my @data;
                foreach my $attribute_node ($day_period->getAttributes) {
                    if ($attribute_node->getLocalName() eq 'type') {
                        $type = $attribute_node->getData;
                    }
                    else {
                        push @data, [
                            $attribute_node->getLocalName,
                            $attribute_node->getData
                        ]
                    }
                }
                $data{$type} = \@data;
            }
            my @locales = split / /, $locales;
            @day_period_data{@locales} = (\%data) x @locales;
        }
    }

    return $day_period_data{$locale};
}

#/ldml/dates/calendars/calendar/dayPeriods/
sub process_day_periods {
    my ($xpath, $type) = @_;

    say "Processing Day Periods ($type)" if $verbose;

    my %dayPeriods;
    my $dayPeriods_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/alias));
    if ($dayPeriods_alias->size) {
        my $path = ($dayPeriods_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$dayPeriods{alias} = $alias;
    }
	else {
		my $dayPeriods_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext));
		return 0 unless $dayPeriods_nodes->size;

		foreach my $context_node ($dayPeriods_nodes->get_nodelist) {
			my $context_type = $context_node->getAttribute('type');
        
			my $context_alias_nodes = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context_type"]/alias)
			);
			
			if ($context_alias_nodes->size) {
                my $path = ($context_alias_nodes->get_nodelist)[0]->getAttribute('path');
                my ($new_context) = $path =~ /dayPeriodContext\[\@type='([^']+)'\]/;
                $dayPeriods{$context_type}{alias} = $new_context;
				next;
            }
				
			my $width = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context_type"]/dayPeriodWidth)
			);
        
			foreach my $width_node ($width->get_nodelist) {
				my $width_type = $width_node->getAttribute('type');
            
				my $width_alias_nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context_type"]/dayPeriodWidth[\@type="$width_type"]/alias)
				);
			
				if ($width_alias_nodes->size) {
                    my $path = ($width_alias_nodes->get_nodelist)[0]->getAttribute('path');
                    my ($new_width_type) = $path =~ /dayPeriodWidth\[\@type='([^']+)'\]/;
					$dayPeriods{$context_type}{$width_type}{alias} = $new_width_type;
					next;
                }
                
				my $dayPeriod_nodes = findnodes($xpath, 
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context_type"]/dayPeriodWidth[\@type="$width_type"]/dayPeriod)
				);
            
				foreach my $dayPeriod ($dayPeriod_nodes->get_nodelist) {
					my $dayPeriod_type = $dayPeriod->getAttribute('type');
					$dayPeriods{$context_type}{$width_type}{$dayPeriod_type} = 
						$dayPeriod->getChildNode(1)->getValue();
				}
			}
		}
    }
	
	return \%dayPeriods;
}

#/ldml/dates/calendars/calendar/eras/
sub process_eras {
    my ($xpath, $type) = @_;

    say "Processing Eras ($type)" if $verbose;

    my %eras;
	my %alias_size = (
		eraNames 	=> 'wide',
		eraAbbr		=> 'abbreviated',
		eraNarrow	=> 'narrow',
	);
	
    my $eras_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/alias));
	if ($eras_alias->size) {
        my $path = ($eras_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$eras{alias} = $alias;
    }
	else {
		my $eras_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras));
		return {} unless $eras_nodes->size;
		
		my $eraNames_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNames/alias));
		if ($eraNames_alias->size) {
			my $path = ($eraNames_alias->get_nodelist)[0]->getAttribute('path');
			my ($alias) = $path=~/\.\.\/(.*)/;
			$eras{wide}{alias} = $alias_size{$alias};
		}
		else {
			my $eraNames = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNames/era[not(\@alt)]));
			if ($eraNames->size) {
				foreach my $eraName ($eraNames->get_nodelist) {
					my $era_type = $eraName->getAttribute('type');
					$eras{wide}{$era_type} = $eraName->getChildNode(1)->getValue();
				}
			}
        }
    
		my $eraAbbrs_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraAbbr/alias));
		if ($eraAbbrs_alias->size) {
			my $path = ($eraAbbrs_alias->get_nodelist)[0]->getAttribute('path');
			my ($alias) = $path=~/\.\.\/(.*)/;
			$eras{abbreviated}{alias} = $alias_size{$alias};
		}
		else {
			my $eraAbbrs = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraAbbr/era[not(\@alt)]));
			if ($eraAbbrs->size) {
				foreach my $eraAbbr ($eraAbbrs->get_nodelist) {
					my $era_type = $eraAbbr->getAttribute('type');
					$eras{abbreviated}{$era_type} = $eraAbbr->getChildNode(1)->getValue();
				}
			}
		}
		
		my $eraNarrow_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNarrow/alias));
		if ($eraNarrow_alias->size) {
			my $path = ($eraNarrow_alias->get_nodelist)[0]->getAttribute('path');
			my ($alias) = $path=~/\.\.\/(.*)/;
			$eras{narrow}{alias} = $alias_size{$alias};
		}
		else {
			my $eraNarrows = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNarrow/era[not(\@alt)]));
			if ($eraNarrows->size) {
				foreach my $eraNarrow ($eraNarrows->get_nodelist) {
					my $era_type = $eraNarrow->getAttribute('type');
					$eras{narrow}{$era_type} = $eraNarrow->getChildNode(1)->getValue();
				}
			}
		}
    }
    
    return \%eras;
}

#/ldml/dates/calendars/calendar/dateFormats/
sub process_date_formats {
    my ($xpath, $type) = @_;

    say "Processing Date Formats ($type)" if $verbose;

    my %dateFormats;
	my $dateFormats_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/alias));
	if ($dateFormats_alias->size) {
		my $path = ($dateFormats_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$dateFormats{alias} = $alias;
    }
	else {
		my $dateFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats));

		return {} unless $dateFormats->size;

		my $dateFormatLength_nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/dateFormatLength)
        );

		foreach my $dateFormatLength ($dateFormatLength_nodes->get_nodelist) {
			my $date_format_width = $dateFormatLength->getAttribute('type');

			my $patterns = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/dateFormatLength[\@type="$date_format_width"]/dateFormat/pattern)
			);

			my $pattern = $patterns->[0]->getChildNode(1)->getValue;
			$dateFormats{$date_format_width} = $pattern;
		}
    }
		
	return \%dateFormats;
}

#/ldml/dates/calendars/calendar/timeFormats/
sub process_time_formats {
    my ($xpath, $type) = @_;

    say "Processing Time Formats ($type)" if $verbose;

    my %timeFormats;
	my $timeFormats_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/alias));
	if ($timeFormats_alias->size) {
		my $path = ($timeFormats_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$timeFormats{alias} = $alias;
    }
	else {
		my $timeFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats));

		return {} unless $timeFormats->size;

		my $timeFormatLength_nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/timeFormatLength)
        );

		foreach my $timeFormatLength ($timeFormatLength_nodes->get_nodelist) {
			my $time_format_width = $timeFormatLength->getAttribute('type');

			my $patterns = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/timeFormatLength[\@type="$time_format_width"]/timeFormat/pattern)
			);

			my $pattern = $patterns->[0]->getChildNode(1)->getValue;
			$timeFormats{$time_format_width} = $pattern;
		}
    }
		
	return \%timeFormats;
}

#/ldml/dates/calendars/calendar/dateTimeFormats/
sub process_datetime_formats {
    my ($xpath, $type) = @_;

    say "Processing Date Time Formats ($type)" if $verbose;

    my %dateTimeFormats;
    my $dateTimeFormats_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/alias));

    if ($dateTimeFormats_alias->size) {
		my $path = ($dateTimeFormats_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$dateTimeFormats{alias} = $alias;
    }
	else {
		my $dateTimeFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats));

		return {} unless $dateTimeFormats->size;
		
		my $dateTimeFormatLength_nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/dateTimeFormatLength)
        );

		foreach my $dateTimeFormatLength ($dateTimeFormatLength_nodes->get_nodelist) {
			my $dateTime_format_type = $dateTimeFormatLength->getAttribute('type');

			my $patterns = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/dateTimeFormatLength[\@type="$dateTime_format_type"]/dateTimeFormat/pattern)
			);

			my $pattern = $patterns->[0]->getChildNode(1)->getValue;
			$dateTimeFormats{formats}{$dateTime_format_type} = $pattern;
		}

		# Available Formats
		my $availableFormats_nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/availableFormats/dateFormatItem)
		);

		foreach my $dateFormatItem ($availableFormats_nodes->get_nodelist) {
			my $id = $dateFormatItem->getAttribute('id');

			my $pattern = $dateFormatItem->getChildNode(1)->getValue;
			$dateTimeFormats{available_formats}{$id} = $pattern;
		}
    
		# Append items
		my $appendItems_nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/appendItems/appendItem)
        );

		foreach my $appendItem ($appendItems_nodes->get_nodelist) {
			my $request = $appendItem->getAttribute('request');

			my $pattern = $appendItem->getChildNode(1)->getValue;
			$dateTimeFormats{appendItem}{$request} = $pattern;
		}

		# Interval formats
		my $intervalFormats_nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/intervalFormats/intervalFormatItem)
        );

		my $fallback_node = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/intervalFormats/intervalFormatFallback)
        );
    
		if ($fallback_node->size) {
			$dateTimeFormats{interval}{fallback} = ($fallback_node->get_nodelist)[0]->getChildNode(1)->getValue;
		}

		foreach my $intervalFormatItem ($intervalFormats_nodes->get_nodelist) {
			my $id = $intervalFormatItem->getAttribute('id');
        
			my $greatestDifference_nodes = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/intervalFormats/intervalFormatItem[\@id="$id"]/greatestDifference)
            );

            foreach my $greatestDifference ($greatestDifference_nodes->get_nodelist) {
                my $pattern = $greatestDifference->getChildNode(1)->getValue;
                my $gd_id = $greatestDifference->getAttribute('id');
                $dateTimeFormats{interval}{$id}{$gd_id} = $pattern;
            }
		}
    }
	
    return \%dateTimeFormats;
}

#/ldml/dates/calendars/calendar/fields/field
sub process_fields {
    my ($xpath, $type) = @_;

    say "Processing Fields ($type)" if $verbose;

    my %fields;
    my $fields_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/fields/field));

    return 0 unless $fields_nodes->size;

    foreach my $field ($fields_nodes->get_nodelist) {
        my $ftype = $field->getAttribute('type');
        my $displayName_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/fields/field[\@type="$ftype"]/displayName));

        if ($displayName_nodes->size) {
            my $text_node = ($displayName_nodes->get_nodelist)[0]->getChildNode(1);
            $fields{$ftype}{name} = $text_node->getValue 
                if $text_node;
        }

        my $relative_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/fields/field[\@type="$ftype"]/relative));
        next unless $relative_nodes->size;

        foreach my $relative ($relative_nodes->get_nodelist) {
            my $rtype = $relative->getAttribute('type');
            $fields{$ftype}{relative}{$rtype} = $relative->getChildNode(1)->getValue;
        }
    }

    return \%fields;
}

#/ldml/dates/timeZoneNames/
sub process_time_zone_names {
    my ($file, $xpath) = @_;

    say "Processing Time Zone Names"
		if $verbose;

    my $time_zone_names = findnodes($xpath,
        q(/ldml/dates/timeZoneNames/*));

    return unless $time_zone_names->size;

    print $file <<EOT;
has 'time_zone_names' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    my (%zone, %metazone);
    foreach my $node($time_zone_names->get_nodelist) {
        SWITCH:
        foreach ($node->getLocalName) {
            if (/^(?:
                hourFormat
                |gmtFormat
                |gmtZeroFormat
                |regionFormat
                |fallbackFormat
                |fallbackRegionFormat
            )$/x) {
                my $value = $node->string_value;
                say $file "\t\t$_ => q($value),";
                last SWITCH;
            }
            if ($_ eq 'singleCountries') {
                my $value = $node->getAttribute('list');
                my @value = split / /, $value;
                say $file "\t\tsingleCountries => [ ", 
                    join (', ',
                    map {"q($_)"}
                    @value),
                    ' ]';
                last SWITCH;
            }
            if (/(?:meta)*zone/) {
                my $name = $node->getAttribute('type');
                $zone{$name} //= {};
                my $length_nodes = findnodes($xpath,
                    qq(/ldml/dates/timeZoneNames/$_) . qq([\@type="$name"]/*));
                foreach my $length_node ($length_nodes->get_nodelist) {
                    my $length = $length_node->getLocalName;
                    if ($length eq 'exemplarCity') {
                        $zone{$name}{exemplarCity} = $length_node->string_value;
                        next;
                    }

                    $zone{$name}{$length} //= {};
                    my $tz_type_nodes = findnodes(
						$xpath,
                        qq(/ldml/dates/timeZoneNames/$_) . qq([\@type="$name"]/$length/*)
					);
					
                    foreach my $tz_type_node ($tz_type_nodes->get_nodelist) {
                        my $type = $tz_type_node->getLocalName;
                        my $value = $tz_type_node->string_value;
                        $zone{$name}{$length}{$type} = $value;
                    }
                }
                last SWITCH;
            }
        }
    }

    foreach my $name (sort keys %zone) {
        say $file "\t\t'$name' => {";
        foreach my $length (sort keys %{$zone{$name}}) {
            if ($length eq 'exemplarCity') {
                say $file "\t\t\texemplarCity => q#$zone{$name}{exemplarCity}#,";
                next;
            }
            say $file "\t\t\t$length => {";
            foreach my $type (sort keys %{$zone{$name}{$length}}) {
                say $file "\t\t\t\t'$type' => q($zone{$name}{$length}{$type}),";
            }
            say $file "\t\t\t},";
        }
        say $file "\t\t},";
    }

    say $file "\t } }";
    say $file ");";
}

sub process_plurals {
	my ($file, $cardanal_xml, $ordinal_xml) = @_;
	
	my %plurals;
	foreach my $xml ($cardanal_xml, $ordinal_xml) {
		my $plurals = findnodes($xml,
			q(/supplementalData/plurals));
		
		foreach my $plural ($plurals->get_nodelist) {
			my $type = $plural->getAttribute('type');
			my $pluralRules = findnodes($xml, qq(/supplementalData/plurals[\@type='$type']/pluralRules));
			foreach my $pluralRules_node ($pluralRules->get_nodelist) {
				my $regions = $pluralRules_node->getAttribute('locales');
				my @regions = split /\s+/, $regions;
				my $pluralRule_nodes = findnodes($xml, qq(/supplementalData/plurals[\@type='$type']/pluralRules[\@locales="$regions"]/pluralRule));
				foreach my $pluralRule ($pluralRule_nodes->get_nodelist) {
					my $count = $pluralRule->getAttribute('count');
					next if $count eq 'other';
					my $rule = findnodes($xml, qq(/supplementalData/plurals[\@type='$type']/pluralRules[\@locales="$regions"]/pluralRule[\@count="$count"]/text()));
					foreach my $region (@regions) {
						$plurals{$type}{$region}{$count} = $rule;
					}
				}
			}
		}
	}
	
	say  $file "my %_plurals = (";
	
	foreach my $type (sort keys %plurals) {
		say $file "\t$type => {";
		foreach my $region (sort keys %{$plurals{$type}}) {
			say $file "\t\t$region => {";
			foreach my $count ( sort keys %{$plurals{$type}{$region}} ) {
				say $file "\t\t\t$count => sub {";
				print $file <<'EOT';
				
				my $number = shift;
				my $n = abs($number);
				my $i = int($n);
				my ($f) = $number =~ /\.(.*)$/;
				$f //= '';
				my $t = length $f ? $f + 0 : '';
				my $v = length $f;
				my $w = length $t;

EOT
				say $file "\t\t\t\t", get_format_rule( $plurals{$type}{$region}{$count});
				say $file "\t\t\t},";
			}
			say $file "\t\t},";
		}
		say $file "\t},";
	}
	print $file <<'EOT';
);

sub plural {
	my ($self, $number, $type) = @_;
	$type //= 'cardinal';
	my $language_id = $self->language_id || $self->likely_subtag->language_id;
	
	foreach my $count (qw( zero one two few many )) {
		next unless exists $_plurals{$type}{$language_id}{$count};
		return $count if $_plurals{$type}{$language_id}{$count}->($number);
	}
	return 'other';
}

EOT
}

sub process_plural_ranges {
	my ($file, $xml) = @_;
	
	my %range;
	my $plurals = findnodes($xml,
		q(/supplementalData/plurals/pluralRanges)
	);

	foreach my $plural_node ($plurals->get_nodelist) {
		my $locales = $plural_node->getAttribute('locales');
		my @locales = split /\s+/, $locales;
		my $range_nodes = findnodes($xml,
			qq(/supplementalData/plurals/pluralRanges[\@locales='$locales']/pluralRange)
		);
	
		foreach my $range_node ($range_nodes->get_nodelist) {
			my ($start, $end, $result) = ($range_node->getAttribute('start'), $range_node->getAttribute('end'), $range_node->getAttribute('result'));
			foreach my $locale (@locales) {
				$range{$locale}{$start}{$end} = $result;
			}
		}
	}
	
	say $file "my %_plural_ranges = (";
	foreach my $locale (sort keys %range) {
		say $file "\t$locale => {";
		foreach my $start (sort keys %{$range{$locale}}) {
			say $file "\t\t$start => {";
			foreach my $end (sort keys %{$range{$locale}{$start}}) {
				say $file "\t\t\t$end => '$range{$locale}{$start}{$end}',";
			}
			say $file "\t\t},";
		}
		say $file "\t},";
	}
	say $file <<'EOT';
);
	
sub plural_range {
	my ($self, $start, $end) = @_;
	my $language_id = $self->language_id || $self->likely_subtag->language_id;
	
	$start = $self->plural($start) if $start =~ /^-?(?:[0-9]+\.)?[0-9]+$/;
	$end   = $self->plural($end)   if $end   =~ /^-?(?:[0-9]+\.)?[0-9]+$/;
	
	return $_plural_ranges{$language_id}{$start}{$end} // 'other';
}

EOT
}

sub get_format_rule {
	my $rule = shift;
	
	$rule =~ s/\@.*$//;
	
	return 1 unless $rule =~ /\S/; 
	
	# Basic substitutions
	$rule =~ s/\b([niftvw])\b/\$$1/g;
	
	my $digit = qr/[0123456789]/;
	my $value = qr/$digit+/;
	my $decimal_value = qr/$value(?:\.$value)?/;
	my $range = qr/$decimal_value\.\.$decimal_value/;
	my $range_list = qr/(\$.*?)\s(!?)=\s((?:$range|$decimal_value)(?:,(?:$range|$decimal_value))*)/;
	
	$rule =~ s/$range_list/$2 scalar (grep {$1 == \$_} ($3))/g;
	#$rule =~ s/\s=/ ==/g;
	
	$rule =~ s/\band\b/&&/g;
	$rule =~ s/\bor\b/||/g;
	
	return "return $rule;";
}

sub process_footer {
    my $file = shift;
    my $isRole = shift;
    $isRole = $isRole ? '::Role' : '';

    say "Processing Footer"
        if $verbose;

    say $file "no Moose$isRole;";
    say $file '__PACKAGE__->meta->make_immutable;' unless $isRole;
    say $file '';
    say $file '1;';
    say $file '';
    say $file '# vim: tabstop=4';
}

# Segmentation
sub process_segments {
    my ($file, $xpath) = @_;
    say "Processing Segments" if $verbose;

    foreach my $type (qw( GraphemeClusterBreak WordBreak SentenceBreak LineBreak )) {
        my $variables = findnodes($xpath, qq(/ldml/segmentations/segmentation[\@type="$type"]/variables/variable));
        next unless $variables->size;

        print $file <<EOT;
has '${type}_variables' => (
\tis => 'ro',
\tisa => 'ArrayRef',
\tinit_arg => undef,
\tdefault => sub {[
EOT
        foreach my $variable ($variables->get_nodelist) {
            # Check for deleting variables
            my $value = $variable->getChildNode(1);
            if (defined $value) {
                $value = "'" . $value->getValue . "'";
            }
            else {
                $value = 'undef()';
            }

            say $file "\t\t'", $variable->getAttribute('id'), "' => ", $value, ",";
        }

        say $file "\t]}\n);";

        my $rules = findnodes($xpath, qq(/ldml/segmentations/segmentation[\@type="$type"]/segmentRules/rule));
        next unless $rules->size;

        print $file <<EOT;

has '${type}_rules' => (
\tis => 'ro',
\tisa => 'HashRef',
\tinit_arg => undef,
\tdefault => sub { {
EOT
        foreach my $rule ($rules->get_nodelist) {
            # Check for deleting rules
            my $value = $rule->getChildNode(1);
            if (defined $value) {
                $value = "'" . $value->getValue . "'";
            }
            else {
                $value = 'undef()';
            }
            say $file "\t\t'", $rule->getAttribute('id'), "' => ", $value, ",";
        }

        say $file "\t}}\n);";
    }    
}

sub process_transforms {
    my ($dir, $xpath, $xml_file_name) = @_;

    my $transform_nodes = findnodes($xpath, q(/supplementalData/transforms/transform));
    foreach my $transform_node ($transform_nodes->get_nodelist) {
        my $variant   = ucfirst lc $transform_node->getAttribute('variant') || 'Any';
        my $source    = ucfirst lc $transform_node->getAttribute('source')  || 'Any';
        my $target    = ucfirst lc $transform_node->getAttribute('target')  || 'Any';
        my $direction = $transform_node->getAttribute('direction') || 'both';

        my @directions = $direction eq 'both'
            ? qw(forward backward)
            : $direction;

        foreach my $direction (@directions) {
            if ($direction eq 'backward') {
                ($source, $target) = ($target, $source);
            }

            my $package = "Locale::CLDR::Transformations::${variant}::${source}::$target";
			push @transformation_list, $package;
            my $dir_name = File::Spec->catdir($dir, $variant, $source);
         
            make_path($dir_name) unless -d $dir_name;

            open my $file, '>', File::Spec->catfile($dir_name, "$target.pm");
            process_header($file, $package, $CLDR_VERSION, $xpath, $xml_file_name);
            process_transform_data($file, $xpath, (
                $direction eq 'forward'
                ? "\x{2192}"
                : "\x{2190}"
            ) );

            process_footer($file);
            close $file;
        }
    }
}

sub process_transform_data {
    my ($file, $xpath, $direction) = @_;

    my $nodes = findnodes($xpath, q(/supplementalData/transforms/transform/*));
	my @nodes = $nodes->get_nodelist;

    my @transforms;
    my %vars;
    foreach my $node (@nodes) {
        next if $node->getLocalName() eq 'comment';
		next unless $node->getChildNode(1);
        my $rule = $node->getChildNode(1)->getValue;
		
		my @terms = grep { defined && /\S/ } parse_line(qr/\s+|[{};\x{2190}\x{2192}\x{2194}=\[\]]/, 'delimiters', $rule);
		
		# Escape transformation meta characters inside a set
		my $brackets = 0;
		my $count = 0;
		foreach my $term (@terms) {
		    $count++;
			$brackets++ if $term eq '[';
			$brackets-- if $term eq ']';
			if ($brackets && $term =~ /[{};]/) {
			    $term = "\\$term";
			}
			last if ! $brackets && $term =~ /;\s*(?:#.*)?$/;
		}
		@terms = @terms[ 0 .. $count - 2 ]; 
		

        # Check for conversion rules
        if ($terms[0] =~ s/^:://) {
            push @transforms, process_transform_conversion(\@terms, $direction);
            next;
        }

        # Check for Variables
		if ($terms[0] =~ /^\$/ && $terms[1] eq '=') {
		    my $value = join (' ', @terms[2 .. @terms]);
			$value =~ s/\[ /[/g;
			$value =~ s/ \]/]/g;
            $vars{$terms[0]} = process_transform_substitute_var(\%vars, $value);
			$vars{$terms[0]} =~ s/^\s*(.*\S)\s*$/$1/;
            next;
        }

        # check we are in the right direction
        my $split = qr/^\x{2194}|$direction$/;
        next unless any { /$split/ } @terms;
        @terms = map { process_transform_substitute_var(\%vars, $_) } @terms;
        if ($direction eq "\x{2192}") {
            push @transforms, process_transform_rule_forward($split, \@terms);
        }
        else {
            push @transforms, process_transform_rule_backward($split, \@terms);
        }
    }
    @transforms = reverse @transforms if $direction eq "\x{2190}";

    # Print out transforms
    print $file <<EOT;
BEGIN {
\tdie "Transliteration requires Perl 5.18 or above"
\t\tunless \$^V ge v5.18.0;
}

no warnings 'experimental::regex_sets';
has 'transforms' => (
\tis => 'ro',
\tisa => 'ArrayRef',
\tinit_arg => undef,
\tdefault => sub { [
EOT
    if ($transforms[0]{type} ne 'filter') {
        unshift @transforms, {
            type => 'filter',
            match => qr/\G./m,
        }
    }

	say $file "\t\tqr/$transforms[0]->{match}/,";
	shift @transforms;
	
	my $previous = 'transform';
	print $file <<EOT;
\t\t{
\t\t\ttype => 'transform',
\t\t\tdata => [
EOT
	foreach my $transform (@transforms) {
        if ($transform->{type} ne $previous) {
			$previous = $transform->{type};
			print $file <<EOT;
\t\t\t],
\t\t},
\t\t{
\t\t\ttype => '$previous',
\t\t\tdata => [
EOT
		}
		
        if ($previous eq 'transform') {
            print $file <<EOT;
\t\t\t\t{
\t\t\t\t\tfrom => q($transform->{from}),
\t\t\t\t\tto => q($transform->{to}),
\t\t\t\t},
EOT
        }
        if ($previous eq 'conversion') {
            print $file <<EOT;
\t\t\t\t{
\t\t\t\t\tbefore  => q($transform->{before}),
\t\t\t\t\tafter   => q($transform->{after}),
\t\t\t\t\treplace => q($transform->{replace}),
\t\t\t\t\tresult  => q($transform->{result}),
\t\t\t\t\trevisit => @{[length($transform->{revisit})]},
\t\t\t\t},
EOT
        }
    }
    print $file <<EOT;
\t\t\t]
\t\t},
\t] },
);

EOT
}

sub process_transform_conversion {
    my ($terms, $direction) = @_;

    # If the :: marker was it's own term then $terms->[0] will
    # Be the null string. Shift it off so we can test for the type
    # Of conversion
    shift @$terms unless length $terms->[0];

    # Do forward rules first
    if ($direction eq "\x{2192}") {
        # Filter
        my $filter = join '', @$terms;
        if ($terms->[0] =~ /^\[/) {
            $filter =~ s/^(\[ # Start with a [
                (?:
                    [^\[\]]++ # One or more non [] not backtracking
                    (?<!\\)   # Not preceded by a single back slash
                    (?>\\\\)* # After we eat an even number of 0 or more backslashes
                    |
                    (?1)     # Recurs capture group 1
                )*
                \]           # Followed by the terminating ]
                )
                \K           # Keep all that and
                .*$//x;      # Remove the rest

            return process_transform_filter($filter)
        }
        # Transform Rules
        my ($from, $to) = $filter =~ /^(?:(\w+)-)?(\w+)/;
		
		return () unless defined( $from ) + defined( $to );
		
        foreach ($from, $to) {
            $_ = 'Any' unless defined $_;
            s/^und/Any/;
        }

        return {
            type => 'transform',
            from => $from,
            to   => $to,
        }
    }
    else { # Reverse
        # Filter
        my $filter = join '', @$terms;
        
        # Look for a reverse filter
        if ($terms->[0] =~ /^\(\s*\[/) {
            $filter =~ s/^\(
            	(\[               # Start with a [
                    (?:
                        [^\[\]]++ # One or more non [] not backtracking
                        (?<!\\)   # Not preceded by a single back slash
                        (?>\\\\)* # After we eat an even number of 0 or more backslashes
                        |
                        (?1)      # Recurs capture group 1
                    )*
                \]                # Followed by the terminating ]
                )
                \)
                \K                # Keep all that and
                .*$//x;           # Remove the rest

            # Remove the brackets
            $filter =~ s/^\(\s*(.*\S)\s*\)/$1/;
            return process_transform_filter($filter)
        }
        # Transform Rules
        my ($from, $to) = $filter =~ /^(?:\S+)?\((?:(\w+)-)?(\w+)\)/;
		
		return () unless defined( $from ) + defined( $to );
		
        foreach ($from, $to) {
            $_ = 'Any' unless length $_;
            s/^und/Any/;
        }

        return {
            type => 'transform',
            from => $from,
            to   => $to,
        }
    }
}

sub process_transform_filter {
    my $filter = shift;
    my $match = unicode_to_perl($filter);

    return {
        type => 'filter',
        match => qr/\G$match/im,
    }
}

sub process_transform_substitute_var {
    my ($vars, $string) = @_;

    return $string =~ s/(\$\p{XID_Start}\p{XID_Continue}*)/$vars->{$1}/gr;
}

sub process_transform_rule_forward {
    my ($direction, $terms) = @_;

    my (@lhs, @rhs);
    my $rhs = 0;
    foreach my $term (@$terms) {
        if ($term =~ /$direction/) {
            $rhs = 1;
            next;
        }

        push ( @{$rhs ? \@rhs : \@lhs}, $term);
    }
    my $before = 0;
    my (@before, @replace, @after);

    $before = 1 if any { '{' eq $_ } @lhs;
    if ($before) {
        while (my $term = shift @lhs) {
            last if $term eq '{';
            push @before, $term;
        }
    }
    while (my $term = shift @lhs) {
        last if $term eq '}';
        next if ($term eq '|');
        push @replace, $term;
    }
    @after = @lhs;

    # Done lhs now do rhs
    if (any { '{' eq $_ } @rhs) {
        while (my $term = shift @rhs) {
            last if $term eq '{';
        }
    }
    my (@result, @revisit);
    my $revisit = 0;
    while (my $term = shift @rhs) {
        last if $term eq '}';
        if ($term eq '|') {
            $revisit = 1;
            next;
        }

        push(@{ $revisit ? \@revisit : \@result}, $term);
    }

	# Strip out quotes
	foreach my $term (@before, @after, @replace, @result, @revisit) {
		$term =~ s/(?<quote>['"])(.+?)\k<quote>/\\Q$1\\E/g;
		$term =~ s/(["'])(?1)/$1/g;
	}
	
    return {
        type    => 'conversion',
        before  => unicode_to_perl( join('', @before) ),
        after   => unicode_to_perl( join('', @after) ),
        replace => unicode_to_perl( join('', @replace) ),
        result  => join('', @result),
        revisit => join('', @revisit),
    };
}

sub process_transform_rule_backward {
    my ($direction, $terms) = @_;

    my (@lhs, @rhs);
    my $rhs = 0;
    foreach my $term (@$terms) {
        if ($term =~ /$direction/) {
            $rhs = 1;
            next;
        }

        push ( @{$rhs ? \@rhs : \@lhs}, $term);
    }
    my $before = 0;
    my (@before, @replace, @after);

    $before = 1 if any { '{' eq $_ } @rhs;
    if ($before) {
        while (my $term = shift @rhs) {
            last if $term eq '{';
            push @before, $term;
        }
    }
    while (my $term = shift @rhs) {
        last if $term eq '}';
        next if ($term eq '|');
        push @replace, $term;
    }
    @after = @rhs;

    # Done lhs now do rhs
    if (any { '{' eq $_ } @lhs) {
        while (my $term = shift @lhs) {
            last if $term eq '{';
        }
    }
    my (@result, @revisit);
    my $revisit = 0;
    while (my $term = shift @lhs) {
        last if $term eq '}';
        if ($term eq '|') {
            $revisit = 1;
            next;
        }

        push(@{ $revisit ? \@revisit : \@result}, $term);
    }

	# Strip out quotes and escapes
	foreach my $term (@before, @after, @replace, @result, @revisit) {
	    $term =~ s/(?:\\\\)*+\K\\([^\\])/\Q$1\E/g;
		$term =~ s/\\\\/\\/g;
		$term =~ s/(?<quote>['"])(.+?)\k<quote>/\\Q$1\\E/g;
		$term =~ s/(["'])(?1)/$1/g;
	}
	
    return {
        type    => 'conversion',
        before  => unicode_to_perl( join('', @before) ),
        after   => unicode_to_perl( join('', @after) ),
        replace => unicode_to_perl( join('', @replace) ),
        result  => join('', @result),
        revisit => join('', @revisit),
    };
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
	return qr/$regex/;
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
				\s*      		# Possible Whitespace
				(?&posix)		# A posix class
				(?!         	# Not followed by
					\s*			# Possible whitespace
					[&-]    	# A Unicode regex op
					\s*     	# Possible whitespace
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

# Rule based number formats
sub process_rbnf {
	my ($file, $xml) = @_;
	
	use bignum;
	
	# valid_algorithmic_formats
	my @valid_formats;
	my %types = ();
	my $rulesetGrouping_nodes = findnodes($xml, q(/ldml/rbnf/rulesetGrouping));
	
	foreach my $rulesetGrouping_node ($rulesetGrouping_nodes->get_nodelist()) {
		my $grouping = $rulesetGrouping_node->getAttribute('type');
		
		my $ruleset_nodes = findnodes($xml, qq(/ldml/rbnf/rulesetGrouping[\@type='$grouping']/ruleset));
		
		foreach my $ruleset_node ($ruleset_nodes->get_nodelist()) {
			my $ruleset = $ruleset_node->getAttribute('type');
			my $access  = $ruleset_node->getAttribute('access');
			push @valid_formats, $ruleset unless $access && $access eq 'private';
			
			my $ruleset_attributes = "\@type='$ruleset'" . ($access ne '' ? " and \@access='$access'" : '');
			
			my $rule_nodes = findnodes($xml, qq(/ldml/rbnf/rulesetGrouping[\@type='$grouping']/ruleset[$ruleset_attributes]/rbnfrule));
			
			foreach my $rule ($rule_nodes->get_nodelist()) {
				my $base = $rule->getAttribute('value');
				my $divisor = $rule->getAttribute('radix');
				my $rule = $rule->getChildNode(1)->getNodeValue();
				
				$rule =~ s/;.*$//;
				
				my @base_value = ($base =~ /[^0-9]/ ? () : ( base_value => $base ));
				# We add .5 to $base below to offset rounding errors
				my @divisor = ( divisor => ($divisor || ($base_value[1] ? (10 ** ($base ? int( log( $base+ .5 ) / log(10) ) : 0) ) :1 )));
				$types{$ruleset}{$access || 'public'}{$base} = {
					rule => $rule,
					@divisor,
					@base_value
				};
			}
		}
	}
	
	if (@valid_formats) {
		my $valid_formats = "'" . join("','", @valid_formats) . "'";
		print $file <<EOT;
has 'valid_algorithmic_formats' => (
	is => 'ro',
	isa => 'ArrayRef',
	init_arg => undef,
	default => sub {[ $valid_formats ]},
);

EOT
	}
	
	print $file <<EOT;
has 'algorithmic_number_format_data' => (
	is => 'ro',
	isa => 'HashRef',
	init_arg => undef,
	default => sub { 
		use bignum;
		return {
EOT
	foreach my $ruleset (sort keys %types) {
		say $file "\t\t'$ruleset' => {";
		foreach my $access (sort keys %{$types{$ruleset}}) {
			say $file "\t\t\t'$access' => {";
			my $max = 0;
			no warnings;
			foreach my $type (sort { $a <=> $b || $a cmp $b } keys %{$types{$ruleset}{$access}}) {
				$max = $type;
				say $file "\t\t\t\t'$type' => {";
				foreach my $data (sort keys %{$types{$ruleset}{$access}{$type}}) {
					say $file "\t\t\t\t\t$data => q($types{$ruleset}{$access}{$type}{$data}),";
				}
				say $file "\t\t\t\t},";
			}
			say $file "\t\t\t\t'max' => {";
				foreach my $data (sort keys %{$types{$ruleset}{$access}{$max}}) {
					say $file "\t\t\t\t\t$data => q($types{$ruleset}{$access}{$max}{$data}),";
				}
			say $file "\t\t\t\t},";
			say $file "\t\t\t},";
		}
		say $file "\t\t},";
	}
	print $file <<EOT;
	} },
);

EOT
}

sub write_out_number_formatter {
	# In order to keep git out of the CLDR directory we need to 
	# write out the code for the CLDR::NumberFormater module
	my $file = shift;
	
	say $file <<EOT;
package Locale::CLDR::NumberFormatter;

use version;

our \$VERSION = version->declare('v$VERSION');
EOT
	binmode DATA, ':utf8';
	while (my $line = <DATA>) {
		last if $line =~ /^__DATA__/;
		print $file $line;
	}
}

=for comment

sub write_out_collator {
	# In order to keep git out of the CLDR directory we need to 
	# write out the code for the CLDR::Collator module
	my $file = shift;
	
	say $file <<EOT;
package Locale::CLDR::Collator;

use version;

our \$VERSION = version->declare('v$VERSION');
EOT
	print $file $_ while (<DATA>);
}

=end

=cut

sub build_bundle {
	my ($directory, $territories, $name, $territory_names) = @_;

	say "Building Bundle ", ucfirst lc $name if $verbose;
	
	$name =~ s/[^a-zA-Z0-9]//g;
	$name = ucfirst lc $name;

	my $packages = defined $territory_names
		?expand_territories($territories, $territory_names)
		:$territories;
	
	my $filename = File::Spec->catfile($directory, "${name}.pm");

	open my $file, '>', $filename;
	
	print $file <<EOT;
package Bundle::Locale::CLDR::$name;

use version;

our \$VERSION = version->declare('v$VERSION');

=head1 NAME Bundle::Locale::CLDR::$name

=head1 CONTENTS

EOT

	foreach my $package (@$packages) {
		# Only put En and Root in the base bundle
		next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::Root';
		next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::En';
		say $file "$package $VERSION" ;
	}

	print $file <<EOT;

=cut

1;

EOT

}

sub expand_territories {
	my ($territories, $names) = @_;
	
	my %packages;
	foreach my $territory (@$territories) {
		my $packages = $territory_to_package{lc $territory};
		$packages //= [ 'Bundle::Locale::CLDR::' . ucfirst lc (($names->{$territory} // $territory) =~ s/[^a-zA-Z0-9]//gr) ];
		foreach my $package (@$packages) {
			eval "require $package";
			my @packages = grep /Locale::CLDR/, $package->can('meta')
				? $package->meta->linearized_isa
				: $package;
			@packages{@packages} = ();
		}
	}
	
	return [sort { length $a <=> length $b || $a cmp $b } keys %packages];
}

sub build_distributions {
	make_path($distributions_directory) unless -d $distributions_directory;

	build_base_distribution();
	build_transforms_distribution();
	build_language_distributions();
	build_territory_distributions();
}

sub copy_tests {
	my $distribution = shift;
	
	my $source_directory = File::Spec->catdir($tests_directory, $distribution);
	my $destination_directory = File::Spec->catdir($distributions_directory, $distribution, 't');
	make_path($destination_directory) unless -d $destination_directory;
	
	opendir my $dir, $source_directory;
	while (my $file = readdir($dir)) {
		next if $file =~/^\./;
		copy(File::Spec->catfile($source_directory, $file), $destination_directory);
	}
}

sub make_distribution {
	my $path = shift;
	chdir $path;
	system( 'perl', 'Build.PL');
	system( qw( perl Build manifest));
	system( qw( perl Build dist));
	chdir $FindBin::Bin;
}

sub build_base_distribution {

	my $distribution = File::Spec->catdir($distributions_directory, qw(Base lib));
	make_path($distribution)
		unless -d $distribution;

	copy_tests('Base');
	
	open my $build_file, '>', File::Spec->catfile($distributions_directory, 'Base','Build.PL');
	print $build_file <<EOT;
use strict;
use warnings;
use Module::Build;

my \$builder = Module::Build->new(
    module_name         => 'Locale::CLDR',
    license             => 'perl',
    requires        => {
        'version'                   => '0.95',
        'DateTime'                  => '0.72',
        'Moose'                     => '2.0401',
        'MooseX::ClassAttribute'    => '0.26',
        'perl'                      => '5.10.0',
    },
    dist_author         => q{John Imrie <john.imrie1\@gmail.com>},
    dist_version_from   => 'lib/Locale/CLDR.pm',
    build_requires => {
        'ok'                => 0,
        'Test::Exception'   => 0,
        'Test::More'        => '0.98',
    },
    add_to_cleanup      => [ 'Locale-CLDR-*' ],
	configure_requires => { 'Module::Build' => '0.40' },
    create_makefile_pl => 'traditional',
	release_status => '$RELEASE_STATUS',
);

\$builder->create_build_script();
EOT

	close $build_file;
	
	foreach my $file (@base_bundle) {
		my @path = split /::/, $file;
		$path[-1] .= '.pm';
		my $source_name = File::Spec->catfile($build_directory, @path);
		my $destination_name = File::Spec->catdir($distribution, @path[0 .. @path - 2]);
		make_path($destination_name)
			unless -d $destination_name;
		copy($source_name, $destination_name);
	}
	
	# Get the readme and changes files
	copy(File::Spec->catfile($FindBin::Bin, 'README'), File::Spec->catdir($distributions_directory, 'Base'));
	copy(File::Spec->catfile($FindBin::Bin, 'CHANGES'), File::Spec->catdir($distributions_directory, 'Base'));
	make_distribution(File::Spec->catdir($distributions_directory, 'Base'));
}

sub build_text {
	my ($module, $version) = @_;
	$file = $module;
	if ($version) {
		$version = "/$version";
	}
	else {
		$version = '';
		$file =~ s/::/\//g;
	}
	
	my $build_text = <<EOT;
use strict;
use warnings;
use Module::Build;

my \$builder = Module::Build->new(
    module_name         => 'Locale::CLDR::$module',
    license             => 'perl',
    requires        => {
        'version'                   => '0.95',
        'DateTime'                  => '0.72',
        'Moose'                     => '2.0401',
        'MooseX::ClassAttribute'    => '0.26',
        'perl'                      => '5.10.0',
		'Locale::CLDR'              => '$VERSION'
    },
    dist_author         => q{John Imrie <john.imrie1\@gmail.com>},
    dist_version_from   => 'lib/Locale/CLDR/$file$version',
    build_requires => {
        'ok'                => 0,
        'Test::Exception'   => 0,
        'Test::More'        => '0.98',
    },
    add_to_cleanup      => [ 'Locale-CLDR-$module-*' ],
	configure_requires => { 'Module::Build' => '0.40' },
    create_makefile_pl => 'traditional',
	release_status => '$RELEASE_STATUS',
	dist_abstract => 'Locale::CLDR - Data Package $module',
);

\$builder->create_build_script();
EOT

	return $build_text;
}

sub get_files_recursive {
	my $dir_name = shift;
	$dir_name = [$dir_name] unless ref $dir_name;
	
	my @files;
	opendir my $dir, File::Spec->catdir(@$dir_name);
	while (my $file = readdir($dir)) {
		next if $file =~ /^\./;
		if (-d File::Spec->catdir(@$dir_name, $file)) {
			push @files, get_files_recursive([@$dir_name, $file]);
		}
		else {
			push @files, [@$dir_name, $file];
		}
	}
	
	return @files;
}

sub build_transforms_distribution {
	my $distribution = File::Spec->catdir($distributions_directory, qw(Transformations lib));
	make_path($distribution)
		unless -d $distribution;

	copy_tests('Transformations');
	
	open my $build_file, '>', File::Spec->catfile($distributions_directory, 'Transformations','Build.PL');
	print $build_file build_text('Transformations', 'Any/Any/Accents.pm');
	close $build_file;
	
	my @files = get_files_recursive($transformations_directory);
	
	foreach my $file (@files) {
		my $source_name = File::Spec->catfile(@$file);
		my $destination_name = File::Spec->catdir($distribution, qw(Locale CLDR Transformations), @{$file}[1 .. @$file - 2]);
		make_path($destination_name)
			unless -d $destination_name;
		copy($source_name, $destination_name);
	}
	
	make_distribution(File::Spec->catdir($distributions_directory, 'Transformations'));
}

sub build_language_distributions {
	opendir (my $dir, $locales_directory);
	while (my $file = readdir($dir)) {
		next unless -f File::Spec->catfile($locales_directory, $file);

		my $language = $file;
		$language =~ s/\.pm$//;
		my $distribution = File::Spec->catdir($distributions_directory, $language, 'lib');
		make_path($distribution)
			unless -d $distribution;

		copy_tests($language);
	
		open my $build_file, '>', File::Spec->catfile($distributions_directory, $language,'Build.PL');
		print $build_file build_text("Locales::$file");
		close $build_file;
	
		my $source_name = File::Spec->catfile($locales_directory, $file);
		my $destination_name = File::Spec->catdir($distribution, qw(Locale CLDR Locales), $file);
		make_path(File::Spec->catdir($distribution, qw(Locale CLDR Locales)))
			unless -d File::Spec->catdir($distribution, qw(Locale CLDR Locales));
		copy($source_name, $destination_name);
		
		my @files = (
			get_files_recursive(File::Spec->catdir($locales_directory, $language))
		);
	
		foreach my $file (@files) {
			my $source_name = File::Spec->catfile(@$file);
			my $destination_name = File::Spec->catdir($distribution, qw(Locale CLDR Locales), $language, @{$file}[1 .. @$file - 2]);
			make_path($destination_name)
				unless -d $destination_name;
			copy($source_name, $destination_name);
		}
	
		make_distribution(File::Spec->catdir($distributions_directory, $language));
	}
}

sub build_territory_distributions{
}

__DATA__

use v5.10;
use mro 'c3';
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Moose::Role;

sub format_number {
	my ($self, $number, $format, $currency, $for_cash) = @_;
	
	# Check if the locales numbering system is algorithmic. If so ignore the format
	my $numbering_system = $self->default_numbering_system();
	if ($self->numbering_system->{$numbering_system}{type} eq 'algorithmic') {
		$format = $self->numbering_system->{$numbering_system}{data};
		return $self->_algorithmic_number_format($number, $format);
	}
	
	$format //= '0';
	
	return $self->_format_number($number, $format, $currency, $for_cash);
}

sub _format_number {
	my ($self, $number, $format, $currency, $for_cash) = @_;
	
	# First check to see if this is an algorithmic format
	my @valid_formats = $self->_get_valid_algorithmic_formats();
	
	if (grep {$_ eq $format} @valid_formats) {
		return $self->_algorithmic_number_format($number, $format);
	}
	
	# Some of these algorithmic formats are in locale/type/name format
	if (my ($locale_id, $type, $format) = $format =~ m(^(.*?)/(.*?)/(.*?)$)) {
		my $locale = Locale::CLDR->new($locale_id);
		return $locale->format_number($number, $format);
	}
	
	my $currency_data;
	
	# Check if we need a currency and have not been given one.
	# In that case we look up the default currency for the locale
	if ($format =~ tr/¤/¤/) {
	
		$for_cash //=0;
		
		$currency = $self->default_currency()
			if ! defined $currency;
		
		$currency_data = $self->_get_currency_data($currency);
		
		$currency = $self->currency_symbol($currency);
	}
	
	$format = $self->parse_number_format($format, $currency, $currency_data, $for_cash);
	
	$number = $self->get_formatted_number($number, $format, $currency_data, $for_cash);
	
	return $number;
}

sub add_currency_symbol {
	my ($self, $format, $symbol) = @_;
	
	
	$format =~ s/¤/'$symbol'/;
	
	return $format;
}

sub _get_currency_data {
	my ($self, $currency) = @_;
	
	my $currency_data = $self->currency_fractions($currency);
	
	return $currency_data;
}

sub _get_currency_rounding {

	my ($self, $currency_data, $for_cash) = @_;
	
	my $rounder = $for_cash ? 'cashrounding' : 'rounding' ;
	
	return $currency_data->{$rounder};
}

sub _get_currency_digits {
	my ($self, $currency_data, $for_cash) = @_;
	
	my $digits = $for_cash ? 'cashdigits' : 'digits' ;
	
	return $currency_data->{$digits};
}

sub parse_number_format {
	my ($self, $format, $currency, $currency_data, $for_cash) = @_;

	use feature 'state';
	
	state %cache;
	
	return $cache{$format} if exists $cache{$format};
	
	$format = $self->add_currency_symbol($format, $currency)
		if defined $currency;
	
	my ($positive, $negative) = $format =~ /^((?:(?:'[^']*')*+[^';]+)+) (?:;(.+))?$/x;
	
	my $type = 'positive';
	foreach my $to_parse ( $positive, $negative ) {
		last unless defined $to_parse;
		my ($prefix, $suffix);
		if (($prefix) = $to_parse =~ /^((?:[^0-9@#.,E+'*-] | (?:'[^']*')++)+)/x) {
			$to_parse =~ s/^((?:[^0-9@#.,E+'*-] | (?:'[^']*')++)+)//x;
		}
		if( ($suffix) = $to_parse =~ /((?:[^0-9@#.,E+'-] | (?:'[^']*')++)+)$/x) {
			$to_parse =~ s/((?:[^0-9@#.,E+'-] | (?:'[^']*')++)+)$//x;
		}
		
		# Fix escaped '
		foreach my $str ($prefix, $suffix) {
			$str //= '';
			$str =~ s/'((?:'')++ | [^']+)'/$1/gx;
			$str =~ s/''/'/g;
		}
		
		# Look for padding
		my ($pad_character, $pad_location);
		if (($pad_character) = $prefix =~ /^\*(\p{Any})/ ) {
			$prefix =~ s/^\*(\p{Any})//;
			$pad_location = 'before prefix';
		}
		elsif ( ($pad_character) = $prefix =~ /\*(\p{Any})$/ ) {
			$prefix =~ s/\*(\p{Any})$//;
			$pad_location = 'after prefix';
		}
		elsif (($pad_character) = $suffix =~ /^\*(\p{Any})/ ) {
			$suffix =~ s/^\*(\p{Any})//;
			$pad_location = 'before suffix';
		}
		elsif (($pad_character) = $suffix =~ /\*(\p{Any})$/ ) {
			$suffix =~ s/\*(\p{Any})$//;
			$pad_location = 'after suffix';
		}
		
		my $pad_length = defined $pad_character 
			? length($prefix) + length($to_parse) + length($suffix) + 2
			: 0;
		
		# Check for a multiplier
		my $multiplier = 1;
		$multiplier = 100  if $prefix =~ tr/%/%/ || $suffix =~ tr/%/%/;
		$multiplier = 1000 if $prefix =~ tr/‰/‰/ || $suffix =~ tr/‰/‰/;
		
		my $rounding = $to_parse =~ /([1-9][0-9]*(?:\.[0-9]+)?)/;
		$rounding ||= 0;
		
		$rounding = $self->_get_currency_rounding($currency_data, $for_cash)
			if defined $currency;
		
		my ($integer, $decimal) = split /\./, $to_parse;
		
		my ($minimum_significant_digits, $maximum_significant_digits, $minimum_digits);
		if (my ($digits) = $to_parse =~ /(\@+)/) { 
			$minimum_significant_digits = length $digits;
			($digits ) = $to_parse =~ /\@(#+)/;
			$maximum_significant_digits = $minimum_significant_digits + length ($digits // '');
		}
		else {
			$minimum_digits = $integer =~ tr/0-9/0-9/;
		}
		
		# Check for exponent
		my $exponent_digits = 0;
		my $need_plus = 0;
		my $exponent;
		my $major_group;
		my $minor_group;
		if ($to_parse =~ tr/E/E/) {
			($need_plus, $exponent) = $to_parse  =~ m/E(\+?)([0-9]+)/;
			$exponent_digits = length $exponent;
		}
		else {
			# Check for grouping
			my ($grouping) = split /\./, $to_parse;
			my @groups = split /,/, $grouping;
			shift @groups;
			($major_group, $minor_group) = map {length} @groups;
			$minor_group //= $major_group;
		}
		
		$cache{$format}{$type} = {
			prefix 						=> $prefix // '',
			suffix 						=> $suffix // '',
			pad_character 				=> $pad_character,
			pad_location				=> $pad_location // 'none',
			pad_length					=> $pad_length,
			multiplier					=> $multiplier,
			rounding					=> $rounding,
			minimum_significant_digits	=> $minimum_significant_digits, 
			maximum_significant_digits	=> $maximum_significant_digits,
			minimum_digits				=> $minimum_digits // 0,
			exponent_digits				=> $exponent_digits,
			exponent_needs_plus			=> $need_plus,
			major_group					=> $major_group,
			minor_group					=> $minor_group,
		};
		
		$type = 'negative';
	}
	
	$cache{$format}{negative} //= $cache{$format}{positive};
	return $cache{$format};
}

# Rounding function
sub round {
	my ($self, $number, $increment, $decimal_digits) = @_;

	if ($increment ) {
		$number /= $increment;
		$number = int ($number + .5 );
		$number *= $increment;
	}
	
	if ( $decimal_digits ) {
		$number *= 10 ** $decimal_digits;
		$number = int $number;
		$number /= 10 ** $decimal_digits;
		
		my ($decimal) = $number =~ /(\..*)/; 
		$decimal //= '.'; # No fraction so add a decimal point
		
		$number = int ($number) . $decimal . ('0' x ( $decimal_digits - length( $decimal ) +1 ));
	}
	else {
		# No decimal digits wanted
		$number = int $number;
	}
	
	return $number;
}

sub get_formatted_number {
	my ($self, $number, $format, $currency_data, $for_cash) = @_;
	
	my @digits = $self->get_digits;
	my @number_symbols_bundles = reverse $self->_find_bundle('number_symbols');
	my %symbols = map { %{$_->number_symbols} } @number_symbols_bundles;
	my $symbols_type = $self->default_numbering_system;
	
	$symbols_type = $symbols{$symbols_type}{alias} if exists $symbols{$symbols_type}{alias};
	
	my $type = $number < 0 ? 'negative' : 'positive';
	
	$number *= $format->{$type}{multiplier};
	
	if ($format->{rounding} || defined $for_cash) {
		my $decimal_digits = 0;
		
		if (defined $for_cash) {
			$decimal_digits = $self->_get_currency_digits($currency_data, $for_cash)
		}
		
		$number = $self->round($number, $format->{$type}{rounding}, $decimal_digits);
	}
	
	my $pad_zero = $format->{$type}{minimum_digits} - length "$number";
	if ($pad_zero > 0) {
		$number = ('0' x $pad_zero) . $number;
	}
	
	# Handle grouping
	my ($integer, $decimal) = split /\./, $number;

	my ($separator, $decimal_point) = ($symbols{$symbols_type}{group}, $symbols{$symbols_type}{decimal});
	my ($minor_group, $major_group) = ($format->{$type}{minor_group}, $format->{$type}{major_group});
	
	if (defined $minor_group && $separator) {
		# Fast commify using unpack
		my $pattern = "(A$minor_group)(A$major_group)*";
		$number = reverse join $separator, grep {length} unpack $pattern, reverse $integer;
	}
	
	$number.= "$decimal_point$decimal" if defined $decimal;
	
	# Fix digits
	$number =~ s/([0-9])/$digits[$1]/eg;
		
	my ($prefix, $suffix) = ( $format->{$type}{prefix}, $format->{$type}{suffix});
	
	# This needs fixing for escaped symbols
	foreach my $string ($prefix, $suffix) {
		$string =~ s/%/$symbols{$symbols_type}{percentSign}/;
		$string =~ s/‰/$symbols{$symbols_type}{perMille}/;
	}
	
	$number = $prefix . $number . $suffix;
	
	return $number;
}

# Get the digits for the locale. Assumes a numeric numbering system
sub get_digits {
	my $self = shift;
	
	my $numbering_system = $self->default_numbering_system();
	
	$numbering_system = 'latn' unless  $self->numbering_system->{$numbering_system}{type} eq 'numeric'; # Fall back to latn if the numbering system is not numeric
	
	my $digits = $self->numbering_system->{$numbering_system}{data};
	
	return @$digits;
}

# RBNF
# Note that there are a couple of assumptions with the way
# I handle Rule Base Number Formats.
# 1) The number is treated as a string for as long as possible
#	This allows things like -0.0 to be correctly formatted
# 2) There is no fall back. All the rule sets are self contained
#	in a bundle. Fall back is used to find a bundle but once a 
#	bundle is found no further processing of the bundle chain
#	is done. This was found by trial and error when attempting 
#	to process -0.0 correctly into English.
sub _get_valid_algorithmic_formats {
	my $self = shift;
	
	my @formats = map { @{$_->valid_algorithmic_formats()} } $self->_find_bundle('valid_algorithmic_formats');
	
	my %seen;
	return sort grep { ! $seen{$_}++ } @formats;
}

# Main entry point to RBNF
sub _algorithmic_number_format {
	my ($self, $number, $format_name, $type) = @_;
	
	my $format_data = $self->_get_algorithmic_number_format_data_by_name($format_name, $type);
	
	return $number unless $format_data;
	
	return $self->_process_algorithmic_number_data($number, $format_data);
}

sub _get_algorithmic_number_format_data_by_name {
	my ($self, $format_name, $type) = @_;
	
	# Some of these algorithmic formats are in locale/type/name format
	if (my ($locale_id, undef, $format) = $format_name =~ m(^(.*?)/(.*?)/(.*?)$)) {
		my $locale = Locale::CLDR->new($locale_id);
		return $locale->_get_algorithmic_number_format_data_by_name($format, $type)
			if $locale;

		return undef;
	}
	
	$type //= 'public';
	
	my %data = ();
	
	my @data_bundles = $self->_find_bundle('algorithmic_number_format_data');
	foreach my $data_bundle (@data_bundles) {
		my $data = $data_bundle->algorithmic_number_format_data();
		next unless $data->{$format_name};
		next unless $data->{$format_name}{$type};
		
		foreach my $rule (keys %{$data->{$format_name}{$type}}) {
			$data{$rule} = $data->{$format_name}{$type}{$rule};
		}
		
		last;
	}
	
	return keys %data ? \%data : undef;
}
	
sub _process_algorithmic_number_data {
	my ($self, $number, $format_data, $in_fraction_rule_set) = @_;
	
	$in_fraction_rule_set //= 0;
	
	my $format = $self->_get_algorithmic_number_format($number, $format_data);
	
	my $format_rule = $format->{rule};
	my $divisor = $format->{divisor};
	my $base_value = $format->{base_value} // '';
	
	# Negative numbers
	if ($number =~ /^-/) {
		my $positive_number = $number;
		$positive_number =~ s/^-//;
		
		if ($format_rule =~ /→→/) {
			$format_rule =~ s/→→/$self->_process_algorithmic_number_data($positive_number, $format_data)/e;
		}
		elsif((my $rule_name) = $format_rule =~ /→(.+)→/) {
			my $type = 'public';
			if ($rule_name =~ s/^%%/%/) {
				$type = 'private';
			}
			my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
			if($format_data) {
				# was a valid name
				$format_rule =~ s/→(.+)→/$self->_process_algorithmic_number_data($positive_number, $format_data)/e;
			}
			else {
				# Assume a format
				$format_rule =~ s/→(.+)→/$self->_format_number($positive_number, $1)/e;
			}
		}
		elsif($format_rule =~ /=%%.*=/) {
			$format_rule =~ s/=%%(.*?)=/$self->_algorithmic_number_format($number, $1, 'private')/eg;
		}
		elsif($format_rule =~ /=%.*=/) {
			$format_rule =~ s/=%(.*?)=/$self->_algorithmic_number_format($number, $1, 'public')/eg;
		}
		elsif($format_rule =~ /=.*=/) {
			$format_rule =~ s/=(.*?)=/$self->_format_number($number, $1)/eg;
		}
	}
	# Fractions
	elsif( $number =~ /\./ ) {
		my $in_fraction_rule_set = 1;
		my ($integer, $fraction) = $number =~ /^([^.]*)\.(.*)$/;
		
		if ($number >= 0 && $number < 1) {
			$format_rule =~ s/\[.*\]//;
		}
		else {
			$format_rule =~ s/[\[\]]//g;
		}
		
		if ($format_rule =~ /→→/) {
			$format_rule =~ s/→→/$self->_process_algorithmic_number_data_fractions($fraction, $format_data)/e;
		}
		elsif((my $rule_name) = $format_rule =~ /→(.*)→/) {
			my $type = 'public';
			if ($rule_name =~ s/^%%/%/) {
				$type = 'private';
			}
			my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
			if ($format_data) {
				$format_rule =~ s/→(.*)→/$self->_process_algorithmic_number_data_fractions($fraction, $format_data)/e;
			}
			else {
				$format_rule =~ s/→(.*)→/$self->_format_number($fraction, $1)/e;
			}
		}
		
		if ($format_rule =~ /←←/) {
			$format_rule =~ s/←←/$self->_process_algorithmic_number_data($integer, $format_data, $in_fraction_rule_set)/e;
		}
		elsif((my $rule_name) = $format_rule =~ /←(.+)←/) {
			my $type = 'public';
			if ($rule_name =~ s/^%%/%/) {
				$type = 'private';
			}
			my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
			if ($format_data) {
				$format_rule =~ s/←(.*)←/$self->_process_algorithmic_number_data($integer, $format_data, $in_fraction_rule_set)/e;
			}
			else {
				$format_rule =~ s/←(.*)←/$self->_format_number($integer, $1)/e;
			}
		}
		
		if($format_rule =~ /=.*=/) {
			if($format_rule =~ /=%%.*=/) {
				$format_rule =~ s/=%%(.*?)=/$self->_algorithmic_number_format($number, $1, 'private')/eg;
			}
			elsif($format_rule =~ /=%.*=/) {
				$format_rule =~ s/=%(.*?)=/$self->_algorithmic_number_format($number, $1, 'public')/eg;
			}
			else {
				$format_rule =~ s/=(.*?)=/$self->_format_number($integer, $1)/eg;
			}
		}
	}
	
	# Everything else
	else {
		# At this stage we have a non negative integer
		if ($format_rule =~ /\[.*\]/) {
			if ($in_fraction_rule_set && $number * $base_value == 1) {
				$format_rule =~ s/\[.*\]//;
			}
			# Not fractional rule set      Number is a multiple of $divisor and the multiple is even
			elsif (! $in_fraction_rule_set && ! ($number % $divisor) ) {
				$format_rule =~ s/\[.*\]//;
			}
			else {
				$format_rule =~ s/[\[\]]//g;
			}
		}
		
		if ($in_fraction_rule_set) {
			if (my ($rule_name) = $format_rule =~ /←(.*)←/) {
				if (length $rule_name) {
					my $type = 'public';
					if ($rule_name =~ s/^%%/%/) {
						$type = 'private';
					}
					my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
					if ($format_data) {
						$format_rule =~ s/←(.*)←/$self->_process_algorithmic_number_data($number * $base_value, $format_data, $in_fraction_rule_set)/e;
					}
					else {
						$format_rule =~ s/←(.*)←/$self->_format_number($number * $base_value, $1)/e;
					}
				}
				else {
					$format_rule =~ s/←←/$self->_process_algorithmic_number_data($number * $base_value, $format_data, $in_fraction_rule_set)/e;
				}
			}
			elsif($format_rule =~ /=.*=/) {
				$format_rule =~ s/=(.*?)=/$self->_format_number($number, $1)/eg;
			}
		}
		else {
			if (my ($rule_name) = $format_rule =~ /→(.*)→/) {
				if (length $rule_name) {
					my $type = 'public';
					if ($rule_name =~ s/^%%/%/) {
						$type = 'private';
					}
					my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
					if ($format_data) {
						$format_rule =~ s/→(.+)→/$self->_process_algorithmic_number_data($number % $divisor, $format_data)/e;
					}
					else {
						$format_rule =~ s/→(.*)→/$self->_format_number($number % $divisor, $1)/e;
					}
				}
				else {
					$format_rule =~ s/→→/$self->_process_algorithmic_number_data($number % $divisor, $format_data)/e;
				}
			}
			
			if (my ($rule_name) = $format_rule =~ /←(.*)←/) {
				if (length $rule_name) {
					my $type = 'public';
					if ($rule_name =~ s/^%%/%/) {
						$type = 'private';
					}
					my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
					if ($format_data) {
						$format_rule =~ s|←(.*)←|$self->_process_algorithmic_number_data(int ($number / $divisor), $format_data)|e;
					}
					else {
						$format_rule =~ s|←(.*)←|$self->_format_number(int($number / $divisor), $1)|e;
					}
				}
				else {
					$format_rule =~ s|←←|$self->_process_algorithmic_number_data(int($number / $divisor), $format_data)|e;
				}
			}
			
			if($format_rule =~ /=.*=/) {
				if($format_rule =~ /=%%.*=/) {
					$format_rule =~ s/=%%(.*?)=/$self->_algorithmic_number_format($number, $1, 'private')/eg;
				}
				elsif($format_rule =~ /=%.*=/) {
					$format_rule =~ s/=%(.*?)=/$self->_algorithmic_number_format($number, $1, 'public')/eg;
				}
				else {
					$format_rule =~ s/=(.*?)=/$self->_format_number($number, $1)/eg;
				}
			}
		}
	}
	
	return $format_rule;
}

sub _process_algorithmic_number_data_fractions {
	my ($self, $fraction, $format_data) = @_;
	
	my $result = '';
	foreach my $digit (split //, $fraction) {
		$result .= $self->_process_algorithmic_number_data($digit, $format_data, 1);
	}
	
	return $result;
}

sub _get_algorithmic_number_format {
	my ($self, $number, $format_data) = @_;
	
	use bignum;
	return $format_data->{'-x'} if $number =~ /^-/ && exists $format_data->{'-x'};
	return $format_data->{'x.x'} if $number =~ /\./ && exists $format_data->{'x.x'};
	return $format_data->{0} if $number == 0 || $number =~ /^-/;
	return $format_data->{max} if $number >= $format_data->{max}{base_value};
	
	my $previous = 0;
	foreach my $key (sort { $a <=> $b } grep /^[0-9]+$/, keys %$format_data) {
		next if $key == 0;
		return $format_data->{$key} if $number == $key;
		return $format_data->{$previous} if $number < $key;
		$previous = $key;
	}
}
	
no Moose::Role;

1;

# vim: tabstop=4
__DATA__
package Locale::CLDR::Collator;

use version;

our $VERSION = version->declare('v0.26.4');

use v5.10;
use mro 'c3';
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Unicode::Normalize('NFD');

use Moose;

with 'Locale::CLDR::CollatorBase';

has 'type' => (
	is => 'ro',
	isa => 'Str',
	default => 'standard',
);

has 'locale' => (
	is => 'ro',
	isa => 'Locale::CLDR',
	required => 1,
);

has 'strength' => (
	is => 'ro',
	isa => 'Int',
	default => 3,
);

# Set up the locale overrides
sub BUILD {
	my $self = shift;
	
	my $overrides = $self->locale->collation_overrides($self->type);
	
	foreach my $override (@$overrides) {
		$self->_set_ce(@$override);
	}
}

sub _get_sort_digraphs_rx {
	my $self = shift;
	
	my $digraphs = $self->_get_sort_digraphs();
	
	my $rx = join '|', @$digraphs, '.';
	
	return qr/$rx/;
}

# Converts $string into a string of Collation Elements
sub getSortKey {
	my ($self, $string) = @_;
	
	$string = NFD($string);
	
	my $entity_rx = $self->_get_sort_digraphs_rx();
	
	(my $ce = $string) =~ s/($entity_rx)/ $self->get_collation_element($1) || do { my $ce = $self->generate_ce($1); $self->_set_ce($1, $ce); $ce } /eg;
		
	my $ce_length = length($ce) / 4;
	
	my $max_level = $self->strength;
	my $key = '';
	
	my @lvl_re = (
		undef,
		'(.)...' x $ce_length,
		'.(.)..' x $ce_length,
		'..(.).' x $ce_length,
		'...(.)' x $ce_length,
	);
	
	foreach my $level ( 1 .. $max_level ) {
		$key .= join '', grep {$_ ne "\x0"} $ce =~ /^$lvl_re[$level]$/;
		$key .= "\x0";
	}
	
	return $key;
}

sub generate_ce {
	my ($character) = @_;
	
	my $base;
	
	if ($character =~ /\p{Unified_Ideograph}/) {
		if ($character =~ /\p{Block=CJK_Unified_Ideograph}/ || $character =~ /\p{Block=CJK_Compatibility_Ideographs}/) {
			$base = 0xFB40;
		}
		else {
			$base = 0xFB80;
		}
	}
	else {
		$base = 0xFBC0;
	}
	
	my $aaaa = $base + unpack( 'L', (pack ('L', ord($character)) >> 15));
	my $bbbb = unpack('L', (pack('L', ord($character)) & 0x7FFF) | 0x8000);
	
	return join '', map {chr($_)} $aaaa, 0x0020, 0x0002,0, $bbbb,0,0,0;
}

# sorts a list according to the locales collation rules
sub sort {
	my $self = shift;
	
	return map { $_->[0]}
		sort { $a->[1] cmp $b->[1] }
		map { [$_, $self->getSortKey($_)] }
		@_;
}

sub cmp {
	my ($self, $a, $b) = @_;
	
	return $self->getSortKey($a) cmp $self->getSortKey($b);
}

sub eq {
	my ($self, $a, $b) = @_;
	
	return $self->getSortKey($a) eq $self->getSortKey($b);
}

sub ne {
	my ($self, $a, $b) = @_;
	
	return $self->getSortKey($a) ne $self->getSortKey($b);
}

sub lt {
	my ($self, $a, $b) = @_;
	
	return $self->getSortKey($a) lt $self->getSortKey($b);
}

sub le {
	my ($self, $a, $b) = @_;
	
	return $self->getSortKey($a) le $self->getSortKey($b);
}
sub gt {
	my ($self, $a, $b) = @_;
	
	return $self->getSortKey($a) lt $self->getSortKey($b);
}

sub ge {
	my ($self, $a, $b) = @_;
	
	return $self->getSortKey($a) le $self->getSortKey($b);
}

# Get Human readable sort key
sub viewSortKey {
	my ($self, $sort_key) = @_;
	
#	my $sort_key = $self->getSortKey($a);
	
	my @levels = split/\x0/, $sort_key;
	
	foreach my $level (@levels) {
		$level = join ' ',  map { sprintf '%0.4X', ord } split //, $level;
	}
	
	return '[ ' . join (' | ', @levels) . ' ]';
}

no Moose;

1;

# vim: tabstop=4
