#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use open IO => ':utf8';

use FindBin;
use File::Spec;
use XML::XPath;
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

	process_header($file, "Locale::CLDR::$package", $VERSION, $xml, 
		File::Spec->catfile($base_directory, 'main', $file_name)
	);

	process_fallback($file, $xml);
	process_display_pattern($file, $xml);
	process_display_language($file, $xml);
	process_display_script($file, $xml);

	process_footer($file);

	close $file;
}

# Process the elements of the file
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
	my (\$self, \$name) = \@_;

	my \$lang_code = \$name->language;
	my \$display_pattern = '$display_pattern';
	\$display_pattern =~s/\\\{0\\\}/\$lang_code/g;
	my \$subtags = join '$display_seperator', grep {defined} (
		\$name->script,
		\$name->territory,
		\$name->variant,
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
		$name =~s/\//\/\//g;
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
		$name =~s/\//\/\//g;
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

sub process_footer {
	my $file = shift;

	say $file 'no Moose;';
	say $file '1;';
}
