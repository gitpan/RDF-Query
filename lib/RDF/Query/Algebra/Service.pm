# RDF::Query::Algebra::Service
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Service - Algebra class for SERVICE (federation) patterns

=head1 VERSION

This document describes RDF::Query::Algebra::Service version 2.200, released 6 August 2009.

=cut

package RDF::Query::Algebra::Service;

use strict;
use warnings;
use base qw(RDF::Query::Algebra);

use Log::Log4perl;
use URI::Escape;
use MIME::Base64;
use Data::Dumper;
use RDF::Query::Error;
use Carp qw(carp croak confess);
use Scalar::Util qw(blessed reftype);
use Storable qw(store_fd fd_retrieve);
use RDF::Trine::Iterator qw(sgrep smap swatch);

######################################################################

our ($VERSION, $BLOOM_FILTER_ERROR_RATE);
BEGIN {
	$BLOOM_FILTER_ERROR_RATE	= 0.1;
	$VERSION	= '2.200';
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<new ( $endpoint, $pattern )>

Returns a new Service structure.

=cut

sub new {
	my $class		= shift;
	my $endpoint	= shift;
	my $pattern		= shift;
	return bless( [ 'SERVICE', $endpoint, $pattern ], $class );
}

=item C<< construct_args >>

Returns a list of arguments that, passed to this class' constructor,
will produce a clone of this algebra pattern.

=cut

sub construct_args {
	my $self	= shift;
	return ($self->endpoint, $self->pattern);
}

=item C<< endpoint >>

Returns the endpoint resource of the named graph expression.

=cut

sub endpoint {
	my $self	= shift;
	if (@_) {
		my $endpoint	= shift;
		$self->[1]	= $endpoint;
	}
	my $endpoint	= $self->[1];
	return $endpoint;
}

=item C<< pattern >>

Returns the graph pattern of the named graph expression.

=cut

sub pattern {
	my $self	= shift;
	if (@_) {
		my $pattern	= shift;
		$self->[2]	= $pattern;
	}
	return $self->[2];
}

=item C<< add_bloom ( $variable, $filter ) >>

Adds a FILTER to the enclosed GroupGraphPattern to restrict values of the named
C<< $variable >> to the values encoded in the C<< $filter >> (a
L<Bloom::Filter|Bloom::Filter> object).

=cut

sub add_bloom {
	my $self	= shift;
	my $class	= ref($self);
	my $var		= shift;
	my $bloom	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.algebra.service");
	
	unless (blessed($var)) {
		$var	= RDF::Query::Node::Variable->new( $var );
	}
	
	my $pattern	= $self->pattern;
	my $iri		= RDF::Query::Node::Resource->new('http://kasei.us/code/rdf-query/functions/bloom/filter');
	$l->debug("Adding a bloom filter (with " . $bloom->key_count . " items) function to a remote query");
	my $frozen	= $bloom->freeze;
	my $literal	= RDF::Query::Node::Literal->new( $frozen );
	my $expr	= RDF::Query::Expression::Function->new( $iri, $var, $literal );
	my $filter	= RDF::Query::Algebra::Filter->new( $expr, $pattern );
	return $class->new( $self->endpoint, $filter );
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	my $context	= shift;
	my $prefix	= shift || '';
	my $indent	= $context->{indent};
	
	return sprintf(
		"(service\n${prefix}${indent}%s\n${prefix}${indent}%s)",
		$self->endpoint->sse( $context, "${prefix}${indent}" ),
		$self->pattern->sse( $context, "${prefix}${indent}" )
	);
}

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $context	= shift;
	my $indent	= shift;
	my $string	= sprintf(
		"SERVICE %s %s",
		$self->endpoint->as_sparql( $context, $indent ),
		$self->pattern->as_sparql( $context, $indent ),
	);
	return $string;
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'SERVICE';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	my @list	= $self->pattern->referenced_variables;
	return @list;
}

=item C<< definite_variables >>

Returns a list of the variable names that will be bound after evaluating this algebra expression.

=cut

sub definite_variables {
	my $self	= shift;
	return RDF::Query::_uniq(
		map { $_->name } grep { $_->isa('RDF::Query::Node::Variable') } ($self->graph),
		$self->pattern->definite_variables,
	);
}


=item C<< qualify_uris ( \%namespaces, $base ) >>

Returns a new algebra pattern where all referenced Resource nodes representing
QNames (ns:local) are qualified using the supplied %namespaces.

=cut

sub qualify_uris {
	my $self	= shift;
	my $class	= ref($self);
	my $ns		= shift;
	my $base	= shift;
	
	my $pattern	= $self->pattern->qualify_uris( $ns, $base );
	my $endpoint	= $self->endpoint;
	my $uri	= $endpoint->uri;
	return $class->new( $endpoint, $pattern );
}


=item C<< fixup ( $query, $bridge, $base, \%namespaces ) >>

Returns a new pattern that is ready for execution using the given bridge.
This method replaces generic node objects with bridge-native objects.

=cut

sub fixup {
	my $self	= shift;
	my $class	= ref($self);
	my $query	= shift;
	my $bridge	= shift;
	my $base	= shift;
	my $ns		= shift;
	
	if (my $opt = $query->algebra_fixup( $self, $bridge, $base, $ns )) {
		return $opt;
	} else {
		my $endpoint	= ($self->endpoint->isa('RDF::Query::Node'))
					? $bridge->as_native( $self->endpoint )
					: $self->endpoint->fixup( $query, $bridge, $base, $ns );
		my $fpattern	= $self->pattern->fixup( $query, $bridge, $base, $ns );
		my $service		= $class->new( $endpoint, $fpattern );
		
		if ($self->pattern->isa('RDF::Query::Algebra::GroupGraphPattern')) {
			my ($bgp)	= $self->pattern->patterns;
			if ($bgp->isa('RDF::Query::Algebra::BasicGraphPattern')) {
				my $bf	= $bgp->bf;
				$service->[3]{ 'log-service-pattern' }	= $bf;
			}
		}
		return $service;
	}
}

=item C<< execute ( $query, $bridge, \%bound, $context, %args ) >>

=cut

sub execute {
	my $self		= shift;
	my $query		= shift;
	my $bridge		= shift;
	my $bound		= shift;
	my $outer_ctx	= shift;
	my %args		= @_;
	my $l			= Log::Log4perl->get_logger("rdf.query.algebra.service");
	
	if ($outer_ctx) {
		throw RDF::Query::Error::QueryPatternError ( -text => "Can't use nested SERVICE graphs" );
	}

	my $endpoint	= $self->endpoint;
	if (my $log = $query->logger) {
		$log->push_value( service_endpoints => $endpoint->uri_value );
	}
	
	my %ns			= (%{ $query->{parsed}{namespaces} });
	my $trial		= 'k';
	$trial++ while (exists($ns{ $trial }));
	$ns{ $trial }	= 'http://kasei.us/code/rdf-query/functions/bloom/';
	
	my $sparql		= join("\n",
						(map { sprintf("PREFIX %s: <%s>", $_, $ns{$_}) } (keys %ns)),
						sprintf("SELECT * WHERE %s", $self->pattern->as_sparql({namespaces => \%ns}, ''))
					);
	my $url			= $endpoint->uri_value . '?query=' . uri_escape($sparql);
	
	$l->debug("SERVICE REQUEST $endpoint:\n$sparql\n");
	if ($ENV{RDFQUERY_THROW_ON_SERVICE}) {
		warn "SERVICE REQUEST $endpoint:{{{\n$sparql\n}}}\n";
		warn "QUERY LENGTH: " . length($sparql) . "\n";
		warn "QUERY URL: $url\n";
		throw RDF::Query::Error::RequestedInterruptError -text => "Won't execute SERVICE block. Unset RDFQUERY_THROW_ON_SERVICE to continue.";
	}
	
	
	# we jump through some hoops here to defer the actual execution unti the first
	# result is pulled from the stream. this has a slight speed hit in general,
	# but will have a huge benefit when, for example, two service calls are
	# concatenated with a union.
	my $stream;
	my $extra		= {};
	my @vars		= $self->pattern->referenced_variables;
	
	
	$l->debug("forking in $$\n");
	my $pid = open my $fh, "-|";
	die unless defined $pid;
	unless ($pid) {
		$RDF::Trine::Store::DBI::IGNORE_CLEANUP	= 1;
		_get_and_parse_url( $query, $url, $fh, $pid );
		exit 0;
	}
	
	my $count	= 0;
	my $open	= 1;
	my $args	= fd_retrieve $fh or die "I can't read args from file descriptor\n";
	my $sub	= sub {
		return unless ($open);
		my $result = fd_retrieve $fh or die "I can't read from file descriptor\n";
		$l->debug("got result in HEAD: " . Dumper($result));
		if (not($result) or ref($result) ne 'HASH') {
			$l->debug("got \\undef signalling end of stream");
			if (my $log = $query->logger) {
				$log->push_key_value( 'cardinality-service', $self->as_sparql, $count );
				if (my $bf = $self->[3]{ 'log-service-pattern' }) {
					$log->push_key_value( 'cardinality-bf-service-' . $endpoint->uri_value, $bf, $count );
				}
			}
			$open	= 0;
			return;
		}
#		warn "SERVICE returning " . Dumper($result);
		$count++;
		return $result;
	};
	my $results		= RDF::Trine::Iterator::Bindings->new( $sub, @$args );
	
# 	my $ua			= $query->useragent;
# 	my $results		= RDF::Trine::Iterator::Bindings->new( sub {
# 		unless (defined $stream) {
# # 			use IO::Socket::INET;
# # 			my $uri		= URI->new( $url );
# # 			my $canon	= $uri->canonical;
# # 			my $path	= substr($canon, index($canon, $uri->host) + length($uri->host));
# # 			warn $uri->host;
# # 			warn $uri->port;
# # 			my $sock	= IO::Socket::INET->new( PeerAddr => $uri->host, PeerPort => ($uri->port || 80), Proto => 'tcp' );
# # # 			my $req		= sprintf("GET %s HTTP/1.1\nHost: %s\nAccept: application/sparql-results+xml;q=0.9,application/rdf+xml;q=0.5,text/turtle;q=0.7,text/xml\n\n", $path, $uri->host);
# # 			my $req		= sprintf("GET %s HTTP/1.0\nAccept: application/sparql-results+xml;q=0.9,application/rdf+xml;q=0.5,text/turtle;q=0.7,text/xml\n\n", $path, $uri->host);
# # 			warn $req;
# # 			$sock->print( $req );
# # 			
# # 			my $buffer	= '';
# # 			my $prelude	= '';
# # 			while (1) {
# # 				my $b;
# # 				$sock->recv($b, 512);
# # # 				$sock->sysread($b, 512);
# # # 				warn ">>>>>>>>>>>>>>> adding: <<$b>>\n";
# # 				$buffer	.= $b;
# # 				if ($buffer =~ m/(?:\r?\n){2}(.*)$/ms) {
# # 					$prelude	= $1;
# # 					warn "##############\nGOT HEADER:\n$buffer\n##############\n";
# # 					warn "PRELUDE:\n$prelude\n##############\n";
# # 					last;
# # 				}
# # 			}
# # 			
# # 			$stream		= RDF::Trine::Iterator->from_handle_incremental( $sock, 2048, $prelude );
# 			
# 			my $resp	= $ua->get( $url );
# 			unless ($resp->is_success) {
# 				throw RDF::Query::Error -text => "SERVICE query couldn't get remote content: " . $resp->status_line;
# 			}
# 			my $content	= $resp->content;
# 			warn '>>>>>>>>' . $content . '<<<<<<<<<<<<<' if ($debug);
# 			$stream		= RDF::Trine::Iterator->from_string( $content );
# 			
# 			if (my $e = $stream->extra_result_data) {
# 				%$extra	= %$e;
# 			}
# 		}
# 		
# 		return $stream->next;
# 	}, \@vars, extra_result_data => $extra );
	
	my $cast		= smap {
						my $bindings	= $_;
						return undef unless ($bindings);
						my %cast	= map {
										$_ => RDF::Query::Model::RDFTrine::_cast_to_local( $bindings->{ $_ } )
									} (keys %$bindings);
						return \%cast;
					} $results;
	return $cast;
}

sub _get_and_parse_url {
	my $query	= shift;
	my $url		= shift;
	my $fh		= shift;
	my $pid		= shift;
#	warn "forked child retrieving content from $url";
	
	eval "
		require XML::SAX::Expat;
		require XML::SAX::Expat::Incremental;
	";
	if ($@) {
		die $@;
	}
	local($XML::SAX::ParserPackage)	= 'XML::SAX::Expat::Incremental';
	my $handler	= RDF::Trine::Iterator::SAXHandler->new();
	my $p	= XML::SAX::Expat::Incremental->new( Handler => $handler );
	$p->parse_start;
	
	my $has_head	= 0;
	my $callback	= sub {
		my $content	= shift;
		my $resp	= shift;
		my $proto	= shift;
#		warn ("got content in $$: " . Dumper($content));
		unless ($resp->is_success) {
			throw RDF::Query::Error -text => "SERVICE query couldn't get remote content: " . $resp->status_line;
		}
		$p->parse_more( $content );
		
		if (not($has_head) and $handler->has_head) {
			my @args	= $handler->iterator_args;
			if (exists( $args[2]{Handler} )) {
				delete $args[2]{Handler};
			}
#			warn ("got args in child: " . Dumper(\@args));
			$has_head	= 1;
			store_fd \@args, \*STDOUT or die "PID $pid can't store!\n";
		}
		
		while (my $data = $handler->pull_result) {
#			warn ("got result in child: " . Dumper($data));
			store_fd $data, \*STDOUT or die "PID $pid can't store!\n";
		}
	};
	my $ua			= $query->useragent;
	$ua->get( $url, ':content_cb' => $callback );
	store_fd \undef, \*STDOUT;
}





=item C<< bloom_filter_for_iterator ( $query, $bridge, $bound, $iterator, $variable, $error ) >>

Returns a Bloom::Filter object containing the Resource and Literal
values that are bound to $variable in the $iterator's data.

=cut

sub bloom_filter_for_iterator {
	my $class	= shift;
	my $query	= shift;
	my $bridge	= shift;
	my $bound	= shift;
	my $iter	= shift;
	my $var		= shift;
	my $error	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.algebra.service");
	
	my $name	= blessed($var) ? $var->name : $var;
	
	my @names;
	my %paths;
	my $node_count	= 0;
	while (my $result = $iter->next) {
		$node_count++;
		my $node	= $result->{ $name };
		push(@names, $class->_names_for_node( $node, $query, $bridge, $bound, \%paths, 0 ));
	}

	my $count	= scalar(@names);
	my $filter	= Bloom::Filter->new( capacity => $count, error_rate => $error );
	if ($l->is_debug) {
		$l->debug($_);
	}
	$filter->add( $_ ) for (@names);
	
	if ($l->is_debug) {
		$l->debug("$node_count total nodes considered");
		$l->debug( "Bloom filter has $count total items");
		my @paths	= keys %paths;
		$l->debug("PATHS:\n" . join("\n", @paths));
	}
	$iter->reset;
	return $filter;
}

sub _names_for_node {
	my $class	= shift;
	my $node	= shift;
	my $query	= shift;
	my $bridge	= shift;
	my $bound	= shift;
	my $paths	= shift;
	my $depth	= shift || 0;
	my $pre		= shift || '';
	my $seen	= shift || {};
	return if ($depth > 2);
	my $l		= Log::Log4perl->get_logger("rdf.query.algebra.service");
	
	my $nodestring	= $node->as_string;
	
	my $context	= RDF::Query::ExecutionContext->new(
					bound	=> $bound,
					model	=> $bridge,
				);
	if (not exists($seen->{ $nodestring })) {
		$l->debug("  " x $depth . "name for node " . $nodestring . "...");
		my @names;
		my $parser	= RDF::Query::Parser::SPARQL->new();
		unless ($node->isa('RDF::Trine::Node::Literal')) {
			{
				our $sa		||= $parser->parse_pattern( '{ ?n <http://www.w3.org/2002/07/owl#sameAs> ?o }' );
				my ($plan)	= RDF::Query::Plan->generate_plans( $sa, $context );
				local($context->bound->{n})	= $node;
				$plan->execute( $context );
				while (my $row = $plan->next) {
					my ($n, $o)	= @{ $row }{qw(n o)};
					push(@names, $class->_names_for_node( $o, $query, $bridge, $bound, $paths, $depth + 1, $pre . '=', $seen ));
				}
			}
			
			{
				our $fp		||= $parser->parse_pattern( '{ ?o ?p ?n . ?p a <http://www.w3.org/2002/07/owl#FunctionalProperty> }' );
				my ($plan)	= RDF::Query::Plan->generate_plans( $fp, $context );
				local($context->bound->{n})	= $node;
				$plan->execute( $context );
				while (my $row = $plan->next) {
					my ($p, $o)	= @{ $row }{qw(p o)};
					push(@names, $class->_names_for_node( $o, $query, $bridge, $bound, $paths, $depth + 1, $pre . '^' . $p->sse, $seen ));
				}
			}
			
			{
				our $ifp	||= $parser->parse_pattern( '{ ?n ?p ?o . ?p a <http://www.w3.org/2002/07/owl#InverseFunctionalProperty> }' );
				my ($plan)	= RDF::Query::Plan->generate_plans( $ifp, $context );
				local($context->bound->{n})	= $node;
				$plan->execute( $context );
				while (my $row = $plan->next) {
					my ($p, $o)	= @{ $row }{qw(p o)};
					push(@names, $class->_names_for_node( $o, $query, $bridge, $bound, $paths, $depth + 1, $pre . '!' . $p->sse, $seen ));
				}
			}
		}
		
		unless ($node->isa('RDF::Trine::Node::Blank')) {
			$paths->{ $pre }++;
			my $string		= $pre . $nodestring;
			push(@names, $string);
		}
		
		@{ $seen->{ $nodestring } }{ @names }	= @names;
	} else {
		$l->debug("identity names for node have been computed before");
	}
	
	my @names	= values %{ $seen->{ $nodestring } };
	$l->debug("  " x $depth . "-> " . join(', ', @names) . "\n");
	return @names;
}


1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
