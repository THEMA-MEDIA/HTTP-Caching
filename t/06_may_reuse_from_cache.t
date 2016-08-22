use Test::Most tests => 3;

use HTTP::Caching;

$HTTP::Caching::DEBUG = 1; # so we get nice helpful messages back

use HTTP::Method;
use HTTP::Request;
use HTTP::Response;

# minimal HTTP::Messages
# - Request: HEAD
#   Method is understood,
#   Method is safe
#   Method is cachable
# - Response: 100 Continue
#   Status Code is understood
#   Status Code is not be default cachable
#   Will fall through
my $rqst_minimal = HTTP::Request->new('HEAD', 'http://localhost/');
my $resp_minimal = HTTP::Response->new(100);

subtest "matching URI's" => sub {
    
    plan tests => 6;
    
    my $test;
    
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    
    my $rqst_identical  = $rqst_minimal->clone;
    my $resp_stored     = $resp_minimal->clone;
    my $rqst_associated = $rqst_minimal->clone;
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_identical,
            $resp_stored,
            $rqst_associated
        )
    }
        { carped => "" },
        "URI's are identical";
    ok ( ( not defined $test ),
        "... and falls through" );
    
    my $rqst_normalized = $rqst_minimal->clone;
    $rqst_normalized->uri('http://LOCALHOST:80/');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_normalized,
            $resp_stored,
            $rqst_associated
        )
    }
        { carped => "" },
        "URI's do match";
    ok ( ( not defined $test ),
        "... and falls through" );
    
    
    my $rqst_different = $rqst_minimal->clone;
    $rqst_different->uri('http://localhost:8080/');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_different,
            $resp_stored,
            $rqst_associated
        )
    }
        { carped => qr/NO REUSE: URI's do not match/ },
        "NO REUSE: URI's do not match";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
};


subtest "matching Request Methods" => sub {
    
    plan tests => 6;
    
    my $test;
    
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    
    my $rqst_identical  = $rqst_minimal->clone;
    my $resp_stored     = $resp_minimal->clone;
    my $rqst_associated = $rqst_minimal->clone;
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_identical,
            $resp_stored,
            $rqst_associated
        )
    }
        { carped => "" },
        "Methods are identical";
    ok ( ( not defined $test ),
        "... and falls through" );
    
    my $rqst_normalized = $rqst_minimal->clone;
    $rqst_normalized->method('head');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_normalized,
            $resp_stored,
            $rqst_associated
        )
    }
        { carped => qr/NO REUSE: Methods do not match/ },
        "NO REUSE: Methods are case-sensitive";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
    my $rqst_different = $rqst_minimal->clone;
    $rqst_different->method('OPTIONS');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_different,
            $resp_stored,
            $rqst_associated
        )
    }
        { carped => qr/NO REUSE: Methods do not match/ },
        "NO REUSE: Methods do not match";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
};


subtest "matching Nominated Headers in 'Vary'" => sub {
    
    plan tests => 12;
    
    my $test;
    
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
        warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_minimal,
            $resp_minimal,
            $rqst_minimal
        )
    }
        { carped => "" },
        "No 'Vary'";
    ok ( ( not defined $test ),
        "... and falls through" );
    
    my $resp_vary = $resp_minimal->clone;
    $resp_vary->header('Vary' => 'FOO');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_minimal,
            $resp_vary,
            $rqst_minimal,
        )
    }
        { carped => "" },
        "'Nominated Headers are not present in either request";
    ok ( ( not defined $test ),
        "... and falls through" );
    
    
    my $rqst_foo_bar = $rqst_minimal->clone;
    $rqst_foo_bar->header('FOO' => 'bar');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_minimal,
            $resp_vary,
            $rqst_foo_bar
        )
    }
        { carped => qr/NO REUSE: Nominated headers in 'Vary' do not match/ },
        "NO REUSE: Nominated Headers are not both in each request";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
    my $rqst_foo_baz = $rqst_minimal->clone;
    $rqst_foo_baz->header('FOO' => 'baz');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_foo_baz,
            $resp_vary,
            $rqst_foo_bar
        )
    }
        { carped => qr/NO REUSE: Nominated headers in 'Vary' do not match/ },
        "NO REUSE: Nominated Headers do not have the same value";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_foo_bar,
            $resp_vary,
            $rqst_foo_bar
        )
    }
        { carped => "" },
        "Nominated Headers are the same";
    ok ( ( not defined $test ),
        "... and falls through" );
    
    my $resp_star = $resp_minimal->clone;
    $resp_star->header('Vary' => '*');
    
    warning_like {
        $test = $none_caching->_may_reuse_from_cache(
            $rqst_foo_bar,
            $resp_star,
            $rqst_foo_bar
        )
    }
        { carped => qr/NO REUSE: 'Vary' equals '*'/ },
        "NO REUSE: 'Vary' equals '*'";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
};
