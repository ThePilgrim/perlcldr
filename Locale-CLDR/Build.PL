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
        'Readonly'                  => '1.03',
        'XML::Parser'               => '2.41',
        'XML::XPath'                => '1.13',
    },
    dist_author         => q{John Imrie <j.imrie1@.virginmedia.com>},
    dist_version_from   => 'lib/Locale/CLDR.pm',
    build_requires => {
        'Archive::Extract'  => '0.58',
        'Archive::Zip'      => '1.30',
        'File::Spec'        => '3.33',
        'FindBin'           => '1.50',
        'LWP'               => '6.03',
        'Test::More'        => '0.98',
    },
    add_to_cleanup      => [ 'Locale-CLDR-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
