package HTTP::Caching;

=head1 NAME

HTTP::Caching

=cut

use strict;
use warnings;

use Carp;
use Digest::MD5;
use Time::HiRes;

use HTTP::Response;

# Since we have dependencies
use Moo;
use MooX::Types::MooseLike::Base ':all';

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
    isa         => Maybe[ ConsumerOf['CHI::Driver::Role::HasSubcaches'] ],
    builder     => sub {
        warn __PACKAGE__ . " without cache, forwards requests and responses\n";
        return undef
    },
);

has cache_type => (
    is          => 'ro',
    required    => 1,
    isa         => Enum['private', 'public'],
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

=head1 METHODS

=head2 new

    my $http_caching = HTTP::Caching->new(
        cache           => $chi_cache,
        cache_type      => 'private',
        cache_request   => 'max-age=86400, min-fresh=60',
        forwarder       => sub { return $ua->request(shift) }
    );

Constructs a new C<HTTP::Caching> object that knows how to find cached responses
and will forward if needed.

The following attributes are used:

=over

=item cache

A L<CHI> compatible cache. To have most benifits from a cache, it could be
stored on a files-system if you like to have it between processes. A L1 Cache is
very useful because of the way HTTP Caching has to handle the responses. Since
it is possible that there are multiple responses associated with a specific URI,
it needs to inspect all variants and if needed, validate against the upstream
server. After the response comes back, it then needs to reselct a stored
response, based on the the recieved response. The L1-cache will only be used
for the request and response headers, the actual response body or the payload
will be stored in the primary cache, on filesystem.

See L<CHI> for more information about creating a cache. The one shown in the
synopsis is a good starter.

=item cache_type

This must either be C<'private'> or C<'public'>. For most L<LWP::UserAgents>, it
can be C<'private'> as it will probably not be shared with other processes on
the same macine. If this module is being used at the serverside in a
L<Plack::Middleware> then the cache will be used by all other clients connecting
to the server, and thus should be set to C<'public'>.

Responses to Authenticated request should not be held in public caches and also
those responses that specifacally have their cache-control headerfield set to
C<'private'>.

=item cache_control_request

A string that contains the Cache-control header-field settings that will be sent
as default with the request. So you do not have to set those each time. See
RFC 7234 Section 5.2.1 for the list of available cache-control directives.

=item cache_control_response

Like the above, but those will be set for each response. This is useful for
server side caching. See RFC 7234 Section 5.2.2.

=item forwarder

This CodeRef must be a callback function that accepts a L<HTTP::Request> and
returns a L<HTTP::Response>. Since this module does not know how to do a request
it will use the C<forwarder>. It will be used to sent of validation requests
with C<If-None-Match> and/or C<If-Modified-Since> header-fields. Or if it does
not have a stored response it will send the original full request (with the
extra directives from C<cache_request>).

Failing to return a C<HTTP::Response> might cause the module to die or generate
a response itself with status code C<502 Bad Gateway>. 

=back

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
    
    my $presented_request = shift;
    croak __PACKAGE__
        . " missing request"
        unless defined $presented_request;
    croak __PACKAGE__
        . " request is not a HTTP::Request [$presented_request]"
        unless $presented_request->isa('HTTP::Request');
    
    my @params = @_;

    # add the default Cache-Control request header-field
    $presented_request->headers->push_header(
        cache_control => $self->cache_control_request,
    ) if $self->cache_control_request();
    
    my $response;
    
    unless ($self->cache) {
        $response = $self->_forward($presented_request, @params);
    } else {
        if (my $chi_cache_resp =
            $self->_retrieve_response_for_request($presented_request)
        ) {
            $response = $chi_cache_resp;
        } else {
            $response = $self->_forward($presented_request, @params);
            $self->_store_request_with_response($presented_request, $response);
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
        unless $forwarded_resp->isa('HTTP::Response');
    
    return $forwarded_resp;
}

sub _store_request_with_response {
    my $self        = shift;
    my $rqst        = shift;
    my $resp        = shift;
    
    # store the response content on it's own
    my $content_key = $self->_store_content($resp->content);
    my $request_key = Digest::MD5::md5_hex($rqst->uri()->as_string);
    
    # strip the request and response from their content, not used during checks
    my $rqst_clone = $rqst->clone;
    $rqst_clone->content(undef);
    my $resp_clone = $resp->clone;
    $resp_clone->content(undef);
    
    $self->cache->set( $request_key => {
            stripped_rqst   => $rqst_clone,
            stripped_resp   => $resp_clone,
            content_key     => $content_key
        }
    );
    
}

sub _store_content {
    my $self        = shift;
    my $content     = shift;
    
    my $content_key = Digest::MD5::md5_hex(Time::HiRes::time());
    
    eval { $self->cache->set( $content_key => $content ) };
    return $content_key unless $@;
    
    croak __PACKAGE__
        . " could not store content in cache with key [$content_key], $@";
    
    return
}

sub _retrieve_response_for_request {
    my $self        = shift;
    my $rqst        = shift;
    
    # check cache for stored meta-data 
    my $request_key = Digest::MD5::md5_hex($rqst->uri()->as_string);
    my $meta_data   = $self->cache->get( $request_key );
    return unless $meta_data;
    
    # check cache for content
    my $content_key = $meta_data->{content_key};
    my $content = $self->_retrieve_content($content_key);
    return unless $content;
    
    # compose response
    my $resp = $meta_data->{stripped_resp};
    my $resp_clone = $resp->clone;
    $resp_clone->content($content);
    
    return $resp_clone
}

sub _retrieve_content {
    my $self        = shift;
    my $content_key = shift;
    
    my $content = eval { $self->cache->get( $content_key ) };
    return $content unless $@;
    
    croak __PACKAGE__
        . " could not retrieve content from cache with key [$content_key], $@";
    
    return
}

1;
