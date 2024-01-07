#!/usr/bin/perl

# There are two optional parameters to this script -v which turns on verbose output and a file name
# which should be the last successfully processed file should you wish to restart the script after
# a crash or some other stoppage

use v5.18;
use strict;
use warnings;

# Turn all warnings into dies
use warnings 'FATAL';
no warnings "experimental::regex_sets";

# Do all inputs and outputs in utf8. Make sure your 
# command shell can handle that
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
use List::Util qw( min max );
use Unicode::Regex::Set();

use lib "${FindBin::Bin}/lib";

my $start_time = time();
my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');

# Simple way of handling paramaters
our $verbose = 0;
$verbose = 1 if grep /-v/, @ARGV;
@ARGV = grep !/-v/, @ARGV;

use version;
my $API_VERSION     = 0; # This will get bumped if a release is not backwards compatible with the previous release
my $CLDR_VERSION    = '40'; # This needs to match the revision number of the CLDR revision being generated against
my $REVISION        = 1; # This is the build number against the CLDR revision
my $TRIAL_REVISION  = ''; # This is the trial revision for unstable releases. Set to '' for the first trial release after that start counting from 1
our $VERSION        = version->parse(join '.', $API_VERSION, ($CLDR_VERSION=~s/^([^.]+).*/$1/r), $REVISION);
my $CLDR_PATH       = $CLDR_VERSION;

# $RELEASE_STATUS relates to the CPAN status it can be one of 'stable', for a
# full release or 'unstable' for a developer release
my $RELEASE_STATUS = 'stable';

# Set up the names for the directory structure for the build. Using File::Spec here to maximise portability
chdir $FindBin::Bin;
my $data_directory            = File::Spec->catdir($FindBin::Bin, 'Data');
my $core_filename             = File::Spec->catfile($data_directory, 'core.zip');
my $base_directory            = File::Spec->catdir($data_directory, 'common');
my $transform_directory       = File::Spec->catdir($base_directory, 'transforms');
my $build_directory           = File::Spec->catdir($FindBin::Bin, 'lib');
my $lib_directory             = File::Spec->catdir($build_directory, 'Locale', 'CLDR');
my $locales_directory         = File::Spec->catdir($lib_directory, 'Locales');
my $bundles_directory         = File::Spec->catdir($build_directory, 'Bundle', 'Locale', 'CLDR');
my $transformations_directory = File::Spec->catdir($lib_directory, 'Transformations');
my $distributions_directory   = File::Spec->catdir($FindBin::Bin, 'Distributions');
my $tests_directory           = File::Spec->catdir($FindBin::Bin, 't');

# Some sanity checks on the revision and status
if ($TRIAL_REVISION && $RELEASE_STATUS eq 'stable') {
    warn "\$TRIAL_REVISION is set to $TRIAL_REVISION and this is a stable release resetting \$TRIAL_REVISION to ''";
    $TRIAL_REVISION = '';
}

my $dist_suffix = '';
if ($TRIAL_REVISION && $RELEASE_STATUS eq 'unstable') {
    $dist_suffix = "\n    dist_suffix         => 'TRIAL$TRIAL_REVISION',\n";
}

# Check if we have a Data directory
if (! -d $data_directory ) {
    mkdir $data_directory
        or die "Can not create $data_directory: $!";
}

# Check the lib directory
if(! -d $lib_directory) {
    make_path($lib_directory);
}

# There is a lot of say '' if $verbose so I'm going to factor that out
sub vsay(@);
if( $verbose ) {
    *vsay = sub(@) { say @_ };
}
else {
    *vsay = sub(@) {};
}

# This function displays the Processing file message it takes the file name and an 
# optional hash ref containing count => how far through the list of files we are and
# num => the number of files in the list
sub psay {
    my ($count, $num) = (0, 0);
    if (ref $_[-1] eq 'HASH' && $_[-1]{num}) {
        my %args = %{pop @_};
        ($count, $num) = @args{qw( count num )};
        my $percent = $count / $num * 100;
        vsay sprintf("Processing file %s: $count of $num, %.2f%% done", $_[0], $percent);
    }
    else {
        vsay "Processing file ", @_;
    }
}

# Get the data file from the Unicode Consortium
if (! -e $core_filename ) {
    vsay "Getting data file from the Unicode Consortium";

    my $ua = LWP::UserAgent->new(
        agent => "perl Locale::CLDR/$VERSION (Written by john.imrie1\@gmail.com)",
    );
    my $response = $ua->get("http://unicode.org/Public/cldr/$CLDR_PATH/core.zip",
        ':content_file' => $core_filename
    );

    if (! $response->is_success) {
        die "Can not access http://unicode.org/Public/cldr/$CLDR_PATH/core.zip' "
             . $response->status_line;
    }
}

# Now uncompress the file
if (! -d $base_directory) {
    vsay "Extracting Data";
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

# We look at the root.xml data file to get the cldr version number
my $xml_parser = XML::Parser->new(
    NoLWP           => 1,
    ParseParamEnt   => 1,
);

my $vf = XML::XPath->new(
    parser      => $xml_parser,
    filename    => File::Spec->catfile(
        $base_directory,
        'main',
        'root.xml'
    ),
);

vsay "Checking CLDR version";
my $cldrVersion = $vf->findnodes('/ldml/identity/version')
    ->get_node(1)
    ->getAttribute('cldrVersion');

die "Incorrect CLDR Version found $cldrVersion. It should be $CLDR_VERSION"
    unless version->parse("$cldrVersion") == $CLDR_VERSION;

vsay "Processing files";

# Note that the Number Formatter code comes before the collator in the data section
# of this file so this needs to be done first
# Number Formatter
open my $file, '>', File::Spec->catfile($lib_directory, 'NumberFormatter.pm');
write_out_number_formatter($file);
close $file;

# Collator
# The Collater code needs a lot of work on it
{
    open my $file, '>', File::Spec->catfile($lib_directory, 'Collator.pm');
    write_out_collator($file);
    close $file;
}

# This subrouteen factors out the process_header and process_footer calls
# which are used in every generated file it takes the following named arguments
#   name => the name of the XML file the data id being generated from
#   num => the optional number of files to process in the current directory
#   count => the optional number of the currently processed file
#   num and count are used to calculate the percentage done display
#   file => an open file handle to the outputted file
#   packge => name of the package being generated
#   is_role => a flag which if true will mahe this file a Moo::Role
#   is_language => a flag which if true and containing the language name will add a comment with the language name to the generated file
#   subs => an array ref of sub refs that will extract the required data from the given XPath and process it into Perl code then print it to the given output file.
#   subs uses the closure facility to pass in the paramaters to the process_* subrouteens so when we actually call them we don't need to know the parameters
sub process_file {
    my %args = @_;
    psay $args{name}, $args{num} ? { count => $args{count}, num => $args{num}} : ();
    process_header(@args{ qw( file package name is_role is_language) });
    foreach my $sub ( @{$args{subs}} ) {
        $sub->();
    }
    process_footer(@args{ qw( file is_role) });
}

# The next 6 blocks go throughe various bits of supplemental data, 
# data not tied to a specific locale, and convert the XML into 
# Perl modules

# Likely sub-tags
{
    my $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'likelySubtags.xml'
    );

    my $xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile($file_name)
    );

    open my $file, '>', File::Spec->catfile($lib_directory, 'LikelySubtags.pm');
    process_file(
        file    => $file,
        package => 'Locale::CLDR::LikelySubtags',
        name    => $file_name,
        is_role => 1,
        subs    => [
            sub { process_likely_subtags($file, $xml) },
        ],
    );
    close $file;
}

# Numbering Systems
{
    my $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'numberingSystems.xml'
    );

    my $xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile($file_name)
    );

    open my $file, '>', File::Spec->catfile($lib_directory, 'NumberingSystems.pm');
    process_file(
        file    => $file,
        package => 'Locale::CLDR::NumberingSystems',
        name    => $file_name,
        is_role => 1,
        subs    => [
            sub { process_numbering_systems($file, $xml) },
        ],
    );
    close $file;
}

#Plural rules
{
    my $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'plurals.xml'
    );

    my $plural_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile($file_name)
    );

    $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'ordinals.xml'
    );

    my $ordanal_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile($file_name)
    );

    $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'pluralRanges.xml'
    );

    my $plural_ranges_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile($file_name)
    );

    open $file, '>', File::Spec->catfile($lib_directory, 'Plurals.pm');
    process_file(
        file    => $file,
        package => 'Locale::CLDR::Plurals',
        name    => $file_name,
        is_role => 1,
        subs    => [
            sub { process_plurals($file, $plural_xml, $ordanal_xml) },
            sub { process_plural_ranges($file, $plural_ranges_xml) },
        ],
    );
    close $file;
}

# Valid codes
{
    open my $file, '>', File::Spec->catfile($lib_directory, 'ValidCodes.pm');

    my $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'supplementalMetadata.xml'
    );

    my $xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'validity',
            'language.xml',
        )
    );

    my $script_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'validity',
            'script.xml',
        )
    );

    my $region_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'validity',
            'region.xml',
        )
    );

    my $variant_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'validity',
            'variant.xml',
        )
    );

    my $currency_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'validity',
            'currency.xml',
        )
    );

    my $subdivision_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'validity',
            'subdivision.xml',
        )
    );

    my $unit_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'validity',
            'unit.xml',
        )
    );

# The supplemental/supplementalMetaData.xml file contains a list of all valid
# aliases and keys
    my $alias_xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'supplemental',
            'supplementalMetadata.xml',
        )
    );

    process_file(
        file    => $file,
        package => 'Locale::CLDR::ValidCodes',
        name    => $file_name,
        is_role => 1,
        subs    => [
            sub { process_valid_languages($file, $xml) },
            sub { process_valid_scripts($file, $script_xml) },
            sub { process_valid_regions($file, $region_xml) },
            sub { process_valid_variants($file, $variant_xml) },
            sub { process_valid_currencies($file, $currency_xml) },
            sub { process_valid_subdivisions($file, $subdivision_xml) },
            sub { process_valid_units($file, $unit_xml) },
            sub { process_valid_keys($file, $base_directory) },
            sub { process_valid_language_aliases($file, $alias_xml) },
            sub { process_valid_region_aliases($file, $alias_xml) },
            sub { process_valid_variant_aliases($file, $alias_xml) },
        ],
    );
    close $file;
}

my %parent_locales = ();

# Suplimental data
{
    my $xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile(
            $base_directory,
            'supplemental',
            'supplementalData.xml',
        )
    );

    my $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'supplementalData.xml'
    );

    # File for era boundaries
    {
        open my $file, '>', File::Spec->catfile($lib_directory, 'EraBoundries.pm');

        process_file(
            file    => $file,
            package => 'Locale::CLDR::EraBoundries',
            name    => $file_name,
            is_role => 1,
            subs    => [
                sub { process_era_boundries($file, $xml) },
            ],
        );

        close $file;
    }

    # Currency defaults
    {
        open my $file, '>', File::Spec->catfile($lib_directory, 'Currencies.pm');

        process_file(
            file    => $file,
            package => 'Locale::CLDR::Currencies',
            name    => $file_name,
            is_role => 1,
            subs    => [
                sub { process_currency_data($file, $xml) },
            ],
        );

        close $file;
    }

    # region Containment
    {
        open my $file, '>', File::Spec->catfile($lib_directory, 'RegionContainment.pm');

        process_file(
            file    => $file,
            package => 'Locale::CLDR::RegionContainment',
            name    => $file_name,
            is_role => 1,
            subs    => [
                sub { process_region_containment_data($file, $xml) },
            ],
        );

        close $file;
    }

    # Calendar Preferences
    {
        open my $file, '>', File::Spec->catfile($lib_directory, 'CalendarPreferences.pm');

        process_file(
            file    => $file,
            package => 'Locale::CLDR::CalendarPreferences',
            name    => $file_name,
            is_role => 1,
            subs    => [
                sub { process_calendar_preferences($file, $xml) },
            ],
        );

        close $file;
    }

    # Week data
    {
        open my $file, '>', File::Spec->catfile($lib_directory, 'WeekData.pm');

        process_file(
            file    => $file,
            package => 'Locale::CLDR::WeekData',
            name    => $file_name,
            is_role => 1,
            subs    => [
                sub { process_week_data($file, $xml) },
            ],
        );

        close $file;
    }

    # Measurement System Data
    {
        open my $file, '>', File::Spec->catfile($lib_directory, 'MeasurementSystem.pm');
        process_file(
            file    => $file,
            package => 'Locale::CLDR::MeasurementSystem',
            name    => $file_name,
            is_role => 1,
            subs    => [
                sub { process_measurement_system_data($file, $xml) },
            ],
        );

        close $file;
    }

    # Parent data
    %parent_locales = get_parent_locales($xml);
}

# Language Matching: Under development

=begin comment
{
    open my $file, '>', File::Spec->catfile($lib_directory, 'LanguageMatching.pm');

    my $file_name = File::Spec->catfile(
        $base_directory,
        'supplemental',
        'languageInfo.xml',
    );

    my $xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => $file_name,
    );

    process_file(
        file    => $file,
        package => 'Locale::CLDR::LanguageMatching',
        name    => $file_name,
        is_role => 1,
        subs    => [
            sub { process_paradigm_locales( $file, $xml ) },
            sub { process_match_variable( $file, $xml ) },
            sub { process_language_match( $file, $xml ) },
        ],
    );

    close $file;
}

=end comment

=cut

# Transformations
# Transformation files hold data on how to perform translitteration between two scripts
make_path($transformations_directory) unless -d $transformations_directory;
opendir (my $dir, $transform_directory);
my $num_files = grep { -f File::Spec->catfile($transform_directory,$_)} readdir $dir;
my $count_files = 0;
rewinddir $dir;

# Each transformation package name is stored in the @transformation_list array so we can print them in the transformations bundle
my @transformation_list;

foreach my $file_name ( sort grep /^[^.]/, readdir($dir) ) {
    my $percent         = ++$count_files / $num_files * 100;
    my $full_file_name  = File::Spec->catfile($transform_directory, $file_name);

    vsay sprintf("Processing Transformation File %s: $count_files of $num_files, %.2f%% done", $full_file_name, $percent);
    my $xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => $full_file_name
    );

    process_transforms($transformations_directory, $xml, $full_file_name);
}

# Write out a dummy Locale::CLDR::Transformations module to keep CPAN happy
{
    open my $file, '>', File::Spec->catfile($lib_directory, 'Transformations.pm');
    print $file <<EOT;
package Locale::CLDR::Transformations;

=head1 NAME

Locale::CLDR::Transformations - Dummy base class to keep CPAN happy

=cut

use version;

our VERSION = version->declare('v$VERSION');

1;
EOT
}

push @transformation_list, 'Locale::CLDR::Transformations';

#Collation
# This needs more work on it

# Perl older than 5.16 can't handle all the utf8 encoded code points, so we need a version of Locale::CLDR::CollatorBase
# that does not have the characters as raw utf8
{
    vsay "Copying base collation file";
    open (my $Allkeys_in, '<', File::Spec->catfile($base_directory, 'uca', 'allkeys_CLDR.txt'));
    open (my $Fractional_in, '<', File::Spec->catfile($base_directory, 'uca', 'FractionalUCA_SHORT.txt'));
    open (my $Allkeys_out, '>', File::Spec->catfile($lib_directory, 'CollatorBase.pm'));
    process_file(
        file    => $Allkeys_out,
        package => 'Locale::CLDR::CollatorBase',
        name    => File::Spec->catfile($base_directory, 'uca', 'FractionalUCA_SHORT.txt'),
        is_role => 1,
        subs    => [
            sub { process_collation_base($Fractional_in, $Allkeys_in, $Allkeys_out) },
        ],
    );
    close $Allkeys_in;
    close $Fractional_in;
    close $Allkeys_out;
}

# Main directory
my $main_directory = File::Spec->catdir($base_directory, 'main');
opendir ( $dir, $main_directory);

# Count the number of files
$num_files      = grep { -f File::Spec->catfile($main_directory,$_)} readdir $dir;
$num_files      += 3; # We do root.xml, en.xml and en_US.xml twice
$count_files    = 0;
rewinddir $dir;

# Segmentation ruls describe how to break up text into sentances, lines, words and graphemes
my $segmentation_directory  = File::Spec->catdir($base_directory, 'segments');

# RBNF, Rule Based Number Formatting, gives a list of rules on how to display numbers in locales that dont use position
# based digits such as roman numerals where 4 is formatted as IV
my $rbnf_directory          = File::Spec->catdir($base_directory, 'rbnf');

my %region_to_package;

# The following three variables will be populated once we have generated the en_Any_US Locale data
my $en; # Stores the Local::CLDR::Languages::En::Any::US object so we can generate valid output for names
my $languages; # A hash ref of all language keys and their names in US English
my $regions; # A hash ref of all region keys and their names in US English

# We are going to process the root en and en_US locales twice the first time as the first three
# locales so we can then use the data in the processed files to create names and other labels in
# the locale files
foreach my $file_name ( 'root.xml', 'en.xml', 'en_US.xml', sort grep /^[^.]/, readdir($dir) ) {
    if (@ARGV) { # Allow us to supply the last processed file for a restart after a crash
        next unless grep {$file_name eq $_} @ARGV;
    }

    my $xml = XML::XPath->new(
        parser      => $xml_parser,
        filename    => File::Spec->catfile($main_directory, $file_name)
    );

    my $segment_xml = undef;
    if (-f File::Spec->catfile($segmentation_directory, $file_name)) {
        $segment_xml = XML::XPath->new(
            parser      => $xml_parser,
            filename    => File::Spec->catfile($segmentation_directory, $file_name)
        );
    }

    my $rbnf_xml = undef;
    if (-f File::Spec->catfile($rbnf_directory, $file_name)) {
        $rbnf_xml = XML::XPath->new(
            parser      => $xml_parser,
            filename    => File::Spec->catfile($rbnf_directory, $file_name)
        );
    }

    my @output_file_parts   = output_file_name($xml);
    my $current_locale      = lc $output_file_parts[0];

    my $package = join '::', @output_file_parts;

    $output_file_parts[-1]  .= '.pm';

    my $out_directory       = File::Spec->catdir(
        $locales_directory,
        @output_file_parts[0 .. $#output_file_parts - 1]
    );

    make_path($out_directory) unless -d $out_directory;

    if (defined( my $t = $output_file_parts[2])) {
        $t =~ s/\.pm$//;
        push @{$region_to_package{lc $t}}, join('::','Locale::CLDR::Locales',@output_file_parts[0,1],$t);
    }

    # If we have already created the US English module we can use it to produce the correct local
    # names in each modules documentation
    my $has_en = -e File::Spec->catfile($locales_directory, 'En', 'Any', 'Us.pm');

    # If we have the en module and haven't loaded it yet, load it now
    if ($has_en && ! $en) {
        require lib;
        lib::import(undef,File::Spec->catdir($FindBin::Bin, 'lib'));
        require Locale::CLDR;
        $en = Locale::CLDR->new('en');
        $languages = $en->all_languages;
        $regions = $en->all_regions;
    }

    open my $file, '>', File::Spec->catfile($locales_directory, @output_file_parts);

    my $full_file_name = File::Spec->catfile($base_directory, 'main', $file_name);
    process_class_any($locales_directory, @output_file_parts[0 .. $#output_file_parts -1]);

    process_file(
        file        => $file,
        package     => "Locale::CLDR::Locales::$package",
        name        => $full_file_name,
        is_language => $languages->{$current_locale},
        count       => ++$count_files,
        num         => $num_files,
        subs        => [
            $segment_xml    ? sub { process_segments($file, $segment_xml) } : (),
            $rbnf_xml       ? sub { process_rbnf($file, $rbnf_xml) } : (),
            sub { process_display_pattern($file, $xml) },
            sub { process_display_language($file, $xml) },
            sub { process_display_script($file, $xml) },
            sub { process_display_region($file, $xml) },
            sub { process_display_variant($file, $xml) },
            sub { process_display_key($file, $xml) },
            sub { process_display_type($file,$xml) },
            sub { process_display_measurement_system_name($file, $xml) },
            sub { process_display_transform_name($file,$xml) },
            sub { process_code_patterns($file, $xml) },
            sub { process_orientation($file, $xml) },
            sub { process_exemplar_characters($file, $xml) },
            sub { process_ellipsis($file, $xml) },
            sub { process_more_information($file, $xml) },
            sub { process_delimiters($file, $xml) },
            sub { process_units($file, $xml) },
            sub { process_posix($file, $xml) },
            sub { process_list_patterns($file, $xml) },
            sub { process_context_transforms($file, $xml) },
            sub { process_numbers($file, $xml) },
            sub { process_calendars($file, $xml, $current_locale) },
            sub { process_time_zone_names($file, $xml) },
        ]
    );
    close $file;
}

# Build Bundles and Distributions
my $out_directory = File::Spec->catdir($lib_directory, '..', '..', 'Bundle', 'Locale','CLDR');
make_path($out_directory) unless -d $out_directory;

# region bundles
my $region_contains = $en->region_contains();
my $region_names = $en->all_regions();

foreach my $region (keys %$region_names) {
    $region_names->{$region} = ucfirst( lc $region ) . '.pm'
        unless exists $region_contains->{$region};
}

foreach my $region (sort keys %$region_contains) {
    my $name = lc ( $region_names->{$region} // '' );
    $name=~tr/a-z0-9//cs; # Remove anything that isn't a to z or 0 to 9
    build_bundle($out_directory, [ $region, @{$region_contains->{$region}} ], $name, $region_names);
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

# This method gets the package name for each given file by looking for the first package keyword in the file
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
    # Recurse into sub directories
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
# This bundle contains the minimum number of packages to allow the test suite to pass
my @base_bundle = (
    'Locale::CLDR',
    'Locale::CLDR::CalendarPreferences',
    'Locale::CLDR::Collator',
    'Locale::CLDR::CollatorBase',
    'Locale::CLDR::Currencies',
    'Locale::CLDR::EraBoundries',
    'Locale::CLDR::LikelySubtags',
    'Locale::CLDR::LanguageMatching',
    'Locale::CLDR::MeasurementSystem',
    'Locale::CLDR::NumberFormatter',
    'Locale::CLDR::NumberingSystems',
    'Locale::CLDR::Plurals',
    'Locale::CLDR::RegionContainment',
    'Locale::CLDR::ValidCodes',
    'Locale::CLDR::WeekData',
    'Locale::CLDR::Locales::Root',
    'Locale::CLDR::Locales::En',
    'Locale::CLDR::Locales::En::Any',
    'Locale::CLDR::Locales::En::Any::Us',
);

build_bundle($out_directory, \@base_bundle, 'Base');

# All Bundle
my @all_bundle = (
    'Bundle::Locale::CLDR::World',
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

vsay "Duration: ", sprintf "%02i:%02i:%02i", @duration;

# This sub looks for nodes along an xpath. It's probably redundent now but the code works so I don't want to remove it.
sub findnodes {
    my ($xpath, $path ) = @_;
    my $nodes = $xpath->findnodes($path);

    return $nodes;
}

# Calculate the output file name
sub output_file_name {
    my $xpath = shift;
    my @nodes;

    # Look for the 4 elements that we use to create the file name
    foreach my $name (qw( language script territory variant )) {
        my $nodes = findnodes($xpath, "/ldml/identity/$name");
        if ($nodes->size) {;
            push @nodes, $nodes->get_node(1)->getAttribute('type');
        }
        else {
            # Non existant values are replaced with 'Any' to keep the directory
            # structure identical
            push @nodes, 'Any';
        }
    };

    # Strip off Any's from end of list
    pop @nodes while $nodes[-1] eq 'Any';

    return map {ucfirst lc} @nodes;
}

# Fill in any missing script or region with the pseudo class Any
sub process_class_any {
    my ($lib_path, @path_parts) = @_;

    my $package = 'Locale::CLDR::Locales';
    foreach my $path (@path_parts) {
        my $parent = $package;
        $parent = 'Locale::CLDR::Locales::Root' if $parent eq 'Locale::CLDR::Locales';
        $package .= "::$path";
        $lib_path = File::Spec->catfile($lib_path, $path);

        next unless $path eq 'Any';

        open my $file, '>:utf8', "$lib_path.pm";
        print $file <<EOT;
package $package;

# This file auto generated
#\ton $now GMT

use version;

our \$VERSION = version->declare('v$VERSION');

use v5.10.1;
use mro 'c3';
use if \$^V ge v5.12.0, feature => 'unicode_strings';

use Moo;

extends('$parent');

no Moo;

1;
EOT
        close $file;
    }
}

# Process the elements of the file note
sub process_header {
    my ($file, $class, $xml_name, $isRole, $language) = @_;
    vsay "Processing Header";

    $isRole = $isRole ? '::Role' : '';

    # Strip of anything before Data in the file name. This keeps the file names consistant
    # and not determind on where the script was run.
    $xml_name =~s/^.*(Data.*)$/$1/;

    # If we know the language then print some usefull pod at the top
    # of the file
    if ($language) {
        print $file <<EOT;
=encoding utf8

=head1 NAME

$class - Package for language $language

=cut

EOT
    }

    # Print the boilerplate at the top of each file
    print $file <<EOT;
package $class;
# This file auto generated from $xml_name
#\ton $now GMT

use strict;
use warnings;
use version;

our \$VERSION = version->declare('v$VERSION');

use v5.10.1;
use mro 'c3';
use utf8;
use if \$^V ge v5.12.0, feature => 'unicode_strings';
use Types::Standard qw( Str Int HashRef ArrayRef CodeRef RegexpRef );
use Moo$isRole;

EOT

    # If this is a language file then calculate the parent class by
    # capturing everything before the last :: characters in the class name
    if (!$isRole && $class =~ /^Locale::CLDR::Locales::...?(?:::|$)/) {
        my ($parent) = $class =~ /^(.+)::/;

        # The ultimate parent is Locale::CLDR::Locales::Root so if we end up with a
        # parent with no language id on it then use Locale::CLDR::Locales::Root instead
        $parent = 'Locale::CLDR::Locales::Root' if $parent eq 'Locale::CLDR::Locales';
        $parent = $parent_locales{$class} // $parent;
        say $file "extends('$parent');";
    }
}

sub process_paradigm_locales {
    my ($file, $xpath) = @_;
    vsay "Processing Paradigm Locals";
    
    my $paradigm_locales = 
        findnodes($xpath, '/supplementalData/languageMatching/languageMatches/paradigmLocales');

    my @locale_list = $paradigm_locales->get_nodelist();
    
    my $locale_string = $locale_list[0]->getAttribute('locales');
    
    my @locales = split /\s+/, $locale_string;
    
    my $locales = join ' ', @locales;
    
    print $file <<EOT;
has 'paradigm_locales' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub {
\t\treturn [ qw( $locales ) ],
\t},
);

EOT
}

{
    my %variables = ();
    
    sub expand_region {
        my $region = shift;
        my @region;
        
        # Check if the region is a variable
        # if so look it up
        if ($region =~ /^\$!?/) {
            $region =~ s/^\$!?//;
            my $regions = $variables{$region};
            @region = split ' ', $regions;
        }
        else {
            @region = ($region);
        }
        
        if (! exists &{'_expand_region'}) {
            eval <<'EOT';
package Locale::CLDR::expand {
    use Moo;
    with 'Locale::CLDR::RegionContainment';

    sub expand_region {
        my $self = shift;
        my @region = @_;
        my @return = ();
        
        foreach my $region (@region) {
            if (my @expanded = @{$self->region_contains()->{$region} // []}) {
                push @return, $self->expand_region(@expanded);
            }
            else {
                push @return, $region;
            }
        }
        
        return @return;
    };
    
    *main::_expand_region = sub { our $ExpandedRegion //= Locale::CLDR::expand->new(); return $ExpandedRegion->expand_region(@_) };
}
EOT
        }

        return _expand_region(@region);
    }
    
    sub process_match_variable {
        my ($file, $xpath) = @_;
        vsay "Processing Match Variables";
        
        my $variables =
            findnodes( $xpath, '/supplementalData/languageMatching/languageMatches/matchVariable');
    
        foreach my $variable ($variables->get_nodelist()) {
            my $id      = $variable->getAttribute('id');
            $id =~ s/^\$//;
            my $value   = $variable->getAttribute('value');
            # Im going to cheat here, the spec says these are sets allowing both + and -
            # however there are no - in the current data so I'm going to assume that 
            # all the listed regions are valid
            $value =~ s/\+/ /g;
            $variables{$id} = $value;
        }
    }
    
    sub process_language_match {
        my ($file, $xpath) = @_;
        vsay "Processing Language Match";
        
        my $languageMatch =
            findnodes($xpath, '/supplementalData/languageMatching/languageMatches/languageMatch');

        my @language_distance = ();

        foreach my $match ($languageMatch->get_nodelist) {
            my $desired     = $match->getAttribute('desired');
            my $supported   = $match->getAttribute('supported');
            my $distance    = $match->getAttribute('distance');
            my $oneway      = ($match->getAttribute('oneway')  // 'false') eq 'true';
            
            # Variables starting with d_ are the desired Locales
            # Variables starting with s_ are the supplied Locales
            my ($d_language, $d_script, $d_region) = split /_/, $desired;
            my ($s_language, $s_script, $s_region) = split /_/, $supported;
            
            $d_script ||= '*';
            $s_script ||= '*';
            
            $d_region ||= '*';
            $s_region ||= '*';
            
            my $ndr = $d_region =~ /!/ ? 1 : 0;
            my $nsr = $s_region =~ /!/ ? 1 : 0;
            my @d_region = expand_region( $d_region );
            my @s_region = expand_region( $s_region );
            
            foreach my $dr (@d_region) {
                foreach my $sr (@s_region) {
                    push @language_distance, {
                        d_language  => $d_language,
                        d_script    => $d_script,
                        d_region    => $dr,
                        not_dr      => $ndr,
                        s_language  => $s_language,
                        s_script    => $s_script,
                        s_region    => $sr,
                        not_sr      => $nsr,
                        distance    => $distance,
                    };
                    push @language_distance, {
                        d_language  => $s_language,
                        d_script    => $s_script,
                        d_region    => $sr,
                        not_dr      => $nsr,
                        s_language  => $d_language,
                        s_script    => $d_script,
                        s_region    => $dr,
                        not_sr      => $ndr,
                        distance    => $distance,
                    }
                        if $oneway eq 'false';
                }
            }
        }
        
        print $file <<EOT;
has 'language_match' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub {
\t\treturn [
EOT
foreach my $ld (@language_distance) {
    say $file "\t\t\t{";
    foreach my $key (sort keys %$ld ) {
        say $file "\t\t\t\t$key\t=> '", $ld->{$key}, "',";
    }
    say $file "\t\t\t},";
}
say $file <<EOT
\t\t];
\t},
);
EOT
    }
}

sub process_collation_base {
    my ($Fractional_in, $Allkeys_in, $Allkeys_out) = @_;
    my %characters;
    my @multi;

    while (my $line = <$Allkeys_in>) {
        next if $line =~ /^\s*$/; # Empty lines
        next if $line =~ /^#/; # Comments

        next if $line =~ /^\@version /; # Version line

        # Characters
        if (my ($character, $collation_element) = $line =~ /^(\p{hex}{4,6}(?: \p{hex}{4,6})*) *; ((?:\[[.*]\p{hex}{4}\.\p{hex}{4}\.\p{hex}{4}\])+) #.*$/) {
            $character = join '', map {chr hex $_} split / /, $character;
            if (length $character > 1) {
                push(@multi,$character);
            }
            $characters{$character} = process_collation_element($collation_element);
        }
    }

    # Get block ranges
    my %block;
    my $old_name;
    my $fractional = join '', <$Fractional_in>;
    while ($fractional =~ /(\p{hex}{4,6});[^;]+?(?:\nFDD0 \p{hex}{4,6};[^;]+?)?\nFDD1.*?# (.+?) first.*?\n(\p{hex}{4,6});/gs ) {
        my ($end, $name, $start ) = ($1, $2, $3);
        if ($old_name) {
            $block{$old_name}{end} = $characters{chr hex $end} // generate_ce(chr hex $end);
            $block{Meroitic_Hieroglyphs}{end} = $characters{chr hex $end}
                if $old_name eq 'HIRAGANA';
            $block{KATAKANA}{end} = $characters{chr hex $end}
                if $old_name eq 'Meroitic_Cursive';
        }
        $old_name = $name;
        $block{$name}{start} = $characters{chr hex $start} // generate_ce(chr hex $start);
        $block{KATAKANA}{start} = $characters{chr hex $start}
                if $old_name eq 'HIRAGANA';
        $block{Meroitic_Hieroglyphs}{start} = $characters{chr hex $start}
                if $old_name eq 'Meroitic_Cursive';
    }

    print $Allkeys_out <<EOT;
has multi_class => (
    is => 'ro',
    isa => ArrayRef,
    init_arg => undef,
    default => sub {
        return [
EOT
    foreach ( @multi ) {
        my $multi = $_; # Make sure that $multi is not a reference into @multi
        no warnings 'utf8';
        $multi =~ s/'/\\'/g;
        print $Allkeys_out "\t\t\t'$multi',\n";
    }

    print $Allkeys_out <<EOT;
        ]
    }
);

has multi_rx => (
    is => 'ro',
    isa => ArrayRef,
    init_arg => undef,
    default => sub {
        return [
EOT
    foreach my $multi ( @multi ) {
        no warnings 'utf8';
        $multi =~ s/(.)/$1\\P{ccc=0}/g;
        $multi =~ s/'/\\'/g;
        print $Allkeys_out "\t\t\t'$multi',\n";
    }

    print $Allkeys_out <<EOT;
        ]
    }
);
EOT

    print $Allkeys_out <<EOT;
has collation_elements => (
    is => 'ro',
    isa => HashRef,
    init_arg => undef,
    default => sub {
        no if \$^V < v5.13.9, qw<warnings utf8>; 
        return {
EOT
    no warnings 'utf8';
    foreach my $character (sort (keys %characters)) {
        my $character_out = $character;
        $character_out = sprintf '"\\x{%0.4X}"', ord $character_out;
        print $Allkeys_out "\t\t\t$character_out => '";
        my @ce = @{$characters{$character}};
        foreach my $ce (@ce) {
            $ce = join '', map { defined $_ ? $_ : '' } @$ce;
        }
        my $ce = join("\x{0001}", @ce) =~ s/([\\'])/\\$1/r;
        print $Allkeys_out $ce, "',\n";
    }

    print $Allkeys_out <<EOT;
        }
    }
);

has collation_sections => (
    is => 'ro',
    isa => HashRef,
    init_arg => undef,
    default => sub {
        return {
EOT
    foreach my $block (sort keys %block) {
        my $end = defined $block{$block}{end}
            ? 'q(' . (
                ref $block{$block}{end}
                ? join("\x{0001}", map { join '', @$_} @{$block{$block}{end}})
                : $block{$block}{end}) . ')'
            : 'undef';

        my $start = defined $block{$block}{start}
            ? 'q(' . (
                ref $block{$block}{start}
                ? join("\x{0001}", map { join '', @$_} @{$block{$block}{start}})
                : $block{$block}{start}) . ')'
            : 'undef';

        $block = lc $block;
        $block =~ tr/ -/_/;
        print $Allkeys_out "\t\t\t$block => [ $start, $end ],\n";
    }
    print $Allkeys_out <<EOT;
        }
    }
);
EOT
}

# Sub to generate the colation element of a given character
sub generate_ce {
    my ($character) = @_;
    my $LEVEL_SEPARATOR = "\x{0001}";
    my $aaaa;
    my $bbbb;

    if ($^V ge v5.26 && eval q($character =~ /(?!\p{Cn})(?:\p{Block=Tangut}|\p{Block=Tangut_Components})/)) {
        $aaaa = 0xFB00;
        $bbbb = (ord($character) - 0x17000) | 0x8000;
    }
    # Block Nushu was added in Perl 5.28
    elsif ($^V ge v5.28 && eval q($character =~ /(?!\p{Cn})\p{Block=Nushu}/)) {
        $aaaa = 0xFB01;
        $bbbb = (ord($character) - 0x1B170) | 0x8000;
    }
    elsif ($character =~ /(?=\p{Unified_Ideograph=True})(?:\p{Block=CJK_Unified_Ideographs}|\p{Block=CJK_Compatibility_Ideographs})/) {
        $aaaa = 0xFB40 + (ord($character) >> 15);
        $bbbb = (ord($character) & 0x7FFFF) | 0x8000;
    }
    elsif ($character =~ /(?=\p{Unified_Ideograph=True})(?!\p{Block=CJK_Unified_Ideographs})(?!\p{Block=CJK_Compatibility_Ideographs})/) {
        $aaaa = 0xFB80 + (ord($character) >> 15);
        $bbbb = (ord($character) & 0x7FFFF) | 0x8000;
    }
    else {
        $aaaa = 0xFBC0 + (ord($character) >> 15);
        $bbbb = (ord($character) & 0x7FFFF) | 0x8000;
    }
    return join '', map {chr($_)} $aaaa, 0x0020, 0x0002, ord ($LEVEL_SEPARATOR), $bbbb, 0, 0;
}

sub process_collation_element {
    my ($collation_string) = @_;
    my @collation_elements = $collation_string =~ /\[(.*?)\]/g;
    foreach my $element (@collation_elements) {
        my (undef, $primary, $secondary, $tertiary) = split(/[.*]/, $element);
        foreach my $level ($primary, $secondary, $tertiary) {
            $level //= 0;
            $level = chr hex $level;
        }
        $element = [$primary, $secondary, $tertiary];
    }

    return \@collation_elements;
}

# The LDML specification has a mecanism to compress ranges of characters
# using a ~ as a compression operator this mecanism alows a posible set of
# base characters followed by a range. So A~C expands to A B C and Fred~h
# expands to Fred Free Fref Freg Freh
sub expand_text {
    my $string = shift;

    my @elements = grep {length} split /\s+/, $string;
    foreach my $element (@elements) {
        next unless $element =~ /~/;
        my ($base, $start, $end) = $element =~ /^(.*)(.)~(.)$/;
        $element = [ map { "$base$_" } ($start .. $end) ];
    }

    return map { ref $_ ? @$_ : $_ } @elements;
}


# Most of the valid id code is identicle so factor it out here
sub process_valid_id {
    my ($file, $xpath, $name, $pname, $active) = @_;
    my $label = ucfirst $pname;
    $active = $active ? '[@idStatus!="deprecated"]' : '';
    vsay "Processing Valid $label";

    my $ids = findnodes($xpath, qq(/supplementalData/idValidity/id[\@type="$name"]$active));

    my @ids =
        map {"$_\n"}
        map { expand_text($_) }
        map {$_->string_value }
        $ids->get_nodelist;

    print $file <<EOT
has 'valid_$pname' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub {[qw( @ids \t)]},
);

around valid_$pname => sub {
    my (\$orig, \$self) = \@_;

    my \$$pname = \$self->\$orig;
    return \@{\$$pname};
};

EOT
}

# Create the list of valid language id's from the suplemental data file
sub process_valid_languages {
    process_valid_id(@_, 'language', 'languages', 1);
}

# Create the list of valid script id's from the suplemental data file
sub process_valid_scripts {
    process_valid_id(@_, 'script', 'scripts', 1);
}

# Create the list of valid region id's from the suplemental data file
sub process_valid_regions {
    process_valid_id(@_, 'region', 'regions', 1);
}

# Create the list of valid variant id's from the suplemental data file
sub process_valid_variants {
    process_valid_id(@_, 'variant', 'variants');
}

# Create the list of valid currency id's from the suplemental data file
sub process_valid_currencies {
    process_valid_id(@_, 'currency', 'currencies', 1);
}

# Create the list of valid subdivision id's from the suplemental data file
sub process_valid_subdivisions {
    process_valid_id(@_, 'subdivision', 'subdivisions', 1);
}

# Create the list of valid unit id's from the suplemental data file
sub process_valid_units {
    process_valid_id(@_, 'unit', 'units');
}

# Create the list of valid key id's from the bcp47 data files
sub process_valid_keys {
    my ($file, $base_directory) = @_;
    vsay "Processing Valid Keys";

    opendir (my $dir, File::Spec->catdir($base_directory, 'bcp47'))
        || die "Can't open directory: $!";

    my @files = map {File::Spec->catfile($base_directory, 'bcp47', $_)}
        grep /\.xml \z/xms, readdir $dir;

    closedir $dir;
    my %keys;
    foreach my $file_name (@files) {
        my $xml = XML::XPath->new(
            parser => $xml_parser,
            filename => $file_name
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub { return {
EOT
    foreach my $key (sort keys %keys) {
        my $alias = lc ($keys{$key}{alias} // '');
        next unless $alias;
        say $file "\t\t'$key' => '$alias',";
    }
    print $file <<EOT;
\t}},
);

around key_aliases => sub {
    my (\$orig, \$self) = \@_;
    my \$aliases = \$self->\$orig;

    return %{\$aliases};
};

has 'key_names' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tlazy\t\t=> 1,
\tdefault\t=> sub { return { reverse shift()->key_aliases }; },
);

around key_names => sub {
    my (\$orig, \$self) = \@_;
    my \$names = \$self->\$orig;

    return %{\$names};
};

has 'valid_keys' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
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

around valid_keys => sub {
    my (\$orig, \$self) = \@_;

    my \$keys = \$self->\$orig;
    return %{\$keys};
};

EOT
}

sub process_valid_language_aliases {
    my ($file, $xpath) = @_;
    vsay "Processing Valid Language Aliases";

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/languageAlias');
    print $file <<EOT;
has 'language_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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

sub process_valid_region_aliases {
    my ($file, $xpath) = @_;

    vsay "Processing Valid region Aliases";

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/territoryAlias');
    print $file <<EOT;
has 'region_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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

    vsay "Processing Valid Variant Aliases";

    print $file <<EOT;
has 'variant_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub { return {
\t\tbokmal\t\t=> { language\t=> 'nb' },
\t\tnynorsk\t\t=> { language\t=> 'nn' },
\t\taaland\t\t=> { region\t=> 'AX' },
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
\tisa\t\t\t=> HashRef,
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

# Now we get lots of process_* functions, each one processes part of the XML and 
# generates code to be output into the file
sub process_numbering_systems {
    my ($file, $xpath) = @_;

    my $systems = findnodes($xpath,
        q(/supplementalData/numberingSystems/numberingSystem));

    print $file <<EOT;
has 'numbering_system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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
\tisa\t\t\t=> Str,
\tinit_arg\t=> undef,
\tdefault\t=> '',
\tclearer\t=> '_clear_default_nu',
\twriter\t=> '_set_default_numbering_system',
);

sub _set_default_nu {
    my (\$self, \$system) = \@_;
    my \$default = \$self->_default_numbering_system // '';
    \$self->_set_default_numbering_system("\$default\$system");
}

sub _test_default_nu {
    my \$self = shift;
    return length \$self->_default_numbering_system ? 1 : 0;
}

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
    vsay "Processing Era Boundries";

    my $calendars = findnodes($xpath,
        q(/supplementalData/calendarData/calendar));

    print $file <<EOT;

sub era_boundry {
    my (\$self, \$type, \$date) = \@_;
    my \$era = \$self->_era_boundry;
    return \$era->(\$self, \$type, \$date);
}

has '_era_boundry' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> CodeRef,
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
                $m ||= 0;
                $d ||= 0;
                $y ||= 0;
                $start = sprintf('%d%0.2d%0.2d',$y,$m,$d);
                $start =~ s/^0+//;
                say $file "\t\t\t\t\$return = $type if \$date >= $start;";
            }
            if (length $end) {
                my ($y, $m, $d) = split /-/, $end;
                $m ||= 0;
                $d ||= 0;
                $y ||= 0;
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

    say "Processing Week Data";

    my $week_data_min_days = findnodes($xpath,
        q(/supplementalData/weekData/minDays));

    print $file <<EOT;
has '_week_data_min_days' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_min_days->get_nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
        shift @regions if $regions[0] eq '';
        my $count = $node->getAttribute('count');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => $count,";
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_first_day->get_nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
        shift @regions if $regions[0] eq '';
        my $day = $node->getAttribute('day');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => '$day',";
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_weekend_start->get_nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
        shift @regions if $regions[0] eq '';
        my $day = $node->getAttribute('day');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => '$day',";
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_weekend_end->get_nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
        my $day = $node->getAttribute('day');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT

}

sub process_calendar_preferences {
    my ($file, $xpath) = @_;
    vsay "Processing Calendar Preferences";

    my $calendar_preferences = findnodes($xpath,
        q(/supplementalData/calendarPreferenceData/calendarPreference));

    print $file <<EOT;
has 'calendar_preferences' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($calendar_preferences->get_nodelist) {
        my @regions = split / /,$node->getAttribute('territories');
        my @ordering = split / /, $node->getAttribute('ordering');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => ['", join("','", @ordering), "'],";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
}

sub process_valid_timezone_aliases {
    my ($file, $xpath) = @_;
    vsay "Processing Valid Time Zone Aliases";

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/zoneAlias');
    print $file <<EOT;
has 'zone_aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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
    vsay "Processing Display Pattern";

    my $display_pattern =
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localePattern');
    return unless $display_pattern->size;
    $display_pattern = $display_pattern->get_node(1)->string_value;

    my $display_seperator =
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localeSeparator');
    $display_seperator = $display_seperator->size ? $display_seperator->get_node(1)->string_value : '';

    my $display_key_type =
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localeKeyTypePattern');
    $display_key_type = $display_key_type->size ? $display_key_type->get_node(1)->string_value : '';

    return unless defined $display_pattern;
    foreach ($display_pattern, $display_seperator, $display_key_type) {
        s/\//\/\//g;
        s/'/\\'/g;
    }

    print $file <<EOT;
# Need to add code for Key type pattern
sub display_name_pattern {
\tmy (\$self, \$name, \$region, \$script, \$variant) = \@_;

\tmy \$display_pattern = '$display_pattern';
\t\$display_pattern =~s/\\\{0\\\}/\$name/g;
\tmy \$subtags = join '$display_seperator', grep {\$_} (
\t\t\$region,
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
    vsay "Processing Display Language";

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
\tisa\t\t\t=> CodeRef,
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
    vsay "Processing Display Script";

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
\tisa\t\t\t=> CodeRef,
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

sub process_display_region {
    my ($file, $xpath) = @_;

    vsay "Processing Display region";

    my $regions = findnodes($xpath, '/ldml/localeDisplayNames/territories/territory');

    return unless $regions->size;
    my @regions = $regions->get_nodelist;
    foreach my $region (@regions) {
        my $type = $region->getAttribute('type');
        my $variant = $region->getAttribute('alt');
        if ($variant) {
            $type .= "\@alt=$variant";
        }

        my $node = $region->getChildNode(1);
        my $name = $node ? $node->getValue : '';
        $name =~s/\\/\/\\/g;
        $name =~s/'/\\'/g;
        $region = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display_name_region' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit_arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@regions
\t\t}
\t},
);

EOT
}

sub process_display_variant {
    my ($file, $xpath) = @_;

    vsay "Processing Display Variant";

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
\tisa\t\t\t=> HashRef[Str],
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

    vsay "Processing Display Key";

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
\tisa\t\t\t=> HashRef[Str],
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

    vsay "Processing Display Type";

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
\tisa\t\t\t=> HashRef[HashRef[Str]],
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

    vsay "Processing Display Mesurement System";

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
\tisa\t\t\t=> HashRef[Str],
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

    vsay "Processing Display Transform Names";

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
\tisa\t\t\t=> HashRef[Str],
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
    vsay "Processing Code Patterns";

    my $patterns = findnodes($xpath, '/ldml/localeDisplayNames/codePatterns/codePattern');
    return unless $patterns->size;

    my @patterns = $patterns->get_nodelist;
    foreach my $pattern (@patterns) {
        my $type = $pattern->getAttribute('type');
        $type = 'region' if $type eq 'territory';
        my $value = $pattern->getChildNode(1)->getValue;
        $pattern =~s/\\/\\\\/g;
        $pattern =~s/'/\\'/g;
        $pattern = "\t\t\t'$type' => '$value',\n";
    }

    print $file <<EOT;
has 'display_name_code_patterns' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
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

    vsay "Processing Orientation";
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
\tisa\t\t\t=> HashRef[Str],
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

    vsay "Processing Exemplar Characters";
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
\tisa\t\t\t=> HashRef,
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

    vsay "Processing Ellipsis";
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
\tisa\t\t\t=> HashRef,
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

    vsay 'Processing More Information';
    my $info = findnodes($xpath, '/ldml/characters/moreInformation');
    return unless $info->size;
    my @info = $info->get_nodelist;
    $info = $info[0]->getChildNode(1)->getValue;

    print $file <<EOT;
has 'more_information' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> Str,
\tinit_arg\t=> undef,
\tdefault\t\t=> qq{$info},
);

EOT
}

sub process_delimiters {
    my ($file, $xpath) = @_;

    vsay 'Processing Delimiters';
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
\tisa\t\t\t=> Str,
\tinit_arg\t=> undef,
\tdefault\t\t=> qq{$value},
);

EOT
    }
}

sub process_measurement_system_data {
    my ($file, $xpath) = @_;

    vsay 'Processing Measurement System Data';
    my $measurementData = findnodes($xpath, '/supplementalData/measurementData/*');
    return unless $measurementData->size;

    my @measurementSystem;
    my @paperSize;

    foreach my $measurement ($measurementData->get_nodelist) {
        my $what = $measurement->getLocalName;
        my $type = $measurement->getAttribute('type');
        my $regions = $measurement->getAttribute('territories');

        push @{$what eq 'measurementSystem' ? \@measurementSystem : \@paperSize },
            [$type, $regions ];
    }

    print $file <<EOT;
has 'measurement_system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

    foreach my $measurement ( @measurementSystem ) {
        foreach my $region (split /\s+/, $measurement->[1]) {
            say $file "\t\t\t\t'$region'\t=> '$measurement->[0]',";
        }
    }

    print $file <<EOT;
\t\t\t} },
);

EOT

    print $file <<EOT;
has 'paper_size' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

    foreach my $paper_size ( @paperSize) {
        foreach my $region (split /\s+/, $paper_size->[1]) {
            say $file "\t\t\t\t'$region'\t=> '$paper_size->[0]',";
        }
    }

    print $file <<EOT;
\t\t\t} },
);

EOT
}

sub get_parent_locales {
    my $xpath = shift;
    my $parentData = findnodes($xpath, '/supplementalData/parentLocales/*');
    my %parents;
    foreach my $parent_node ($parentData->get_nodelist) {
        my $parent = $parent_node->getAttribute('parent');
        my @locales = split / /, $parent_node->getAttribute('locales');
        foreach my $locale (@locales, $parent) {
            my @path = split /_/, $locale;
            @path = ($path[0], 'Any', $path[1])
                if ( @path == 2 );
            $locale = join '::', 'Locale::CLDR::Locales', map { ucfirst lc } @path;
        }
        @parents{@locales} = ($parent) x @locales;
    }

    return %parents;
}

sub process_units {
    my ($file, $xpath) = @_;

    vsay 'Processing Units';
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
            my $unit_type_name = $unit_type->getAttribute('type') // '';
            my $unit_type_alias = findnodes($xpath, qq(/ldml/units/unitLength[\@type="$length"]/unit[\@type="$unit_type_name"]/alias));
            if ($unit_type_alias->size) {
                my ($node) = $unit_type_alias->get_nodelist;
                my $path = $node->getAttribute('path');
                my ($type) = $path =~ /\[\@type=['"](.*)['"]\]/;
                $aliases{$length}{$unit_type_name} = $type;
                next;
            }

            foreach my $unit_pattern ($unit_type->getChildNodes) {
                next if $unit_pattern->isTextNode;

                # Currently I'm ignoring case and gender
                next if $unit_pattern->getAttribute('case');
                next if $unit_pattern->getAttribute('gender');

                my $count = $unit_pattern->getAttribute('count') || 1;
                $count = 'name' if $unit_pattern->getLocalName eq 'displayName';
                $count = 'per' if $unit_pattern->getLocalName eq 'perUnitPattern';
                if ($unit_pattern->getLocalName eq 'coordinateUnitPattern') {
                    $unit_type_name = 'coordinate';
                    $count = $unit_pattern->getAttribute('type');
                }
                my $pattern = $unit_pattern->getChildNode(1)->getValue;
                $units{$length}{$unit_type_name}{$count} = $pattern;
            }
        }
    }

    if (keys %duration_units) {
        print $file <<EOT;
has 'duration_units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $type (sort keys %duration_units) {
            my $units = $duration_units{$type};
            $units =~ s/'/\\'/g; # Escape a ' in unit name
            say $file "\t\t\t\t$type => '$units',";
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $from (sort keys %aliases) {
            if (ref $aliases{$from}) {
                say $file "\t\t\t\t$from => {";
                foreach my $old_unit (sort keys %{$aliases{$from}}) {
                    say $file "\t\t\t\t\t'$old_unit' => '$aliases{$from}{$old_unit}',";
                }
                say $file "\t\t\t\t},";
            }
            else {
                say $file "\t\t\t\t$from => '$aliases{$from}',";
            }
        }

        print $file <<EOT;
\t\t\t} }
);

EOT
    }

    print $file <<EOT;
has 'units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[HashRef[HashRef[Str]]],
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
    foreach my $length (sort keys %units) {
        say $file "\t\t\t\t'",$length,"' => {";
        foreach my $type (sort keys %{$units{$length}}) {
            say $file "\t\t\t\t\t# Long Unit Identifier";
            say $file "\t\t\t\t\t'$type' => {";
                foreach my $count (sort keys %{$units{$length}{$type}}) {
                    say $file "\t\t\t\t\t\t'$count' => q(",
                        $units{$length}{$type}{$count},
                        "),";
                }
            say $file "\t\t\t\t\t},";
            say $file "\t\t\t\t\t# Core Unit Identifier";
            my $core_type = $type =~ s/^[^-]+-//r;
            say $file "\t\t\t\t\t'$core_type' => {";
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

    vsay 'Processing Posix';
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
    s/'/\\'/g foreach ($yes, $no);

    print $file <<EOT if defined $yes;
has 'yesstr' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> RegexpRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { qr'^(?i:$yes)\$' }
);

EOT

    print $file <<EOT if defined $no;
has 'nostr' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> RegexpRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { qr'^(?i:$no)\$' }
);

EOT
}

# List patterns
#/ldml/listPatterns/
sub process_list_patterns {
    my ($file, $xpath) = @_;

    vsay "Processing List Patterns";

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
\tisa\t\t\t=> HashRef,
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

    vsay "Processing Numbers";

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

    # minimum grouping digits
    my $minimum_grouping_digits_nodes = findnodes($xpath, '/ldml/numbers/minimumGroupingDigits/text()');
    my $minimum_grouping_digits = 0;
    if ($minimum_grouping_digits_nodes->size) {
        $minimum_grouping_digits = ($minimum_grouping_digits_nodes->get_nodelist)[0]->getValue;
        # Fix for invalid data in Nepalise language data
        $minimum_grouping_digits = $minimum_grouping_digits =~ /^[0-9]+$/ ? $minimum_grouping_digits : 1;
    }

    # Symbols
    my %symbols;
    my $symbols_nodes = findnodes($xpath, '/ldml/numbers/symbols');
    foreach my $symbols ($symbols_nodes->get_nodelist) {
        my $type = $symbols->getAttribute('numberSystem') // '';
        foreach my $symbol ( qw( alias decimal group list percentSign minusSign plusSign exponential superscriptingExponent perMille infinity nan currencyDecimal currencyGroup timeSeparator) ) {
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
            my $number_system = $format_node->getAttribute('numberSystem') // '';
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
                            $currency_formats{$number_system}{pattern}{$length_node_type || 'default'}{$currency_type}{positive} = $positive;
                            $currency_formats{$number_system}{pattern}{$length_node_type || 'default'}{$currency_type}{negative} = $negative
                                if defined $negative;
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
\tisa\t\t\t=> Str,
\tinit_arg\t=> undef,
\tdefault\t\t=> '$default_numbering_system',
);

EOT

    foreach my $numbering_system (qw( native traditional finance )) {
        if ($other_numbering_systems{$numbering_system}) {
            print $file <<EOT;
has ${numbering_system}_numbering_system => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> Str,
\tinit_arg\t=> undef,
\tdefault\t\t=> '$other_numbering_systems{$numbering_system}',
);

EOT
        }
    }

    # Minimum grouping digits
    print $file <<EOT if $minimum_grouping_digits;
has 'minimum_grouping_digits' => (
\tis\t\t\t=>'ro',
\tisa\t\t\t=> Int,
\tinit_arg\t=> undef,
\tdefault\t\t=> $minimum_grouping_digits,
);

EOT
    if (keys %symbols) {
        print $file <<EOT;
has 'number_symbols' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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
\tisa\t\t\t=> HashRef,
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
\tisa\t\t\t=> HashRef,
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
has 'currencies' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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

    vsay "Processing currency data";

    # Do fraction data
    my $fractions = findnodes($xml, '/supplementalData/currencyData/fractions/info');
    my %fractions;
    foreach my $node ($fractions->get_nodelist) {
        $fractions{$node->getAttribute('iso4217')} = {
            digits            => $node->getAttribute('digits'),
            rounding        => $node->getAttribute('rounding'),
            cashrounding    => $node->getAttribute('cashRounding')     || $node->getAttribute('rounding'),
            cashdigits        => $node->getAttribute('cashDigits')     || $node->getAttribute('digits'),
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
\tisa\t\t\t=> HashRef,
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
        digits          => 2,
        cashdigits      => 2,
        rounding        => 0,
        cashrounding    => 0,
    } unless $currency_data;

    return $currency_data;
}

has '_default_currency' => (
    is          => 'ro',
    isa         => HashRef,
    init_arg    => undef,
    default     => sub { {
EOT

    foreach my $region (sort keys %default_currency) {
        say $file "\t\t\t\t'$region' => '$default_currency{$region}',";
    }

    say $file <<EOT;
\t } },
);

EOT
}


# region Containment data
sub process_region_containment_data {
    my ($file, $xpath) = @_;

    my $data = findnodes($xpath, q(/supplementalData/territoryContainment/group[not(@status) or @status!='deprecated']));

    my %contains;
    my %contained_by;
    foreach my $node ($data->get_nodelist) {
        my $base = $node->getAttribute('type');
        my @contains = split /\s+/, $node->getAttribute('contains');
        push @{$contains{$base}}, @contains;
        # Ignore UN, EU and EZ political regions, use the gographical region only
        next if grep { $base eq $_ } qw(UN EU EZ);
        @contained_by{@contains} = ($base) x @contains;
    }

    say $file <<EOT;
has 'region_contains' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

    foreach my $region ( sort { ($a =~ /^\d$/a && $b =~ /^\d$/a && $a <=> $b ) || $a cmp $b } keys %contains ) {
        say $file "\t\t'$region' => [ qw( @{$contains{$region}} ) ], ";
    }

    say $file <<EOT;
\t} }
);

has 'region_contained_by' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

    foreach my $region ( sort { ($a =~ /^\d$/a && $b =~ /^\d$/a && $a <=> $b )  || $a cmp $b } keys %contained_by ) {
        say $file "\t\t'$region' => '$contained_by{$region}', ";
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

    vsay "Processing Calendars";

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
        my $month_patterns = process_month_patterns($xpath, $type);
        $calendars{month_patterns}{$type} = $month_patterns if $month_patterns;
        my $cyclic_name_sets = process_cyclic_name_sets($xpath, $type);
        $calendars{cyclic_name_sets}{$type} = $cyclic_name_sets if $cyclic_name_sets;
    }

    # Got all the data now write it out to the file;
    if (keys %{$calendars{months}}) {
        print $file <<EOT;
has 'calendar_months' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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
                            my $month = $_ // '';
                            $month =~ s/'/\\'/g;
                            $month = "'$month'";
                            $month = 'undef()' if $month eq q('');
                            $month;
                        } @{$calendars{months}{$type}{$context}{$width}{nonleap}};
                    print $file "\t\t\t\t\t\t],\n\t\t\t\t\t\tleap => [\n\t\t\t\t\t\t\t";

                    say $file join ",\n\t\t\t\t\t\t\t",
                        map {
                            my $month = $_ // '';
                            $month =~ s/'/\\'/g;
                            $month = "'$month'";
                            $month = 'undef()' if $month eq q('');
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
\tisa\t\t\t=> HashRef,
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
\tisa\t\t\t=> HashRef,
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
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> CodeRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { sub {
\t\t# Time in hhmm format
\t\tmy (\$self, \$type, \$time, \$day_period_type) = \@_;
\t\t\$day_period_type //= 'default';
\t\tSWITCH:
\t\tfor (\$type) {
EOT
        foreach my $ctype (sort keys %{$calendars{day_period_data}}) {
            say $file "\t\t\tif (\$_ eq '$ctype') {";
            foreach my $day_period_type (sort keys %{$calendars{day_period_data}{$ctype}}) {
                say $file "\t\t\t\tif(\$day_period_type eq '$day_period_type') {";
                my %type_boundries;
                my @type_with_boundry_at;
                my @type_without_boundry_at;
                foreach my $type (keys %{$calendars{day_period_data}{$ctype}{$day_period_type}}) {
                    my %boundries = map {@$_} @{$calendars{day_period_data}{$ctype}{$day_period_type}{$type}};
                    if (exists $boundries{at}) {
                        push @type_with_boundry_at, $type;
                    } else {
                        push @type_without_boundry_at, $type;
                    }
                    $type_boundries{$type} = \%boundries;
                }

                # Sort 'at' periods to the top of the list so they are printed first,
                # as they compare with an absolute value that might be inside a range
                # for other types
                my @sorted = (
                    (sort @type_with_boundry_at),
                    (sort @type_without_boundry_at),
                );

                foreach my $type (@sorted) {
                    my $boundries = $type_boundries{$type};
                    if (exists $boundries->{at}) {
                        my ($hm) = $boundries->{at};
                        $hm =~ s/://;
                        $hm = $hm + 0;
                        say $file "\t\t\t\t\treturn '$type' if \$time == $hm;";
                        next;
                    }

                    my $stime = $boundries->{from};
                    my $etime = $boundries->{before};

                    foreach ($stime, $etime) {
                        s/://;
                        $_ = $_ + 0;
                    }

                    if ($etime < $stime) {
                        # Time crosses midnight
                        say $file "\t\t\t\t\treturn '$type' if \$time >= $stime;";
                        say $file "\t\t\t\t\treturn '$type' if \$time < $etime;";
                    }
                    else {
                        say $file "\t\t\t\t\treturn '$type' if \$time >= $stime";
                        say $file "\t\t\t\t\t\t&& \$time < $etime;";
                    }
                }
                say $file "\t\t\t\t}";
            }
            say $file "\t\t\t\tlast SWITCH;";
            say $file "\t\t\t\t}"
        }
        print $file <<EOT;
\t\t}
\t} },
);

around day_period_data => sub {
    my (\$orig, \$self) = \@_;
    return \$self->\$orig;
};

EOT
    }

    if (keys %{$calendars{day_periods}}) {
        print $file <<EOT;
has 'day_periods' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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

                foreach my $width (sort keys %{$calendars{day_periods}{$ctype}{$type}}) {
                    say $file "\t\t\t\t'$width' => {";
                    if (exists $calendars{day_periods}{$ctype}{$type}{$width}{alias}) {
                        say $file "\t\t\t\t\t'alias' => {";
                        say $file "\t\t\t\t\t\t'context' => '$calendars{day_periods}{$ctype}{$type}{$width}{alias}{context}',";
                        say $file "\t\t\t\t\t\t'width' => '$calendars{day_periods}{$ctype}{$type}{$width}{alias}{width}',";
                        say $file "\t\t\t\t\t},";
                        say $file "\t\t\t\t},";
                        next;
                    }

                    foreach my $period (sort keys %{$calendars{day_periods}{$ctype}{$type}{$width}}) {
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
\tisa\t\t\t=> HashRef,
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
                } sort { ($a =~ /^\d+$/a ? $a : 0) <=> ($b =~ /^\d+$/a ? $b : 0) } keys %{$calendars{eras}{$ctype}{$type}};
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
\tisa\t\t\t=> HashRef,
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
\tisa\t\t\t=> HashRef,
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
\tisa\t\t\t=> HashRef,
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{datetime_formats}}) {
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

        foreach my $ctype (sort keys %{$calendars{datetime_formats}}) {
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
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

        foreach my $ctype (sort keys %{$calendars{datetime_formats}}) {
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

    if (keys %{$calendars{month_patterns}}) {
        print $file <<EOT;
has 'month_patterns' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{month_patterns}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $context (sort keys %{$calendars{month_patterns}{$ctype}}) {
                if ($context eq 'alias' ) {
                    say $file "\t\t\talias => '$calendars{month_patterns}{$ctype}{alias}'",
                }
                else {
                    say $file "\t\t\t'$context' => {";
                    foreach my $width (sort keys %{$calendars{month_patterns}{$ctype}{$context}}) {
                        say $file "\t\t\t\t'$width' => {";
                        foreach my $type ( sort keys %{$calendars{month_patterns}{$ctype}{$context}{$width}}) {
                            # Check for aliases
                            if ($type eq 'alias') {
                                say $file <<EOT;
                    alias => {
                        context => '$calendars{month_patterns}{$ctype}{$context}{$width}{alias}{context}',
                        width    => '$calendars{month_patterns}{$ctype}{$context}{$width}{alias}{width}',
                    },
EOT
                            }
                            else {
                                say $file "\t\t\t\t\t'$type' => q{$calendars{month_patterns}{$ctype}{$context}{$width}{$type}},";
                            }
                        }
                        say $file "\t\t\t\t},";
                    }
                    say $file "\t\t\t},";
                }
            }
            say $file "\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{cyclic_name_sets}}) {
        print $file <<EOT;
has 'cyclic_name_sets' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{cyclic_name_sets}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $context (sort keys %{$calendars{cyclic_name_sets}{$ctype}}) {
                if ($context eq 'alias' ) {
                    say $file "\t\t\talias => '$calendars{cyclic_name_sets}{$ctype}{alias}',",
                }
                else {
                    say $file "\t\t\t'$context' => {";
                    foreach my $width (sort keys %{$calendars{cyclic_name_sets}{$ctype}{$context}}) {
                        if ($width eq 'alias') {
                            say $file "\t\t\t\talias => q($calendars{cyclic_name_sets}{$ctype}{$context}{alias}),"
                        }
                        else {
                            say $file "\t\t\t\t'$width' => {";
                                foreach my $type ( sort keys %{$calendars{cyclic_name_sets}{$ctype}{$context}{$width}}) {
                                say $file "\t\t\t\t\t'$type' => {";
                                foreach my $id (sort { ($a =~ /^\d+$/a ? $a : 0) <=> ($b =~ /^\d+$/a ? $b : 0) } keys %{$calendars{cyclic_name_sets}{$ctype}{$context}{$width}{$type}} ) {
                                    if ($id eq 'alias') {
                                        print $file <<EOT;
\t\t\t\t\t\talias => {
\t\t\t\t\t\t\tcontext\t=> q{$calendars{cyclic_name_sets}{$ctype}{$context}{$width}{$type}{alias}{context}},
\t\t\t\t\t\t\tname_set\t=> q{$calendars{cyclic_name_sets}{$ctype}{$context}{$width}{$type}{alias}{name_set}},
\t\t\t\t\t\t\ttype\t=> q{$calendars{cyclic_name_sets}{$ctype}{$context}{$width}{$type}{alias}{type}},
\t\t\t\t\t\t},
EOT
                                    }
                                    else {
                                        say $file "\t\t\t\t\t\t$id => q($calendars{cyclic_name_sets}{$ctype}{$context}{$width}{$type}{$id}),";
                                    }
                                }
                                say $file "\t\t\t\t\t},";
                            }
                            say $file "\t\t\t\t},";
                        }
                    }
                    say $file "\t\t\t},";
                }
            }
            say $file "\t\t},";
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

    vsay "Processing Months ($type)";

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
                        context    => $new_width_context,
                        type    => $new_width_type,
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

    vsay "Processing Days ($type)";

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
                        context    => $new_width_context,
                        type    => $new_width_type,
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

    vsay "Processing Quarters ($type)";

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
                        context    => $new_width_context,
                        type    => $new_width_type,
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
            parser => $xml_parser,
            filename => File::Spec->catfile(
                $base_directory,
                'supplemental',
                'dayPeriods.xml',
            )
        );

        my $dayPeriodRuleSets = findnodes($xml,
            q(/supplementalData/dayPeriodRuleSet)
        );

        foreach my $dayPeriodRuleSet ($dayPeriodRuleSets->get_nodelist) {
            my $day_period_type = $dayPeriodRuleSet->getAttribute('type');

            my $dayPeriodRules = findnodes($xml,
                $day_period_type
                ? qq(/supplementalData/dayPeriodRuleSet[\@type="$day_period_type"]/dayPeriodRules)
                : qq(/supplementalData/dayPeriodRuleSet[not(\@type)]/dayPeriodRules)
            );

            foreach my $day_period_rule ($dayPeriodRules->get_nodelist) {
                my $locales = $day_period_rule->getAttribute('locales');
                my %data;
                my $day_periods = findnodes($xml,
                    $day_period_type
                    ? qq(/supplementalData/dayPeriodRuleSet[\@type="$day_period_type"]/dayPeriodRules[\@locales="$locales"]/dayPeriodRule)
                    : qq(/supplementalData/dayPeriodRuleSet[not(\@type)]/dayPeriodRules[\@locales="$locales"]/dayPeriodRule)
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
                foreach my $locale (@locales) {
                    $day_period_data{$locale}{$day_period_type // 'default'} = \%data;
                }
            }
        }
    }

    return $day_period_data{$locale};
}

#/ldml/dates/calendars/calendar/dayPeriods/
sub process_day_periods {
    my ($xpath, $type) = @_;

    vsay "Processing Day Periods ($type)";

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
                    my ($new_context_type) = $path =~ /dayPeriodContext\[\@type='([^']+)'\]/;
                    $dayPeriods{$context_type}{$width_type}{alias}{width} = $new_width_type;
                    $dayPeriods{$context_type}{$width_type}{alias}{context} = $new_context_type || $context_type;
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

    vsay "Processing Eras ($type)";

    my %eras;
    my %alias_size = (
        eraNames     => 'wide',
        eraAbbr        => 'abbreviated',
        eraNarrow    => 'narrow',
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

    vsay "Processing Date Formats ($type)";

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

    vsay "Processing Time Formats ($type)";

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

    vsay "Processing Date Time Formats ($type)";

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

#/ldml/dates/calendars/calendar/monthPatterns/
sub process_month_patterns {
    my ($xpath, $type) = @_;

    vsay "Processing Month Patterns ($type)";
    my (%month_patterns);
    my $month_patterns_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/alias));
    if ($month_patterns_alias->size) {
        my $path = ($month_patterns_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
        $month_patterns{alias} = $alias;
    }
    else {
        my $month_patterns_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext));

        return 0 unless $month_patterns_nodes->size;

        foreach my $context_node ($month_patterns_nodes->get_nodelist) {
            my $context_type = $context_node->getAttribute('type');

            my $width = findnodes($xpath,
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext[\@type="$context_type"]/monthPatternWidth));

            foreach my $width_node ($width->get_nodelist) {
                my $width_type = $width_node->getAttribute('type');

                my $width_alias_nodes = findnodes($xpath,
                    qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext[\@type="$context_type"]/monthPatternWidth[\@type="$width_type"]/alias)
                );

                if ($width_alias_nodes->size) {
                    my $path = ($width_alias_nodes->get_nodelist)[0]->getAttribute('path');
                    my ($new_width_context) = $path =~ /monthPatternContext\[\@type='([^']+)'\]/;
                    $new_width_context //= $context_type;
                    my ($new_width_type) = $path =~ /monthPatternWidth\[\@type='([^']+)'\]/;
                    $month_patterns{$context_type}{$width_type}{alias} = {
                        context    => $new_width_context,
                        width    => $new_width_type,
                    };
                    next;
                }
                my $month_pattern_nodes = findnodes($xpath,
                    qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext[\@type="$context_type"]/monthPatternWidth[\@type="$width_type"]/monthPattern));
                foreach my $month_pattern ($month_pattern_nodes->get_nodelist) {
                    my $month_pattern_type = $month_pattern->getAttribute('type');
                    $month_patterns{$context_type}{$width_type}{$month_pattern_type} =
                        $month_pattern->getChildNode(1)->getValue();
                }
            }
        }
    }
    return \%month_patterns;
}

#/ldml/dates/calendars/calendar/cyclicNameSets/
sub process_cyclic_name_sets {
    my ($xpath, $type) = @_;

    vsay "Processing Cyclic Name Sets ($type)";

    my (%cyclic_name_sets);
    my $cyclic_name_sets_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/alias));
    if ($cyclic_name_sets_alias->size) {
        my $path = ($cyclic_name_sets_alias->get_nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
        $cyclic_name_sets{alias} = $alias;
    }
    else {
        my $cyclic_name_sets_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet));

        return 0 unless $cyclic_name_sets_nodes->size;

        foreach my $name_set_node ($cyclic_name_sets_nodes->get_nodelist) {
            my $name_set_type = $name_set_node->getAttribute('type');
            my $cyclic_name_set_alias = findnodes($xpath,
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name_set_type"]/alias)
            );

            if ($cyclic_name_set_alias->size) {
                my $path = ($cyclic_name_set_alias->get_nodelist)[0]->getAttribute('path');
                my ($alias) = $path=~/\[\@type='(.*?)']/;
                $cyclic_name_sets{$name_set_type}{alias} = $alias;
                next;
            }
            else {
                my $context_nodes = findnodes($xpath,
                    qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name_set_type"]/cyclicNameContext)
                );

                foreach my $context_node ($context_nodes->get_nodelist) {
                    my $context_type = $context_node->getAttribute('type');

                    my $width = findnodes($xpath,
                        qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name_set_type"]/cyclicNameContext[\@type="$context_type"]/cyclicNameWidth));

                    foreach my $width_node ($width->get_nodelist) {
                        my $width_type = $width_node->getAttribute('type');

                        my $width_alias_nodes = findnodes($xpath,
                            qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name_set_type"]/cyclicNameContext[\@type="$context_type"]/cyclicNameWidth[\@type="$width_type"]/alias)
                        );

                        if ($width_alias_nodes->size) {
                            my $path = ($width_alias_nodes->get_nodelist)[0]->getAttribute('path');
                            my ($new_width_type) = $path =~ /cyclicNameWidth\[\@type='([^']+)'\]/;
                            my ($new_context_type) = $path =~ /cyclicNameContext\[\@type='([^']+)'\]/;
                            my ($new_name_type) = $path =~ /cyclicNameSet\[\@type='([^']+)'\]/;
                            $cyclic_name_sets{$name_set_type}{$context_type}{$width_type}{alias} = {
                                name_set => ($new_name_type // $name_set_type),
                                context => ($new_context_type // $context_type),
                                type    => $new_width_type,
                            };
                            next;
                        }

                        my $cyclic_name_set_nodes = findnodes($xpath,
                            qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name_set_type"]/cyclicNameContext[\@type="$context_type"]/cyclicNameWidth[\@type="$width_type"]/cyclicName));
                        foreach my $cyclic_name_set ($cyclic_name_set_nodes->get_nodelist) {
                            my $cyclic_name_set_type = $cyclic_name_set->getAttribute('type') -1;
                            $cyclic_name_sets{$name_set_type}{$context_type}{$width_type}{$cyclic_name_set_type} =
                                $cyclic_name_set->getChildNode(1)->getValue();
                        }
                    }
                }
            }
        }
    }
    return \%cyclic_name_sets;
}

#/ldml/dates/calendars/calendar/fields/field
sub process_fields {
    my ($xpath, $type) = @_;

    vsay "Processing Fields ($type)";

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

    vsay "Processing Time Zone Names";

    my $time_zone_names = findnodes($xpath,
        q(/ldml/dates/timeZoneNames/*));

    return unless $time_zone_names->size;

    print $file <<EOT;
has 'time_zone_names' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
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
                say $file "\t\t\t\t'$type' => q#$zone{$name}{$length}{$type}#,";
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
                    $rule =~ s/\@.*$//;
                    foreach my $region (@regions) {
                        $plurals{$type}{$region}{$count} = $rule;
                    }
                }
            }
        }
    }

    say  $file <<'EOT';
sub _parse_number_plurals {
    use bigfloat;
    my $number = shift;
    my $e = my $c = ($number =~ /[ce](.*)$/ // 0);

    if ($e) {
        $number =~ s/[ce].*$//;
    }

    $number *= 10 ** $e
        if $e;

    my $n = abs($number);
    my $i = int($n);
    my ($f) = $number =~ /\.(.*)$/;
    $f //= '';
    my $t = length $f ? $f + 0 : '';
    my $v = length $f;
    my $w = length $t;
    $t ||= 0;

    return ( $n, $i, $v, $w, $f, $t, $c, $e );
}

my %_plurals = (
EOT

    foreach my $type (sort keys %plurals) {
        say $file "\t$type => {";
        foreach my $region (sort keys %{$plurals{$type}}) {
            say $file "\t\t$region => {";
            foreach my $count ( sort keys %{$plurals{$type}{$region}} ) {
                say $file "\t\t\t$count => sub {";
                say $file "\t\t\t\tmy \$number = shift;";
                say $file "\t\t\t\t" . 'my ( $n, $i, $v, $w, $f, $t, $c, $e ) = _parse_number_plurals( $number );';
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

# Convert format rules into Perl code
sub get_format_rule {
    my $rule = shift;

    $rule =~ s/\@.*$//;

    return 1 unless $rule =~ /\S/;

    # Basic substitutions
    $rule =~ s/\b([niftvwce])\b/\$$1/g;

    my $digit = qr/[0123456789]/;
    my $value = qr/$digit+/;
    my $decimal_value = qr/$value(?:\.$value)?/;
    my $range = qr/$decimal_value\.\.$decimal_value/;
    my $range_list = qr/(\$.*?)\s*(!?)=\s*((?:$range|$decimal_value)(?:,(?:$range|$decimal_value))*)/;

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

    vsay "Processing Footer";

    say $file "no Moo$isRole;";
    say $file '';
    say $file '1;';
    say $file '';
    say $file '# vim: tabstop=4';
}

# Segmentation
sub process_segments {
    my ($file, $xpath) = @_;
    vsay "Processing Segments";

    foreach my $type (qw( GraphemeClusterBreak WordBreak SentenceBreak LineBreak )) {
        my $variables = findnodes($xpath, qq(/ldml/segmentations/segmentation[\@type="$type"]/variables/variable));
        next unless $variables->size;

        print $file <<EOT;
has '${type}_variables' => (
\tis => 'ro',
\tisa => ArrayRef,
\tinit_arg => undef,
\tdefault => sub {[
EOT
        foreach my $variable ($variables->get_nodelist) {
            # Check for deleting variables
            my $value = $variable->getChildNode(1);
            if (defined $value) {
                $value = "'" . $value->getValue . "'";

                # Fix \U escapes
                $value =~ s/ \\ u ( \p{ASCII_Hex_Digit}{4} ) /chr hex $1/egx;
                $value =~ s/ \\ U ( \p{ASCII_Hex_Digit}{8} ) /chr hex $1/egx;
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
\tisa => HashRef,
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
        my $variant   = ucfirst lc ($transform_node->getAttribute('variant') || 'Any');
        my $source    = ucfirst lc ($transform_node->getAttribute('source')  || 'Any');
        my $target    = ucfirst lc ($transform_node->getAttribute('target')  || 'Any');
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
            process_header($file, $package, $xml_file_name);
            process_transform_data(
                $file,
                $xpath,
                (
                    $direction eq 'forward'
                        ? "\x{2192}"
                        : "\x{2190}"
                )
            );

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
        my $rules = $node->getChildNode(1)->getValue;

        # Split into lines
        my @rules = split /\n/, $rules;
        foreach my $rule (@rules) {
            next if $rule =~ /^\s*#/; # Skip comments
            next if $rule =~ /^\s*$/; # Skip empty lines

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
            $terms[0] //= '';
            if ($terms[0] =~ s/^:://) {
                push @transforms, process_transform_conversion(\@terms, $direction);
                next;
            }

            # Check for Variables
            if ($terms[0] =~ /^\$/ && $terms[1] eq '=') {
                my $value = join (' ', map { defined $_ ? $_ : '' } @terms[2 .. @terms]);
                $value =~ s/\[ /[/g;
                $value =~ s/ \]/]/g;
                $vars{$terms[0]} = process_transform_substitute_var(\%vars, $value);
                $vars{$terms[0]} =~ s/^\s*(.*\S)\s*$/$1/;
                # Convert \\u... to char
                $vars{$terms[0]} =~ s/ (?:\\\\)*+ \K \\u (\p{Ahex}+) /chr(hex($1))/egx;
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
    }
    @transforms = reverse @transforms if $direction eq "\x{2190}";

    # Some of these files use non character code points so turn of the
    # non character warning
    no warnings "utf8";

    # Print out transforms
    print $file <<EOT;
BEGIN {
\tdie "Transliteration requires Perl 5.18 or above"
\t\tunless \$^V ge v5.18.0;
}

no warnings 'experimental::regex_sets';
has 'transforms' => (
\tis => 'ro',
\tisa => ArrayRef,
\tinit_arg => undef,
\tdefault => sub { [
EOT
    if (($transforms[0]{type} // '') ne 'filter') {
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
        if (($transform->{type} // '' ) ne $previous) {
            $previous = $transform->{type} // '';
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
    my ($filter) = @_;
    my $match = unicode_to_perl($filter);

    no warnings 'regexp';
    return {
        type => 'filter',
        match => qr/\G$match/im,
    }
}

sub process_transform_substitute_var {
    my ($vars, $string) = @_;

    return $string =~ s!(\$\p{XID_Start}\p{XID_Continue}*)!$vars->{$1} // q()!egr;
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
        $term =~ s/(?<quote>['"])(.+?)\k<quote>/\Q$1\E/g;
        $term =~ s/(["'])(?1)/$1/g;
    }

    return {
        type    => 'conversion',
        before  => unicode_to_perl( join('', @before) ) // '',
        after   => unicode_to_perl( join('', @after) ) // '',
        replace => unicode_to_perl( join('', @replace) ) // '',
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

    # Strip out quotes
    foreach my $term (@before, @after, @replace, @result, @revisit) {
        $term =~ s/(?<quote>['"])(.+?)\k<quote>/\Q$1\E/g;
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

sub process_character_sequance {
    my ($character) = @_;

    return '\N{U+' . join ('.', map { sprintf "%X", ord $_ } split //, $character) . '}';
}

# Sub to mangle Unicode regex to Perl regex
sub unicode_to_perl {
    my ($regex) = @_;

    return '' unless length $regex;
    no warnings 'utf8';

    # Convert Unicode escapes \u1234 to characters
    $regex =~ s/ (?:\\\\)*+ \K \\u ( \p{Ahex}{4}) /chr(hex($1))/egx;
    $regex =~ s/ (?:\\\\)*+ \K \\U ( \p{Ahex}{8}) /chr(hex($1))/egx;

    # Fix up digraphs
    $regex =~ s/ \\ \{ \s* ((?[\p{print} - \s ])+?) \s* \\ \} / process_character_sequance($1) /egx;

    # Sometimes we get a set that looks like [[ data ]], convert to [ data ]
    $regex =~ s/ \[ \[ ([^]]+) \] \] /[$1]/x;

    # This works around a malformed UTF-8 error in Perl's Substitute
    return $regex if ($regex =~ /^[^[]*\[[^]]+\][^[]]*$/);

    # Convert Unicode sets to Perl sets
    $regex =~ s/
        (?:\\\\)*+                   # Pairs of \
        (?!\\)                       # Not followed by \
        \K                           # But we don't want to keep that
        (?<set>                     # Capture this
            \[                      # Start a set
                (?:
                    [^\[\]\\]+         # One or more of not []\
                    |               # or
                    (?:
                        (?:\\\\)*+    # One or more pairs of \ without back tracking
                        \\.         # Followed by an escaped character
                    )
                    |                # or
                    (?&set)            # An inner set
                )++                 # Do the inside set stuff one or more times without backtracking
            \]                        # End the set
        )
    / convert($1) /xeg;
    no warnings "experimental::regex_sets";
    no warnings 'utf8';
    no warnings 'regexp';
    return $regex;
}

sub convert {
    my ($set) = @_;

    # Some definitions
    my $posix = qr/(?(DEFINE)
        (?<posix> (?> \[: .+? :\] ) )
        )/x;


    # Check to see if this is a normal character set
    my $normal = 0;

    $normal = 1 if $set =~ /^
        \s*                     # Possible whitespace
        \[                      # Opening set
        ^?                      # Possible negation
        (?:                       # One of
            [^\[\]]++            # Not an open or close set
            |                    # Or
            (?<=\\)[\[\]]       # An open or close set preceded by \
            |                   # Or
            (?:
                \s*              # Possible Whitespace
                (?&posix)        # A posix class
                (?!             # Not followed by
                    \s*            # Possible whitespace
                    [&-]        # A Unicode regex op
                    \s*         # Possible whitespace
                    \[          # A set opener
                )
            )
        )+
        \]                         # Close the set
        \s*                        # Possible whitespace
        $
        $posix
    /x;

    # Convert posix to perl
    $set =~ s/ \[ : ( .*? ) : \] /\\p{$1}/gx;
    $set =~ s/ \[ \\ p \{ ( [^\}]+ ) \} \] /\\p{$1}/gx;

    if ($normal) {
        return $set;
    }

    # Unicode::Regex::Set needs spaces around opperaters
    $set=~s/&/ & /g;
    $set=~s/([\}\]])-(\[|\\[pP])/$1 - $2/g;

    return Unicode::Regex::Set::parse($set);

# This was my hacked up code until I got Unicode::Regex::Set to work
=comment

    my $inner_set = qr/(?(DEFINE)
        (?<inner> [^\[\]]++)
        (?<basic_set> \[ \^? (?&inner) \] | \\[pP]\{[^}]+} )
        (?<op> (?: [-+&] | \s*) )
        (?<compound_set> (?&basic_set) (?: \s* (?&op) \s* (?&basic_set) )*+ | \[ \^? (?&compound_set) (?: \s* (?&op) \s* (?&compound_set) )*+ \])
        (?<set> (?&compound_set) (?: \s* (?&op) \s* (?&compound_set) )*+ )
    )/x;

    # Fix up [abc[de]] to [[abc][de]]
    $set =~ s/ \[ ( [^\]]+ ) (?<! - ) \[ /[$1] [/gx;
    $set =~ s/ \[ \] /[/gx;

    # Fix up [[ab]cde] to [[ab][cde]]
    $set =~ s#$inner_set \[ \^? (?&set)\K \s* ( [^\[]+ ) \]#
        my $six = $6; defined $6 && $6 =~ /\S/ && $six ne ']' ? "[$six]]" : ']]'
    #gxe;

    # Unicode uses ^ to compliment the set where as Perl uses !
    $set =~ s/\[ \^ \s*/[!/gx;

    # The above can leave us with empty sets. Strip them out
    $set =~ s/\[\s*\]//g;

    # Fixup inner sets with no operator
    1 while $set =~ s/ \] \s* \[ /] + [/gx;
    1 while $set =~ s/ \] \s * (\\p\{.*?\}) /] + $1/xg;
    1 while $set =~ s/ \\p\{.*?\} \s* \K \[ / + [/xg;
    1 while $set =~ s/ \\p\{.*?\} \s* \K (\\p\{.*?\}) / + $1/xg;

    # Unicode uses [] for grouping as well as starting an inner set
    # Perl uses ( ) So fix that up now

    $set =~ s/. \K \[ (?> ( !? ) \s*) ( \[ | \\[pP]\{) /($1$2/gx;
    $set =~ s/ ( \] | \} ) \s* \] (.) /$1 )$2/gx;
    no warnings 'regexp';
    no warnings "experimental::regex_sets";
    return qr"(?$set)";
=cut

}

# Rule based number formats
sub process_rbnf {
    my ($file, $xml) = @_;

    use bigfloat;

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

            my $ruleset_attributes = "\@type='$ruleset'" . (length ($access // '' ) ? " and \@access='$access'" : '');

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
    isa => ArrayRef,
    init_arg => undef,
    default => sub {[ $valid_formats ]},
);

EOT
    }

    print $file <<EOT;
has 'algorithmic_number_format_data' => (
    is => 'ro',
    isa => HashRef,
    init_arg => undef,
    default => sub {
        use bigfloat;
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

sub write_out_collator {
    # In order to keep git out of the CLDR directory we need to
    # write out the code for the CLDR::Collator module
    my $file = shift;

    say $file <<EOT;
package Locale::CLDR::Collator;

use version;
our \$VERSION = version->declare('v$VERSION');

use v5.10.1;
use mro 'c3';
use utf8;
use if \$^V ge v5.12.0, feature => 'unicode_strings';
EOT
    print $file $_ while (<DATA>);
}

sub build_bundle {
    my ($directory, $regions, $name, $region_names) = @_;

    vsay "Building Bundle ", ucfirst lc $name;

    $name =~ s/[^a-zA-Z0-9]//g;
    $name = ucfirst lc $name;

    my $packages = defined $region_names
        ?expand_regions($regions, $region_names)
        :$regions;

    my $filename = File::Spec->catfile($directory, "${name}.pm");

    open my $file, '>', $filename;

    print $file <<EOT;
package Bundle::Locale::CLDR::$name;

use version;

our \$VERSION = version->declare('v$VERSION');

=head1 NAME

Bundle::Locale::CLDR::$name

=head1 CONTENTS

EOT

    foreach my $package (@$packages) {
        # Only put En_US and it's parents and Root in the base bundle
        next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::Root';
        next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::En';
        next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::En::Any';
        next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::En::Any::Us';
        
        # Don't include the package in it's own bundle
        next if "Bundle::Locale::CLDR::$name" eq $package;

        print $file "$package $VERSION\n\n" ;
    }

    print $file <<EOT;

=cut

1;

EOT

}

sub expand_regions {
    my ($regions, $names) = @_;

    my %packages;
    foreach my $region (@$regions) {
        next unless $names->{$region};
        if ($names->{$region} !~ /\.pm$/) {
            my $package = 'Bundle::Locale::CLDR::' . ucfirst lc (($names->{$region} ) =~ s/[^a-zA-Z0-9]//gr);
            $packages{$package} = ();
        }
        if (my $packages = $region_to_package{lc $region}) {
            foreach my $package (@$packages) {
                eval "require $package";
                my @packages = @{ mro::get_linear_isa($package) };
                @packages{@packages} = ();
                delete $packages{'Moo::Object'};
            }
        }
    }

    return [sort { length $a <=> length $b || $a cmp $b } keys %packages];
}

sub build_distributions {
    make_path($distributions_directory) unless -d $distributions_directory;

    build_base_distribution();
    build_transforms_distribution();
    build_language_distributions();
    build_bundle_distributions();
}

sub copy_tests {
    my $distribution = shift;

    my $source_directory = File::Spec->catdir($tests_directory, $distribution);
    my $destination_directory = File::Spec->catdir($distributions_directory, $distribution, 't');
    make_path($destination_directory) unless -d $destination_directory;

    my $files = 0;
    return 0 unless -d $source_directory;
    opendir( my ($dir), $source_directory );
    while (my $file = readdir($dir)) {
        next if $file =~/^\./;
        copy(File::Spec->catfile($source_directory, $file), $destination_directory);
        $files++;
    }
    return $files;
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
        'Moo'                       => '2',
        'MooX::ClassAttribute'      => '0.011',
        'perl'                      => '5.10.1',
        'Type::Tiny'                => 0,
        'Class::Load'               => 0,
        'DateTime::Locale'          => 0,
        'namespace::autoclean'      => 0.16,
        'List::MoreUtils'           => 0,
        'Unicode::Regex::Set'       => 0,
        'bigfloat'                  => 0,
    },
    dist_author         => q{John Imrie <john.imrie1\@gmail.com>},
    dist_version_from   => 'lib/Locale/CLDR.pm',$dist_suffix
    build_requires => {
        'ok'                => 0,
        'Test::Exception'   => 0,
        'Test::More'        => '0.98',
        'File::Spec'        => 0,
    },
    add_to_cleanup      => [ 'Locale-CLDR-*' ],
    configure_requires => { 'Module::Build' => '0.40' },
    release_status => '$RELEASE_STATUS',
    meta_add => {
        keywords => [ qw( locale CLDR ) ],
        resources => {
            homepage => 'https://github.com/ThePilgrim/perlcldr',
            bugtracker => 'https://github.com/ThePilgrim/perlcldr/issues',
            repository => 'https://github.com/ThePilgrim/perlcldr.git',
        },
    },
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
    $module =~ s/\.pm$//;
    my $is_bundle = $module =~ /^Bundle::/ ? 1 : 0;

    my $cleanup = $module =~ s/::/-/gr;
    if ($version) {
        $version = "/$version";
    }
    else {
        $version = '';
        $file =~ s/::/\//g;
    }

    my $language = lc $module;
    $language =~ s/^.*::([^:]+)$/$1/;
    my $name = '';
    $name = "Perl localization data for $languages->{$language}" if exists $languages->{$language};
    $name = "Perl localization data for transliterations" if $language eq 'transformations';
    $name = "Perl localization data for $regions->{uc $language}" if exists $regions->{uc $language} && $is_bundle;
    my $module_base = $is_bundle ? '' : 'Locale::CLDR::';
    my $module_cleanup = $is_bundle ? '' : 'Locale-CLDR-';
    my $requires_base = $is_bundle ? '' : "'Locale::CLDR'              => '$VERSION'";
    my $dist_version = $is_bundle ? "dist_version        => '$VERSION'" : "dist_version_from   => 'lib/Locale/CLDR/$file$version'";
    my $build_text = <<EOT;
use strict;
use warnings;
use utf8;

use Module::Build;

my \$builder = Module::Build->new(
    module_name         => '$module_base$module',
    license             => 'perl',
    requires        => {
        'version'                   => '0.95',
        'DateTime'                  => '0.72',
        'Moo'                       => '2',
        'MooX::ClassAttribute'      => '0.011',
        'Type::Tiny'                => 0,
        'perl'                      => '5.10.1',
        $requires_base,
    },
    dist_author         => q{John Imrie <john.imrie1\@gmail.com>},$dist_suffix
    $dist_version,
    build_requires => {
        'ok'                => 0,
        'Test::Exception'   => 0,
        'Test::More'        => '0.98',
    },
    add_to_cleanup      => [ '$module_cleanup$cleanup-*' ],
    configure_requires => { 'Module::Build' => '0.40' },
    release_status => '$RELEASE_STATUS',
    dist_abstract => 'Locale::CLDR - Data Package ( $name )',
    meta_add => {
        keywords => [ qw( locale CLDR locale-data-pack ) ],
        resources => {
            homepage => 'https://github.com/ThePilgrim/perlcldr',
            bugtracker => 'https://github.com/ThePilgrim/perlcldr/issues',
            repository => 'https://github.com/ThePilgrim/perlcldr.git',
        },
    },
);

\$builder->create_build_script();
EOT

    return $build_text;
}

sub get_files_recursive {
    my $dir_name = shift;
    $dir_name = [$dir_name] unless ref $dir_name;

    my @files;
    return @files unless -d File::Spec->catdir(@$dir_name);
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

    # Copy over the dummy base file
    copy(File::Spec->catfile($lib_directory, 'Transformations.pm'), File::Spec->catfile($distribution, qw(Locale CLDR Transformations.pm)));

    make_distribution(File::Spec->catdir($distributions_directory, 'Transformations'));
}

sub build_language_distributions {
    opendir (my $dir, $locales_directory);
    while (my $file = readdir($dir)) {

        # Skip the Root language as it's subsumed into Base
        next if $file eq 'Root.pm';
        next unless -f File::Spec->catfile($locales_directory, $file);

        my $language = $file;
        $language =~ s/\.pm$//;
        my $distribution = File::Spec->catdir($distributions_directory, $language, 'lib');
        make_path($distribution)
            unless -d $distribution;

        open my $build_file, '>', File::Spec->catfile($distributions_directory, $language,'Build.PL');
        print $build_file build_text("Locales::$file");
        close $build_file;

        my $source_name = File::Spec->catfile($locales_directory, $file);
        my $destination_name = File::Spec->catdir($distribution, qw(Locale CLDR Locales), $file);
        make_path(File::Spec->catdir($distribution, qw(Locale CLDR Locales)))
            unless -d File::Spec->catdir($distribution, qw(Locale CLDR Locales));
        copy($source_name, $destination_name);
        my $parent;
        if ( $parent = $parent_locales{"Locale::CLDR::Locales::$language"} ) {
            my @parent = split /::/, $parent;
            $parent = [$locales_directory, $parent[-1]];
            $parent->[-1].='.pm';
        }
        my @files = (
            get_files_recursive(File::Spec->catdir($locales_directory, $language)),
            ( $parent // ())
        );

        # This construct attempts to copy tests from the t directory and
        # then creates the default tests passing in the flag returned by
        # copy_tests saying whether any tests where copied
        create_default_tests($language, \@files, copy_tests($language));

        foreach my $file (@files) {
            my $source_name = File::Spec->catfile(@$file);
            my $destination_name;
            if($file->[0]=~/Locales$/) {
                $destination_name = File::Spec->catfile($distribution, qw(Locale CLDR Locales), $file->[1]);
            }
            else {
                $destination_name = File::Spec->catdir($distribution, qw(Locale CLDR Locales), $language, @{$file}[1 .. @$file - 2]);
                make_path($destination_name)
                    unless -d $destination_name;
            }
            copy($source_name, $destination_name);
        }

        make_distribution(File::Spec->catdir($distributions_directory, $language));
    }
}

sub create_default_tests {
    my ($distribution, $files, $has_tests) = @_;
    my $destination_directory = File::Spec->catdir($distributions_directory, $distribution, 't');
    make_path($destination_directory) unless -d $destination_directory;

    my $test_file_contents = <<EOT;
#!perl -T
use Test::More;
use Test::Exception;
use ok( 'Locale::CLDR' );
my \$locale;

diag( "Testing Locale::CLDR $Locale::CLDR::VERSION, Perl \$], \$^X" );
use ok 'Locale::CLDR::Locales::$distribution';
EOT
    foreach my $locale (@$files) {
        my ($base, @names) = @$locale;
        $names[-1] =~ s/\.pm$//;
        my $full_name;
        if ($base =~ /Locales$/) {
            $full_name = $names[-1];
        }
        else {
            $full_name = join '::', $distribution, @names;
        }
        $full_name =~ s/\.pm$//;
        $test_file_contents .= "use ok 'Locale::CLDR::Locales::$full_name';\n";
    }

    $test_file_contents .= "\ndone_testing();\n";

    open my $file, '>', File::Spec->catfile($destination_directory, '00-load.t');

    print $file $test_file_contents;

    $destination_directory = File::Spec->catdir($distributions_directory, $distribution);
    open my $readme, '>', File::Spec->catfile($destination_directory, 'README');

    print $readme <<EOT;
Locale-CLDR

Please note that this code requires Perl 5.10.1 and above in the main. There are some parts that require
Perl 5.18 and if you are using Unicode in Perl you really should be using Perl 5.18 or later

The general overview of the project is to convert the XML of the CLDR into a large number of small Perl
modules that can be loaded from the main Local::CLDR when needed to do what ever localisation is required.

Note that the API is not yet fixed. I'll try and keep things that have tests stable but any thing else
is at your own risk.

INSTALLATION

To install this module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Locale Data
This is a locale data package, you will need the Locale::CLDR package to get it to work, which if you are using the
CPAN client should have been installed for you.
EOT

    print $readme <<EOT unless $has_tests;
WARNING
This package has insufficient tests. If you feel like helping get hold of the Locale::CLDR::Locales::En package from CPAN
or use the git repository at https://github.com/ThePilgrim/perlcldr and use the tests from that to create a propper test
suite for this language pack. Please send me a copy of the tests, either by a git pull request, which will get your name into
the git history or by emailing me using my email address on CPAN.
EOT
}

sub build_bundle_distributions {
    opendir (my $dir, $bundles_directory);
    while (my $file = readdir($dir)) {
        next unless -f File::Spec->catfile($bundles_directory, $file);

        my $bundle = $file;
        $bundle =~ s/\.pm$//;
        my $distribution = File::Spec->catdir($distributions_directory, 'Bundles', $bundle, 'lib');
        make_path($distribution)
            unless -d $distribution;

        open my $build_file, '>', File::Spec->catfile($distributions_directory, 'Bundles', $bundle, 'Build.PL');
        print $build_file build_text("Bundle::Locale::CLDR::$file");
        close $build_file;

        my $source_name = File::Spec->catfile($bundles_directory, $file);
        my $destination_name = File::Spec->catdir($distribution, qw(Bundle Locale CLDR), $file);
        make_path(File::Spec->catdir($distribution, qw(Bundle Locale CLDR)))
            unless -d File::Spec->catdir($distribution, qw(Bundle Locale CLDR));
        copy($source_name, $destination_name);

        make_distribution(File::Spec->catdir($distributions_directory, 'Bundles', $bundle));
    }
}

# Below are the number formatter code and the Colation code. They are stored hear to keep git out of the CLDR directory
__DATA__

use v5.10.1;
use mro 'c3';
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Moo::Role;

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

sub format_currency {
    my ($self, $number, $for_cash) = @_;

    my $format = $self->currency_format;
    return $self->format_number($number, $format, undef(), $for_cash);
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


    $format =~ s/¤/'$symbol'/g;

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

    my ($positive, $negative) = $format =~ /^( (?: (?: ' [^']* ' )*+ | [^';]+ )+ ) (?: ; (.+) )? $/x;

    $negative //= "-$positive";

    my $type = 'positive';
    foreach my $to_parse ( $positive, $negative ) {
        my ($prefix, $suffix);
        if (($prefix) = $to_parse =~ /^ ( (?: [^0-9@#.,E'*] | (?: ' [^']* ' )++ )+ ) /x) {
            $to_parse =~ s/^ ( (?: [^0-9@#.,E'*] | (?: ' [^']* ' )++ )+ ) //x;
        }
        if( ($suffix) = $to_parse =~ / ( (?: [^0-9@#.,E'] | (?: ' [^']* ' )++ )+ ) $ /x) {
            $to_parse =~ s/( (?:[^0-9@#.,E'] | (?: ' [^']* ' )++ )+ ) $//x;
        }

        # Fix escaped ', - and +
        foreach my $str ($prefix, $suffix) {
            $str //= '';
            $str =~ s/(?: ' (?: (?: '' )++ | [^']+ ) ' )*? \K ( [-+\\] ) /\\$1/gx;
            $str =~ s/ ' ( (?: '' )++ | [^']++ ) ' /$1/gx;
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

        my $rounding = $to_parse =~ / ( [1-9] [0-9]* (?: \. [0-9]+ )? ) /x;
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
            ($need_plus, $exponent) = $to_parse  =~ m/ E ( \+? ) ( [0-9]+ ) /x;
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
            prefix                         => $prefix // '',
            suffix                         => $suffix // '',
            pad_character                 => $pad_character,
            pad_location                => $pad_location // 'none',
            pad_length                    => $pad_length,
            multiplier                    => $multiplier,
            rounding                    => $rounding,
            minimum_significant_digits    => $minimum_significant_digits,
            maximum_significant_digits    => $maximum_significant_digits,
            minimum_digits                => $minimum_digits // 0,
            exponent_digits                => $exponent_digits,
            exponent_needs_plus            => $need_plus,
            major_group                    => $major_group,
            minor_group                    => $minor_group,
        };

        $type = 'negative';
    }

    return $cache{$format};
}

# Rounding function
sub round {
    my ($self, $number, $increment, $decimal_digits) = @_;

    if ($increment ) {
        $increment /= 10 ** $decimal_digits;
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
    my %symbols;
    foreach my $bundle (@number_symbols_bundles) {
        my $current_symbols = $bundle->number_symbols;
        foreach my $type (keys %$current_symbols) {
            foreach my $symbol (keys %{$current_symbols->{$type}}) {
                $symbols{$type}{$symbol} = $current_symbols->{$type}{$symbol};
            }
        }
    }

    my $symbols_type = $self->default_numbering_system;

    $symbols_type = $symbols{$symbols_type}{alias} if exists $symbols{$symbols_type}{alias};

    my $type = $number=~ s/^-// ? 'negative' : 'positive';

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

    my $minimum_grouping_digits = $self->_find_bundle('minimum_grouping_digits');
    $minimum_grouping_digits = $minimum_grouping_digits
        ? $minimum_grouping_digits->minimum_grouping_digits()
        : 0;

    my ($separator, $decimal_point) = ($symbols{$symbols_type}{group}, $symbols{$symbols_type}{decimal});
    if (($minimum_grouping_digits && length $integer >= $minimum_grouping_digits) || ! $minimum_grouping_digits) {
        my ($minor_group, $major_group) = ($format->{$type}{minor_group}, $format->{$type}{major_group});

        if (defined $minor_group && $separator) {
            # Fast commify using unpack
            my $pattern = "(A$minor_group)(A$major_group)*";
            $number = reverse join $separator, grep {length} unpack $pattern, reverse $integer;
        }
        else {
            $number = $integer;
        }
    }
    else {
        $number = $integer;
    }

    $number.= "$decimal_point$decimal" if defined $decimal;

    # Fix digits
    $number =~ s/([0-9])/$digits[$1]/eg;

    my ($prefix, $suffix) = ( $format->{$type}{prefix}, $format->{$type}{suffix});

    # This needs fixing for escaped symbols
    foreach my $string ($prefix, $suffix) {
        $string =~ s/%/$symbols{$symbols_type}{percentSign}/;
        $string =~ s/‰/$symbols{$symbols_type}{perMille}/;
        if ($type eq 'negative') {
            $string =~ s/(?: \\ \\ )*+ \K \\ - /$symbols{$symbols_type}{minusSign}/x;
            $string =~ s/(?: \\ \\)*+ \K \\ + /$symbols{$symbols_type}{minusSign}/x;
        }
        else {
            $string =~ s/(?: \\ \\ )*+ \K \\ - //x;
            $string =~ s/(?: \\ \\ )*+ \K \\ + /$symbols{$symbols_type}{plusSign}/x;
        }
        $string =~ s/ \\ \\ /\\/gx;
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
#    This allows things like -0.0 to be correctly formatted
# 2) There is no fall back. All the rule sets are self contained
#    in a bundle. Fall back is used to find a bundle but once a
#    bundle is found no further processing of the bundle chain
#    is done. This was found by trial and error when attempting
#    to process -0.0 correctly into English.
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

sub _get_plural_form {
    my ($self, $plural, $from) = @_;

    my ($result) = $from =~ /$plural\{(.+?)\}/;
    ($result) = $from =~ /other\{(.+?)\}/ unless defined $result;

    return $result;
}

sub _process_algorithmic_number_data {
    my ($self, $number, $format_data, $plural, $in_fraction_rule_set) = @_;

    $in_fraction_rule_set //= 0;

    my $format = $self->_get_algorithmic_number_format($number, $format_data);

    my $format_rule = $format->{rule};
    if (! $plural && $format_rule =~ /(cardinal|ordinal)/) {
        my $type = $1;
        $plural = $self->plural($number, $type);
        $plural = [$type, $plural];
    }

    # Sort out plural forms
    if ($plural) {
        $format_rule =~ s/\$\($plural->[0],(.+)\)\$/$self->_get_plural_form($plural->[1],$1)/eg;
    }

    my $divisor = $format->{divisor};
    my $base_value = $format->{base_value} // '';

    # Negative numbers
    if ($number =~ /^-/) {
        my $positive_number = $number;
        $positive_number =~ s/^-//;

        if ($format_rule =~ /→→/) {
            $format_rule =~ s/→→/$self->_process_algorithmic_number_data($positive_number, $format_data, $plural)/e;
        }
        elsif((my $rule_name) = $format_rule =~ /→(.+)→/) {
            my $type = 'public';
            if ($rule_name =~ s/^%%/%/) {
                $type = 'private';
            }
            my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
            if($format_data) {
                # was a valid name
                $format_rule =~ s/→(.+)→/$self->_process_algorithmic_number_data($positive_number, $format_data, $plural)/e;
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
            $format_rule =~ s/→→/$self->_process_algorithmic_number_data_fractions($fraction, $format_data, $plural)/e;
        }
        elsif((my $rule_name) = $format_rule =~ /→(.*)→/) {
            my $type = 'public';
            if ($rule_name =~ s/^%%/%/) {
                $type = 'private';
            }
            my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
            if ($format_data) {
                $format_rule =~ s/→(.*)→/$self->_process_algorithmic_number_data_fractions($fraction, $format_data, $plural)/e;
            }
            else {
                $format_rule =~ s/→(.*)→/$self->_format_number($fraction, $1)/e;
            }
        }

        if ($format_rule =~ /←←/) {
            $format_rule =~ s/←←/$self->_process_algorithmic_number_data($integer, $format_data, $plural, $in_fraction_rule_set)/e;
        }
        elsif((my $rule_name) = $format_rule =~ /←(.+)←/) {
            my $type = 'public';
            if ($rule_name =~ s/^%%/%/) {
                $type = 'private';
            }
            my $format_data = $self->_get_algorithmic_number_format_data_by_name($rule_name, $type);
            if ($format_data) {
                $format_rule =~ s/←(.*)←/$self->_process_algorithmic_number_data($integer, $format_data, $plural, $in_fraction_rule_set)/e;
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
                        $format_rule =~ s/←(.*)←/$self->_process_algorithmic_number_data($number * $base_value, $format_data, $plural, $in_fraction_rule_set)/e;
                    }
                    else {
                        $format_rule =~ s/←(.*)←/$self->_format_number($number * $base_value, $1)/e;
                    }
                }
                else {
                    $format_rule =~ s/←←/$self->_process_algorithmic_number_data($number * $base_value, $format_data, $plural, $in_fraction_rule_set)/e;
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
                        $format_rule =~ s/→(.+)→/$self->_process_algorithmic_number_data($number % $divisor, $format_data, $plural)/e;
                    }
                    else {
                        $format_rule =~ s/→(.*)→/$self->_format_number($number % $divisor, $1)/e;
                    }
                }
                else {
                    $format_rule =~ s/→→/$self->_process_algorithmic_number_data($number % $divisor, $format_data, $plural)/e;
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
                        $format_rule =~ s|←(.*)←|$self->_process_algorithmic_number_data(int ($number / $divisor), $format_data, $plural)|e;
                    }
                    else {
                        $format_rule =~ s|←(.*)←|$self->_format_number(int($number / $divisor), $1)|e;
                    }
                }
                else {
                    $format_rule =~ s|←←|$self->_process_algorithmic_number_data(int($number / $divisor), $format_data, $plural)|e;
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
    my ($self, $fraction, $format_data, $plural) = @_;

    my $result = '';
    foreach my $digit (split //, $fraction) {
        $result .= $self->_process_algorithmic_number_data($digit, $format_data, $plural, 1);
    }

    return $result;
}

sub _get_algorithmic_number_format {
    my ($self, $number, $format_data) = @_;

    use bigfloat;
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

no Moo::Role;

1;

# vim: tabstop=4
__DATA__
#line 6538
use Unicode::Normalize('NFD');
use Unicode::UCD qw( charinfo );
use List::MoreUtils qw(pairwise);
use Moo;
use Types::Standard qw(Str Int Maybe ArrayRef InstanceOf RegexpRef Bool);
with 'Locale::CLDR::CollatorBase';

my $NUMBER_SORT_TOP = "\x{FD00}\x{0034}";
my $LEVEL_SEPARATOR = "\x{0001}";

has 'type' => (
    is => 'ro',
    isa => Str,
    default => 'standard',
);

has 'locale' => (
    is => 'ro',
    isa => Maybe[InstanceOf['Locale::CLDR']],
    default => undef,
    predicate => 'has_locale',
);

has 'alternate' => (
    is => 'ro',
    isa => Str,
    default => 'noignore'
);

# Note that backwards is only at level 2
has 'backwards' => (
    is => 'ro',
    isa => Str,
    default => 'false',
);

has 'case_level' => (
    is => 'ro',
    isa => Str,
    default => 'false',
);

has 'case_ordering' => (
    is => 'ro',
    isa => Str,
    default => 'false',
);

has 'normalization' => (
    is => 'ro',
    isa => Str,
    default => 'true',
);

has 'numeric' => (
    is => 'ro',
    isa => Str,
    default => 'false',
);

has 'reorder' => (
    is => 'ro',
    isa => ArrayRef,
    default => sub { [] },
);

has 'strength' => (
    is => 'ro',
    isa => Int,
    default => 3,
);

has 'max_variable' => (
    is => 'ro',
    isa => Str,
    default => chr(0x0397),
);

has _character_rx => (
    is => 'ro',
    isa => RegexpRef,
    lazy => 1,
    init_arg => undef,
    default => sub {
        my $self = shift;
        my $list = join '|', @{$self->multi_rx()}, '.';
        return qr/\G($list)/s;
    },
);

has _in_variable_weigting => (
    is => 'rw',
    isa => Bool,
    init_arg => undef,
    default => 0,
);

# Set up the locale overrides
sub BUILD {
    my $self = shift;

    my $overrides = [];
    if ($self->has_locale) {
        $overrides = $self->locale->_collation_overrides($self->type);
    }

    foreach my $override (@$overrides) {
        $self->_set_ce(@$override);
    }
}

# Get the collation element at the current strength
sub get_collation_elements {
    my ($self, $string) = @_;
    my @ce;
    if ($self->numeric eq 'true' && $string =~/^\p{Nd}^/) {
        my $numeric_top = $self->collation_elements()->{$NUMBER_SORT_TOP};
        my @numbers = $self->_convert_digits_to_numbers($string);
        @ce = map { "$numeric_top${LEVEL_SEPARATOR}№$_" } @numbers;
    }
    else {
        my $rx = $self->_character_rx;
        my @characters = $string =~ /$rx/g;

        foreach my $character (@characters) {
            my @current_ce;
            if (length $character > 1) {
                # We have a collation element that dependeds on two or more codepoints
                # Remove the code points that the collation element depends on and if
                # there are still codepoints get the collation elements for them
                my @multi_rx = @{$self->multi_rx};
                my $multi;
                for (my $count = 0; $count < @multi_rx; $count++) {
                    if ($character =~ /$multi_rx[$count]/) {
                        $multi = $self->multi_class()->[$count];
                        last;
                    }
                }

                my $match = $character;
                eval "\$match =~ tr/$multi//cd;";
                push @current_ce, $self->collation_elements()->{$match};
                $character =~ s/$multi//g;
                if (length $character) {
                    foreach my $codepoint (split //, $character) {
                        push @current_ce,
                            $self->collation_elements()->{$codepoint}
                            // $self->generate_ce($codepoint);
                    }
                }
            }
            else {
                my $ce = $self->collation_elements()->{$character};
                $ce //= $self->generate_ce($character);
                push @current_ce, $ce;
            }
            push @ce, $self->_process_variable_weightings(@current_ce);
        }
    }
    return @ce;
}

sub _process_variable_weightings {
    my ($self, @ce) = @_;
    return @ce if $self->alternate() eq 'noignore';

    foreach my $ce (@ce) {
        if ($ce->[0] le $self->max_variable) {
            # Variable waighted codepoint
            if ($self->alternate eq 'blanked') {
                @$ce = map { chr() } qw(0 0 0);

            }
            if ($self->alternate eq 'shifted') {
                my $l4;
                if ($ce->[0] eq "\0" && $ce->[1] eq "\0" && $ce->[2] eq "\0") {
                    $ce->[3] = "\0";
                }
                else {
                    $ce->[3] = $ce->[1];
                }
                @$ce[0 .. 2] = map { chr() } qw (0 0 0);
            }
            $self->_in_variable_weigting(1);
        }
        else {
            if ($self->_in_variable_weigting()) {
                if( $ce->[0] eq "\0" && $self->alternate eq 'shifted' ) {
                    $ce->[3] = "\0";
                }
                elsif($ce->[0] ne "\0") {
                    $self->_in_variable_weigting(0);
                    if ( $self->alternate eq 'shifted' ) {
                        $ce->[3] = chr(0xFFFF)
                    }
                }
            }
        }
    }
}

# Converts $string into a sort key. Two sort keys can be correctly sorted by cmp
sub getSortKey {
    my ($self, $string) = @_;

    $string = NFD($string) if $self->normalization eq 'true';

    my @sort_key;

    my @ce = $self->get_collation_elements($string);

    for (my $count = 0; $count < $self->strength(); $count++ ) {
        foreach my $ce (@ce) {
            $ce = [ split //, $ce] unless ref $ce;
            if (defined $ce->[$count] && $ce->[$count] ne "\0") {
                push @sort_key, $ce->[$count];
            }
        }
    }

    return join "\0", @sort_key;
}

sub generate_ce {
    my ($self, $character) = @_;

    my $aaaa;
    my $bbbb;

    if ($^V ge v5.26 && eval q($character =~ /(?!\p{Cn})(?:\p{Block=Tangut}|\p{Block=Tangut_Components})/)) {
        $aaaa = 0xFB00;
        $bbbb = (ord($character) - 0x17000) | 0x8000;
    }
    # Block Nushu was added in Perl 5.28
    elsif ($^V ge v5.28 && eval q($character =~ /(?!\p{Cn})\p{Block=Nushu}/)) {
        $aaaa = 0xFB01;
        $bbbb = (ord($character) - 0x1B170) | 0x8000;
    }
    elsif ($character =~ /(?=\p{Unified_Ideograph=True})(?:\p{Block=CJK_Unified_Ideographs}|\p{Block=CJK_Compatibility_Ideographs})/) {
        $aaaa = 0xFB40 + (ord($character) >> 15);
        $bbbb = (ord($character) & 0x7FFFF) | 0x8000;
    }
    elsif ($character =~ /(?=\p{Unified_Ideograph=True})(?!\p{Block=CJK_Unified_Ideographs})(?!\p{Block=CJK_Compatibility_Ideographs})/) {
        $aaaa = 0xFB80 + (ord($character) >> 15);
        $bbbb = (ord($character) & 0x7FFFF) | 0x8000;
    }
    else {
        $aaaa = 0xFBC0 + (ord($character) >> 15);
        $bbbb = (ord($character) & 0x7FFFF) | 0x8000;
    }
    return join '', map {chr($_)} $aaaa, 0x0020, 0x0002, ord($LEVEL_SEPARATOR), $bbbb, 0, 0;
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

    return $self->getSortKey($a) gt $self->getSortKey($b);
}

sub ge {
    my ($self, $a, $b) = @_;

    return $self->getSortKey($a) ge $self->getSortKey($b);
}

# Get Human readable sort key
sub viewSortKey {
    my ($self, $sort_key) = @_;

    my @levels = split/\x0/, $sort_key;

    foreach my $level (@levels) {
        $level = join ' ',  map { sprintf '%0.4X', ord } split //, $level;
    }

    return '[ ' . join (' | ', @levels) . ' ]';
}

sub _convert_digits_to_numbers {
    my ($self, $digits) = @_;
    my @numbers = ();
    my $script = '';
    foreach my $number (split //, $digits) {
        my $char_info = charinfo(ord($number));
        my ($decimal, $chr_script) = @{$char_info}{qw( decimal script )};
        if ($chr_script eq $script) {
            $numbers[-1] *= 10;
            $numbers[-1] += $decimal;
        }
        else {
            push @numbers, $decimal;
            $script = $chr_script;
        }
    }
    return @numbers;
}

no Moo;

1;

# vim: tabstop=4
