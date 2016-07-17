use Test::Most tests => 2;

use HTTP::Caching;

use CHI;
use HTTP::Request;
use HTTP::Response;

use Readonly;

# Although it does look like a proper URI, no, the file does not need to exist.
Readonly my $URI_LOCATION  => 'file:///tmp/HTTP_Cacing/greetings.txt';
Readonly my $URI_MD5       => '7d3d0fc115036f144964caafaf2c7df2';

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
my $forwarded_resp = HTTP::Response->new(501);
$forwarded_resp->content('Hello World!');

my $http_caching = HTTP::Caching->new(
    cache                   => $chi_cache,
    cache_type              => 'private',
    cache_request_control   => 'max-age=3600',
    forwarder               => sub { return $forwarded_resp }
);

$http_caching->make_request($request);

my $stored_l1 = $chi_cache->get($URI_MD5);

my $stored_content = $chi_cache->get( $stored_l1->{content_key} );
is ($chi_cache->get( $stored_l1->{content_key} ), 'Hello World!',
    'Stored response content' );

my $stored_status = $stored_l1->{resp}->code;
is ($stored_l1->{resp}->code, '501',
    'Stored response header');
