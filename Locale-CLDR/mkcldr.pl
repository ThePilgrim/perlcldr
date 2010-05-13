#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use open IO => ':utf8';

use FindBin;
use File::Spec;
use File::Path qw(make_path);
use XML::XPath; 
use XML::XPath::Node::Text;
use LWP::UserAgent;
use Archive::Extract;
use DateTime;

our $verbose = 0;
$verbose = 1 if grep /-v/, @ARGV;

use version;
our $VERSION = version->parse('1.8.0');

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
		agent => "perl Local::CLDR/$VERSION (Written by john.imrie\@vodafoneemail.co.uk)",
	);
	my $response = $ua->get("http://unicode.org/Public/cldr/$VERSION/core.zip",
		':content_file' => $core_filename
	);

	if (! $response->is_success) {
		die "Can not access http://unicode.org/Public/cldr/$VERSION/core.zip' "
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
directory. Is this version $VERSION of the Unicode core.zip file?
EOM

	unless -d File::Spec->catdir($base_directory);

# We look at the supplemental data file to get the cldr version number
my $sdf = XML::XPath->new(File::Spec->catfile($base_directory, 
	'supplemental',
	'supplementalData.xml'));

say "Checking CLDR version" if $verbose;
my $cldrVersion = $sdf->findnodes('/supplementalData/version')
	->get_node
	->getAttribute('cldrVersion');

die "Incorrect CLDR Version found $cldrVersion. It should be $VERSION"
	unless version->parse("$cldrVersion.0") == $VERSION;

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
process_header($file, 'Locale::CLDR::ValidCodes', $VERSION, $xml, $file_name, 1);
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

my $main_directory = File::Spec->catdir($base_directory, 'main');
opendir ( my $dir, $main_directory);
# Count the number of files
my $num_files = grep { -f File::Spec->catfile($main_directory,$_)} readdir $dir;
my $count_files = 0;
rewinddir $dir;

foreach my $file_name (grep /^[^.]/, readdir($dir)) {
	$xml = XML::XPath->new(File::Spec->catfile($main_directory, $file_name));

	my @output_file_parts = output_file_name($xml);

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
	process_header($file, "Locale::CLDR::$package", $VERSION, $xml, $file_name);
	process_cp($xml);
	process_fallback($file, $xml);
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
	process_footer($file);

	close $file;
}

# This sub looks for nodes along an xpath. If it can't find
# any it starts looking for alias nodes
sub findnodes {
	my ($xpath, $path ) = @_;
	my $nodes = $xpath->findnodes($path);
	return $nodes if $nodes->size;
	return process_alias($xpath, $path);
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

	# Strip of Any's from end of list
	pop @nodes while $nodes[-1] eq 'Any';

	return map {ucfirst lc} @nodes;
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

	print $file <<EOT;
package $class;
# This file auto generated from $xml_name
#\ton $now GMT
# XML file generated $xml_generated

use Moose$isRole;

EOT
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
\tdefault\t=> sub {[qw(
@languages
\t)]},
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
\tdefault\t=> sub {[qw(
@scripts
\t)]},
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
\tdefault\t=> sub {[qw(
@territories
\t)]},
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
\tdefault\t=> sub {[qw(
@variants
\t)]},
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
\tdefault\t=> sub {[qw(
@currencies
\t)]},
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
		grep /\.xml \z/xms, 
		readdir $dir;

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
		print $file "\t'$from' => '$to',\n";
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

sub process_alias {
	my ($xpath, $path) = @_;
	my $origanal_path = $path;

	my $nodes;
	while (1) {
		# check if we have dropped back into the pre alias part of the path
		my $test = $xpath->findnodes($path);
		return $xpath->findnodes($origanal_path) if $test->size;

		$path=~s/\/[^\/]*$/\/alias/;
		$nodes = $xpath->findnodes($path);
		unless ($nodes->size) {
			if ($path=~s/\/[^\/]+\/alias$/\/alias/) {
				next;
			}
			else {
				return $nodes;
			}
		}
		# now replace the node
		my $node = $nodes->get_node;
		my $new_path=$node->getAttribute('path');
		my $parent = $node->getParentNode;
		# Process local nodes
		if ($node->getAttribute('source') eq 'locale' ) {
			my @replacements = $xpath->findnodes("$new_path/*", $node)
				->get_nodelist;
			foreach my $replacement (@replacements) {
				$parent->insertBefore($replacement,$node);
			}
			$parent->removeChild($node);
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
				$parent->insertBefore($replacement, $node);
			}
			$parent->removeChild($node);
		}

		return $xpath->findnodes($origanal_path);
	}
}

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
	my ($file, $xpath) = @_;

	say "Processing Fallback"
		if $verbose;

	my $fallback = findnodes($xpath, '/ldml/fallback');
	$fallback = $fallback->size ? $fallback->get_node->string_value : '';

	print $file <<EOT;
has 'fallback' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> 'ArrayRef[Str]',
\tauto_deref\t=> 1,
\tinit_arg\t=> undef,
\tdefault\t\t=> sub { [ qw( $fallback ) ] },
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
		my $name = $language->getChildNode(1)->getValue;
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
			push @types, "\t\t\t\t'$type' => '$values{$key}{$type}',\n";
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
		$name = "\t\t\t'$type' => '$value',\n";
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
