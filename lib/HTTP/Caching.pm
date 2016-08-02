package HTTP::Caching;

=head1 NAME

HTTP::Caching - The RFC 7234 compliant brains to do caching right

=head1 VERSION

Version 0.02 Alpha 01

=cut

our $VERSION = '0.02_01';

use strict;
use warnings;

use Carp;
use Digest::MD5;
use HTTP::Method;
use List::MoreUtils qw{ any };
use Time::HiRes;

use Moo;
use MooX::Types::MooseLike::Base ':all';

our $DEBUG = 0;

=head1 SYNOPSIS

    my $chi_cache = CHI->new(
        driver          => 'File',
        root_dir        => '/tmp/HTTP_Caching',
        file_extension  => '.cache',
        l1_cache        => {
            driver          => 'Memory',
            global          => 1,
            max_size        => 1024*1024
        }
    );
    
    my $ua = LWP::UserAgent->new();
    
    my $http_caching = HTTP::Caching->new(
        cache         => $chi_cache,
        cache_type    => 'private',
        forwarder     => sub { return $ua->request(shift) }
    );
    
    my $rqst = HTTP::Request->new( GET => 'http://example.com' );
    
    my $resp = $http_caching->make_request( $rqst );
    
=cut

has cache => (
    is          => 'ro',
    required    => 0,
    isa         => Maybe[ HasMethods['set', 'get'] ],
    builder     => sub {
        warn __PACKAGE__ . " without cache, forwards requests and responses\n";
        return undef
    },
);

has cache_type => (
    is          => 'ro',
    required    => 1,
    isa         => Maybe[ Enum['private', 'public'] ],
);

has cache_control_request => (
    is          => 'ro',
    required    => 0,
    isa         => Str,
);

has cache_control_response => (
    is          => 'ro',
    required    => 0,
    isa         => Str,
);

has forwarder => (
    is          => 'ro',
    required    => 1,
    isa         => CodeRef,
);

sub is_shared {
    my $self = shift;
    
    return unless $self->cache_type;
    return $self->cache_type eq 'public'
}
=head1 DESCRIPTION

This module tries to provide caching for HTTP responses based on
L<RFC 7234 Hypertext Transfer Protocol (HTTPE<sol>1.1): Caching|
    http://tools.ietf.org/html/rfc7234>.

Basicly it looks like the following steps below:

=over

=item

For a presented request, it will check with the cache if there is a suitable
response available AND if it can be served or that it needs to be revalidated
with an upstream server.

=item

If there was no response available at all, or non were suitable, the (modified)
request will simply be forwarded.

=item

Depending on the response it gets back, it will do one of the following
dependingon the response status code:

=over

=item 200 OK

it will update the cache and serve the response as is

=item 304 Not Modified

the cached version is valid, update the cache with new header info and serve the
cached response

=item 500 Server Error

in general, this is an error, and pass that onto the caller, however, in some
cases it could be fine to serve a (stale) cached response

=back

=back

The above is a over-simplified version of the RFC

=cut

=head1 CONSTRUCTORS

=head2 new

    my $http_caching = HTTP::Caching->new(
        cache           => $chi_cache,
        cache_type      => 'private',
        cache_request   => 'max-age=86400, min-fresh=60',
        forwarder       => sub { return $ua->request(shift) }
    );

Constructs a new C<HTTP::Caching> object that knows how to find cached responses
and will forward if needed.

=head1 ATRRIBUTES

=head2 cache

Cache must be an object that MUST implement two methods

=over

=item sub set ($key, $data)

to store data in the cache

=item sub get ($key)

to retrieve the data stored under the key

=back

This can be as simple as a hash, like we use in the tests:

    use Test::MockObject;
    
    my %cache;
    my $mocked_cache = Test::MockObject->new;
    $mocked_cache->mock( set => sub { $cache{$_[1]} = $_[2] } );
    $mocked_cache->mock( get => sub { return $cache{$_[1]} } );

But very convenient is to use L<CHI>, which implements both required methods and
also has the option to use a L1 cache to speed things up even more. See the
SYNOPSIS for an example

=head2 cache_type

This must either be C<'private'> or C<'public'>. For most L<LWP::UserAgents>, it
can be C<'private'> as it will probably not be shared with other processes on
the same macine. If this module is being used at the serverside in a
L<Plack::Middleware> then the cache will be used by all other clients connecting
to the server, and thus should be set to C<'public'>.

Responses to Authenticated request should not be held in public caches and also
those responses that specifacally have their cache-control headerfield set to
C<'private'>.

=head2 cache_control_request

A string that contains the Cache-control header-field settings that will be sent
as default with the request. So you do not have to set those each time. See
RFC 7234 Section 5.2.1 for the list of available cache-control directives.

=head2 cache_control_response

Like the above, but those will be set for each response. This is useful for
server side caching. See RFC 7234 Section 5.2.2.

=head2 forwarder

This CodeRef must be a callback function that accepts a L<HTTP::Request> and
returns a L<HTTP::Response>. Since this module does not know how to do a request
it will use the C<forwarder>. It will be used to sent of validation requests
with C<If-None-Match> and/or C<If-Modified-Since> header-fields. Or if it does
not have a stored response it will send the original full request (with the
extra directives from C<cache_request>).

Failing to return a C<HTTP::Response> might cause the module to die or generate
a response itself with status code C<502 Bad Gateway>. 

=head1 METHODS

=head2 make_request

This is the only public provided method and will take a L<HTTP::Request>. Like
described above, it might have to forward the (modified) request throug the
CodeRef in the C<forwarder> attribute.

It will return a L<HTTP::Response> from cache or a new retrieved one. This might
be a HTTP respons with a C<500 Error> message.

In other cases it might die and let the caller know what was wrong, or send
another 5XX Error.

=cut

sub make_request {
    my $self = shift;
    
    croak __PACKAGE__
        . " missing request"
        unless defined $_[0];
    croak __PACKAGE__
        . " request is not a HTTP::Request [$_[0]]"
        unless UNIVERSAL::isa($_[0],'HTTP::Request');
    
    my $presented_request = shift->clone;
    
    my @params = @_;

    # add the default Cache-Control request header-field
    $presented_request->headers->push_header(
        cache_control => $self->cache_control_request,
    ) if $self->cache_control_request();
    
    my $response;
    
    unless ($self->cache) {
        $response = $self->_forward($presented_request, @params);
    } else {
        if (my $cache_resp =
            $self->_retrieve($presented_request)
        ) {
            $response = $cache_resp;
        } else {
            $response = $self->_forward($presented_request, @params);
            $self->_store($presented_request, $response);
        }
    }
    
     # add the default Cache-Control response header-field
    $response->headers->push_header(
        cache_control => $self->cache_control_response,
    ) if $self->cache_control_request;
   
    return $response;
    
}

sub _forward {
    my $self = shift;
    
    my $forwarded_rqst = shift;
    
    my $forwarded_resp = $self->forwarder->($forwarded_rqst, @_);
    
    croak __PACKAGE__
        . " response from forwarder is not a HTTP::Response [$forwarded_resp]"
        unless UNIVERSAL::isa($forwarded_resp,'HTTP::Response');
    
    return $forwarded_resp;
}

sub _store {
    my $self        = shift;
    my $rqst        = shift;
    my $resp        = shift;
    
    my $request_key = Digest::MD5::md5_hex($rqst->uri()->as_string);
    
    $self->cache->set( $request_key => $resp );
    
    return $request_key;
}

sub _retrieve {
    my $self        = shift;
    my $rqst        = shift;
    
    my $request_key = Digest::MD5::md5_hex($rqst->uri()->as_string);
    
    my $resp = $self->cache->get( $request_key );
    
    return $resp;
}

# _may_store_in_cache()
#
# based on some headers in the request, but mostly on those in the new response
# the cache can hold a copy of it or not.
#
# see RFC 7234 Section 3: Storing Responses in Caches
#
sub _may_store_in_cache {
    my $self = shift;
    my $rqst = shift;
    my $resp = shift;
    
    # $msg->header('cache-control) is supposed to return a list, but only works
    # if it has been generated as a list, not as string with 'comma'
    # $msg->header in scalar context gives a ', ' joined string
    # which we now split and trim whitespace
    my @rqst_directives =
        map { my $str = $_; $str =~ s/^\s+//; $str =~ s/\s+$//; $str }
        split ',', scalar $rqst->header('cache-control') || '';
    my @resp_directives =
        map { my $str = $_; $str =~ s/^\s+//; $str =~ s/\s+$//; $str }
        split ',', scalar $resp->header('cache-control') || '';
    
    
    #                                               RFC 7234 Section 3
    #
    # A cache MUST NOT store a response to any request, unless:
    
    #                                               RFC 7234 Section 3 #1
    #
    # the request method is understood by the cache and defined as being
    # cacheable
    #
    do {
        my $string = $rqst->method;
        my $method = eval { HTTP::Method->new($string) };
        
        unless ($method) {
            carp "NO CACHE: method is not understood: '$string'\n"
                if $DEBUG;
            return 0
        }
        unless ($method->is_method_cachable) {
            carp "NO CACHE: method is not cachable: '$string'\n"
                if $DEBUG;
            return 0
        }
    };
    
    #                                               RFC 7234 Section 3 #2
    #
    # the response status code is understood by the cache
    #
    do {
        my $code = $resp->code; 
        my $message = eval { HTTP::Status::status_message($code) };
        
        unless ($message) {
            carp "NO CACHE: response status code is not understood: '$code'\n"
                if $DEBUG;
            return 0
        }
    };
    
    
    #                                               RFC 7234 Section 3 #3
    #
    # the "no-store" cache directive (see Section 5.2) does not appear
    # in request or response header fields
    #
    do {
        if (any { lc $_ eq 'no-store' } @rqst_directives) {
            carp "NO CACHE: 'no-store' appears in request cache directives\n"
                if $DEBUG;
            return 0
        }
        if (any { lc $_ eq 'no-store' } @resp_directives) {
            carp "NO CACHE: 'no-store' appears in response cache directives\n"
                if $DEBUG;
            return 0
        }
    };
    
    #                                               RFC 7234 Section 3 #4
    #
    # the "private" response directive (see Section 5.2.2.6) does not
    # appear in the response, if the cache is shared
    #
    if ($self->is_shared) {
        if (any { lc $_ eq 'private' } @resp_directives) {
            carp "NO CACHE: 'private' appears in cache directives when shared\n"
                if $DEBUG;
            return 0
        }
    };
    
    #                                               RFC 7234 Section 3 #5
    #
    # the Authorization header field (see Section 4.2 of [RFC7235]) does
    # not appear in the request, if the cache is shared, unless the
    # response explicitly allows it (see Section 3.2)
    #
    if ($self->is_shared) {
        if ($rqst->header('Authorization')) {
            if (any { lc $_ eq 'must-revalidate' } @resp_directives) {
                carp "DO CACHE: 'Authorization' appears: must-revalidate\n"
                    if $DEBUG;
                return 1
            }
            if (any { lc $_ eq 'public' } @resp_directives) {
                carp "DO CACHE: 'Authorization' appears: public\n"
                    if $DEBUG;
                return 1
            }
            if (any { lc $_ =~ m/^s-maxage=\d+$/ } @resp_directives) {
                carp "DO CACHE: 'Authorization' appears: s-maxage\n"
                    if $DEBUG;
                return 1
            }
            carp "NO CACHE: 'Authorization' appears in request when shared\n"
                if $DEBUG;
            return 0
        }
    };
    
    
    #                                               RFC 7234 Section 3 #6
    #
    # the response either:
    #
    # - contains an Expires header field (see Section 5.3)
    #
    do {
        my $expires_at = $resp->header('Expires');
        
        if ($expires_at) {
            carp "OK CACHE: 'Expires' at: $expires_at\n"
                if $DEBUG;
            return 1
        }
    };
    
    # - contains a max-age response directive (see Section 5.2.2.8)
    #
    do {
        if (any { lc $_ =~ m/^max-age=\d+$/ } @resp_directives) {
            carp "DO CACHE: 'max-age' appears in response cache directives\n"
                if $DEBUG;
            return 1
        }
    };
    
    # - contains a s-maxage response directive (see Section 5.2.2.9)
    #   and the cache is shared
    #
    if ($self->is_shared) {
        if (any { lc $_ =~ m/^s-maxage=\d+$/ } @resp_directives) {
            carp "DO CACHE: 's-maxage' appears in response cache directives\n"
                if $DEBUG;
            return 1
        }
    };
    
    
    # - contains a Cache Control Extension (see Section 5.2.3) that
    #   allows it to be cache
    #
    # TODO  it looks like this is only used for special defined cache-control
    #       directives. As such, those need special treatment.
    #       It does not seem a good idea to hardcode those here, a config would
    #       be a better solution.
    
    
    # - has a status code that is defined as cacheable by default (see
    #   Section 4.2.2)
    #
#   TODO
    
    
    # - contains a public response directive (see Section 5.2.2.5)
    #
#   TODO
    
    
    return undef;
}

1;
