use Test::Most tests => 1;

use HTTP::Caching;

use HTTP::Request;
use HTTP::Response;

subtest 'Simple modifiactions' => sub {
    plan tests => 3;
    
    my $http_caching =
    new_ok('HTTP::Caching', [
            cache                   => undef,
            cache_type              => 'private',
            cache_control_request   => 'min-fresh=60',
            cache_control_response  => 'must-revalidate',
            forwarder               => sub {
                my $forward_rqst = shift;
                my $directive = $forward_rqst->header('cache-control');
                
                is($directive, 'min-fresh=60', 'modified request');
                
                return HTTP::Response->new(100)
            },
        ] , 'my $http_caching'
    );
    
    my $request = HTTP::Request->new();
    $request->method('TEST');
    
    my $response = $http_caching->make_request($request);
    
    my $directive = $response->header('cache-control');
    is($directive, 'must-revalidate', 'modified response');
    
}