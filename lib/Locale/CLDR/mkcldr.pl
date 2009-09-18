#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use 5.010; # Nead at least this for full unicode regex's
use utf8;
use open OUT => ':utf8';
use lib '../..';

use XML::XPath;
use File::Spec;
use File::Path;
use File::Basename;
use Unicode::Regex::Parser;
use Locale::CLDR::Setup::Segmentations;
use Locale::CLDR::Setup::Transforms;

our $verbose = '';
if (grep /-v/, @ARGV) {
  $verbose = 1;
}

# Match version to CLDR version
our $VERSION = '1.6.1';

# Get the directories to parse
my @directories;
my $dir;
if (opendir($dir, 'Data')) {
  foreach my $file (readdir($dir)) {
    next unless -d File::Spec->catdir("Data",$file); # Skip none directories
    next if $file=~/^\./;                           # Skip hidden files
    # Testing
#    next unless $file =~/^main/;
    push @directories, File::Spec->catdir("Data",$file);
  }
}
else {
  die $!;
}

foreach my $directory (@directories) {
  my $dir;
  if(opendir($dir, $directory)) {
    foreach my $filename (readdir $dir) {
      my $fullname = File::Spec->catfile($directory,$filename);
      next unless -f $fullname;       # Skip anything that is not a regular file
      next if $filename=~/^\./;        # Skip hidden files
      next unless $filename=~/\.xml$/i; # Skip anything without an .xml extention
      process_file($fullname);
    }
  }
  else {
    warn "Unable to process directory $directory: $!, skipping\n";
  }
}

sub process_file {
  my $filename = shift;
  #testing
#  exit unless $filename eq 'Data/main/aa.xml';

  print STDERR "Processing $filename\n" if $verbose;
  
  my $xpath = XML::XPath->new(filename => $filename);
  process_data($filename, $xpath);
}

sub process_data {
  my ($filename, $xpath) = @_;
  my $data;
  $data->{file_name} = $filename;
  $data->{xpath}     = $xpath;
  (undef, $data->{_section_}) = File::Spec->splitdir($data->{file_name});
  bless $data,_get_class($data);
  $data->{version} = $VERSION;
  $data->create_file_path;
  $data->create_files;
}

sub _get_class {
  my $data = shift;
  return 'Locale::CLDR::Setup::Segmentations' if $data->{xpath}->exists('/ldml/segmentations');
  return 'Locale::CLDR::Setup::Transforms'    if $data->{xpath}->exists('/supplementalData/transforms');
  die "Unknown Class";
}

