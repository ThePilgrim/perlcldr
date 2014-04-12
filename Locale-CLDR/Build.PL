use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Locale::CLDR',
    license             => 'perl',
    requires        => {
        'version'                   => '0.95',
        'DateTime'                  => '0.72',
        'Moose'                     => '2.0401',
        'MooseX::ClassAttribute'    => '0.26',
        'XML::Parser'               => '2.41',
        'XML::XPath'                => '1.13',
    },
    dist_author         => q{John Imrie <john.imrie1@gmail.com>},
    dist_version_from   => 'lib/Locale/CLDR.pm',
    build_requires => {
        'Archive::Extract'  => '0.58',
        'Archive::Zip'      => '1.30',
        'File::Spec'        => '3.33',
        'FindBin'           => '1.50',
        'LWP'               => '6.03',
        'Test::More'        => '0.98',
		'ok'				=> '0.11',
    },
    add_to_cleanup      => [ 'Locale-CLDR-*' ],
	configure_requires => { 'Module::Build' => '0.40' },
    create_makefile_pl => 'traditional',
	release_status => 'stable',
);

$builder->create_build_script();
