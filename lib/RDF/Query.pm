# RDF::Query
# -------------
# $Revision: 127 $
# $Date: 2006-02-08 14:53:21 -0500 (Wed, 08 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query - An RDF query implementation of SPARQL/RDQL in Perl for use with RDF::Redland and RDF::Core.

=head1 VERSION

This document describes RDF::Query version 1.031

=head1 SYNOPSIS

 my $query = new RDF::Query ( $rdql, undef, undef, 'rdql' );
 my @rows = $query->execute( $model );
 
 my $query = new RDF::Query ( $sparql, undef, undef, 'sparql' );
 my $iterator = $query->execute( $model );
 while (my $row = $iterator->()) {
   ...
 }

=head1 DESCRIPTION

RDF::Query allows RDQL and SPARQL queries to be run against an RDF model, returning rows
of matching results.

See L<http://www.w3.org/TR/rdf-sparql-query/> for more information on SPARQL.
See L<http://www.w3.org/Submission/2004/SUBM-RDQL-20040109/> for more information on RDQL.

=head1 REQUIRES

L<RDF::Redland|RDF::Redland> or L<RDF::Core|RDF::Core>

L<Parse::RecDescent|Parse::RecDescent>

L<LWP::Simple|LWP::Simple>

L<DateTime::Format::W3CDTF>

=cut

package RDF::Query;

use strict;
use warnings;
use Carp qw(carp croak confess);

use Data::Dumper;
use LWP::Simple ();

use RDF::Query::Stream;

use RDF::Query::Model::DBI;
use RDF::Query::Model::Redland;
use RDF::Query::Model::RDFCore;

use RDF::Query::Parser::RDQL;
use RDF::Query::Parser::SPARQL;

######################################################################

our ($REVISION, $VERSION, $debug);
BEGIN {
	$debug		= 0;
	$REVISION	= do { my $REV = (qw$Revision: 127 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$VERSION	= 1.031;
}

######################################################################

=head1 METHODS

=over 4

=item C<new ( $query, $baseuri, $languri, $lang )>

Returns a new RDF::Query object for the query specified.
The query language used will be set if $languri or $lang
is passed as the URI or name of the query language, otherwise
the query defaults to SPARQL.

=cut
sub new {
	my $class	= shift;
	my ($query, $baseuri, $languri, $lang)	= @_;
	my $self 	= bless( {}, $class );
	no warnings 'uninitialized';
	my $parser	= ($lang eq 'rdql' or $languri eq 'http://jena.hpl.hp.com/2003/07/query/RDQL')
				? RDF::Query::Parser::RDQL->new()
				: RDF::Query::Parser::SPARQL->new();
	$self->{parser}	= $parser;
	my $parsed		= $parser->parse( $query );
	$self->{parsed}	= $parsed;
	unless ($parsed->{'triples'} and scalar(@{ $parsed->{'triples'} })) {
		if ($debug) {
			warn "*** Failed to parse. Parse trace follows:\n\n";
			local($::RD_TRACE)	= 1;
			local($::RD_HINT)	= 1;
			$parser->parse( $query );
		}
		return undef;
	}
	$self->{parsed}{namespaces}{rdf}	= 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
	return $self;
}

=item C<get ( $model )>

Executes the query using the specified model,
and returns the first row found.

=cut
sub get {
	my $self	= shift;
	my $stream	= $self->execute( @_ );
	if ($stream) {
		my $row		= $stream->();
		if (ref($row)) {
			return @{ $row };
		}
	}
	return undef;
}

=item C<execute ( $model )>

Executes the query using the specified model. If called in a list
context, returns an array of rows, otherwise returns an iterator.

=cut
sub execute {
	my $self	= shift;
	my $model	= shift;
	
	my $bridge	= $self->get_bridge( $model );
	
	$self->{model}		= $model;
	$self->{bridge}		= $bridge;
	
	my $parser	= $self->{parser};
	my $parsed	= $self->fixup( $self->{parsed} );
	my $stream	= $self->query_more( bound => {}, triples => [@{ $parsed->{'triples'} }] );
	_debug( "got stream: $stream" );
	$stream		= RDF::Query::Stream->new(
					$self->sort_rows( $stream, $parsed ),
					'bindings',
					[ $self->variables() ],
					bridge	=> $bridge
				);
	if ($parsed->{'method'} eq 'DESCRIBE') {
		$stream	= $self->describe( $stream );
	} elsif ($parsed->{'method'} eq 'CONSTRUCT') {
		$stream	= $self->construct( $stream );
	} elsif ($parsed->{'method'} eq 'ASK') {
		$stream	= $self->ask( $stream );
	}
	
	if (wantarray) {
		return $stream->get_all();
	} else {
		return $stream;
	}
}

sub describe {
	my $self	= shift;
	my $stream	= shift;
	my $bridge	= $self->bridge;
	my @nodes;
	my %seen;
	while ($stream and not $stream->finished) {
		my $row	= $stream->current;
		foreach my $node (@$row) {
			unless ($seen{ $bridge->as_string( $node ) }++) {
				push(@nodes, $node);
			}
		}
	} continue {
		$stream->next;
	}
	
	my @streams;
	$self->{'describe_nodes'}	= [];
	foreach my $node (@nodes) {
		push(@{ $self->{'describe_nodes'} }, $node);
		push(@streams, $bridge->get_statements( $node, undef, undef ));
		push(@streams, $bridge->get_statements( undef, undef, $node ));
	}
	
	my $ret	= sub {
		while (@streams) {
			my $val	= $streams[0]->current;
			if (defined $val) {
				$streams[0]->next;
				return $val;
			} else {
				shift(@streams);
				return undef unless (@streams);
			}
		}
	};
	return RDF::Query::Stream->new( $ret, 'graph', undef, bridge => $bridge );
}

sub construct {
	my $self	= shift;
	my $stream	= shift;
	my $bridge	= $self->bridge;
	my @streams;
	
	my %seen;
	my %variable_map;
	my %blank_map;
	foreach my $var_count (0 .. $#{ $self->parsed->{'variables'} }) {
		$variable_map{ $self->parsed->{'variables'}[ $var_count ][1] }	= $var_count;
	}
	
	while ($stream and not $stream->finished) {
		my $row	= $stream->current;
		my @triples;
		foreach my $triple (@{ $self->parsed->{'construct_triples'} }) {
			my @triple	= @{ $triple };
			for my $i (0 .. 2) {
				if (UNIVERSAL::isa($triple[$i], 'ARRAY')) {
					if ($triple[$i][0] eq 'VAR') {
						$triple[$i]	= $row->[ $variable_map{ $triple[$i][1] } ];
					} elsif ($triple[$i][0] eq 'BLANK') {
						unless (exists($blank_map{ $triple[$i][1] })) {
							$blank_map{ $triple[$i][1] }	= $self->bridge->new_blank();
						}
						$triple[$i]	= $blank_map{ $triple[$i][1] };
					}
				}
			}
			push(@triples, $bridge->new_statement( @triple ));
		}
		push(@streams, RDF::Query::Stream->new( sub { shift(@triples) } ));
	} continue {
		$stream->next;
	}
	
	
	my $ret	= sub {
		while (@streams) {
			if ($streams[0]->open and $streams[0]->finished) {
				shift(@streams);
			} else {
				$streams[0]->next;
				my $val	= $streams[0]->current;
				return $val if (defined $val);
			}
		}
		return undef;
	};
	return RDF::Query::Stream->new( $ret, 'graph', undef, bridge => $bridge );
}

sub ask {
	my $self	= shift;
	my $stream	= shift;
	return RDF::Query::Stream->new( $stream, 'boolean', undef, bridge => $self->bridge );
}

######################################################################

sub supports {
	my $self	= shift;
	my $model	= shift;
	my $bridge	= $self->get_bridge( $model );
	return $bridge->supports( @_ );
}

sub set_named_graph_query {
	my $self	= shift;
	my $bridge	= $self->new_bridge();
	_debug( "Replacing model bridge with a new (empty) one for a named graph query" );
	$self->{bridge}	= $bridge;
}

sub new_bridge {
	my $self	= shift;
	
	eval "use RDF::Redland;";
	if (not $@) {
		require RDF::Query::Model::Redland;
		my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory',contexts='yes'");
		my $model	= new RDF::Redland::Model($storage, "");
		my $bridge	= RDF::Query::Model::Redland->new( $model );
		return $bridge;
	}
	
	eval "use RDF::Core;";
	if (not $@) {
		require RDF::Query::Model::RDFCore;
		my $storage	= new RDF::Core::Storage::Memory;
		my $model	= new RDF::Core::Model (Storage => $storage);
		my $bridge	= RDF::Query::Model::RDFCore->new( $model );
		return $bridge;
	}
	
	return undef;
}

sub get_bridge {
	my $self	= shift;
	my $model	= shift;
	
	my $bridge;
	
	if (not $model) {
		$bridge	= $self->new_bridge();
	} elsif (UNIVERSAL::isa($model, 'RDF::Redland::Model')) {
		require RDF::Query::Model::Redland;
		$bridge	= RDF::Query::Model::Redland->new( $model );
	} elsif (UNIVERSAL::isa($model, 'ARRAY') and UNIVERSAL::isa($model->[0], 'DBI::db')) {
		require RDF::Query::Model::DBI;
		$bridge	= RDF::Query::Model::DBI->new( $model );
	} else {
		require RDF::Query::Model::RDFCore;
		$bridge	= RDF::Query::Model::RDFCore->new( $model );
	}
	
	return $bridge;
}

sub fixup {
	my $self		= shift;
	my $parsed		= shift;
	my $bridge		= $self->{bridge};
	
	my %known_variables;
	
	## LOAD ANY EXTERNAL RDF FILES
	my $sources	= $parsed->{'sources'};
	if (UNIVERSAL::isa( $sources, 'ARRAY' )) { # and scalar(@{ $sources })) {
		my $named_query	= 0;
		foreach my $source (@{ $sources }) {
			my $named_source	= (3 == @{$source} and $source->[2] eq 'NAMED');
			if ($named_source and not $named_query) {
				$named_query++;
				$self->set_named_graph_query();
				$bridge		= $self->{bridge};
				unless ($bridge->supports( 'named_graph' )) {
					die "This RDF model does not support named graphs.";
				}
			}
			
			$self->parse_url( $source->[1], $named_source );
		}
	}
	
	## CONVERT URIs to Resources, and strings to Literals
	my @triples	= @{ $parsed->{'triples'} || [] };
	while (my $triple = shift(@triples)) {
		if ($triple->[0] eq 'OPTIONAL') {
			push(@triples, @{$triple->[1]});
		} elsif ($triple->[0] eq 'GRAPH') {
			push(@triples, @{$triple->[2]});
			if ($triple->[1][0] eq 'URI') {
				$triple->[1]	= $bridge->new_resource( $triple->[1][1] );
			}
		} elsif ($triple->[0] eq 'UNION') {
			push(@triples, @{$triple->[1]});
			push(@triples, @{$triple->[2]});
		} else {
			my @vars	= map { $_->[1] } grep { UNIVERSAL::isa($_,'ARRAY') and $_->[0] eq 'VAR' } @{ $triple };
			foreach my $var (@vars) {
				$known_variables{ $var }++
			}
			$self->fixup_triple_bridge_variables( $triple );
		}
	}
	
	## SELECT * implies selecting all known variables
	no warnings 'uninitialized';
	if ($parsed->{variables}[0] eq '*') {
		$parsed->{variables}	= [ map { ['VAR', $_] } (keys %known_variables) ];
	}
	
	
	## FULLY QUALIFY URIs IN CONSTRAINTS
	if (ref($parsed->{'constraints'})) {
		my @constraints	= $parsed->{'constraints'};
		while (my $data = shift @constraints) {
			_debug( "FIXING CONSTRAINT DATA: " . Dumper($data), 2 );
			if (UNIVERSAL::isa($data, 'ARRAY')) {
				my ($op, $rest)	= @{ $data };
				if ($op and $op eq 'URI') {
					$data->[1]	= $self->qualify_uri( $data );
					_debug( "FIXED: " . $data->[1], 2 );
				}
				push(@constraints, @{ $data }[1 .. $#{ $data }]);
			}
		}
		_debug( 'filters: ' . Dumper($parsed->{'constraints'}), 2 );
	}
	
	## DEFAULT METHOD TO 'SELECT'
	$parsed->{'method'}	||= 'SELECT';
	
	## CONSTRUCT HAS IMPLICIT VARIABLES
	if ($parsed->{'method'} eq 'CONSTRUCT') {
		my %seen;
		foreach my $triple (@{ $parsed->{'construct_triples'} }) {
			$self->fixup_triple_bridge_variables( $triple );
		}
		foreach my $triple (@{ $parsed->{triples} }) {
			my @nodes	= @{ $triple };
			foreach my $node (@nodes) {
				if (UNIVERSAL::isa($node, 'ARRAY') and $node->[0] eq 'VAR') {
					push(@{ $parsed->{'variables'} }, ['VAR', $node->[1]]) unless ($seen{$node->[1]}++);
				}
			}
		}
	}
	
	return $parsed;
}

sub fixup_triple_bridge_variables {
	my $self	= shift;
	my $triple	= shift;
	my ($sub,$pred,$obj)	= @{ $triple };
	if (UNIVERSAL::isa($pred, 'ARRAY') and $pred->[0] eq 'URI') {
		my $preduri		= $self->qualify_uri( $pred );
		$triple->[1]	= $self->bridge->new_resource($preduri);
	}
	
	if (UNIVERSAL::isa($sub, 'ARRAY') and $sub->[0] eq 'URI') {
		my $resource	= $self->qualify_uri( $sub );
		$triple->[0]	= $self->bridge->new_resource($resource);
# 	} elsif ($sub->[0] eq 'LITERAL') {
# 		my $literal		= $self->bridge->new_literal($sub->[1]);
# 		$triple->[0]	= $literal;
	}
	
# XXX THIS CONDITIONAL SHOULD ALWAYS BE TRUE ... ? (IT IS IN ALL TEST CASES)
#	if (ref($obj)) {
		if (UNIVERSAL::isa($obj, 'ARRAY') and $obj->[0] eq 'LITERAL') {
			if (UNIVERSAL::isa($obj->[3], 'ARRAY') and $obj->[3][0] eq 'URI') {
				$obj->[3]	= $self->qualify_uri( $obj->[3] );
			}
			my $literal		= $self->bridge->new_literal(@{$obj}[ 1 .. $#{$obj} ]);
			$triple->[2]	= $literal;
		} elsif (UNIVERSAL::isa($obj, 'ARRAY') and $obj->[0] eq 'URI') {
			my $resource	= $self->qualify_uri( $obj );
			$triple->[2]	= $self->bridge->new_resource($resource);
		}
#	} else {
#		warn "Object not a reference: " . Dumper($obj) . ' ';
#	}
}

=for private

=item C<query_more ( bound => $bound, triples => \@triples )>

Internal recursive query function to bind pivot variables until only result
variables are left and found from the RDF store. Called from C<query>.

=end private

=cut
sub query_more {
	my $self	= shift;
	my %args	= @_;
	
	my $bound	= delete($args{bound});
	my $triples	= delete($args{triples});
	my $context	= $args{context};
	
	my @triples	= @{$triples};
	if ($debug > 0.1) {
		warn 'query_more: ' . Data::Dumper->Dump([\@triples, $bound], [qw(triples bound)]);
		warn "with context: " . Dumper($context) if ($context);
	}
	our $indent;

	my $parsed		= $self->parsed;
	my $bridge		= $self->bridge;
	
	if ($triples[0][0] eq 'OPTIONAL') {
		return $self->optional( bound => $bound, triples => \@triples, %args );
	} elsif ($triples[0][0] eq 'GRAPH') {
		if ($context) {
			die "Can't use nested named graphs";
		} else {
			return $self->named_graph( bound => $bound, triples => \@triples );
		}
	} elsif ($triples[0][0] eq 'UNION') {
		return $self->union( bound => $bound, triples => \@triples, %args );
	}
	
	my $triple		= shift(@triples);
	unless (ref($triple)) {
		carp "Something went wrong. No triple passed to query_more";
		return undef;
	}
	my @triple		= @{ $triple };
	
	no warnings 'uninitialized';
	_debug( "${indent}query_more: " . join(' ', map { (($bridge->isa_node($_)) ? '<' . $bridge->as_string($_) . '>' : $_->[1]) } @triple) . "\n" );
	_debug( "${indent}-> with " . scalar(@triples) . " triples to go\n" );
	_debug( "${indent}-> more: " . (($_->[0] =~ m/^(OPTIONAL|GRAPH)$/) ? "$1 block" : join(' ', map { $bridge->isa_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
	
	my $vars	= 0;
	my ($var, $method);
	my (@vars, @methods);
	
	my @methodmap	= $bridge->statement_method_map;
	for my $idx (0 .. 2) {
		_debug( "looking at triple " . $methodmap[ $idx ] );
		my $data	= $triple[$idx];
		if (UNIVERSAL::isa($data, 'ARRAY')) {	# and $data->[0] eq 'VAR'
			if ($data->[0] eq 'VAR' or $data->[0] eq 'BLANK') {
				my $tmpvar	= ($data->[0] eq 'VAR') ? $data->[1] : '_' . $data->[1];
				my $val		= $bound->{ $tmpvar };
				if ($bridge->isa_node($val)) {
					_debug( "${indent}-> already have value for $tmpvar: " . $bridge->as_string( $val ) . "\n" );
					$triple[$idx]	= $val;
				} elsif (++$vars > 2) {
					_debug( "${indent}-> we've seen $vars variables in this triple... punt\n" );
					if (1 + $self->{punt} >= scalar(@{$self->{parsed}{triples}})) {
						_debug( "${indent}-> we've punted too many times. binding on ?$tmpvar" );
						$triple[$idx]	= undef;
						$vars[$idx]		= $tmpvar;
						$methods[$idx]	= $methodmap[ $idx ];
					} elsif (scalar(@triples)) {
						$self->{punt}++;
						push(@triples, $triple);
						return $self->query_more( bound => { %{ $bound } }, triples => [@triples] );
					} else {
						carp "Something went wrong. Not enough triples passed to query_more";
						return undef;
					}
				} else {
					_debug( "${indent}-> found variable $tmpvar (we've seen $vars variables already)\n" );
					$triple[$idx]	= undef;
					$vars[$idx]		= $tmpvar;
					$methods[$idx]	= $methodmap[ $idx ];
				}
			}
		}
	}
	
	_debug( "${indent}getting: " . join(', ', grep defined, @vars) . "\n" );
	_debug( 'query_more triple: ' . Dumper([map { ($_) ? $bridge->as_string($_) : 'undef' } (@triple, (($bridge->isa_node($context)) ? $context : ()))]) );
	
	my @streams;
	my $stream;
	
	my @graph;
	if (UNIVERSAL::isa($context, 'ARRAY') and ($context->[0] eq 'VAR')) {
		my $context_var	= $context->[1];
		my $graph		= $bound->{ $context_var };
		if ($graph) {
			@graph	= $graph;
		}
	} elsif ($bridge->isa_node( $context )) {
		@graph	= $context;
	}
	
	
	
#	my @graph		= (($bridge->isa_node($context)) ? $context : ());
	my $statments	= $bridge->get_statements( @triple, @graph );
	if ($statments) {
		push(@streams, sub {
			my $result;
			_debug_closure( $statments );
			my $stmt	= $statments->current();
			unless ($stmt) {
				_debug( 'no more statements' );
				$statments	= undef;
				return undef;
			}
			
			my $context_var;
			if (UNIVERSAL::isa($context, 'ARRAY') and ($context->[0] eq 'VAR')) {
				warn "Trying to get context of current statement..." if ($debug);
				my $graph	= $statments->context;
				if ($graph) {
					$context_var				= $context->[1];
					$bound->{ $context_var }	= $graph;
#					$context					= $graph;
					warn "Got context ($context_var) from iterator: " . $bridge->as_string( $graph ) if ($debug);
				} else {
					warn "No context returned by iterator." if ($debug);
				}
			}
			
			$statments->next;
			if ($vars) {
				my %private_bound;
				foreach (0 .. $#vars) {
					_debug( "looking at variable $_" );
					next unless defined($vars[$_]);
					my $var		= $vars[ $_ ];
					my $method	= $methods[ $_ ];
					_debug( "${indent}-> got variable $var = " . $bridge->as_string( $stmt->$method() ) . "\n" );
					if (defined($private_bound{$var})) {
						_debug( "${indent}-> uh oh. $var has been defined more than once.\n" );
						if ($bridge->as_string( $stmt->$method() ) eq $bridge->as_string( $private_bound{$var} )) {
							_debug( "${indent}-> the two values match. problem avoided.\n" );
						} else {
							_debug( "${indent}-> the two values don't match. this triple won't work.\n" );
							_debug( "${indent}-> the existing value is" . $bridge->as_string( $private_bound{$var} ) . "\n" );
							return ();
						}
					} else {
						$private_bound{ $var }	= $stmt->$method();
					}
				}
				@{ $bound }{ keys %private_bound }	= values %private_bound;
			} else {
				_debug( "${indent}-> triple with no variable. ignoring.\n" );
			}
			
			if (scalar(@triples)) {
				_debug( "${indent}-> now for more triples...\n" );
				_debug( "${indent}-> more: " . (($_->[0] eq 'OPTIONAL') ? 'OPTIONAL block' : join(' ', map { $bridge->isa_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
				_debug( "${indent}-> " . Dumper(\@triples) );
				$indent	.= '  ';
				_debug( 'adding a new stream for more triples' );
				unshift(@streams, $self->query_more( bound => { %{ $bound } }, triples => [@triples], ($context ? (context => $context ) : ()) ) );
			} else {
				my @values	= map { $bound->{$_} } $self->variables();
				_debug( "${indent}-> no triples left: result: " . join(', ', map {$bridge->as_string($_)} grep defined, @values) . "\n" );
				if ($self->check_constraints( $bound, $parsed->{'constraints'} )) {
					my @values	= map { $bound->{$_} } $self->variables();
					$result	= [@values];
				} else {
					_debug( "${indent}-> failed constraints check\n" );
				}
			}
			
			foreach my $var (@vars) {
				if (defined($var)) {
					_debug( "deleting value for $var" );
					delete $bound->{ $var };
				}
			}
			
			if ($context_var) {
				_debug( "deleting value for $context_var" );
				delete $bound->{ $context_var };
			}
			
			if ($result) {
				local($Data::Dumper::Indent)	= 0;
				_debug( 'found a result: ' . Dumper($result) );
				return ($result);
			} else {
				_debug( 'no results yet...' );
				return ();
			}
		} );
	}
	
	substr($indent, -2, 2)	= '';
	
	return sub {
		_debug( 'query_more closure with ' . scalar(@streams) . ' streams' );
		while (@streams) {
			_debug( '-> fetching from stream ' . $streams[0] );
			_debug_closure( $streams[0] );
			
			my @val	= $streams[0]->();
			_debug( '-> ' . (@val ? 'got' : 'no') . ' value' );
			if (@val) {
				_debug( '-> "' . $val[0] . '"', 1, 1);
				if (defined $val[0]) {
					return $val[0];
				}
			} else {
				_debug( '-> no value returned from stream. using next stream.', 1);
				next;
			}
			shift(@streams);
		}

		_debug( '-> no more streams.', 1);
		return undef;
	};	
}

sub union {
	my $self		= shift;
	my %args	= @_;
	
	my $bound	= delete($args{bound});
	my $triples	= delete($args{triples});
	my $context	= $args{context};
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my $parsed		= $self->parsed;
	my @streams;
	foreach my $u_triples (@{ $triple }[1 .. $#{$triple}]) {
		my $stream	= $self->query_more( bound => { %{ $bound } }, triples => [@{ $u_triples }, @triples], %args );
		push(@streams, $stream);
	}
	return sub {
		while (@streams) {
			_debug_closure( $streams[0] );
			my @val	= $streams[0]->();
			if (@val) {
				return $val[0] if defined($val[0]);
			} else {
				next;
			}
			shift(@streams);
		}
		return undef;
	};	
}

sub optional {
	my $self		= shift;
	my %args	= @_;
	
	my $bound	= delete($args{bound});
	my $triples	= delete($args{triples});
	my $context	= $args{context};
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my $parsed		= $self->parsed;
	
	my @triple		= @{ $triple };
	my @opt_triples	= @{ $triple[1] };
	_debug( 'optional triples: ' . Dumper(\@opt_triples), 2 );
	my $ostream	= $self->query_more( bound => { %{ $bound } }, triples => [@opt_triples], %args );
	$ostream	= RDF::Query::Stream->new(
					$ostream,
					'bindings',
					[ $self->variables() ],
					bridge => $self->bridge
				);
	if ($ostream and not $ostream->finished) {
		_debug( 'got optional stream' );
		if (@triples) {
			_debug( "with more triples to match." );
			my $stream;
			return sub {
				while ($ostream and not $ostream->finished) {
					if (ref($stream)) {
						my $data	= $stream->();
						return $data;
					}
					
					foreach my $i (0 .. $ostream->bindings_count - 1) {
						my $name	= $ostream->binding_name( $i );
						my $value	= $ostream->binding_value( $i );
						if (defined $value) {
							$bound->{ $name }	= $value;
							_debug( "Setting $name = $value\n" );
						}
					}
					$stream	= $self->query_more( bound => { %{ $bound } }, triples => [@triples] );
				}
				return undef;
			};
		} else {
			_debug( "No more triples. Returning OPTIONAL stream." );
			if ($self->check_constraints( $bound, $parsed->{'constraints'} )) {
				return sub {
					return undef unless ($ostream and not $ostream->finished);
					my $data	= $ostream->current;
					$ostream->next;
					return $data;
				};
			} else {
				_debug( "failed constraints check\n" );
			}
		}
	} else {
		_debug( "OPTIONAL block failed" );
		if (@triples) {
			_debug( "More triples. Re-dispatching" );
			return $self->query_more( bound => { %{ $bound } }, triples => [@triples] );
		} else {
			_debug( "No more triples. Returning empty results." );
			my @vars	= $self->variables;
			my @values	= map { $bound->{$_} } $self->variables();
			my @results	= [@values];
			my $stream;
			$stream	= sub {
						while (@results) {
							my $result	= shift(@results);
							my %bound;
							@bound{ @vars }	= @$result;
							if ($self->check_constraints( \%bound, $parsed->{'constraints'} )) {
								return $result;
							}
						}
					};
			return $stream;
		}
	}
}

sub named_graph {
	my $self		= shift;
	my %args	= @_;
	
	my $bound	= { %{ delete($args{bound}) } };
	my $triples	= delete($args{triples});
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my $parsed		= $self->parsed;
	
	my (undef, $context, $named_triples)	= @{ $triple };
	my @named_triples	= @{ $named_triples };
	
#	local($debug)	= 1;
	_debug( 'named triples: ' . Dumper(\@named_triples), 1 );
	my $variables	= [ $self->variables ];
	my $nstream	= $self->query_more( bound => $bound, triples => \@named_triples, context => $context );
	
	_debug( 'named stream: ' . $nstream, 1 );
	_debug_closure( $nstream );
	
	if ($nstream) {
		_debug( 'got named stream' );
		if (@triples) {
			_debug( "with more triples to match." );
			my $stream;
			return sub {
				while ($nstream or $stream) {
					if (ref($stream)) {
						my $data	= $stream->();
						if ($data) {
							return $data;
						} else {
							undef $stream;
						}
					}
					
					if ($nstream) {
						my $data	= $nstream->();
						if ($data) {
							foreach my $i (0 .. $#{ $variables }) {
								my $name	= $variables->[ $i ];
								my $value	= $data->[ $i ];
								if (defined $value) {
									$bound->{ $name }	= $value;
									_debug( "Setting $name from named graph = $value\n" );
								}
							}
							$stream	= $self->query_more( bound => $bound, triples => \@triples );
						} else {
							undef $nstream;
						}
					}
				}
				return undef;
			};
		} else {
			_debug( "No more triples. Returning NAMED stream." );
			return $nstream;
		}
	} else {
		_debug( "NAMED block failed" );
		if (@triples) {
			_debug( "More triples. Re-dispatching" );
			return $self->query_more( bound => $bound, triples => \@triples );
		} else {
			_debug( "No more triples. Returning empty results." );
			my @vars	= $self->variables;
			my @values	= map { $bound->{$_} } $self->variables();
			my @results	= [@values];
			my $stream;
			$stream	= sub {
						while (@results) {
							my $result	= shift(@results);
							my %bound;
							@bound{ @vars }	= @$result;
							if ($self->check_constraints( \%bound, $parsed->{'constraints'} )) {
								return $result;
							}
						}
					};
			return $stream;
		}
	}
}

sub qualify_uri {
	my $self	= shift;
	my $data	= shift;
	my $parsed	= $self->{parsed};
	my $uri;
	if (ref($data->[1])) {
		my $prefix	= $data->[1][0];
		unless (exists($parsed->{'namespaces'}{$data->[1][0]})) {
			_debug( "No namespace defined for prefix '${prefix}'" );
		}
		my $ns	= $parsed->{'namespaces'}{$prefix};
		$uri	= join('', $ns, $data->[1][1]);
	} else {
		$uri	= $data->[1];
	}
	
	return $uri;
}

{
no warnings 'numeric';
my %dispatch	= (
					VAR		=> sub { my ($self, $values, $data) = @_; return $self->get_value( $values->{ $data->[0] } ) },
					URI		=> sub { my ($self, $values, $data) = @_; return $data->[0] },
					LITERAL	=> sub { my ($self, $values, $data) = @_; return $data->[0] },
					'~~'	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] =~ /$operands[1]/) },
					'=='	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return ncmp($operands[0], $operands[1]) == 0 },
					'!='	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return ncmp($operands[0], $operands[1]) != 0 },
					'<'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return ncmp($operands[0], $operands[1]) == -1 },
					'>'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return ncmp($operands[0], $operands[1]) == 1 },
					'<='	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return ncmp($operands[0], $operands[1]) != 1 },
					'>='	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return ncmp($operands[0], $operands[1]) != -1 },
					'&&'	=> sub { my ($self, $values, $data) = @_; foreach my $part (@{ $data }) { return 0 unless $self->check_constraints( $values, $part ); } return 1 },
					'||'	=> sub { my ($self, $values, $data) = @_; foreach my $part (@{ $data }) { return 1 if $self->check_constraints( $values, $part ); } return 0 },
					'*'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return $operands[0] * $operands[1] },
					'/'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return $operands[0] / $operands[1] },
					'+'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return $operands[0] + $operands[1] },
					'-'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->check_constraints( $values, $_ ) } @{ $data }; return $operands[0] - $operands[1] },
					'FUNCTION'	=> sub {
						our %functions;
						my ($self, $values, $data) = @_;
						my $uri		= $data->[0][1];
						my $func	= $self->{'functions'}{$uri}
									|| $RDF::Query::functions{ $uri };
						if ($func) {
							$self->{'values'}	= $values;
							my $value	= $func->(
											$self,
											map {
												($_->[0] eq 'VAR')
													? $values->{ $_->[1] }
													: $self->check_constraints( $values, $_ )
											} @{ $data }[1..$#{ $data }]
										);
							_debug( "function <$uri> -> $value" );
							return $value;
						} else {
							warn "No function defined for <${uri}>\n";
							return undef;
						}
					},
				);
sub check_constraints {
	my $self	= shift;
	my $values	= shift;
	my $data	= shift;
	_debug( 'check_constraints: ' . Dumper($data), 2 );
	return 1 unless scalar(@$data);
	my $op		= $data->[0];
	my $code	= $dispatch{ $op };
	if ($code) {
#		local($Data::Dumper::Indent)	= 0;
		my $result	= $code->( $self, $values, [ @{$data}[1..$#{$data}] ] );
		_debug( "OP: $op -> " . Dumper($data), 2 );
#		warn "RESULT: " . $result . "\n\n";
		return $result;
	} else {
		confess "OPERATOR $op NOT IMPLEMENTED!";
	}
}
}

sub get_value {
	my $self	= shift;
	my $value	= shift;
	my $bridge	= $self->bridge;
	if ($bridge->isa_resource($value)) {
		return $bridge->uri_value( $value );
	} elsif ($bridge->isa_literal($value)) {
		return $bridge->literal_value( $value );
	} else {
		return $bridge->blank_identifier( $value );
	}
}

sub add_function {
	my $self	= shift;
	my $uri		= shift;
	my $code	= shift;
	if (ref($self)) {
		$self->{'functions'}{$uri}	= $code;
	} else {
		our %functions;
		$RDF::Query::functions{ $uri }	= $code;
	}
}

sub ncmp ($$) {
	my ($a, $b)	= @_;
	return ($a =~ /^[-+]?[0-9.]+$/ and $b =~ /^[-+]?[0-9.]+$/)
		? ($a <=> $b)
		: ($a cmp $b)
}

sub sort_rows {
	my $self	= shift;
	my $nodes	= shift;
	my $parsed	= shift;
	my $bridge	= $self->bridge;
	my $args		= $parsed->{options} || {};
	my $limit		= $args->{'limit'};
	my $unique		= $args->{'distinct'};
	my $orderby		= $args->{'orderby'};
	my $offset		= $args->{'offset'} || 0;
	my @variables	= $self->variables;
	my %colmap		= map { $variables[$_] => $_ } (0 .. $#variables);
	
	if ($unique or $orderby or $offset or $limit) {
		_debug( 'sort_rows column map: ' . Dumper(\%colmap) );
	}
	
	if ($unique) {
		my %seen;
		my $old	= $nodes;
		$nodes	= sub {
			while (my $row = $old->()) {
				next if $seen{ join($;, map {$bridge->as_string( $_ )} @$row) }++;
				return $row;
			}
		};
	}
	
	if ($orderby) {
		my $cols		= $args->{'orderby'};
		my ($dir, $col)	= @{ $cols->[0][1] };
		_debug( "ordering by $col" );
		my @nodes;
		while (my $node = $nodes->()) {
			_debug( "node for sorting: " . Dumper($node) );
			push(@nodes, $node);
		}
		no warnings 'numeric';
		@nodes	= map { $_->[0] }
					sort { ncmp($a->[1], $b->[1]) }
						map { [$_, $bridge->as_string( $_->[$colmap{$col}] )] }
							@nodes;
		@nodes	= reverse @nodes if ($dir eq 'DESC');
		$nodes	= sub {
			my $row	= shift(@nodes);
			return $row;
		};
	}
	
	if ($offset) {
		$nodes->() while ($offset--);
	}
	
	if ($limit) {
		my $old	= $nodes;
		$nodes	= sub {
			return undef unless ($limit);
			$limit--;
			return $old->();
		};
	}
	
	return $nodes;
}

=for private

=item C<parse_url ( $url, $named )>

Retrieve a remote file by URL, and parse RDF into the RDF store.
If $named is TRUE, associate all parsed triples with a named graph.

=end private

=cut
sub parse_url {
	my $self	= shift;
	my $url		= shift;
	my $named	= shift;
	my $bridge	= $self->bridge;
	
	$bridge->add_uri( $url, $named );
}

sub variables {
	my $self	= shift;
	my $parsed	= $self->parsed;
	my @vars	= map { $_->[1] } @{ $parsed->{'variables'} };
	return @vars;
}

sub _debug_closure {
	return unless ($debug > 1);
	my $closure	= shift;
	require B::Deparse;
	my $deparse	= B::Deparse->new("-p", "-sC");
	my $body	= $deparse->coderef2text($closure);
	warn "--- --- CLOSURE --- ---\n";
	carp $body;
}

sub _debug {
	my $mesg	= shift;
	my $level	= shift	|| 1;
	my $trace	= shift || 0;
	my ($package, $filename, $line, $sub, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask)	= caller(1);
	
	$sub		=~ s/^.*://;
	chomp($mesg);
	my $output	= join(' ', $mesg, 'at', $filename, $line); # . "\n";
	if ($debug >= $level) {
		carp $output;
		if ($trace) {
			unless ($filename =~ m/Redland/) {
				warn Carp::longmess();
			}
		}
	}
}

sub AUTOLOAD {
	my $self	= $_[0];
	my $class	= ref($_[0]) || return undef;
	our $AUTOLOAD;
	return if ($AUTOLOAD =~ /:DESTROY$/);
	my $method		= $AUTOLOAD;
	$method			=~ s/^.*://;
	
	if (exists($self->{ $method })) {
		no strict 'refs';
		*$AUTOLOAD	= sub {
			my $self        = shift;
			my $class       = ref($self);
			return $self->{ $method };
		};
		goto &$method;
	} else {
		croak qq[Can't locate object method "$method" via package $class];
	}
}


our %functions;

### XSD CASTING FUNCTIONS

$functions{"sop:boolean"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($node->is_literal) {
		my $value	= $bridge->literal_value( $node );
		my $type	= $bridge->literal_datatype( $node );
		if ($type and $type->as_string eq 'http://www.w3.org/2001/XMLSchema#boolean') {
			return 0 if ($value eq 'false');
		}
		return 0 if (length($value) == 0);
		return 0 if ($value == 0);
	}
	return 1;
};

$functions{"sop:numeric"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $value	= $bridge->literal_value( $node );
		my $type	= $bridge->literal_datatype( $node );
		if ($type and $type->as_string eq 'http://www.w3.org/2001/XMLSchema#integer') {
			return int($value)
		}
		return +$value;
	}
	return 0;
};

$functions{"sop:str"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $value	= $bridge->literal_value( $node );
		my $type	= $bridge->literal_datatype( $node );
		return $value;
	} elsif ($bridge->is_resource($node)) {
		return $bridge->uri_value($node);
	}
	return '';
};

$functions{"sop:lang"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $lang	= $bridge->literal_value_language( $node );
		return $lang;
	}
	return '';
};

$functions{"sop:datatype"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $type	= $bridge->literal_datatype( $node );
		return $type;
	}
	return '';
};

use DateTime::Format::W3CDTF;
my $f = DateTime::Format::W3CDTF->new;
$functions{"sop:date"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $dt		= eval { $f->parse_datetime( $functions{'sop:str'}->( $node ) ) };
	return $dt;
};


# sop:logical-or
$functions{"sop:logical-or"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:boolean';
	return ($functions{$cast}->($nodea) || $functions{$cast}->($nodeb));
};

# sop:logical-and
$functions{"sop:logical-and"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:boolean';
	return ($functions{$cast}->($nodea) && $functions{$cast}->($nodeb));
};

# sop:isBound
$functions{"sop:isBound"}	= sub {
	my $query	= shift;
	my $node	= shift;
	return ref($node) ? 1 : 0;
};

# sop:isURI
$functions{"sop:isURI"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	return $bridge->is_resource( $node );
};

# sop:isBlank
$functions{"sop:isBlank"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	return $bridge->is_blank( $node );
};

# sop:isLiteral
$functions{"sop:isLiteral"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	return $bridge->is_literal( $node );
};

# op:dateTime-equal
$functions{"op:dateTime-equal"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:date';
	return ($functions{$cast}->($nodea) == $functions{$cast}->($nodeb));
};

# op:dateTime-less-than
$functions{"op:dateTime-less-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:date';
	return ($functions{$cast}->($nodea) < $functions{$cast}->($nodeb));
};

# op:dateTime-greater-than
$functions{"op:dateTime-greater-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:date';
	return ($functions{$cast}->($nodea) > $functions{$cast}->($nodeb));
};

# op:numeric-equal
$functions{"op:numeric-equal"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($nodea) == $functions{$cast}->($nodeb));
};

# op:numeric-less-than
$functions{"op:numeric-less-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($nodea) < $functions{$cast}->($nodeb));
};

# op:numeric-greater-than
$functions{"op:numeric-greater-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($nodea) > $functions{$cast}->($nodeb));
};

# op:numeric-multiply
$functions{"op:numeric-multiply"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($nodea) * $functions{$cast}->($nodeb));
};

# op:numeric-divide
$functions{"op:numeric-divide"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($nodea) / $functions{$cast}->($nodeb));
};

# op:numeric-add
$functions{"op:numeric-add"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($nodea) + $functions{$cast}->($nodeb));
};

# op:numeric-subtract
$functions{"op:numeric-subtract"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($nodea) - $functions{$cast}->($nodeb));
};

# fn:compare
$functions{"http://www.w3.org/2005/04/xpath-functionscompare"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:str';
	return ($functions{$cast}->($nodea) cmp $functions{$cast}->($nodeb));
};

# fn:not
$functions{"http://www.w3.org/2005/04/xpath-functionsnot"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:str';
	return (0 != ($functions{$cast}->($nodea) cmp $functions{$cast}->($nodeb)));
};

# fn:matches
$functions{"http://www.w3.org/2005/04/xpath-functionsmatches"}	= sub {
	my $query	= shift;
	my $cast	= 'sop:str';
	my $string	= $functions{$cast}->( shift );
	my $pattern	= $functions{$cast}->( shift );
	return undef if (index($pattern, '(?{') != -1);
	return undef if (index($pattern, '(??{') != -1);
	my $flags	= $functions{$cast}->( shift );
	if ($flags) {
		$pattern	= "(?${flags}:${pattern})";
		return $string =~ /$pattern/;
	} else {
		return ($string =~ /$pattern/) ? 1 : 0;
	}
};

# sop:	http://www.w3.org/TR/rdf-sparql-query/
# xs:	http://www.w3.org/2001/XMLSchema
# fn:	http://www.w3.org/2005/04/xpath-functions
# xdt:	http://www.w3.org/2005/04/xpath-datatypes
# err:	http://www.w3.org/2004/07/xqt-errors





1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.30  2006/01/13 23:55:48  greg
 - Updated requirements POD formatting.

 Revision 1.29  2006/01/11 06:16:19  greg
 - Added support for SELECT * in SPARQL queries.
 - Bugfix where one of two identical triple variables would be ignored ({ ?a ?a ?b })

 Revision 1.28  2005/11/19 00:58:07  greg
 - Fixed FILTER support in OPTIONAL queries.

 Revision 1.27  2005/07/27 00:30:04  greg
 - Added arithmetic operators to check_constraints().
 - Dependency cleanups.
 - Added debugging warnings when parsing fails.

 Revision 1.26  2005/06/06 00:49:00  greg
 - Added new DBI model bridge (accesses Redland's mysql storage directly).
 - Added built-in SPARQL functions and operators (not connected to grammar yet).
 - Added bridge methods for accessing typed literal information.

 Revision 1.25  2005/06/04 07:27:12  greg
 - Added support for typed literals.
   - (Redland support for datatypes is currently broken, however.)

 Revision 1.24  2005/06/02 19:28:49  greg
 - All debugging is now centrally located in the _debug method.
 - Internal code now uses the variables method.
 - Removed redundant code from ORDER BY/LIMIT/OFFSET handling.
 - Removed unused parse_files method.
 - Bridge object is now passed to the Stream constructor.

 Revision 1.23  2005/06/01 22:10:46  greg
 - Moved Stream class to lib/RDF/Query/Stream.pm.
 - Fixed tests that broke with previous fix to CONSTRUCT queries.
 - Fixed tests that broke with previous change to ASK query results.

 Revision 1.22  2005/06/01 21:21:09  greg
 - Fixed bug in CONSTRUCT queries that used blank nodes.
 - ASK queries now return a Stream object; Use the new get_boolean method.
 - Graph and Boolean streams now respond to is_graph and is_boolean methods.

 Revision 1.21  2005/06/01 05:06:33  greg
 - Added SPARQL UNION support.
 - Broke OPTIONAL handling code off into a seperate method.
 - Added new debugging code to trace errors in the twisty web of closures.

 Revision 1.20  2005/05/18 23:05:53  greg
 - Added support for SPARQL OPTIONAL graph patterns.
 - Added binding_values and binding_names methods to Streams.

 Revision 1.19  2005/05/18 04:19:45  greg
 - Added as_xml method to Stream class for XML Binding Results format.

 Revision 1.18  2005/05/16 17:37:06  greg
 - Added support for binding_name and is_bindings Stream methods.

 Revision 1.17  2005/05/09 01:03:20  greg
 - Added SPARQL test that was breaking when missing triples.
   - Added foaf:aimChatID to test foaf data.
 - Calling bindings_count on a stream now returns 0 with no data.

 Revision 1.16  2005/05/08 08:26:09  greg
 - Added initial support for SPARQL ASK, DESCRIBE and CONSTRUCT queries.
   - Added new test files for new query types.
 - Added methods to bridge classes for creating statements and blank nodes.
 - Added as_string method to bridge classes for getting string versions of nodes.
 - Broke out triple fixup code into fixup_triple_bridge_variables().
 - Updated FILTER test to use new Geo::Distance API.

 Revision 1.15  2005/05/03 05:51:25  greg
 - Added literal_value, uri_value, and blank_identifier methods to bridges.
 - Redland bridge now calls sources/arcs/targets when only one field is missing.
 - Fixes to stream code. Iterators are now destroyed in a timely manner.
   - Complex queries no longer max out mysql connections under Redland.
 - Cleaned up node sorting code.
   - Removed dependency on Sort::Naturally.
   - Added new node sorting function ncmp().
 - check_constraints now calls ncmp() for logical comparisons.
 - Added get_value method to make bridge calls and return a scalar value.
 - Fixed node creation in Redland bridge.
 - Moved DISTINCT handling code to occur before LIMITing.
 - Added variables method to retrieve bound variable names.
 - Added binding_count and get_all methods to streams.
 - get_statments bridge methods now return RDF::Query::Stream objects.

 Revision 1.14  2005/04/26 04:22:13  greg
 - added constraints tests
 - URIs in constraints are now part of the fixup
 - parser is removed from the Redland bridge in DESTROY
 - SPARQL FILTERs are now properly part of the triple patterns (within the braces)
 - added FILTER tests

 Revision 1.13  2005/04/26 02:54:40  greg
 - added core support for custom function constraints support
 - added initial SPARQL support for custom function constraints
 - SPARQL variables may now begin with the '$' sigil
 - broke out URL fixups into its own method
 - added direction support for ORDER BY (ascending/descending)
 - added 'next', 'current', and 'end' to Stream API

 Revision 1.12  2005/04/25 01:27:40  greg
 - stream objects now handle being constructed with an undef coderef

 Revision 1.11  2005/04/25 00:59:29  greg
 - streams are now objects usinig the Redland QueryResult API
 - RDF namespace is now always available in queries
 - row() now uses a stream when calling execute()
 - check_constraints() now copies args for recursive calls (instead of pass-by-ref)
 - added ORDER BY support to RDQL parser
 - SPARQL constraints now properly use the 'FILTER' keyword
 - SPARQL constraints can now use '&&' as an operator
 - SPARQL namespace declaration is now optional

 Revision 1.10  2005/04/21 08:12:07  greg
 - updated MANIFEST
 - updated POD

 Revision 1.9  2005/04/21 05:24:54  greg
 - execute now returns an iterator
 - added core support for DISTINCT, LIMIT, OFFSET
 - added initial core support for ORDER BY (only works on one column right now)
 - added SPARQL support for DISTINCT and ORDER BY
 - added stress test for large queries and sorting on local scutter model

 Revision 1.8  2005/04/21 02:21:44  greg
 - major changes (resurecting the project)
 - broke out the query parser into it's own RDQL class
 - added initial support for a SPARQL parser
   - added support for blank nodes
   - added lots of syntactic sugar (with blank nodes, multiple predicates and objects)
 - moved model-specific code into RDF::Query::Model::*
 - cleaned up the model-bridge code
 - moving over to redland's query API (pass in the model when query is executed)

 Revision 1.7  2005/02/10 09:57:24  greg
 - add code and grammar for initial constraints support
 - misc updates

 Revision 1.6  2004/07/12 11:24:09  greg
 - changed order of some Parse::RecDescent rules for common case

 Revision 1.5  2004/07/12 11:17:34  greg
 - updated namespace for relationship schema
 - fixed broken qURI regex in RDQL parser
 - query() now reverses result list (hack)
 - RDF::Query::Redland : getLabel now returns identifier for blank nodes

 Revision 1.4  2004/07/07 06:39:32  greg
 - added t/02-coverage.t and made code changes based on Devel::Cover results

 Revision 1.3  2004/07/07 04:45:57  greg
 - updated POD
 - commented out debugging code
 - moved backend model detection code to C<model>
 - changed block eval to string eval to only load one backend if both are present

 Revision 1.2  2004/07/07 03:43:14  greg
 - refactored code that deals with the RDF model
 - moved RDF::Core specific code to RDF::Query::RDFCore
 - added Redland support in RDF::Query::Redland
 - now uses Redland if available, falls back on RDF::Core
 - updated tests (removed RDF::Core specific code)

 Revision 1.1.1.1  2004/07/05 03:05:38  greg
 import

 
=head1 TODO

=over 4

=item * Built-in Operators and Functions

L<http://www.w3.org/TR/rdf-sparql-query/#StandardOperations>

Casting functions: xsd:{boolean,double,float,decimal,integer,dateTime,string}, rdf:{URIRef,Literal}, STR, LANG, DATATYPE
XPath functions: numeric-equal, numeric-less-than, numeric-greater-than, numeric-multiply, numeric-divide, numeric-add, numeric-subtract, not, dateTime-equal, dateTime-greater-than, matches
SPARQL operators: sop:RDFterm-equal, sop:bound, sop:isURI, sop:isBlank, sop:isLiteral, sop:str, sop:lang, sop:datatype, sop:logical-or, sop:logical-and, 
SPARQL functions: REGEX, BOUND, ISURI, ISBLANK, ISLITERAL

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut