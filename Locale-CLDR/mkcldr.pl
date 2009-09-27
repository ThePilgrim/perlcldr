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
We successfully unzipped the core.zip file but don't have a 'common' 
directory. Is this a version $VERSION Unicode core.zip file
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

say "Processing files";

# Process main files

foreach my $file_name ( 'root.xml', 'en.xml') {
	my $xml = XML::XPath->new(File::Spec->catfile($base_directory,
		'main',
		$file_name
	));

	my $output_file_name= $file_name;
	$output_file_name=~s/xml$/pm/;

	my $package = $output_file_name = ucfirst $output_file_name;
	$package =~s/\.pm$//;

	open my $file, '>', File::Spec->catfile($lib_directory, $output_file_name);

	# Note: The order of these calls is important
	process_header($file, "Locale::CLDR::$package", $VERSION, $xml, 
		File::Spec->catfile($base_directory, 'main', $file_name)
	);

	process_alias($file, $xml);
	process_cp($file, $xml);
	process_fallback($file, $xml);
	process_display_pattern($file, $xml);
	process_display_language($file, $xml);
	process_display_script($file, $xml);
	process_display_territory($file, $xml);
	process_display_variant($file, $xml);
	process_display_key($file, $xml);
	process_display_type($file,$xml);
	process_footer($file);

	close $file;
}

# Process the elements of the file note
sub process_header {
	my ($file, $class, $version, $xpath, $xml_name) = @_;
	$xml_name =~s/^.*(Data.*)$/$1/;
	my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');
	my $xml_generated = $xpath->findnodes('/ldml/identity/generation')
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

sub process_alias {
	my ($file, $xpath) = @_;

	# find all the alias nodes
	while ( my @alias = $xpath->findnodes('//alias')->get_nodelist) {

		# now replace the deepest node
		my ($alias, $depth) = ('',0);
		foreach my $test (@alias) {
			if ( (my $current_depth = $xpath
				->find('count(ancestor-or-self::*)', $test)
				->value) > $depth) {
				$depth = $current_depth;
				$alias = $test;
			}
		}
		my $path=$alias->getAttribute('path');
		my $replace_me = $alias->getParentNode;
		# Process local nodes
		if ($alias->getAttribute('source') eq 'locale' ) {
			my @replacements = $xpath->findnodes("$path/*", $replace_me)
				->get_nodelist;
			foreach my $replacement (@replacements) {
				$replace_me->insertBefore($replacement,$alias);
			}
			$replace_me->removeChild($alias);
		}
		else {
			die "Can't process none local aliases";
		}
	}
}

sub process_cp {
	my ($file, $xpath) = @_;
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
	my $fallback = $xpath->getNodeText('/ldml/fallback') // '';

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
	my $display_pattern = $xpath
		->getNodeText('/ldml/localeDisplayNames/localeDisplayPattern/localePattern');
	
	my $display_seperator = $xpath
		->getNodeText('/ldml/localeDisplayNames/localeDisplayPattern/localeSeparator');
	
	return unless defined $display_pattern;
	foreach ($display_pattern, $display_seperator) {
		s/\//\/\//g;
		s/'/\\'/g;
	}
	
	print $file <<EOT;
sub displayNamePattern {
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
	my @languages = $xpath
		->findnodes('/ldml/localeDisplayNames/languages/language');
	
	return unless @languages;
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
has 'displayNameLanguage' => (
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
	my @scripts = $xpath
		->findnodes('/ldml/localeDisplayNames/scripts/script');
	
	return unless @scripts;
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
has 'displayNameScript' => (
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
	my @territories = $xpath
		->findnodes('/ldml/localeDisplayNames/territories/territory');
	
	return unless @territories;
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
has 'displayNameTerritory' => (
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
	my @variants= $xpath
		->findnodes('/ldml/localeDisplayNames/variants/variant');
	
	return unless @variants;
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
has 'displayNameVariant' => (
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
	my @keys= $xpath
		->findnodes('/ldml/localeDisplayNames/keys/key');
	
	return unless @keys;
	foreach my $key (@keys) {
		my $type = $key->getAttribute('type');
		my $name = $key->getChildNode(1)->getValue;
		$name =~s/\\/\\\\/g;
		$name =~s/'/\\'/g;
	}

	print $file 
	
	<<EOT;
has 'displayNameKey' => (
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
}

sub process_footer {
	my $file = shift;

	say $file 'no Moose;';
	say $file '1;';
}
