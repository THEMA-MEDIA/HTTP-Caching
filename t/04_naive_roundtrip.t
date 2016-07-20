use Test::Most tests => 4;

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
    driver                  => 'Memory',
    global                  => 0,
    l1_cache                => {
        driver                  => 'Memory',
        global                  => 0,
        max_size                => 1024*1024
    }
);

my $request = HTTP::Request->new();
$request->method('TEST');
$request->uri($URI_LOCATION);
$request->content('knock knock ...');

# 501 Not Implemented is a 'by default' cachable response
my $forwarded_resp = HTTP::Response->new(501);
$forwarded_resp->content('Who is there?');

my $forwarded_rqst = undef; # flag to be set if we do forward the request

my $http_caching = HTTP::Caching->new(
    cache                   => $chi_cache,
    cache_type              => 'private',
    forwarder               => sub {
        $forwarded_rqst = shift;
        return $forwarded_resp
    }
);

my $response_one = $http_caching->make_request($request);
is ($forwarded_rqst->content(), 'knock knock ...',
    "Request has been forwarded");
is ($response_one->content(), 'Who is there?',
    "... and response one is as expected" );

$forwarded_rqst = undef;

my $response_two = $http_caching->make_request($request);
is ($forwarded_rqst, undef,
    "Request has not been forwarded for the second time");
is ($response_one->content(), 'Who is there?',
    "... and response two is as expected" );

