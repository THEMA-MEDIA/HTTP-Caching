use Test::Most tests => 2;

use HTTP::Caching;

$HTTP::Caching::DEBUG = 1;

use HTTP::Method;
use HTTP::Request;
use HTTP::Response;

subtest "Request Methods and Responses are understood" => sub {
    
    plan tests => 7;
    
    my $rqst = HTTP::Request->new();
    my $resp = HTTP::Response->new();
    my $test = undef;
    
    $rqst->method('DEL');
    
    warning_like { $test = HTTP::Caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: method is not understood/ },
        "NO CACHE: method is not understood";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
    $rqst->method('PUT');
    
    warning_like { $test = HTTP::Caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: method is not cachable/ },
        "NO CACHE: method is not cachable";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
    $rqst->method('HEAD');
    $resp->code(999);
    
    warning_like { $test = HTTP::Caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: response status code is not understood/ },
        "NO CACHE: response status code is not understood";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
    $resp->code(501); # Not Implemented
    
    $test = HTTP::Caching->_may_store_in_cache($rqst, $resp);
    ok ( (!defined $test or $test == 1), # does not return 0
        "So far... So good!" );
    
};

subtest "Cache-Control directives" => sub {
    
    plan tests => 4;
    
    my $rqst = HTTP::Request->new();
    my $resp = HTTP::Response->new();
    my $test = undef;

    $rqst->method('HEAD');
    $rqst->header(cache_control => 'no-store, no-idea');
    
    $resp->code(501);
    
    warning_like { $test = HTTP::Caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: 'no-store' appears in request/ },
        "NO CACHE: 'no-store' appears in request cache directives";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
    $rqst->header(cache_control => undef);
    $resp->header(cache_control => 'no-store, no-idea');

    warning_like { $test = HTTP::Caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: 'no-store' appears in response/ },
        "NO CACHE: 'no-store' appears in response cache directives";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
}