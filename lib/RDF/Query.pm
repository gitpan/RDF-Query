# RDF::Query
# -------------
# $Revision: 1.24 $
# $Date: 2005/06/02 19:28:49 $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query - A SPARQL/RDQL implementation for RDF::Redland and RDF::Core

=cut

package RDF::Query;

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

 L<RDF::Redland|RDF::Redland>
  or
 L<RDF::Core|RDF::Core>

 L<Parse::RecDescent|Parse::RecDescent>
 L<LWP::Simple|LWP::Simple>
 L<Sort::Naturally>

=cut

use strict;
use warnings;
use Carp qw(carp croak confess);

use LWP::Simple ();
use Data::Dumper;

use RDF::Query::Stream;

use RDF::Query::Parser::RDQL;
use RDF::Query::Parser::SPARQL;

use RDF::Query::Model::Redland;
use RDF::Query::Model::RDFCore;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.24 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
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
	$self->{parsed}	= $parser->parse( $query );
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
	my $bridge	= (UNIVERSAL::isa($model, 'RDF::Redland::Model'))
				? RDF::Query::Model::Redland->new( $model )
				: RDF::Query::Model::RDFCore->new( $model );
	$self->{model}		= $model;
	$self->{bridge}		= $bridge;
	
	my $parser	= $self->{parser};
	my $parsed	= $self->fixup( $self->{parsed} );
	my $stream	= $self->query_more( {}, @{ $parsed->{'triples'} } );
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
			while (@streams and $streams[0]->finished) {
				shift(@streams);
				return undef unless(@streams);
			}
			my $val	= $streams[0]->current;
			$streams[0]->next;
			return $val;
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
			while (@streams and $streams[0]->finished) {
				shift(@streams);
				return undef unless(@streams);
			}
			my $val	= $streams[0]->current;
			$streams[0]->next;
			return $val;
		}
	};
	return RDF::Query::Stream->new( $ret, 'graph', undef, bridge => $bridge );
}

sub ask {
	my $self	= shift;
	my $stream	= shift;
	return RDF::Query::Stream->new( $stream, 'boolean', undef, bridge => $self->bridge );
}

######################################################################

sub fixup {
	my $self		= shift;
	my $parsed		= shift;
	
	## CONVERT URIs to Resources, and strings to Literals
	my @triples	= @{ $parsed->{'triples'} || [] };
	while (my $triple = shift(@triples)) {
		if ($triple->[0] eq 'OPTIONAL') {
			push(@triples, @{$triple->[1]});
		} elsif ($triple->[0] eq 'UNION') {
			push(@triples, @{$triple->[1]});
			push(@triples, @{$triple->[2]});
		} else {
			$self->fixup_triple_bridge_variables( $triple );
		}
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
	
	## LOAD ANY EXTERNAL RDF FILES
	my $sources	= $parsed->{'sources'};
	if (UNIVERSAL::isa( $sources, 'ARRAY' )) { # and scalar(@{ $sources })) {
		$self->parse_urls( map { $_->[1] } @{ $sources } );
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
			my $literal		= $self->bridge->new_literal($obj->[1]);
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

=item C<query_more ( @triples )>

Internal recursive query function to bind pivot variables until only result
variables are left and found from the RDF store. Called from C<query>.

=end private

=cut
sub query_more {
	my $self	= shift;
	my $bound	= shift;
	my @triples	= @_;
#	warn 'query_more: ' . Dumper(\@triples);
	our $indent;

	my $parsed		= $self->parsed;
	my $bridge		= $self->bridge;
	my $triple		= shift(@triples);
	unless (ref($triple)) {
		carp "Something went wrong. No triple passed to query_more";
		return undef;
	}
	my @triple		= @{ $triple };
	
	if ($triple[0] eq 'OPTIONAL') {
		return $self->optional( $bound, $triple, @triples );
	} elsif ($triple[0] eq 'UNION') {
		return $self->union( $bound, $triple, @triples );
	}
	
	no warnings 'uninitialized';
	_debug( "${indent}query_more: " . join(' ', map { $bridge->isa_node($_) ? '<' . $_->getLabel . '>' : $_->[1] } @triple) . "\n" );
	_debug( "${indent}-> with " . scalar(@triples) . " triples to go\n" );
	_debug( "${indent}-> more: " . (($_->[0] eq 'OPTIONAL') ? 'OPTIONAL block' : join(' ', map { $bridge->isa_node($_) ? '<' . $_->getLabel . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
	
	my $vars	= 0;
	my ($var, $method);
	my (@vars, @methods);
	
	my @methodmap	= $bridge->statement_method_map;
	for my $idx (0 .. 2) {
		my $data	= $triple[$idx];
		if (UNIVERSAL::isa($data, 'ARRAY')) {	# and $data->[0] eq 'VAR'
			if ($data->[0] eq 'VAR' or $data->[0] eq 'BLANK') {
				my $tmpvar	= ($data->[0] eq 'VAR') ? $data->[1] : '_' . $data->[1];
				my $val		= $bound->{ $tmpvar };
				if ($bridge->isa_node($val)) {
					_debug( "${indent}-> already have value for $tmpvar: " . $val->getLabel . "\n" );
					$triple[$idx]	= $val;
				} elsif (++$vars > 1) {
					_debug( "${indent}-> we've seen $vars variables in this triple... punt\n" );
					if (1 + $self->{punt} >= scalar(@{$self->{parsed}{triples}})) {
						_debug( "${indent}-> we've punted too many times. binding on ?$tmpvar" );
						$triple[$idx]	= undef;
						$vars[$idx]		= $tmpvar;
						$methods[$idx]	= $methodmap[ $idx ];
					} elsif (scalar(@triples)) {
						$self->{punt}++;
						push(@triples, $triple);
						return $self->query_more( { %{ $bound } }, @triples );
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
	_debug( 'query_more triple: ' . Dumper([map { ($_) ? $_->getLabel : 'undef' } @triple]) );
	my @streams;
	my $stream;
	{
		my $statments	= $bridge->get_statements( @triple );
		push(@streams, sub {
			my $result;
			_debug_closure( $statments );
			my $stmt	= $statments->();
			unless ($stmt) {
				_debug( 'no more statements' );
				$statments	= undef;
				return undef;
			}
			if ($vars) {
				foreach (0 .. $#vars) {
					next unless defined($vars[$_]);
					my $var		= $vars[ $_ ];
					my $method	= $methods[ $_ ];
					_debug( "${indent}-> got variable $var = " . $stmt->$method()->getLabel . "\n" );
					$bound->{ $var }	= $stmt->$method();
				}
			} else {
				_debug( "${indent}-> triple with no variable. ignoring.\n" );
			}
			if (scalar(@triples)) {
				_debug( "${indent}-> now for more triples...\n" );
				_debug( "${indent}-> more: " . (($_->[0] eq 'OPTIONAL') ? 'OPTIONAL block' : join(' ', map { $bridge->isa_node($_) ? '<' . $_->getLabel . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
				_debug( "${indent}-> " . Dumper(\@triples) );
				$indent	.= '  ';
				_debug( 'adding a new stream for more triples' );
				unshift(@streams, $self->query_more( { %{ $bound } }, @triples ) );
			} else {
				my @values	= map { $bound->{$_} } $self->variables();
				_debug( "${indent}-> no triples left: result: " . join(', ', map {$_->getLabel} grep defined, @values) . "\n" );
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
				_debug( '-> ' . $val[0], 1, 1);
				return $val[0] if defined($val[0]);
			} else {
				next;
			}
			shift(@streams);
		}
		return undef;
	};	
}

sub union {
	my $self		= shift;
	my $bound		= shift;
	my $triple		= shift;
	my @triples		= @_;
	my $parsed		= $self->parsed;
	my @streams;
	foreach my $u_triples (@{ $triple }[1 .. $#{$triple}]) {
		my $stream	= $self->query_more( { %{ $bound } }, @{ $u_triples }, @triples );
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
	my $bound		= shift;
	my $triple		= shift;
	my @triples		= @_;
	my $parsed		= $self->parsed;
	
	my @triple		= @{ $triple };
	my @opt_triples	= @{ $triple[1] };
	_debug( 'optional triples: ' . Dumper(\@opt_triples), 2 );
	my $ostream	= $self->query_more( { %{ $bound } }, @opt_triples );
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
					if ($stream and not $stream->finished) {
						my $data	= $stream->current;
						$stream->next;
						return $data;
					}
					
					foreach my $i (0 .. $ostream->bindings_count - 1) {
						my $name	= $ostream->binding_name( $i );
						my $value	= $ostream->binding_value( $i );
						if (defined $value) {
							$bound->{ $name }	= $value;
							_debug( "Setting $name = $value\n" );
						}
						$stream	= $self->query_more( { %{ $bound } }, @triples );
						$stream->next;
					}
				}
				return undef;
			};
		} else {
			_debug( "No more triples. Returning OPTIONAL stream." );
			return sub {
				return undef unless ($ostream and not $ostream->finished);
				my $data	= $ostream->current;
				$ostream->next;
				return $data;
			};
		}
	} else {
		_debug( "OPTIONAL block failed" );
		if (@triples) {
			_debug( "More triples. Re-dispatching" );
			return $self->query_more( { %{ $bound } }, @triples );
		} else {
			_debug( "No more triples. Returning empty results." );
			my @values	= map { $bound->{$_} } $self->variables();
			my @results	= [@values];
			return sub { shift(@results) };
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
	my $args		= $parsed->{options} || {};
	my $limit		= $args->{'limit'};
	my $unique		= $args->{'distinct'};
	my $offset		= $args->{'offset'} || 0;
	my @variables	= $self->variables;
	my %colmap		= map { $variables[$_] => $_ } (0 .. $#variables);
	_debug( 'sort_rows column map: ' . Dumper(\%colmap) );
	
	if ($unique) {
		my %seen;
		my $old	= $nodes;
		$nodes	= sub {
			while (my $row = $old->()) {
				next if $seen{ join($;, map {$_->getLabel} @$row) }++;
				return $row;
			}
		};
	}
	
	if (exists $args->{'orderby'}) {
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
						map { [$_, $_->[$colmap{$col}]->getLabel] }
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

=item C<parse_urls ( @urls )>

Retrieve a remote file by URL, and parse RDf into the RDF store.

=end private

=cut
sub parse_urls {
	my $self	= shift;
	my @urls	= @_;
	my $bridge	= $self->bridge;
	
	foreach my $url (@urls) {
		$bridge->add_uri( $url );
	}
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
	use B::Deparse;
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
	my $output	= join(' ', $mesg, 'at', $filename, $line) . "\n";
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

1;

__END__

=back

=head1 REVISION HISTORY

 $Log: Query.pm,v $
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

=item * Typed Literals

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
