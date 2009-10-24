#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use open IO => ':utf8';

use FindBin;
use File::Spec;
use XML::XPath; 
use XML::XPath::Node::Text;
use LWP::UserAgent;
use Archive::Extract;
use DateTime;

our $verbose = 0;
$verbose = 1 if grep /-v/, @ARGV;

our $VERSION = '1.7.1';

my $data_directory = File::Spec->catdir($FindBin::Bin, 'Data');
my $core_filename  = File::Spec->catfile($data_directory, 'core.zip');
my $base_directory = File::Spec->catdir($data_directory, 'common'); 
my $lib_directory  = File::Spec->catdir($FindBin::Bin, 
	'lib', 
	'Locale', 
	'CLDR'
);

# Check if we have a Data directory
if (! -d $data_directory ) {
	mkdir $data_directory
		or die "Can not create $data_directory: $!";
}

# Get the data file from the Unicode Consortium
if (! -e $core_filename ) {
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
	my $zip = Archive::Extract->new(archive => $core_filename);
	$zip->extract(to=>$data_directory)
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

my $cldrVersion = $sdf->findnodes('/supplementalData/cldrVersion')
	->get_node
	->getAttribute('version');

die "Incorrect CLDR Version found $cldrVersion. It should be $VERSION"
	unless $cldrVersion eq $VERSION;

say "Processing files"
	if $verbose;

# The en.xml file contains a list of all valid locale codes
# So we process them first
my $xml = XML::XPath->new(File::Spec->catfile($base_directory,
	'main',
	'en.xml',
));

open my $file, '>', 
		File::Spec->catfile($lib_directory, 'ValidCodes.pm');

process_header($file, 'Locale::CLDR::ValidCodes', $VERSION, $xml,
	File::Spec->catfile($base_directory, 'main', 'en.xml')
);

process_cp($xml);
process_valid_languages($file, $xml);
process_valid_scripts($file, $xml);
process_valid_territories($file, $xml);
process_footer($file);
close $file;

foreach my $file_name ( 'root.xml', 'en.xml') {
	$xml = XML::XPath->new(File::Spec->catfile($base_directory,
		'main',
		$file_name
	));

	my $output_file_name= $file_name;
	$output_file_name=~s/xml$/pm/;

	my $package = $output_file_name = ucfirst $output_file_name;
	$package =~s/\.pm$//;

	open $file,
		'>',
		File::Spec->catfile($lib_directory, $output_file_name);

	# Note: The order of these calls is important
	process_header($file, "Locale::CLDR::$package", $VERSION, $xml, 
		File::Spec->catfile($base_directory, 'main', $file_name)
	);

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

# Process the elements of the file note
sub process_header {
	my ($file, $class, $version, $xpath, $xml_name) = @_;
	say "Processing File $xml_name\nProcessing Header"
		if $verbose;

	$xml_name =~s/^.*(Data.*)$/$1/;
	my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');
	my $xml_generated = findnodes($xpath, '/ldml/identity/generation')
		->get_node
		->getAttribute('date');
	$xml_generated=~s/^\$Date: (.*) \$$/$1/;

	print $file <<EOT;
package $class;
# This file auto generated from $xml_name
# 	on $now GMT
# XML file generated $xml_generated

use Moose;

EOT
}

sub process_valid_languages {
	my ($file, $xpath) = @_;
	say "Processing Valid Languages"
		if $verbose;

	my $languages = findnodes($xpath,'/ldml/localeDisplayNames/languages/language');
	
	my @languages = $languages->get_nodelist;
	my %types;
	foreach my $language (@languages) {
		my $type = $language->getAttribute('type');
		$types{$type} = 1;
	}
	
	my @types = map {"\t\t'$_',\n"} sort keys %types;

	print $file <<EOT
has 'valid_languages' => (
	is			=> 'ro',
	isa			=> 'ArayRef',
	init_args	=> undef,
	auto_deref	=> 1,
	default => sub { [
@types
	] },
);

EOT
}

sub process_valid_scripts {
	my ($file, $xpath) = @_;

	say "Processing Valid Scripts"
		if $verbose;

	my $scripts = findnodes($xpath, '/ldml/localeDisplayNames/scripts/script');
	
	my @scripts = $scripts->get_nodelist;
	my %types;
	foreach my $script (@scripts) {
		my $type = $script->getAttribute('type');
		$types{$type} = 1;
	}
	
	my @types = map {"\t\t'$_',\n"} sort keys %types;

	print $file <<EOT
has 'valid_scripts' => (
	is			=> 'ro',
	isa			=> 'ArayRef',
	init_args	=> undef,
	auto_deref	=> 1,
	default => sub { [
@types
	] },
);

EOT
}

sub process_valid_territories {
	my ($file, $xpath) = @_;

	say "Processing Valid Territories"
		if $verbose;

	my $territories = findnodes($xpath, '/ldml/localeDisplayNames/territories/territory');
	
	my @territories = $territories->get_nodelist;
	my %types;
	foreach my $territory (@territories) {
		my $type = $territory->getAttribute('type');
		$types{$type} = 1;
	}
	
	my @types = map {"\t\t'$_',\n"} sort keys %types;

	print $file <<EOT
has 'valid_teritories' => (
	is			=> 'ro',
	isa			=> 'ArayRef',
	init_args	=> undef,
	auto_deref	=> 1,
	default => sub { [
@types
	] },
);

EOT
}

sub process_alias {
	my ($xpath, $path) = @_;
	my $origanal_path = $path;

	my $nodes;
	while (1) {
		$path=~s/\/[^\/]*$/\/alias/;
		$nodes = $xpath->findnodes($path);
		unless ($nodes->size) {
			if ($path=~s/\/[^\/]+\/alias$/\/alias/) {
				next;
			}
			else {
				return;
			}
		}
		# now replace the node
		my $new_path=$nodes->getAttribute('path');
		my $replace_me = $nodes->getParentNode;
		# Process local nodes
		if ($nodes->getAttribute('source') eq 'locale' ) {
			my @replacements = $xpath->findnodes("$new_path/*", $replace_me)
				->get_nodelist;
			foreach my $replacement (@replacements) {
				$replace_me->insertBefore($replacement,$nodes);
			}
			$replace_me->removeChild($nodes);
			return $xpath->findnodes($origanal_path);
		}
		else {
			die "Can't process remote aliases";
		}
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
	$fallback = $fallback ? $fallback->get_node->string_value : '';

	print $file <<EOT;
has 'fallback' => (
	is			=> 'ro',
	isa			=> 'ArrayRef[Str]',
	auto_deref	=> 1,
	init_args	=> undef,
	default		=> sub { [ qw( $fallback ) ] },
);

EOT
}

sub process_display_pattern {
	my ($file, $xpath) = @_;

	say "Processing Display Pattern"
		if $verbose;

	my $display_pattern = 
		findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localePattern');
	$display_pattern = defined $display_pattern ? $display_pattern->get_node->string_value : $display_pattern;
	
	my $display_seperator = 
		findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localeSeparator');
	$display_seperator = $display_seperator ? $display_seperator->get_node->string_value : '';
	
	return unless defined $display_pattern;
	foreach ($display_pattern, $display_seperator) {
		s/\//\/\//g;
		s/'/\\'/g;
	}
	
	print $file <<EOT;
sub display_name_pattern {
	my (\$self, \$name, \$territory, \$script, \$variant) = \@_;

	my \$display_pattern = '$display_pattern';
	\$display_pattern =~s/\\\{0\\\}/\$name/g;
	my \$subtags = join '$display_seperator', grep {defined} (
		\$territory,
		\$script,
		\$variant,
	);

	\$display_pattern =~s/\\\{1\\\}/\$subtags/g;
}

EOT
}

sub process_display_language {
	my ($file, $xpath) = @_;
	say "Processing Display Language"
		if $verbose;

	my $languages = findnodes($xpath,'/ldml/localeDisplayNames/languages/language');
	
	return unless $languages;
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
	is		=> 'ro',
	isa		=> 'HashRef[Str]',
	init_args	=> undef,
	default		=> sub { 
		{
@languages
		}
	},
);

EOT
}

sub process_display_script {
	my ($file, $xpath) = @_;

	say "Processing Display Script"
		if $verbose;

	my $scripts = findnodes($xpath, '/ldml/localeDisplayNames/scripts/script');
	
	return unless $scripts;
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
	is		=> 'ro',
	isa		=> 'HashRef[Str]',
	init_args	=> undef,
	default		=> sub { 
		{
@scripts
		}
	},
);

EOT
}

sub process_display_territory {
	my ($file, $xpath) = @_;

	say "Processing Display Territory"
		if $verbose;

	my $territories = findnodes($xpath, '/ldml/localeDisplayNames/territories/territory');
	
	return unless $territories;
	my @territories = $territories->get_nodelist;
	foreach my $territory (@territories) {
		my $type = $territory->getAttribute('type');
		my $variant = $territory->getAttribute('alt');
		if ($variant) {
			$type .= "\@alt=$variant";
		}
		my $name = $territory->getChildNode(1)->getValue;
		$name =~s/\\/\/\\/g;
		$name =~s/'/\\'/g;
		$territory = "\t\t\t'$type' => '$name',\n";
	}

	print $file <<EOT;
has 'display_name_territory' => (
	is		=> 'ro',
	isa		=> 'HashRef[Str]',
	init_args	=> undef,
	default		=> sub { 
		{
@territories
		}
	},
);

EOT
}

sub process_display_variant {
	my ($file, $xpath) = @_;

	say "Processing Display Variant"
		if $verbose;

	my $variants= findnodes($xpath, '/ldml/localeDisplayNames/variants/variant');
	
	return unless $variants;
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
	is		=> 'ro',
	isa		=> 'HashRef[Str]',
	init_args	=> undef,
	default		=> sub { 
		{
@variants
		}
	},
);

EOT
}

sub process_display_key {
	my ($file, $xpath) = @_;

	say "Processing Display Key"
		if $verbose;

	my $keys= findnodes($xpath, '/ldml/localeDisplayNames/keys/key');
	
	return unless $keys;
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
	is		=> 'ro',
	isa		=> 'HashRef[Str]',
	init_args	=> undef,
	default		=> sub { 
		{
@keys
		}
	},
);

EOT
}

sub process_display_type {
	my ($file, $xpath) = @_;

	say "Processing Display Type"
		if $verbose;

	my $types = findnodes($xpath, '/ldml/localeDisplayNames/types/type');
	return unless $types;

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
	is		=> 'ro',
	isa		=> 'HashRef[HashRef[Str]]',
	init_args	=> undef,
	default		=> sub {
		{
@types
		}
	},
);

EOT
}

sub process_display_measurement_system_name {
	my ($file, $xpath) = @_;

	say "Processing Display Mesurement System"
		if $verbose;

	my $names = findnodes($xpath, '/ldml/localeDisplayNames/measurementSystemNames/measurementSystemName');
	return unless $names;

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
	is		=> 'ro',
	isa		=> 'HashRef[Str]',
	init_args	=> undef,
	default		=> sub { 
		{
@names
		}
	},
);

EOT
}

sub process_code_patterns {
	my ($file, $xpath) = @_;
	say "Processing Display Mesurement System"
		if $verbose;

	my $patterns = findnodes($xpath, '/ldml/localeDisplayNames/codePatterns/codePattern');
	return unless $patterns;

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
	is		=> 'ro',
	isa		=> 'HashRef[Str]',
	init_args	=> undef,
	default		=> sub { 
		{
@patterns
		}
	},
);

EOT
}

sub process_footer {
	my $file = shift;

	say "Processing Footer"
		if $verbose;

	say $file 'no Moose;';
	say $file '1;';
}
