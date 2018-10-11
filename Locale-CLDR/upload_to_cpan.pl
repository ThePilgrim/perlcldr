#!/usr/bin/perl

use strict;
use warnings;

use CPAN::Uploader;
use FindBin;
use File::Spec;
use List::Util qw( uniq );

my $last = shift;

die "Config file upload_config.txt not found\n"
    unless -f './upload_config.txt';

my $config = CPAN::Uploader->read_config_file('./upload_config.txt');

my $uploader = CPAN::Uploader->new($config);

my $distributions_directory   = File::Spec->catdir($FindBin::Bin, 'Distributions');

opendir(my $dir, $distributions_directory);

my @directories = grep { -d File::Spec->catdir($distributions_directory,$_) } sort readdir $dir;

closedir($dir);

# Do distributions, sort Base to be the first distribution uploaded
foreach my $directory ( sort { $a eq 'Base' ? -1 : $b eq 'Base' ? 1 : $a cmp $b } @directories ) {
	# Skip bundles until all distributions uploaded
	next if ($directory eq 'Bundles');
	next if $directory =~ /^\./;
	
	if ($last) {
		next unless $last eq $directory;
		$last = '';
	}
	
	my $upload_from = File::Spec->catdir($distributions_directory, $directory);
	opendir( my $dir, $upload_from );
	my ( $file_name ) = grep { /^Locale-CLDR/} readdir $dir;
	closedir $dir;
	
	print "Uploading ", File::Spec->catfile($upload_from, $file_name), "\n";
	
	{
		eval {
			$uploader->upload_file(File::Spec->catfile($upload_from, $file_name));
		};
		last unless $@;
		print "$@\n";
		sleep 300;
		redo;
	}
	
	sleep( ( $directory eq 'Base' ) ? 600 : 60 ); 
	# Sleep for 10 minutes after uploading the Base package and 1 minute after each of the other packages to give PAUSE time to process each package
}

# Do bundles
my $bundles_directory = File::Spec->catdir($distributions_directory, 'Bundles');

#Sort out Bundle order by processing Bundle::Locale::CLDR::Everything down the bundle hierarchy until we run out of Bundles
my @bundle_distributions = (reverse( uniq parse_bundle( 'Everything' )), 'Everything');

foreach my $bundle (@bundle_distributions) {
	my $upload_from = File::Spec->catdir($bundles_directory, $bundle);
	opendir( my $dir, $upload_from );
	my ( $file_name ) = grep { /^Bundle-Locale-CLDR/} readdir $dir;
	closedir $dir;
	
	{
		eval {
			$uploader->upload_file(File::Spec->catfile($upload_from, $file_name));
		};
		last unless $@;
		print "$@\n";
		sleep 300;
		redo;
	}
	
	print "Uploading ", File::Spec->catfile($upload_from, $file_name), "\n";
	
	sleep 60; 
}

sub parse_bundle {
	my $bundle = shift;
	my @distributions = ();
	
	my $bundle_file = File::Spec->catfile($bundles_directory, $bundle, 'lib', 'Bundle', 'Locale', 'CLDR', "${bundle}.pm");
	
	open my $file, '<', $bundle_file;
	my @lines = <$file>;
	close $file;
	
	foreach my $line (@lines) {
		next unless $line =~ /^Bundle::/;
		my ($new_bundle) = (split / /, $line =~ s/^Bundle::Locale::CLDR:://r )[0];
		push @distributions, $new_bundle;
		push @distributions, parse_bundle($new_bundle);
	}
	
	return @distributions;
}
