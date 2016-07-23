use Test::Most tests => 1;

use HTTP::Caching;

use HTTP::Request;
use HTTP::Response;

subtest 'Simple modifiactions' => sub {
    plan tests => 3;
    
    my $forwarded_rqst;
    
    my $http_caching =
        new_ok('HTTP::Caching', [
            cache                   => undef, # no cache needed for these tests
            cache_type              => 'private',
            cache_control_request   => 'min-fresh=60',
            cache_control_response  => 'must-revalidate',
            forwarder               => sub {
                $forwarded_rqst = shift;
                return HTTP::Response->new(501)
            },
        ] , 'my $http_caching'
    );
    
    my $request = HTTP::Request->new();
    $request->method('TEST');
    
    my $response = $http_caching->make_request($request);
    
    is($forwarded_rqst->header('cache-control'), 'min-fresh=60',
        "modified request");
    
    is($response->header('cache-control'), 'must-revalidate',
        "modified response");
    
}