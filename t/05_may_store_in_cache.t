use Test::Most tests => 4;

use HTTP::Caching;

use HTTP::Method;
use HTTP::Request;
use HTTP::Response;

my $rqst = HTTP::Request->new();
my $resp = HTTP::Response->new();
my $test = undef;

$rqst->method('DEL');

$test = HTTP::Caching->_may_store_in_cache($rqst, $resp);
ok ( ( $test == 0),
    "NO CACHE: DEL is not understood" );


$rqst->method('PUT');

$test = HTTP::Caching->_may_store_in_cache($rqst, $resp);
ok ( (defined $test and $test == 0),
    "NO CACHE: PUT is not cachable" );


$rqst->method('HEAD');
$resp->code(999);

$test = HTTP::Caching->_may_store_in_cache($rqst, $resp);
ok ( (defined $test and $test == 0),
    "NO CACHE: 999 is not understood" );


$resp->code(501); # Not Implemented

$test = HTTP::Caching->_may_store_in_cache($rqst, $resp);
ok ( (!defined $test or $test == 1), # does not return 0
    "So far... So good!" );



