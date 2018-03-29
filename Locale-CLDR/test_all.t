#!/usr/bin/perl
use TAP::Parser::Aggregator;
use TAP::Harness;
use File::Spec;
use FindBin;

my $aggregator = TAP::Parser::Aggregator->new();
my $harness = TAP::Harness->new();

$aggregator->start;

my $distributions_directory   = File::Spec->catdir($FindBin::Bin, 'Distributions');

opendir(my $dir, $distributions_directory);

my @Distributions = grep { -d File::Spec->catdir($distributions_directory,$_) } sort grep { ! /^\./ } readdir $dir;

closedir($dir);

foreach my $distribution (@Distributions) {

	next if $distribution eq 'Bundles';

	chdir File::Spec->catdir($distributions_directory, $distribution);
	
	opendir my $test_dir, File::Spec->catdir($distributions_directory, $distribution, 't');
	my @tests = 
		map { File::Spec->catfile($distributions_directory, $distribution, 't', $_) } 
		grep { -f File::Spec->catfile($distributions_directory, $distribution, 't', $_) } 
		sort readdir $test_dir;
	close $test_dir;
	
	$harness->lib(
		[ map { "-I$_" } (
			File::Spec->catdir($distributions_directory, $distribution, 'lib'),
			File::Spec->catdir($distributions_directory, 'Base', 'lib')
			)
		]
	);
	
	$harness->aggregate_tests($aggregator, @tests);
}

$aggregator->stop;

$harness->summary($aggregator);