#!/usr/bin/perl

use 5.014;
use encoding 'utf8';
use strict;
use warnings 'FATAL';
use feature 'unicode_strings';

use open ':encoding(utf8)', ':std';
use FindBin;
use File::Spec;
use File::Path qw(make_path);
use XML::XPath; 
use XML::XPath::Node::Text;
use LWP::UserAgent;
use Archive::Extract;
use POSIX qw(strftime);

use Unicode::Set qw(unicode_to_perl);

our $verbose = 0;
$verbose = 1 if grep /-v/, @ARGV;
@ARGV = grep !/-v/, @ARGV;

use version;
our $VERSION = version->parse('0.1');
my $CLDR_VERSION = version->parse('2.0.1');

my $data_directory = File::Spec->catdir($FindBin::Bin, 'Data');
my $core_filename  = File::Spec->catfile($data_directory, 'core.zip');
my $base_directory = File::Spec->catdir($data_directory, 'common'); 
my $lib_directory  = File::Spec->catdir($FindBin::Bin, 'lib', 'Locale', 'CLDR');

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
        agent => "perl Locale::CLDR/$VERSION (Written by j.imrie1\@virginmedia.com)",
    );
    my $response = $ua->get("http://unicode.org/Public/cldr/$CLDR_VERSION/core.zip",
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
my $vf = XML::XPath->new(File::Spec->catfile($base_directory, 
    'main',
    'root.xml'));

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
my $xml = XML::XPath->new(File::Spec->catfile($base_directory,
    'supplemental',
    'supplementalMetadata.xml',
));

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
process_valid_currencies($file, $xml);
process_valid_keys($file, $base_directory);
process_valid_language_aliases($file,$xml);
process_valid_territory_aliases($file,$xml);
process_valid_variant_aliases($file,$xml);
process_footer($file, 1);
close $file;

# File for era boundries
$xml = XML::XPath->new(File::Spec->catfile($base_directory,
    'supplemental',
    'supplementalData.xml',
));

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

# Main directory
my $main_directory = File::Spec->catdir($base_directory, 'main');
opendir ( my $dir, $main_directory);

# Count the number of files
my $num_files = grep { -f File::Spec->catfile($main_directory,$_)} readdir $dir;
my $count_files = 0;
rewinddir $dir;

my $segmentation_directory = File::Spec->catdir($base_directory, 'segments');
foreach my $file_name ( sort grep /^[^.]/, readdir($dir)) {
    if (@ARGV) {
        next unless grep {$file_name eq $_} @ARGV;
    }
    $xml = XML::XPath->new(File::Spec->catfile($main_directory, $file_name));

    my $segment_xml = undef;
    if (-f File::Spec->catfile($segmentation_directory, $file_name)) {
        $segment_xml = XML::XPath->new( File::Spec->catfile($segmentation_directory, $file_name));
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

    $file_name = File::Spec->catfile($base_directory, 'main', $file_name);
    my $percent = ++$count_files / $num_files * 100;
    say sprintf("Processing File %s: %.2f%% done", $file_name, $percent) if $verbose;

    # Note: The order of these calls is important
    process_class_any($lib_directory, @output_file_parts[0 .. $#output_file_parts -1]);

    process_header($file, "Locale::CLDR::$package", $CLDR_VERSION, $xml, $file_name);
    process_segments($file, $segment_xml) if $segment_xml;
	process_alias($xml);
    process_cp($xml);
    process_fallback($file, $xml, "Locale::CLDR::$package");
    process_display_pattern($file, $xml);
    process_display_language($file, $xml);
    process_display_script($file, $xml);
    process_display_territory($file, $xml);
    process_display_variant($file, $xml);
    process_display_key($file, $xml);
    process_display_type($file,$xml);
    process_display_measurement_system_name($file, $xml);
    process_code_patterns($file, $xml);
    process_orientation($file, $xml);
    process_in_list($file, $xml);
    process_in_text($file, $xml);
#    process_exemplar_characters($file, $xml);
    process_ellipsis($file, $xml);
    process_more_information($file, $xml);
    process_delimiters($file, $xml);
    process_calendars($file, $xml, $current_locale);
    process_footer($file);

    close $file;
}

# This sub looks for nodes along an xpath. If it can't find
# any it starts looking for alias nodes
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

        my $now = strftime('%a %e %b %l:%M:%S %P', gmtime);
        open my $file, '>:utf8', "$lib_path.pm";
        print $file <<EOT;
package $package;
# This file auto generated
#\ton $now GMT

use 5.014;
use encoding 'utf8';
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
    my $now = strftime('%a %e %b %l:%M:%S %P', gmtime);
    my $xml_generated = ( findnodes($xpath, '/ldml/identity/generation')
        || findnodes($xpath, '/supplementalData/generation')
    )->get_node->getAttribute('date');

    $xml_generated=~s/^\$Date: (.*) \$$/$1/;

    my $header = <<EOT;
package $class;
# This file auto generated from $xml_name
#\ton $now GMT
# XML file generated $xml_generated

use 5.014;
use encoding 'utf8';
use feature 'unicode_strings';
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
        my $xml = XML::XPath->new($file_name);
        my $key = findnodes($xml, '/ldmlBCP47/keyword/key')->get_node;
        my ($name, $alias) = ($key->getAttribute('name'), $key->getAttribute('alias'));
        $keys{$name}{alias} = $alias;
        my @types = findnodes($xml,'/ldmlBCP47/keyword/key/type')->get_nodelist;
        foreach my $type (@types) {
            push @{$keys{$name}{type}}, $type->getAttribute('name');
            push @{$keys{$name}{type}}, $type->getAttribute('alias')
                if length $type->getAttribute('alias');
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
        my @types = @{$keys{$key}{type}};
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
        print $file "\t'$from' => '$to',\n";
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
        print $file "\t'$from' => [qw($to)],\n";
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
\ttraits\t\t=> ['Code'],
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'CodeRef',
\tinit_arg\t=> undef,
\thandles\t\t=> { call => 'execute_method' },
\tdefault\t\t=> sub { sub {
\t\tmy (\$self, \$type, \$date) = \@_;
\t\t# \$date in yyyymmdd format
\t\tmy \$return = -1;
\t\tgiven(\$type) {
EOT
	foreach my $calendar ($calendars->get_nodelist) {
		my $type = $calendar->getAttribute('type');
		print $file "\t\t\twhen('$type') {\n";
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
				print $file "\t\t\t\t\$return = $type if \$date >= $start;\n";
			}
			if (length $end) {
				my ($y, $m, $d) = split /-/, $end;
				$m //= '0';
				$d //= '0';
				$end = sprintf('%d%0.2d%0.2d',$y,$m,$d);
				print $file "\t\t\t\t\$return = $type if \$date <= $end;\n";
			}
		}
		print $file "\t\t\t}\n";
	}
	print $file <<EOT;
\t\t} return \$return; }
\t}
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
		my ($ordering) = split / /, $node->getAttribute('ordering');
		foreach my $territory (@territories) {
			say $file "\t\t$territory => '$ordering',";
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
        print $file "\t'$from' => '$to',\n";
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

	my $alias_nodes = $xpath->findnodes('.//alias',($recursed || ()));
	return unless $alias_nodes->size;

    # now replace the node
	foreach my $node ($alias_nodes->get_nodelist) {
        my $new_path=$node->getAttribute('path');
        my $parent = $node->getParentNode;
		
		# Check if we have allready replaced this node.
		# It wont have a parent if we have
		next unless $parent;

        # Process locale nodes
        if ($node->getAttribute('source') eq 'locale' ) {
			my $replacing_with_types
				= $xpath->findnodes("$new_path", $parent)
					->get_nodelist
					> 1;

			if (! $replacing_with_types) {
            	my @replacements = $xpath->findnodes("$new_path/*", $parent)
                	->get_nodelist;
            	foreach my $replacement (@replacements) {
					process_alias($xpath,$replacement);
	               	$parent->insertBefore($replacement,$node);
            	}
            	$parent->removeChild($node);
			}
			else {
				my $grandparent = $parent->getParentNode;
            	my @replacements = $xpath->findnodes($new_path, $parent)
                	->get_nodelist;
            	foreach my $replacement (@replacements) {
					process_alias($xpath,$replacement);
	               	$grandparent->insertBefore($replacement,$parent);
            	}
            	$grandparent->removeChild($parent);
			}
        }
        else {
            my $filename = File::Spec->catfile(
                $base_directory,
                'main',
                $node->getAttribute('source')
            );

            $filename .= '.xml';
            my $new_xpath = XML::XPath->new($filename);
            my @replacements = $new_xpath->findnodes("$new_path/*")
                ->get_nodelist;
            foreach my $replacement (@replacements) {
				process_alias($new_xpath,$replacement);
                $parent->insertBefore($replacement, $node);
            }
            $parent->removeChild($node);
        }
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

sub process_fallback {
    my ($file, $xpath, $package) = @_;

    say "Processing Fallback"
        if $verbose;

    if ($package eq 'Locale::CLDR::Root') {
        $package = '';
    }
    else {
        $package =~ s{ :: [^:]+ \z }{}msx;
        $package = 'Locale::CLDR::Root' if $package eq 'Locale::CLDR';
    }


    my $fallback = findnodes($xpath, '/ldml/fallback');
    $fallback = $fallback->size ? $fallback->get_node->string_value : '';
    my @package;
    foreach my $value (split / +/, $fallback) {
        my @fallback = split /[-_]/, $value;

        # Check for no script in name
        if (2 == @fallback && length $fallback[1] < 4) {
            @fallback = ($fallback[0], 'Any', $fallback[1]);
        }

        push @package, join '::', map { ucfirst lc } @fallback;
    }

    if (@package) {
        $fallback = join "', '",
            $package eq 'Locale::CLDR::Root'
                ? ()
                : $package
            , map { "Locale::CLDR::$_" } @package;
    }
    else {
        $fallback = $package;
    }

    say $file "extends('$fallback');\n"
        if $fallback;
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

    return unless defined $display_pattern;
    foreach ($display_pattern, $display_seperator) {
        s/\//\/\//g;
        s/'/\\'/g;
    }

    print $file <<EOT;
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
        $language = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display_name_language' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@languages
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
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { 
\t\t{
@scripts
\t\t}
\t},
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
    my $orientation = findnodes($xpath, '/ldml/layout/orientation');
    return unless $orientation->size;

    my $node = $orientation->get_node;
    my $lines = $node->getAttribute('lines') || 'top-to-bottom';
    my $characters = $node->getAttribute('characters') || 'left-to-right';

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

sub process_in_list {
    my ($file, $xpath) = @_;

    say "Processing inList" if $verbose;
    my $in_list= findnodes($xpath, '/ldml/layout/inList');
    return unless $in_list->size;

    my $node = $in_list->get_node;
    my $casing = $node->getChildNode(1)->getValue;

    print $file <<EOT;
has 'in_list' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'Str',
\tinit_arg\t=> undef,
\tdefault\t\t=> '$casing',
);

EOT
}

sub process_in_text {
    my ($file, $xpath) = @_;

    say "Processing inText" if $verbose;
    my $in_text= findnodes($xpath, '/ldml/layout/inText');
    return unless $in_text->size;

    my @inText = $in_text->get_nodelist;
    foreach my $node (@inText) {
        my $casing = $node->getChildNode(1)->getValue;
        my $type = $node->getAttribute('type');
        $node = "\t\t\t\t\t$type => '$casing',\n";
    }

    my $value = 
    print $file <<EOT;
has 'in_text' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'HashRef[Str]',
\tinit_arg\t=> undef,
\tdefault\t\t=> sub {
\t return {
@inText
\t\t};
\t},
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

    say "Processing ellipsis" if $verbose;
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
		my $months = process_months($xpath, $type);
        $calendars{months}{$type} = $months if $months;
		my $days = process_days($xpath, $type);
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
\t\tgiven (\$type) {
EOT
		foreach my $ctype (keys  %{$calendars{day_period_data}}) {
			say $file "\t\t\twhen ('$ctype') {";
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

	my $months_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext));
	return 0 unless $months_nodes->size;

	my %months;
	my $default_context = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/default));
	if ($default_context->size) {
		my $default_node = ($default_context->get_nodelist)[0];
		my $choice = $default_node->getAttribute('choice');
		$months{default} = $choice;
	}

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
			my $width_type = $width_node->getAttribute('type');
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
	return \%months;
}

#/ldml/dates/calendars/calendar/days/
sub process_days {
    my ($xpath, $type) = @_;

	say "Processing Days ($type)" if $verbose;

	my $days_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext));
	return 0 unless $days_nodes->size;

	my %days;

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
	return \%days;
}

#/ldml/dates/calendars/calendar/quaters/
sub process_quarters {
    my ($xpath, $type) = @_;

	say "Processing Quarters ($type)" if $verbose;

	my $quarters_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext));
	return 0 unless $quarters_nodes->size;

	my %quarters;
	foreach my $context_node ($quarters_nodes->get_nodelist) {
		my $context_type = $context_node->getAttribute('type');
		my $width = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context_type"]/quarterWidth));
		foreach my $width_node ($width->get_nodelist) {
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
			my $xml = XML::XPath->new(File::Spec->catfile($base_directory,
    			'supplemental',
    			'dayPeriods.xml',
			));
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

	my $dayPeriods_nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext));
	return 0 unless $dayPeriods_nodes->size;

	my %dayPeriods;
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

sub process_footer {
    my $file = shift;
    my $isRole = shift;
    $isRole = $isRole ? '::Role' : '';

    say "Processing Footer"
        if $verbose;

    say $file "no Moose$isRole;";
    say $file '__PACKAGE__->meta->make_immutable;' unless $isRole;
    say $file '1;';
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

            print $file "\t\t'", $variable->getAttribute('id'), "' => ", $value, ",\n";
        }

        print $file "\t]}\n);\n\n";

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
            print $file "\t\t'", $rule->getAttribute('id'), "' => ", $value, ",\n";
        }

        print $file "\t}}\n);\n\n";
    }    
}
