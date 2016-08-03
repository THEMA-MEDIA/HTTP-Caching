use Test::Most tests => 3;
use Test::MockObject;

use HTTP::Caching;

use HTTP::Request;
use HTTP::Response;

use Readonly;

# Although it does look like a proper URI, no, the file does not need to exist.
Readonly my $URI_LOCATION  => 'file:///tmp/HTTP_Cacing/greetings.txt';
Readonly my $URI_MD5       => '7d3d0fc115036f144964caafaf2c7df2';

# mock cache
my %cache;
my $mocked_cache = Test::MockObject->new;
$mocked_cache->mock( set => sub { $cache{$_[1]} = $_[2] } );
$mocked_cache->mock( get => sub { } );

my $request = HTTP::Request->new();
$request->method('HEAD');
$request->uri($URI_LOCATION);
$request->content('knock knock ...');

my $forwarded_resp = HTTP::Response->new(501);
$forwarded_resp->content('Who is there?');

my $http_caching = HTTP::Caching->new(
    cache                   => $mocked_cache,
    cache_type              => 'private',
    forwarder               => sub { return $forwarded_resp }
);

# don't care about responses, we only want to store in the cache
$http_caching->make_request($request);

ok (exists $cache{$URI_MD5}, 
    'stored under the right key');

isa_ok ($cache{$URI_MD5}, 'HTTP::Response',
    '... a HTTP::Request object');

is ($cache{$URI_MD5}->content, 'Who is there?',
    '... with the right contnet');
