#!/usr/bin/perl

use strict;
use warnings;

use CPAN::Uploader;
use FindBin;
use File::Spec;

die "This code is incomplete. Do NOT use";

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
	
	my $upload_from = File::Spec->catdir($distributions_directory, $directory);
	opendir( my $dir, $upload_from );
	my ( $file_name ) = grep { /^Locale-CLDR/} readdir $dir;
	closedir $dir;
	
	$uploader->upload_file(File::Spec->catfile($upload_from, $file_name));
	
	sleep $directory eq 'Base' ? 600 : 10; 
	# Sleep for 10 minutes after uploading the Base package and 10 seconds after each of the other packages to give PAUSE time to process each package
}

# Do bundles
my $bundles_directory = File::Spec->catdir($distributions_directory, 'Bundles');

#Sort out Bundle order by processing Bundle::Locale::CLDR::Everything down the bundle hierarchy until we run out of Bundles
