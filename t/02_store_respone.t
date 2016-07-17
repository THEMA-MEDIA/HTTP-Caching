use Test::Most tests => 6;

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
my $forwarded_resp = HTTP::Response->new(501);
$forwarded_resp->content('Who is there?');

my $http_caching = HTTP::Caching->new(
    cache                   => $chi_cache,
    cache_type              => 'private',
    forwarder               => sub { return $forwarded_resp }
);

# don't care about responses, we only want to store in the cache
$http_caching->make_request($request);

my $stored_l1 = $chi_cache->get($URI_MD5);
# do we have the three keys ?

isa_ok ($stored_l1->{stripped_rqst}, 'HTTP::Request',
    '... stored request');
is ($stored_l1->{stripped_rqst}->content, undef,
    '... that has been stripped');

isa_ok ($stored_l1->{stripped_resp}, 'HTTP::Response',
    '... stored response');
is ($stored_l1->{stripped_resp}->content, undef,
    '... that has been stripped');

is ($stored_l1->{stripped_resp}->code, '501',
    '... response status-code is "Not Implemented"');

is ($chi_cache->get( $stored_l1->{content_key} ), 'Who is there?',
    'Stored response content as expected' );

