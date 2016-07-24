use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'HTTP::Caching',
    AUTHOR           => q{Theo van Hoesel <Th.J.v.Hoesel@THEMA-MEDIA.nl>},
    VERSION_FROM     => 'lib/HTTP/Caching.pm',
    ABSTRACT_FROM    => 'lib/HTTP/Caching.pm',
    LICENSE          => 'artistic_2',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker'           => 0,
    },
    BUILD_REQUIRES => {
        'Test::Most'                    => 0,
        'HTTP::Request'                 => 0,
        'HTTP::Response'                => 0,
        'Readonly'                      => 0,
    },
    PREREQ_PM => {
        'CHI'                           => 0,
        'Carp'                          => 0,
        'Digest::MD5'                   => 0,
        'Time::HiRes'                   => 0,
        'Moo'                           => 0,
        'MooX::Types::MooseLike::Base'  => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'HTTP-Caching-*' },
);
