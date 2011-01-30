use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Locale::CLDR',
    license             => 'perl',
    requires		=> {
	    'Moose'				=> '0.85',
		'XML::XPath'		=> '1.13',
		'version'       	=> '0.74',
		'Regexp::Grammars'	=> '1.002',
		'Readonly'		=> '1.03',
    },
    dist_author         => q{John Imrie <john.imrie@vodafoneemail.co.uk>},
    dist_version_from   => 'lib/Locale/CLDR.pm',
    build_requires => {
        'Test::More'		=> 0,
		'File::Spec'		=> 0,
		'FindBin'			=> 0,
		'LWP'				=> '5.808',
		'Archive::Extract'	=> 0.243,
		'Archive::Zip'		=> 0,
		'DateTime'			=> 0.47
    },
    add_to_cleanup      => [ 'Locale-CLDR-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
