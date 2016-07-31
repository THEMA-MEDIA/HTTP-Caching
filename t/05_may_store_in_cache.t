use Test::Most tests => 1;

use HTTP::Caching;

use HTTP::Method;
use HTTP::Request;
use HTTP::Response;

subtest 'RFC 7234 Section 3 step 1' => sub {
    plan tests => 3;
    
    my $request     = HTTP::Request->new();
    my $response    = HTTP::Response->new(501);
    my $test_result = undef;

    $request->method('GET');
    $test_result = HTTP::Caching->_may_store_in_cache($request, $response);
    ok ( (!defined $test_result or $test_result == 1), # does not return 0
        "GET should not prevent from caching" );
    
    $request->method('DEL');
    $test_result = HTTP::Caching->_may_store_in_cache($request, $response);
    ok ( (defined $test_result and $test_result == 0),
        "DEL is not understood" );
    
    $request->method('PUT');
    $test_result = HTTP::Caching->_may_store_in_cache($request, $response);
    ok ( (defined $test_result and $test_result == 0),
        "PUT is not cachable" );
    
}