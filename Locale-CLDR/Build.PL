use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Locale::CLDR',
    license             => 'perl',
    requires		=> {
		'DateTime'					=> '0.70',
	    'Moose'						=> '2.0010',
		'MooseX::ClassAttribute'	=> '0.24',
		'Readonly'          		=> '1.03',
		'Regexp::Grammas'			=> '1.012',
		'XML::Parser'				=> '2.41',
		'XML::XPath'				=> '1.13',
		'version'       			=> '0.91',
    },
    dist_author         => q{John Imrie <j.imrie1@.virginmedia.com>},
    dist_version_from   => 'lib/Locale/CLDR.pm',
    build_requires => {
		'Archive::Extract'	=> '0.52',
		'Archive::Zip'		=> '1.30',
		'File::Spec'		=> '3.33',
		'FindBin'			=> '1.50',
		'LWP'				=> '5.808',
        'Test::More'		=> '0',
    },
    add_to_cleanup      => [ 'Locale-CLDR-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
