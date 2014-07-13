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
        'perl'                      => '5.10.0',
    },
    dist_author         => q{John Imrie <john.imrie1@gmail.com>},
    dist_version_from   => 'lib/Locale/CLDR.pm',
    build_requires => {
        'ok'                => 0,
        'Archive::Extract'  => '0.58',
        'Archive::Zip'      => '1.30',
        'File::Spec'        => '3.33',
        'FindBin'           => '1.49',
        'LWP'               => '6.03',
        'Test::Exception'   => 0,
        'Test::More'        => '0.98',
    },
    add_to_cleanup      => [ 'Locale-CLDR-*' ],
	configure_requires => { 'Module::Build' => '0.40' },
    create_makefile_pl => 'traditional',
	release_status => 'unstable',
);

$builder->create_build_script();
