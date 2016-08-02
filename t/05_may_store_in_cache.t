use Test::Most tests => 2;

use HTTP::Caching;

$HTTP::Caching::DEBUG = 1;

use HTTP::Method;
use HTTP::Request;
use HTTP::Response;

my $http_caching;

subtest "Request Methods and Responses are understood" => sub {
    
    plan tests => 7;
    
    my $rqst = HTTP::Request->new();
    my $resp = HTTP::Response->new();
    my $test = undef;
    
    $http_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    # NO CACHE: method is not understood: 'DEL'
    #
    $rqst->method('DEL');
    
    warning_like { $test = $http_caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: method is not understood/ },
        "NO CACHE: method is not understood";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # NO CACHE: method is not cachable: 'PUT'
    #
    $rqst->method('PUT');
    
    warning_like { $test = $http_caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: method is not cachable/ },
        "NO CACHE: method is not cachable";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # NO CACHE: response status code is not understood: '999'
    #
    $rqst->method('HEAD');
    $resp->code(999);
    
    warning_like { $test = $http_caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: response status code is not understood/ },
        "NO CACHE: response status code is not understood";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # So far... So good!
    #
    $resp->code(501); # Not Implemented
    
    $test = $http_caching->_may_store_in_cache($rqst, $resp);
    ok ( (!defined $test or $test == 1), # does not return 0
        "So far... So good!" );
    
};

subtest "Cache-Control directives" => sub {
    
    plan tests => 10;
    
    my $rqst = HTTP::Request->new();
    $rqst->method('HEAD');
    
    my $resp = HTTP::Response->new();
    $resp->code(501);
    
    my $test = undef;
    
    $http_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    
    # NO CACHE: 'no-store' appears in request cache directives
    #
    $rqst->header(cache_control => 'no-store, no-idea');
    
    warning_like { $test = $http_caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: 'no-store' appears in request/ },
        "NO CACHE: 'no-store' appears in request cache directives";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    $rqst->header(cache_control => undef);
    
    
    # NO CACHE: 'no-store' appears in response cache directives
    #
    $resp->header(cache_control => 'no-store, no-idea');

    warning_like { $test = $http_caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: 'no-store' appears in response/ },
        "NO CACHE: 'no-store' appears in response cache directives";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    
    # NO CACHE: 'private' appears in response cache directives
    #
    $resp->header(cache_control => 'private');
    
    # HTTP::Caching as 'public' or 'shared
    #
    $http_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => 'public',
        forwarder   => sub { },
    );
    
    warning_like { $test = $http_caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: 'private' appears/ },
        "NO CACHE: 'private' appears in cache directives when shared";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # HTTP::Caching as 'public' or 'shared
    #
    $http_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    # So far... So good!
    #
    $test = $http_caching->_may_store_in_cache($rqst, $resp);
    ok ( (!defined $test or $test == 1), # does not return 0
        "So far... So good!" );
    
    $resp->header(cache_control => undef);
    
    
    # NO CACHE: 'Authorization' appears in request when shared
    #
    $rqst->header('Authorization' => 'Basic am9obi5kb2U6c2VjcmV0');
    
    # HTTP::Caching as 'public' or 'shared
    #
    $http_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => 'public',
        forwarder   => sub { },
    );
    
    warning_like { $test = $http_caching->_may_store_in_cache($rqst, $resp) }
        { carped => qr/NO CACHE: 'Authorization' appears/ },
        "NO CACHE: 'Authorization' appears in request when shared";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # HTTP::Caching as 'public' or 'shared
    #
    $http_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    # So far... So good!
    #
    $test = $http_caching->_may_store_in_cache($rqst, $resp);
    ok ( (!defined $test or $test == 1), # does not return 0
        "So far... So good!" );
    
}