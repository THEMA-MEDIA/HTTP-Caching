use Test::Most tests => 6;

use HTTP::Caching;

use CHI;
use HTTP::Request;
use HTTP::Response;

use Readonly;

# Although it does look like a proper URI, no, the file does not need to exist.
Readonly my $URI_LOCATION   => 'file:///tmp/HTTP_Cacing/greetings.txt';
Readonly my $URI_MD5        => '7d3d0fc115036f144964caafaf2c7df2';
Readonly my $CONTENT_KEY    => '3e5f1b953da8430c6f88b90ac15d78fa'; # or whatever

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
$request->uri($URI_LOCATION);
$request->content('knock knock ...');

# 501 Not Implemented is a 'by default' cachable response
#
# See RFC 7234 Section 3.     Storing Responses in Cach
#                               The response either has ... a statuscode
#     RFC 7234 Section 4.2.2. Calculating Heuristic Freshness
#     RFC 7231 Section 6.1.   Overview of Status Codes
#                      6.6.2. 501 Not Implemented
#
# This means that without any other Cache-control directives, or Expires or
# Last-Modified, this response can always be stored in the cache
#
my $expected_resp = HTTP::Response->new(501);
$expected_resp->content('Who is there');

my $rqst_clone = $request->clone;
$rqst_clone->content(undef);
my $resp_clone = $expected_resp->clone;
$resp_clone->content(undef);

# populate the cache, we could try mocking CHI, but I'm to lazy for that
$chi_cache->set($CONTENT_KEY, 'Who is there?');
$chi_cache->set($URI_MD5,
    {
        stripped_rqst   => $rqst_clone,
        stripped_resp   => $resp_clone,
        content_key     => $CONTENT_KEY,
    }
);

my $http_caching = HTTP::Caching->new(
    cache                   => $chi_cache,
    cache_type              => 'private',
    forwarder               => sub { return undef } # we should ewnd up here
);

my $response = $http_caching->make_request($request);

use DDP; p $response;

