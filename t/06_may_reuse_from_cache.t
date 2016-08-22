use Test::Most tests => 1;

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
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
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
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
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
