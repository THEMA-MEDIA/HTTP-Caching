use Test::Most tests => 4;

use CHI;
use HTTP::Request;
use HTTP::Response;

subtest 'HTTP::Caching' => sub {
    plan tests => 1;
    use_ok('HTTP::Caching');
};

my $chi_cache = CHI->new(
    driver                  => 'File',
    root_dir                => '/tmp/HTTP_Caching',
    file_extension          => '.cache',
    l1_cache                => {
        driver                  => 'Memory',
        global                  => 1,
        max_size                => 1024*1024
    }
);

my $request = HTTP::Request->new();
$request->method('TEST'); # yep, does not exists, thats fine


subtest 'Instantiating HTTP::Caching object' => sub {
    plan tests => 1;
    
    my $http_caching =
    new_ok('HTTP::Caching', [
            cache                   => $chi_cache,
            cache_type              => 'private',
            cache_request_control   => 'max-age=3600',
            forwarder               => sub { return HTTP::Response->new(501) }
        ] , 'my $http_caching'
    );
    
};

subtest 'HTTP::Caching make_request' => sub {
    plan tests => 4;
    
    my $http_caching = eval {
        HTTP::Caching->new(
            cache                   => undef,
            cache_type              => 'private',
            forwarder               => sub { return HTTP::Response->new(501) }
        )
    };
    
    can_ok($http_caching, 'make_request');
    

    my $response = $http_caching->make_request($request);
    ok($response->is_error,
        '... gives an error, but we can continue');
    
    eval {$http_caching->make_request};
    like($@, qr/HTTP::Caching missing request/,
        '... but do not allow missing request');
    
    eval {$http_caching->make_request(0)};
    like($@, qr/HTTP::Caching request is not/,
        '... but do not allow requests other than HTTP::Request objects');
    
};

subtest 'HTTP::Caching forwarding' => sub {
    plan tests => 5;
    
    my $http_caching = eval {
        HTTP::Caching->new(
            cache                   => undef,
            cache_type              => 'private',
            forwarder               => \&_forward,
        )
    };
    
    sub _forward {
        my $forward_rqst = shift;
        
        isa_ok($forward_rqst, 'HTTP::Request',
            'forwarded request from HTTP::Caching');
        is($forward_rqst->method, 'TEST',
            '... with method "TEST"');
        
        my $forward_resp = HTTP::Response->new(501, 'Nay!');
        
        return $forward_resp;
    }
    
    my $response = $http_caching->make_request($request);
    isa_ok ($response, 'HTTP::Response',
        'forwarded response back');
    is($response->message, 'Nay!',
        '... with the message: "Nay!"');
    
    my $errs_caching = eval {
        HTTP::Caching->new(
            cache                   => undef,
            cache_type              => 'private',
            forwarder               => sub { return 1 },
        )
    };
    
    eval {$errs_caching->make_request($request) };
    like($@, qr/HTTP::Caching response from forwarder/,
        '... but do not allow bad responses');
};

=pod

501 Not Implemented is a 'by default' cachable response

See RFC 7234 Section 3.     Storing Responses in Cach
                              The response either has ... a statuscode
    RFC 7234 Section 4.2.2. Calculating Heuristic Freshness
    RFC 7231 Section 6.1.   Overview of Status Codes
                     6.6.2. 501 Not Implemented

This means that without any other Cache-control directives, or Expires or
Last-Modified, this response can always be stored in the cache

=cut
