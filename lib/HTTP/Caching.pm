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
    
    unless ($self->cache) {
        # add the default Cache-Control request header-field
        my $forwarded_rqst =
            $self->_modify_request_cache_control($presented_request);
        
        my $forwarded_resp = $self->_forward($forwarded_rqst, @params);
        
        # add the default Cache-Control response header-field
        my $response =
            $self->_modify_response_cache_control($forwarded_resp);
        
        return $response
    } else {
        # add the default Cache-Control request header-field
        my $forwarded_rqst =
            $self->_modify_request_cache_control($presented_request);
        
        my $forwarded_resp = $self->_forward($forwarded_rqst, @params);
        
        $self->_store_request_with_response($forwarded_rqst, $forwarded_resp);
        
        # add the default Cache-Control response header-field
        my $response =
            $self->_modify_response_cache_control($forwarded_resp);
        
        return $response
    }
    
    # How did we end up here ?
    carp __PACKAGE__
        . 'runaway';
    return HTTP::Response->new(500, "Oops, HTTP::Caching runaway");
    
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
    my $rqst        = shift->clone or croak ;
    my $resp        = shift->clone or die;
    
    my $content_key = $self->_store_response_content($resp);
    my $request_key = Digest::MD5::md5_hex($rqst->uri()->as_string);
    
    $self->cache->set($request_key,
        {
            rqst        => $rqst,
            resp        => $resp,
            content_key => $content_key
        }
    );
    
}

sub _store_response_content {
    my $self        = shift;
    my $resp        = shift;
    
    my $content_key = Digest::MD5::md5_hex(Time::HiRes::time());
    
    eval { $self->cache->set( $content_key, $resp->content() ) };
    return $content_key unless $@;
    
    croak __PACKAGE__
        . " could not store content in cache with key [$content_key], $@";
    
    return
}

sub _modify_request_cache_control {
    my $self        = shift;
    my $rqst        = shift;
    
    my $modified_header = $self->_modify_cache_control_header(
        $rqst->headers,
        $self->cache_control_request,
    );
    
    my $modified_rqst =
        $self->_substitute_request_header( $rqst, $modified_header );
    
    return $modified_rqst
}

sub _modify_response_cache_control {
    my $self        = shift;
    my $resp        = shift;
    
    my $modified_header = $self->_modify_cache_control_header(
        $resp->headers,
        $self->cache_control_response,
    );
    
    my $modified_resp =
        $self->_substitute_response_header( $resp, $modified_header );
    
    return $modified_resp
    
}

sub _modify_cache_control_header {
    my $self        = shift;
    my $header      = shift->clone;
    my $directives  = shift;
    
    if ($directives) {
        $header->header('Cache-Control' => $directives) # TODO This is over symplified
    }
    
    return $header;
}

sub _substitute_request_header {
    my $self        = shift;
    my $rqst        = shift;
    my $head        = shift;
    
    # unraffle the HTTP::Request
    my $rqst_method     = $rqst->method;
    my $rqst_uri        = $rqst->uri;
#   my $rqst_headers    = $rqst->headers; # we'll substitute this
    my $rqst_content    = $rqst->content;
    
    return
        !$head ?
            HTTP::Request->new( $rqst_method, $rqst_uri ) :
        !$rqst_content ?
            HTTP::Request->new( $rqst_method, $rqst_uri, $head ) :
            HTTP::Request->new( $rqst_method, $rqst_uri, $head, $rqst_content )
    
}

sub _substitute_response_header {
    my $self        = shift;
    my $resp        = shift;
    my $head        = shift;
    
    # unraffle the HTTP::Request
    my $resp_code       = $resp->code;
    my $resp_msg        = $resp->message;
#   my $resp_headers    = $resp->headers; # we'll substitute this
    my $resp_content    = $resp->content;
    
    return
        !$head ?
            HTTP::Response->new( $resp_code, $resp_msg ) :
        !$resp_content ?
            HTTP::Response->new( $resp_code, $resp_msg, $head ) :
            HTTP::Response->new( $resp_code, $resp_msg, $head, $resp_content )
    
}

1;
