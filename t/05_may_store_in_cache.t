use Test::Most tests => 6;

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
# - Response: 501 Not Implemented
#   Status Code is understood
#   Status Code is be default cachable
my $rqst_minimal = HTTP::Request->new('HEAD');
my $resp_minimal = HTTP::Response->new(501); # Not Implented
#
# NOTE: RFC 7231 Section 4.1. Request Methods : Overview
#   All general-purpose servers MUST support the methods GET and HEAD.
#   All other methods are OPTIONAL.
#
# a 501 response to a HEAD request SHOULD NOT happen


subtest "Minimal" => sub {
    
    plan tests => 1;
    
    my $test;
    
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    # So far... So good!
    #
    $test = $none_caching->_may_store_in_cache(
        $rqst_minimal,
        $resp_minimal
    );
    ok ( (!defined $test or $test == 1), # does not return 0
        "So far... So good!" );
    
};


subtest "Request Methods and Responses are understood" => sub {
    
    plan tests => 6;
    
    my $test;
    
    my $rqst_null = HTTP::Request->new();
    my $resp_null = HTTP::Response->new();
    
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    # NO CACHE: method is not understood
    #
    my $rqst_bad_method = $rqst_minimal->clone;
    $rqst_bad_method->method('X');
    
    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_bad_method,
            $resp_null
        )
    }
        { carped => qr/NO CACHE: method is not understood/ },
        "NO CACHE: method is not understood";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # NO CACHE: method is not cachable
    #
    my $rqst_not_cachable = $rqst_minimal->clone;
    $rqst_not_cachable->method('PUT');
    
    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_not_cachable,
            $resp_null
        )
    }
        { carped => qr/NO CACHE: method is not cachable/ },
        "NO CACHE: method is not cachable";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # NO CACHE: response status code is not understood
    #
    my $resp_bad_status_code = $resp_minimal->clone;
    $resp_bad_status_code->code(999);
    
    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_minimal,
            $resp_bad_status_code
        )
    }
        { carped => qr/NO CACHE: response status code is not understood/ },
        "NO CACHE: response status code is not understood";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
};


subtest "Cache-Control directive 'no-store'" => sub {
    
    plan tests => 4;
    
    my $test;
    
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    
    # NO CACHE: 'no-store' appears in request cache directives
    #
    my $rqst_not_store = $rqst_minimal->clone;
    $rqst_not_store->header(cache_control => 'no-store, no-idea');
    
    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_not_store,
            $resp_minimal
        )
    }
        { carped => qr/NO CACHE: 'no-store' appears in request/ },
        "NO CACHE: 'no-store' appears in request cache directives";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # NO CACHE: 'no-store' appears in response cache directives
    #
    my $resp_not_store = $resp_minimal->clone;
    $resp_not_store->header(cache_control => 'no-store, no-idea');

    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_minimal,
            $resp_not_store
        )
    }
        { carped => qr/NO CACHE: 'no-store' appears in response/ },
        "NO CACHE: 'no-store' appears in response cache directives";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
};


subtest "Cache-Control directive 'private'" => sub {
    
    plan tests => 4;
    
    my $test;
    
    # NO CACHE: 'private' appears in response cache directives
    #
    my $resp_private = $resp_minimal->clone;
    $resp_private->header(cache_control => 'private');
    
    # HTTP::Caching as 'public' or 'shared
    #
    my $pblc_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => 'public',
        forwarder   => sub { },
    );
    
    warning_like {
        $test = $pblc_caching->_may_store_in_cache(
            $rqst_minimal,
            $resp_private
        )
    }
        { carped => qr/NO CACHE: 'private' appears/ },
        "NO CACHE: 'private' appears in cache directives when shared";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # HTTP::Caching as 'public' or 'shared
    #
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    # So far... So good!
    #
    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_minimal,
            $resp_private
        )
    }
        { carped => '' },
        "OK CACHE: 'private' appears in cache directives when not shared";
    ok ( (!defined $test or $test == 1), # does not return 0
        "... and does not return 0" );
    
};


subtest "Request Header 'Authorization'" => sub {
    
    plan tests => 10;
    
    my $test;
    
    # NO CACHE: 'Authorization' appears in request when shared
    #
    my $rqst_authorization = $rqst_minimal->clone;
    $rqst_authorization->header('Authorization' => 'Basic am9obi5kb2U6c2VjcmV0');
    
    
    # HTTP::Caching not shared
    #
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_authorization,
            $resp_minimal
        )
    }
        { carped => '' },
        "OK CACHE: 'Authorization' appears in request when not shared";
    ok ( (!defined $test or $test == 1), # does not return 0
        "... and does not return 0" );
    
    
    # HTTP::Caching as 'public' or 'shared'
    #
    my $pblc_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => 'public',
        forwarder   => sub { },
    );
    
    warning_like {
        $test = $pblc_caching->_may_store_in_cache(
            $rqst_authorization,
            $resp_minimal
        )
    }
        { carped => qr/NO CACHE: 'Authorization' appears/ },
        "NO CACHE: 'Authorization' appears in request when shared";
    ok ( (defined $test and $test == 0),
        "... and returns 0" );
    
    # DO CACHE: 'Authorization' appears: must-revalidate
    #
    my $resp_must_revalidate = $resp_minimal->clone;
    $resp_must_revalidate->header(cache_control => 'must-revalidate');
    
    warning_like {
        $test = $pblc_caching->_may_store_in_cache(
            $rqst_authorization,
            $resp_must_revalidate
        )
    }
        { carped => qr/DO CACHE: 'Authorization' appears: must-revalidate/ },
        "DO CACHE: 'Authorization' appears: must-revalidate";
    ok ( ($test == 1),
        "... and returns 1" );
    
    # DO CACHE: 'Authorization' appears: public
    #
    my $resp_public = $resp_minimal->clone;
    $resp_public->header(cache_control => 'public');
    
    warning_like {
        $test = $pblc_caching->_may_store_in_cache(
            $rqst_authorization,
            $resp_public
        )
    }
        { carped => qr/DO CACHE: 'Authorization' appears: public/ },
        "DO CACHE: 'Authorization' appears: public";
    ok ( ($test == 1),
        "... and returns 1" );
    
    # DO CACHE: 'Authorization' appears: s-maxage
    #
    my $resp_s_maxage = $resp_minimal->clone;
    $resp_s_maxage->header(cache_control => 's-maxage=3600');
    
    warning_like {
        $test = $pblc_caching->_may_store_in_cache(
            $rqst_authorization,
            $resp_s_maxage
        )
    }
        { carped => qr/DO CACHE: 'Authorization' appears: s-maxage/ },
        "DO CACHE: 'Authorization' appears: s-maxage";
    ok ( ($test == 1),
        "... and returns 1" );
    
};

subtest "Response Header 'Expires'"=> sub {
    
    plan tests => 2;
    
    my $test;
    
    # DO CACHE: 'Authorization' appears: s-maxage
    #
    my $resp_expires = $resp_minimal->clone;
    $resp_expires->header('Expires' => 'Mon, 06 Jun 2016 21:47:33 GMT');
    
    my $none_caching = HTTP::Caching->new(
        cache       => undef,
        cache_type  => undef,
        forwarder   => sub { },
    );
    
    warning_like {
        $test = $none_caching->_may_store_in_cache(
            $rqst_minimal,
            $resp_expires
        )
    }
        { carped => qr/OK CACHE: 'Expires' at/ },
        "OK CACHE: 'Expires' at: ...";
    ok ( ($test == 1),
        "... and returns 1" );
    
};
