#!/usr/bin/perl

use v5.18;
use strict;
use warnings 'FATAL';
use open ':encoding(utf8)', ':std';

use FindBin;
use File::Spec;
use File::Path qw(make_path);
use XML::XPath; 
use XML::XPath::Node::Text;
use LWP::UserAgent;
use Archive::Extract;
use DateTime;
use XML::Parser;
use Text::ParseWords;
use List::MoreUtils qw( any );
no warnings "experimental::regex_sets";

our $verbose = 0;
$verbose = 1 if grep /-v/, @ARGV;
@ARGV = grep !/-v/, @ARGV;

use version;
our $VERSION = version->parse('0.1');
my $CLDR_VERSION = version->parse('23.1');
my $CLDR_PATH = 23.1;

chdir $FindBin::Bin;
my $data_directory            = File::Spec->catdir($FindBin::Bin, 'Data');
my $core_filename             = File::Spec->catfile($data_directory, 'core.zip');
my $base_directory            = File::Spec->catdir($data_directory, 'common'); 
my $transform_directory       = File::Spec->catdir($base_directory, 'transforms');
my $lib_directory             = File::Spec->catdir($FindBin::Bin, 'lib', 'Locale', 'CLDR');
my $transformations_directory = File::Spec->catdir($lib_directory, 'Transformations');

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

# The supplemental/supplementalMetaData.xml file contains a list of all valid
# locale codes
my $xml = XML::XPath->new(
    File::Spec->catfile($base_directory,
        'supplemental',
        'supplementalMetadata.xml',
    )
);

open my $file, '>', File::Spec->catfile($lib_directory, 'ValidCodes.pm');

my $file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'supplementalMetadata.xml'
);

say "Processing file $file_name" if $verbose;

# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::ValidCodes', $CLDR_VERSION, $xml, $file_name, 1);
process_cp($xml);
process_valid_languages($file, $xml);
process_valid_scripts($file, $xml);
process_valid_territories($file, $xml);
process_valid_variants($file, $xml);
#process_valid_currencies($file, $xml);
process_valid_keys($file, $base_directory);
process_valid_language_aliases($file,$xml);
process_valid_territory_aliases($file,$xml);
process_valid_variant_aliases($file,$xml);
process_footer($file, 1);
close $file;

# File for era boundries
$xml = XML::XPath->new(
    File::Spec->catfile($base_directory,
        'supplemental',
        'supplementalData.xml',
    )
);

open $file, '>', File::Spec->catfile($lib_directory, 'EraBoundries.pm');

my $file_name = File::Spec->catfile($base_directory,
    'supplemental',
    'supplementalData.xml'
);

say "Processing file $file_name" if $verbose;


# Note: The order of these calls is important
process_header($file, 'Locale::CLDR::EraBoundries', $CLDR_VERSION, $xml, $file_name, 1);
process_era_boundries($file, $xml);
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

# Transformations
make_path($transformations_directory) unless -d $transformations_directory;
opendir (my $dir, $transform_directory);
my $num_files = grep { -f File::Spec->catfile($transform_directory,$_)} readdir $dir;
my $count_files = 0;
rewinddir $dir;

foreach my $file_name ( sort grep /^[^.]/, readdir($dir) ) {
    my $percent = ++$count_files / $num_files * 100;
    my $full_file_name = File::Spec->catfile($transform_directory, $file_name);
    say sprintf("Processing Transformation File %s: %.2f%% done", $full_file_name, $percent) if $verbose;
	$xml = XML::XPath->new($full_file_name);
    process_transforms($transformations_directory, $xml, $full_file_name);
}

# Main directory
my $main_directory = File::Spec->catdir($base_directory, 'main');
opendir ( my $dir, $main_directory);

# Count the number of files
$num_files = grep { -f File::Spec->catfile($main_directory,$_)} readdir $dir;
$count_files = 0;
rewinddir $dir;

my $segmentation_directory = File::Spec->catdir($base_directory, 'segments');
# Sort files ASCIIbetically
foreach my $file_name ( sort grep /^[^.]/, readdir($dir) ) {
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

    my @output_file_parts = output_file_name($xml);
    my $current_locale = lc $output_file_parts[0];

    my $package = join '::', @output_file_parts;
    $output_file_parts[-1] .= '.pm';

    my $out_directory = File::Spec->catdir(
        $lib_directory, 
        @output_file_parts[0 .. $#output_file_parts - 1]
    );

    make_path($out_directory) unless -d $out_directory;

    open $file, '>', File::Spec->catfile($lib_directory, @output_file_parts);

    my $full_file_name = File::Spec->catfile($base_directory, 'main', $file_name);
    my $percent = ++$count_files / $num_files * 100;
    say sprintf("Processing File %s: %.2f%% done", $full_file_name, $percent) if $verbose;

    # Note: The order of these calls is important
    process_class_any($lib_directory, @output_file_parts[0 .. $#output_file_parts -1]);

    process_header($file, "Locale::CLDR::$package", $CLDR_VERSION, $xml, $full_file_name);
    process_segments($file, $segment_xml) if $segment_xml;
    process_cp($xml);
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
    process_calendars($file, $xml, $current_locale);
    process_time_zone_names($file, $xml);
    process_footer($file);

    close $file;
}

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

# Fill in any missing script or territory with the psudo class Any
sub process_class_any {
    my ($lib_path, @path_parts) = @_;
    
    my $package = 'Locale::CLDR';
    foreach my $path (@path_parts) {
        my $parent = $package;
        $parent = 'Locale::CLDR::Root' if $parent eq 'Locale::CLDR';
        $package .= "::$path";
        $lib_path = File::Spec->catfile($lib_path, $path);

        next unless $path eq 'Any';
        next if -e "$lib_path.pm";

        my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');
        open my $file, '>:utf8', "$lib_path.pm";
        print $file <<EOT;
package $package;
# This file auto generated
#\ton $now GMT

use v5.18;
use mro 'c3';

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
    my ($file, $class, $version, $xpath, $xml_name, $isRole) = @_;
    say "Processing Header" if $verbose;

    $isRole = $isRole ? '::Role' : '';

    $xml_name =~s/^.*(Data.*)$/$1/;
    my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');
    my $xml_generated = ( findnodes($xpath, '/ldml/identity/generation')
        || findnodes($xpath, '/supplementalData/generation')
    )->get_node->getAttribute('date');

    $xml_generated=~s/^\$Date: (.*) \$$/$1/;

    my $header = <<EOT;
package $class;
# This file auto generated from $xml_name
#\ton $now GMT
# XML file generated $xml_generated

use v5.18;
use mro 'c3';

use Moose$isRole;

EOT
    print $file $header;
}

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

sub process_valid_currencies {
    my ($file, $xpath) = @_;

    say "Processing Valid Currencies"
        if $verbose;

    my $currencies = findnodes($xpath, '/supplementalData/metadata/validity/variable[@id="$currency"]');

    my @currencies = map {"$_\n" } split /\s+/,  $currencies->get_node->string_value;

    print $file <<EOT
has 'valid_currencies' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'ArrayRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
\tdefault\t=> sub {[qw( @currencies \t)]},
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
        my $alias = $keys{$key}{alias};
        next unless $alias;
        say $file "\t\t$alias => '$key',";
    }
    print $file <<EOT;
\t}},
);

has 'key_names' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tauto_deref\t=> 1,
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

sub process_era_boundries {
    my ($file, $xpath) = @_;

    say "Processing Era Boundries"
        if $verbose;
    
    my $calendars = findnodes($xpath,
        q(/supplementalData/calendarData/calendar));
    
    print $file <<EOT;
has 'era_boundry' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'CodeRef',
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
                $m //= '0';
                $d //= '0';
                $start = sprintf('%d%0.2d%0.2d',$y,$m,$d);
                say $file "\t\t\t\t\$return = $type if \$date >= $start;";
            }
            if (length $end) {
                my ($y, $m, $d) = split /-/, $end;
                $m //= '0';
                $d //= '0';
                $end = sprintf('%d%0.2d%0.2d',$y,$m,$d);
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
has 'week_data_min_days' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_min_days->get_nodelist) {
        my @territories = split / /,$node->getAttribute('territories');
        my $count = $node->getAttribute('count');
        foreach my $territory (@territories) {
            say $file "\t\t$territory => $count,";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
    
    my $week_data_first_day = findnodes($xpath,
        q(/supplementalData/weekData/firstDay));

    print $file <<EOT;
has 'week_data_first_day' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_first_day->get_nodelist) {
        my @territories = split / /,$node->getAttribute('territories');
        my $day = $node->getAttribute('day');
        foreach my $territory (@territories) {
            say $file "\t\t$territory => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
    
    my $week_data_weekend_start= findnodes($xpath,
        q(/supplementalData/weekData/weekendStart));

    print $file <<EOT;
has 'week_data_weekend_start' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_weekend_start->get_nodelist) {
        my @territories = split / /,$node->getAttribute('territories');
        my $day = $node->getAttribute('day');
        foreach my $territory (@territories) {
            say $file "\t\t$territory => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
    
    my $week_data_weekend_end = findnodes($xpath,
        q(/supplementalData/weekData/weekendEnd));

    print $file <<EOT;
has 'week_data_weekend_end' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week_data_weekend_end->get_nodelist) {
        my @territories = split / /,$node->getAttribute('territories');
        my $day = $node->getAttribute('day');
        foreach my $territory (@territories) {
            say $file "\t\t$territory => '$day',";
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
            say $file "\t\t$territory => '", join("','", @ordering), "',";
        }
    }
    print $file <<EOT;
\t}},
);

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

# Sub to look for alias entries along the given path if we find any
# we replace the alias node with the nodes it points to
sub process_alias {
    my ($xpath, $recursed) = @_;
    say "Processing Aliases" if $verbose and not $recursed;

    my $alias_nodes = ($recursed ? $recursed : $xpath)->findnodes('.//alias');
    return unless $alias_nodes->size;

    # now replace the node
    foreach my $node ($alias_nodes->get_nodelist) {
        my $new_path=$node->getAttribute('path');
        my $parent = $node->getParentNode;
        
        # Check if we have already replaced this node.
        # It wont have a parent if we have
        next unless $parent;

        my @replacements = $parent->findnodes($new_path)->get_nodelist;

        foreach my $replacement (@replacements) {
            process_alias($xpath,$replacement);
            $parent->insertBefore($replacement,$node);
        }
        $parent->removeChild($node);
    }
}

# CP elements are used to encode characters outside the character range 
# allowable in XML
sub process_cp {
    my ($xpath) = @_;

    say "Processing Cp"
        if $verbose;

    foreach my $character ( $xpath->findnodes('//cp')) {
        my $parent = $character->getParentNode;
        my @siblings = $parent->getChildNodes;
        my $text = '';
        foreach my $sibling (@siblings) {
            if ($sibling->isTextNode) {
                $text.=$sibling->getNodeValue;
            }
            else {
                my $hex = $character->getAttribute('hex');
                    my $chr = chr(hex $hex);
                $text .= $chr;
            }
            $parent->removeChild($sibling);
        }
        $parent->appendChild(XML::XPath::Node::Text->new($text));
    }
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
        my $type = $key->getAttribute('type');
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
        my $type = $type_node->getAttribute('type');
        my $key  = $type_node->getAttribute('key');
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
        my $type = $name->getAttribute('type');
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

    say "Processing exemplarCharacters" if $verbose;
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
\tdefault\t\t=> sub {
\tno warnings 'experimental::regex_sets';
\t\treturn {
EOT
    foreach my $type (sort keys %data) {
        say $file "\t\t\t$type => $data{$type}";
    }
    print $file <<EOT;
\t\t};
\t},
);

EOT
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
        say $file "\t\t\t$type => '$data{$type}',";
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

sub process_units {
    my ($file, $xpath) = @_;

    say 'Processing Units' if $verbose;
    my $units = findnodes($xpath, '/ldml/units/*');
    next unless $units->size;

    my @units;
    foreach my $unit ($units->get_nodelist) {
        my $type = $unit->getAttribute('type');
        push @units, {type => $type};
        foreach my $unit_pattern ($unit->getChildNodes) {
            next if $unit_pattern->isTextNode;

            my $count = $unit_pattern->getAttribute('count');
            my $alt = $unit_pattern->getAttribute('alt') || 'default';
            my $pattern = $unit_pattern->getChildNode(1)->getValue;
        $units[-1]{$alt}{$count} = $pattern;
        }
    }
        
    print $file <<EOT;
has 'units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[HashRef[HashRef[Str]]]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
    foreach my $unit (@units) {
        say $file "\t\t\t\t'",$unit->{type},"' => {";
        foreach my $length (grep { $_ ne 'type' } keys %$unit) {
            say $file "\t\t\t\t\t'$length' => {";
                foreach my $count (keys %{$unit->{$length}}) {
                    say $file "\t\t\t\t\t\t'$count' => q(",
                        $unit->{$length}{$count},
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
    next unless $yes->size || $no->size;
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
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> '(?i:$yes)'
);
EOT

    print $file <<EOT if defined $no;
has 'nostr' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> '(?i:$no)'
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
    my $default_nodes = findnodes($xpath,'/ldml/dates/calendars/default');
    if ($default_nodes->size) {
        my $default = ($default_nodes->get_nodelist)[0]->getAttribute('choice');
        $calendars{default} = $default;
    }

    foreach my $calendar ($calendars->get_nodelist) {
        my $type = $calendar->getAttribute('type');
        my ($months, $months_aliases) = process_months($xpath, $type);
        $calendars{months}{$type} = $months if $months;
        $calendars{months_aliases}{$type} = $months_aliases if $months_aliases;
        my ($days, $days_alias) = process_days($xpath, $type);
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
        my $fields = process_fields($xpath, $type);
        $calendars{fields}{$type} = $fields if $fields;
    }

    # Got all the data now write it out to the file;
    if ($calendars{default}) {
        print $file <<EOT;
has 'calendar_default' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> q{$calendars{default}},
);

EOT

    }
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
                if ($context eq 'default') {
                    say $file "\t\t\t\t'default' => q{$calendars{months}{$type}{default}},";
                    next;
                }

                say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{months}{$type}{$context}}) {
                    if ($width eq 'default') {
                        say $file "\t\t\t\t\t'default' => q{$calendars{months}{$type}{$context}{default}},";
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
                            my $month = $_;
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

    if (keys %{$calendars{months_aliases}}) {
        print $file <<EOT;
has 'calendar_months_alias' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $from (sort keys %{$calendars{months_aliases}}) {
            say $file "\t\t\tq($from) => q($calendars{months_aliases}{$from})";
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
                if ($context eq 'default') {
                    say $file "\t\t\t\t'default' => q{$calendars{days}{$type}{default}},";
                    next;
                }

                say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{days}{$type}{$context}}) {
                    if ($width eq 'default') {
                        say $file "\t\t\t\t\tdefault => q{$calendars{days}{$type}{$context}{default}},";
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
                say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{quarters}{$type}{$context}}) {
                    print $file "\t\t\t\t\t$width => [";
                    say $file join ",\n\t\t\t\t\t\t",
                        map {
                            my $quarter = $_;
                            $quarter =~ s/'/\\'/;
                            $quarter = "'$quarter'";
                        } @{$calendars{quarters}{$type}{$context}{$width}};
                    say $file "\t\t\t\t\t],";
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
        foreach my $ctype (keys %{$calendars{day_periods}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $type (keys %{$calendars{day_periods}{$ctype}}) {
                say $file "\t\t\t'$type' => {";
                foreach my $width (keys %{$calendars{day_periods}{$ctype}{$type}}) {
                    say $file "\t\t\t\t'$width' => {";
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
        foreach my $ctype (keys %{$calendars{eras}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $type (keys %{$calendars{eras}{$ctype}}) {
                say $file "\t\t\t$type => [";
                print $file "\t\t\t\t";
                print $file join ",\n\t\t\t\t", map {
                    my $name = $_;
                    $name =~ s/'/\\'/;
                    "'$name'";
                } @{$calendars{eras}{$ctype}{$type}};
                say $file "\n\t\t\t],";
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
        foreach my $ctype (keys %{$calendars{date_formats}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $length (keys %{$calendars{date_formats}{$ctype}}) {
                say $file "\t\t\t'$length' => q{$calendars{date_formats}{$ctype}{$length}},";
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
        foreach my $ctype (keys %{$calendars{time_formats}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $length (keys %{$calendars{time_formats}{$ctype}}) {
                say $file "\t\t\t'$length' => q{$calendars{time_formats}{$ctype}{$length}},";
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
        foreach my $ctype (keys %{$calendars{datetime_formats}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $length (keys %{$calendars{datetime_formats}{$ctype}{formats}}) {
                say $file "\t\t\t'$length' => q{$calendars{datetime_formats}{$ctype}{formats}{$length}},";
            }
            if (exists $calendars{datetime_formats}{$ctype}{default}) {
                say $file "\t\t\tdefault => q{$calendars{datetime_formats}{$ctype}{default}},";
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
            if (exists $calendars{datetime_formats}{$ctype}{available_formats}) {
                say $file "\t\t'$ctype' => {";
                foreach my $type (sort keys %{$calendars{datetime_formats}{$ctype}{available_formats}}) {
                    say $file "\t\t\t$type => q{$calendars{datetime_formats}{$ctype}{available_formats}{$type}},";
                }
                say $file "\t\t},";
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
            if (exists $calendars{datetime_formats}{$ctype}{appendItem}) {
                say $file "\t\t'$ctype' => {";
                foreach my $type (sort keys %{$calendars{datetime_formats}{$ctype}{appendItem}}) {
                    say $file "\t\t\t'$type' => '$calendars{datetime_formats}{$ctype}{appendItem}{$type}',";
                }
                say $file "\t\t},";
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
        print $file <<EOT;
\t} },
);
    
EOT
    }

    if (keys %{$calendars{fields}}) {
        print $file <<EOT;
has 'calendar_fields ' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

        foreach my $ctype (keys %{$calendars{fields}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $type (sort keys %{$calendars{fields}{$ctype}}) {
                say $file "\t\t\t'$type' => {";
                if (exists $calendars{fields}{$ctype}{$type}{name}) {
                    say $file "\t\t\t\tname => '$calendars{fields}{$ctype}{$type}{name}',";
                }
                foreach my $rtype (sort keys %{$calendars{fields}{$ctype}{$type}{relative}}) {
                    say $file "\t\t\t\t$rtype => q{$calendars{fields}{$ctype}{$type}{relative}{$rtype}},";
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
}

#/ldml/dates/calendars/calendar/months/
sub process_months {
    my ($xpath, $type) = @_;

    say "Processing Months ($type)" if $verbose;

    my (%months,$aliases);
    my $default_context = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/default));
    if ($default_context->size) {
        my $default_node = ($default_context->get_nodelist)[0];
        my $choice = $default_node->getAttribute('choice');
        $months{default} = $choice;
    }

    my $months_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/alias));
    if ($months_alias->size) {
        my $path = ($months_alias->get_nodelist)[0]->getAttribute('path');
        ($aliases) = $path=~/\[\@type='(.*?)']/;
    }
    else {
        my $months_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext));

        return 0 unless $months_nodes->size;

        foreach my $context_node ($months_nodes->get_nodelist) {
            my $context_type = $context_node->getAttribute('type');

            my $default_width = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context_type"]/default));

            if ($default_width->size) {
                my $default_node = ($default_width->get_nodelist)[0];
                my $choice = $default_node->getAttribute('choice');
                $months{$context_type}{default} = $choice;
            }

            my $width = findnodes($xpath,
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context_type"]/monthWidth));

            foreach my $width_node ($width->get_nodelist) {
                my $width_type;
                my $width_context = $context_type;

                if ($width_node->getLocalName() eq 'alias') {
                    my $path = $width_node->getAttribute('path');
                    my ($new_width_context) = $path =~ /monthContext\[\@type='([^']+)'\]/;
                    $width_context = $new_width_context if $new_width_context;
                    ($width_type) = $path =~ /monthWidth\[\@type='([^']})'\]/;
                }
                else {
                    $width_type = $width_node->getAttribute('type');
                }

                my $month_nodes = findnodes($xpath, 
                    qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$width_context"]/monthWidth[\@type="$width_type"]/month));
                foreach my $month ($month_nodes->get_nodelist) {
                    my $month_type = $month->getAttribute('type') -1;
                    my $year_type = $month->getAttribute('yeartype') || 'nonleap';
                    $months{$context_type}{$width_type}{$year_type}[$month_type] = 
                        $month->getChildNode(1)->getValue();
                }
            }
        }
    }
    return \%months, $aliases;
}

#/ldml/dates/calendars/calendar/days/
sub process_days {
    my ($xpath, $type) = @_;

    say "Processing Days ($type)" if $verbose;

    my (%days, %aliases);
    my $days_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/alias));
    if ($days_alias->size) {
        my $path = ($days_alias->get_nodelist)[0]->getAttribute('path');
        ($aliases{$type}) = $path=~/\[\@type='(.*?)']/;
    }

    my $days_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext));
    return 0 unless $days_nodes->size;

    my $default_context = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/default));
    if ($default_context->size) {
        my $default_node = ($default_context->get_nodelist)[0];
        my $choice = $default_node->getAttribute('choice');
        $days{default} = $choice;
    }

    foreach my $context_node ($days_nodes->get_nodelist) {
        my $context_type = $context_node->getAttribute('type');

        my $default_width = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context_type"]/default));

        if ($default_width->size) {
            my $default_node = ($default_width->get_nodelist)[0];
            my $choice = $default_node->getAttribute('choice');
            $days{$context_type}{default} = $choice;
        }

        my $width = findnodes($xpath,
            qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context_type"]/dayWidth));
        foreach my $width_node ($width->get_nodelist) {
            my $width_type = $width_node->getAttribute('type');
            my $day_nodes = findnodes($xpath, 
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context_type"]/dayWidth[\@type="$width_type"]/day));
            foreach my $day ($day_nodes->get_nodelist) {
                my $day_type = $day->getAttribute('type');
                $days{$context_type}{$width_type}{$day_type} = 
                    $day->getChildNode(1)->getValue();
            }
        }
    }
    return \%days, \%aliases;
}

#/ldml/dates/calendars/calendar/quarters/
sub process_quarters {
    my ($xpath, $type) = @_;

    say "Processing Quarters ($type)" if $verbose;

    my %quarters;

    my $quarters_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/alias));
    if ($quarters_alias->size) {
        $type = 'gregorian';
    }

    my $quarters_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext));
    return 0 unless $quarters_nodes->size;

    foreach my $context_node ($quarters_nodes->get_nodelist) {
        my $context_type = $context_node->getAttribute('type');
        my $width = findnodes($xpath,
            qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context_type"]/quarterWidth));
        foreach my $width_node ($width->get_nodelist) {
            if ($width_node->getLocalName() eq 'alias') {
                my $path = $width_node->getAttribute('path');
                
            }
            my $width_type = $width_node->getAttribute('type');
            my $quarter_nodes = findnodes($xpath, 
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context_type"]/quarterWidth[\@type="$width_type"]/quarter));
            foreach my $quarter ($quarter_nodes->get_nodelist) {
                my $quarter_type = $quarter->getAttribute('type') -1;
                $quarters{$context_type}{$width_type}[$quarter_type] = 
                    $quarter->getChildNode(1)->getValue();
            }
        }
    }
    return \%quarters;
}

{
    my %day_period_data;
    sub process_day_period_data {
        my $locale = shift;
        unless (keys %day_period_data) {

# The supplemental/dayPeriods.xml file contains a list of all valid
# day periods
            my $xml = XML::XPath->new(
                            File::Spec->catfile($base_directory,
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
}

#/ldml/dates/calendars/calendar/dayPeriods/
sub process_day_periods {
    my ($xpath, $type) = @_;

    say "Processing Day Periods ($type)" if $verbose;

    my %dayPeriods;
    my $dayPeriods_alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/alias));
    if ($dayPeriods_alias->size) {
        $type = 'gregorian';
    }

    my $dayPeriods_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext));
    return 0 unless $dayPeriods_nodes->size;

    foreach my $context_node ($dayPeriods_nodes->get_nodelist) {
        my $context_type = $context_node->getAttribute('type');
        my $width = findnodes($xpath,
            qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context_type"]/dayPeriodWidth));
        foreach my $width_node ($width->get_nodelist) {
            my $width_type = $width_node->getAttribute('type');
            my $dayPeriod_nodes = findnodes($xpath, 
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context_type"]/dayPeriodWidth[\@type="$width_type"]/dayPeriod));
            foreach my $dayPeriod ($dayPeriod_nodes->get_nodelist) {
                my $dayPeriod_type = $dayPeriod->getAttribute('type');
                $dayPeriods{$context_type}{$width_type}{$dayPeriod_type} = 
                    $dayPeriod->getChildNode(1)->getValue();
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
    my $eras = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras));

    return 0 unless $eras->size;
    my $eraNames = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNames/era));
    if ($eraNames->size) {
        foreach my $eraName ($eraNames->get_nodelist) {
            my $era_type = $eraName->getAttribute('type');
            $eras{wide}[$era_type] = $eraName->getChildNode(1)->getValue();
        }
    }
    else {
        if(findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNames/alias))->size) {
            $eraNames = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraAbbr/era));
            foreach my $eraName ($eraNames->get_nodelist) {
                my $era_type = $eraName->getAttribute('type');
                $eras{wide}[$era_type] = $eraName->getChildNode(1)->getValue();
            }
        }
    }
    my $eraAbbrs = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraAbbr/era));
    if ($eraAbbrs->size) {
        foreach my $eraAbbr ($eraAbbrs->get_nodelist) {
            my $era_type = $eraAbbr->getAttribute('type');
            $eras{abbriviated}[$era_type] = $eraAbbr->getChildNode(1)->getValue();
        }
    }
    my $eraNarrows = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNarrow/era));
    if ($eraNarrows->size) {
        foreach my $eraNarrow ($eraNarrows->get_nodelist) {
            my $era_type = $eraNarrow->getAttribute('type');
            $eras{narrow}[$era_type] = $eraNarrow->getChildNode(1)->getValue();
        }
    }
    else {
        if(findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNarrow/alias))->size) {
            $eraNarrows = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraAbbr/era));
            foreach my $eraNarrow ($eraNarrows->get_nodelist) {
                my $era_type = $eraNarrow->getAttribute('type');
                $eras{narrow}[$era_type] = $eraNarrow->getChildNode(1)->getValue();
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
    my $dateFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats));

    return 0 unless $dateFormats->size;

    my %dateFormats;

    my $default_context = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/default));
    if ($default_context->size) {
        my $default_node = ($default_context->get_nodelist)[0];
        my $choice = $default_node->getAttribute('choice');
        $dateFormats{default} = $choice;
    }

    my $dateFormatLength_nodes = findnodes($xpath,
        qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/dateFormatLength)
        );

    foreach my $dateFormatLength ($dateFormatLength_nodes->get_nodelist) {
        my $date_format_type = $dateFormatLength->getAttribute('type');

        my $patterns = findnodes($xpath,
            qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/dateFormatLength[\@type="$date_format_type"]/dateFormat/pattern)
        );

        my $pattern = $patterns->[0]->getChildNode(1)->getValue;
        $dateFormats{$date_format_type} = $pattern;
    }
    return \%dateFormats;
}

#/ldml/dates/calendars/calendar/timeFormats/
sub process_time_formats {
    my ($xpath, $type) = @_;

    say "Processing Time Formats ($type)" if $verbose;

    my %timeFormats;
    my $timeFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats));

    return 0 unless $timeFormats->size;

    my %timeFormats;

    if (findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/alias))->size) {
        $type = 'gregorian';
    }

    my $default_context = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/default));
    if ($default_context->size) {
        my $default_node = ($default_context->get_nodelist)[0];
        my $choice = $default_node->getAttribute('choice');
        $timeFormats{default} = $choice;
    }

    my $timeFormatLength_nodes = findnodes($xpath,
        qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/timeFormatLength)
        );

    foreach my $timeFormatLength ($timeFormatLength_nodes->get_nodelist) {
        my $time_format_type = $timeFormatLength->getAttribute('type');

        my $patterns = findnodes($xpath,
            qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/timeFormatLength[\@type="$time_format_type"]/timeFormat/pattern)
        );

        my $pattern = $patterns->[0]->getChildNode(1)->getValue;
        $timeFormats{$time_format_type} = $pattern;
    }
    return \%timeFormats;
}

#/ldml/dates/calendars/calendar/dateTimeFormats/
sub process_datetime_formats {
    my ($xpath, $type) = @_;

    say "Processing Date Time Formats ($type)" if $verbose;

    my %dateTimeFormats;
    my $dateTimeFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats));

    return 0 unless $dateTimeFormats->size;

    my %dateTimeFormats;

    my $default_context = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/default));
    if ($default_context->size) {
        my $default_node = ($default_context->get_nodelist)[0];
        my $choice = $default_node->getAttribute('choice');
        $dateTimeFormats{default} = $choice;
    }

    my $dateTimeFormatLength_alias = findnodes($xpath,
        qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/dateTimeFormatLength/alias)
        );

    if ($dateTimeFormatLength_alias->size){
        $type = 'gregorian';
    }

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
    my $intervalFormats_alias = findnodes($xpath,
        qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/intervalFormats/alias)
    );

    if ($intervalFormats_alias->size) {
        $type = 'gregorian';
    }

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

    next unless $time_zone_names->size;

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
                    my $tz_type_nodes = findnodes($xpath,
                        qq(/ldml/dates/timeZoneNames/$_) . qq([\@type="$name"]/$length/*));
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
                $value = "'" . unicode_to_perl($value->getValue) . "'";
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

            my $package = "Local::CLDR::Transform::${variant}::${source}::$target";
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
        my $rule = $node->getChildNode(1)->getValue;
		my @terms = grep { /\S/ } parse_line(qr/\s+|[{};\x{2190}\x{2192}\x{2194}=\[\]]/, 'delimiters', $rule);
		
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
			last if $term eq ';';
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
has 'transforms' => (
\tis => 'ro',
\tisa => 'ArrayRef[HashRef]',
\tinit_arg => undef,
\tdefault => sub { [
\t\tno warnings 'experimental::regex_sets';
EOT
    if ($transforms[0]{type} ne 'filter') {
        unshift @transforms, {
            type => 'filter',
            match => qr/\G./m,
        }
    }

    foreach my $transform (@transforms) {
        if ($transform->{type} eq 'filter') {
            say $file "\t\tfilter => qr/$transform->{match}/,"
        }
        if ($transform->{type} eq 'transform') {
            print $file <<EOT;
\t\ttransform => {
\t\t\tfrom => q($transform->{from}),
\t\t\tto => q($transform->{to}),
\t\t},
EOT
        }
        if ($transform->{type} eq 'conversion') {
            print $file <<EOT;
\t\tconversion => {
\t\t\tbefore  => q($transform->{before}),
\t\t\tafter   => q($transform->{after}),
\t\t\treplace => q($transform->{replace}),
\t\t\tresult  => q($transform->{result}),
\t\t\trevisit => q($transform->{revisit}),    
\t\t},
EOT
        }
    }
    print $file <<EOT;
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
                    (?<!\\)   # Not preced by a single back slash
                    (?>\\\\)* # After we eat an even number of 0 or more backslashes
                    |
                    (?1)     # Recurse capture group 1
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
                        (?<!\\)   # Not preced by a single back slash
                        (?>\\\\)* # After we eat an even number of 0 or more backslashes
                        |
                        (?1)      # Recurse capture group 1
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

# vim:tabstop=4
