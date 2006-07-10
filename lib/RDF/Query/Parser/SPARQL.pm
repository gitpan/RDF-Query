# RDF::Query::Parser::SPARQL
# -------------
# $Revision: 160 $
# $Date: 2006-07-07 18:11:20 -0400 (Fri, 07 Jul 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Parser::SPARQL - A SPARQL parser for RDF::Query

=cut

package RDF::Query::Parser::SPARQL;

use strict;
use warnings;
use base qw(RDF::Query::Parser);

use RDF::Query::Error qw(:try);

use Data::Dumper;
use Digest::SHA1  qw(sha1_hex);
use Carp qw(carp croak confess);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 0 || $RDF::Query::Parser::debug;
	$VERSION	= do { my $REV = (qw$Revision: 160 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$lang		= 'sparql';
	$languri	= 'http://www.w3.org/TR/rdf-sparql-query/';
}


######################################################################

=head1 METHODS

=over 4

=item C<new ( $query_object ) >

Returns a new RDF::Query object.

=cut
sub new {
	my $class	= shift;
	my $self 	= bless( {}, $class );
	return $self;
}


=item C<parse ( $query ) >

Parses the supplied RDQL query string, returning a parse tree.

=cut

sub parse {
	my $self	= shift;
	my $query	= shift;
	$self->set_input( $query );
	
	my $error;
	my $parsed;
	try {
		$parsed	= $self->parse_query;
		$self->whitespace;
	} catch RDF::Query::Error::ParseError with {
		$error	= $self->error;
	};
	
	if ($error) {
		$self->unset_commit;
		return $self->fail( $error );
	} else {
		my $text	= $self->{remaining};
		if (length($text)) {
			$self->unset_commit;
			return $self->fail( "Remaining input: '$text'" );
		} else {
			$self->clear_error( undef );
			delete $self->{blank_ids};
			return $parsed;
		}
	}
}

=begin private

=item C<parse_query>

Returns the parse tree for a complete SPARQL query.

=end private

=cut

sub parse_query {
	my $self	= shift;
	
	my $namespaces	= $self->parse_namespaces;
	my $type;
	if ($type = $self->match_pattern(qr/SELECT|DESCRIBE/i)) {
		my $distinct	= ($self->match_literal('DISTINCT', 1));
		my $vars		= $self->parse_variables;
		my $sources		= $self->parse_sources;
		
		$self->match_literal('WHERE', 1);
		my $triples	= $self->parse_triple_patterns;
		
		my $order	= $self->parse_order_by;
		my $limit	= $self->parse_limit;
		my $offset	= $self->parse_offset;
		
		my %options;
		
		my $data	= {
			method		=> uc($type),
			variables	=> $vars,
			sources		=> $sources,
			triples		=> $triples,
			namespaces	=> $namespaces,
		};
		
		if (my $options = $self->get_options( $distinct, $order, $limit, $offset )) {
			$data->{options}	= $options;
		}
		return $data;
	} elsif ($type = $self->match_literal('CONSTRUCT', 1)) {
		my $construct	= $self->parse_triple_patterns;
		my $sources		= $self->parse_sources;
		
		$self->set_commit;
		$self->match_literal('WHERE', 1);
		$self->unset_commit;
		
		my $triples	= $self->parse_triple_patterns;
		
		my $order	= $self->parse_order_by;
		my $limit	= $self->parse_limit;
		my $offset	= $self->parse_offset;
		
		my $data	= {
			method				=> uc($type),
			variables			=> [],
			sources				=> $sources,
			triples				=> $triples,
			namespaces			=> $namespaces,
			construct_triples	=> $construct,
		};
		
		if (my $options = $self->get_options( 1, $order, $limit, $offset )) {
			$data->{options}	= $options;
		}
		return $data;
	} elsif ($type = $self->match_literal('ASK', 1)) {
		my $sources		= $self->parse_sources;
		my $triples	= $self->parse_triple_patterns;
		
		my $data	= {
			method		=> uc($type),
			variables	=> [],
			sources		=> $sources,
			triples		=> $triples,
			namespaces	=> $namespaces,
		};
		return $data;
	} else {
		$self->set_commit;
		return $self->fail('Expecting query type');
	}
}

=begin private

=item C<parse_namespaces>

Returns the parse tree for zero or more namespace declarations.

=end private

=cut

sub parse_namespaces {
	my $self	= shift;
	
	my %namespaces;
	while ($self->match_literal('PREFIX', 1)) {
		my $id	= $self->parse_identifier;
		
		$self->set_commit;
		$self->match_literal(':');
		my $uri	= $self->parse_qURI;
		$self->unset_commit;
		
		my $ns	= $id || '__DEFAULT__';
		$namespaces{ $ns }	= $uri;
	}
	return \%namespaces;
}

=begin private

=item C<parse_identifier>

Returns the parse tree for an identifier.

=end private

=cut

sub parse_identifier {
	my $self	= shift;
	return $self->match_pattern(qr/[a-zA-Z0-9_.-]+/);
}

=begin private

=item C<parse_qURI>

Returns the parse tree for a fully qualified URI.

=end private

=cut

sub parse_qURI {
	my $self	= shift;
	
	if ($self->match_literal('<')) {
		$self->set_commit;
		my $uri	= $self->match_pattern(qr/[A-Za-z0-9_.!~*'()%;\/?:@&=+,#\$-]+/);
		$self->match_literal('>');
		$self->unset_commit;
		return $uri;
	} else {
		return $self->fail('Expecting a qualified URI');
	}
}

=begin private

=item C<parse_variables>

Returns the parse tree for a list of variables for a SELECT query.
'*' is an acceptable substitute for a list of variables.

=end private

=cut

sub parse_variables {
	my $self	= shift;
	
	my @variables;
	my $fail	= 0;
	
	if ($self->match_literal('*')) {
		push(@variables, '*');
	} else {
		while (my $variable = $self->parse_variable) {
			push(@variables, $variable);
		}
	}
	
	return \@variables;
}

=begin private

=item C<parse_variable>

Returns the parse tree for a variable.

=end private

=cut

sub parse_variable {
	my $self	= shift;
	
#	local($debug)	= 3 if ($debug > 1);
	if ($self->match_pattern(qr/[?\$]/)) {
		$self->set_commit;
		my $var	= $self->parse_identifier;
		$self->unset_commit;
		return $self->new_variable( $var );
	} else {
		return $self->fail('Expecting variable');
	}
}

=begin private

=item C<parse_sources>

Returns the parse tree for zero or more source ('FROM' or 'FROM NAMED') declarations.

=end private

=cut

sub parse_sources {
	my $self	= shift;
	
	my @sources;
	while (my $type = $self->match_pattern(qr/SOURCE|(FROM( NAMED)?)/i)) {
		my $uri	= $self->parse_uri;
		if ($type =~ /NAMED/i) {
			push(@sources, [ @$uri, 'NAMED' ]);
		} else {
			push(@sources, $uri);
		}
	}
	return \@sources;
}

=begin private

=item C<parse_uri>

Returns the parse tree for a URI (either fully qualified or a QName).

=end private

=cut

sub parse_uri {
	my $self	= shift;
	if (my $uri = $self->parse_qURI) {
		return $self->new_uri( $uri );
	} elsif (my $qname = $self->parse_QName) {
		return $qname;
	} else {
		return $self->fail( 'Expecting a URI' );
	}
}

=begin private

=item C<parse_ncname_prefix>

Returns the parse tree for a QName prefix.

=end private

=cut

sub parse_ncname_prefix {
	my $self		= shift;
	my $ncchar1p	= qr/[A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{02FF}\x{0370}-\x{037D}\x{037F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]/x;
	my $ncchar		= qr/${ncchar1p}|_|[0-9]|\x{00B7}|[\x{0300}-\x{036F}]|[\x{203F}-\x{2040}]/x;
	my $ncchar_p	= qr/${ncchar1p}((${ncchar}|[.])*${ncchar})?/x;
	return $self->match_pattern(qr/${ncchar_p}/);
}

=begin private

=item C<parse_QName>

Returns the parse tree for a QName.

=end private

=cut

sub parse_QName {
	my $self	= shift;
	
	my $ns;
	if ($self->match_literal(':')) {
		$ns	= '__DEFAULT__';
	} elsif ($ns = $self->parse_ncname_prefix) {
	#	warn "identifier: $id";
	#	Carp::cluck($id) if ($id eq '_');
		$self->set_commit;
		$self->match_literal(':');
	} else {
		return $self->fail( 'Expecting a QName' );
	}
	
	my $localpart	= $self->match_pattern(qr/([^ \t\r\n<>();,]+)/);
	$self->unset_commit;
	return $self->new_qname( $ns, $localpart );
}

=begin private

=item C<parse_blankQName>

Returns the parse tree for a blank QName ('_:foo').

=end private

=cut

sub parse_blankQName {
	my $self	= shift;
	if ($self->match_literal('_:')) {
		my $id	= $self->match_pattern(qr/([^ \t\r\n<>();,]+)/);
		return $self->new_blank($id);
	} else {
		return $self->fail( 'Expecting a blank identifier (QName)' );
	}
}

=begin private

=item C<parse_triple_patterns>

Returns the parse tree for a (possibly nested) set of triple patterns.

=end private

=cut

sub parse_triple_patterns {
	my $self	= shift;
	
	my $triples	= [];
	
	if ($self->match_literal('{')) {
		BALANCED: {
			LOOP: while (my $triple = $self->parse_triplepattern) {
				if ($self->match_literal('UNION', 1)) {
					if (my $unionpart = $self->parse_triple_patterns) {
						$triples		= [ $self->new_union($triple, $unionpart) ];
					} else {
						$self->set_commit;
						return $self->fail('Expecting triple pattern in second position of UNION');
					}
				} else {
					push(@$triples, @$triple);
				}
				
				last LOOP unless $self->match_literal('.');
				last BALANCED if $self->match_literal('}');
			}
			
			$self->set_commit;
			$self->match_literal('}');
			$self->unset_commit;
		}
		
		# put filters at the end
		my @triples;
		my @filters;
		foreach my $data (@$triples) {
			if ($data->[0] eq 'FILTER') {
				push(@filters, $data);
			} else {
				push(@triples, $data);
			}
		}
		
		if (@filters) {
			my @data	= map { $_->[1] } @filters;
			if (1 < @data) {
				@filters	= [ 'FILTER', $self->new_logical_expression('&&', @data) ];
			} else {
				@filters	= [ 'FILTER', $data[0] ];
			}
		}
		
		return [ @triples, @filters ];
	} else {
		return $self->fail('Expecting triple patterns');
	}
}

=begin private

=item C<parse_triplepattern>

Returns the parse tree for a single triple pattern.
May return multiple triples if multiple-object syntax ('?subj :pred ?obj1, ?obj2'),
multiple-predicate syntax ('?subj :pred1 ?obj1 ; :pred2 ?obj2'),
collections ('(1 2 3) :pred ?obj'), or blank nodes ('[ a foaf:Person; foaf:name "Jane" ]')
are used.

=end private

=cut

sub parse_triplepattern {
	my $self	= shift;
	
#	local($debug)	= 2;
	if ($self->match_literal('OPTIONAL', 1)) {
		my $triples	= $self->parse_triple_patterns;
		return [ $self->new_optional( $triples ) ];
#		triplepattern:				/OPTIONAL/i <commit> triplepatterns				{ $return = [[ 'OPTIONAL', ($item{triplepatterns}[0] || []) ]] }
	} elsif ($self->match_literal('GRAPH', 1)) {
		my $varuri	= $self->parse_variable_or_uri;
		my $triples	= $self->parse_triple_patterns;
		return [ $self->new_named_graph( $varuri, $triples ) ];
	} elsif (my $filter = $self->parse_filter) {
		return [$filter];
	} elsif (my $data = $self->parse_triple_patterns) {
		return $data;
	} else {
		my $subj;
		my $triples	= [];
		
		if (my $collection = $self->parse_collection) {
			($subj, $triples)	= @$collection;
		} elsif ($subj = $self->parse_variable_or_uri) {
		} elsif (my $data = $self->parse_blanknode) {
			($subj, $triples)	= @$data;
		} else {
			return $self->fail('Expecting triple pattern');
		}
		
		my ($pred, $obj, $optobjs);
		if (scalar(@$triples)) {
			$pred		= $self->parse_predicate;
			if ($pred) {
				try {
					if (my $data = $self->parse_collection) {
						($obj, my $collection_triples)	= @$data;
						push(@$triples, @{ $collection_triples });
					} else {
						$obj		= $self->parse_object;
					}
					
					if ($obj) {
						$optobjs	= $self->parse_optional_objects;
						push( @$triples, $self->new_triple($subj, $pred, $obj) );
					} else {
						$self->set_commit;
						$self->fail( "Expecting object after predicate" );
					}
				} catch RDF::Query::Error::ParseError with {
					my $err	= shift;
					$self->unset_commit;
					throw $err;
				};
			}
		} else {
			$pred		= $self->parse_predicate;
			if ($pred) {
				if (my $data = $self->parse_collection) {
					($obj, my $collection_triples)	= @$data;
					push(@$triples, @{ $collection_triples });
				} else {
					$obj		= $self->parse_object;
				}
				$optobjs	= $self->parse_optional_objects;
				
				# triples from the object position get bumped after the main triple
				if ($obj) {
					unshift( @$triples, $self->new_triple($subj, $pred, $obj) );
				} else {
					$self->set_commit;
					$self->fail( "Expecting object after predicate" );
				}
			}
		}
		
		my $optpredobjs;
		if ($self->match_literal(';')) {
			$optpredobjs	= $self->parse_optional_predicate_objects;
		}
		
		my @predobjs	= (@{ $optpredobjs || [] }, map { [$pred, $_] } @{ $optobjs || [] });
		push(@$triples,
			map {
				$self->new_triple( $subj, @$_ )
			} @predobjs
		);
		
		return $triples;
	}
	
# 	triplepattern:				constraints										{ $return = [[ 'FILTER', $item[1] ]] }
# 	triplepattern:				blanktriple PredObj(?)							{
# 																					my ($b,$t)	= @{ $item[1] };
# 																					$return = [ (map { ['TRIPLE', $_] } @$t), map { ['TRIPLE', [$b, @$_]] } @{ $item[2] } ];
# 																				}
# 	triplepattern:				triplepatterns									{ $return = $item[1] }
# 	triplepattern:				Collection PredVarObj(?)						{
# 																					my $collection	= $item[1][0][1];
# 																					my @triples		= @{ $item[1] };
# 																					foreach my $elem (@{ $item[2] || [] }) {
# 																						my @triple	= [ $collection, @{ $elem } ];
# 																						push(@triples, \@triple);
# 																					}
# 																					$return = \@triples;
# 																				}
}

=begin private

=item C<parse_object>

Returns the parse tree for the object of a triple pattern (a variable, URI,
constant or collection).

=end private

=cut

sub parse_object {
	my $self	= shift;
	if (my $object = $self->parse_variable_or_uri_or_constant) {
		return $object;
	} else {
		return $self->parse_collection;
	}
}

=begin private

=item C<parse_optional_objects>

Returns the parse tree for a set of optional objects following a full triple
pattern (', ?obj2, ?obj3').

=end private

=cut

sub parse_optional_objects {
	my $self	= shift;
	
	my @objects;
	while ($self->match_literal(',')) {
		push(@objects, $self->parse_object);
	}
	return \@objects;
}

=begin private

=item C<parse_optional_predicate_objects>

Returns the parse tree for a set of optional predicate-objects following a full
triple pattern ('; :pred2 ?obj2 ; :pred3 ?obj3').

=end private

=cut

sub parse_optional_predicate_objects {
	my $self	= shift;
	
	my @pred_objs;
	while (my $data = $self->parse_predicate_object) {
		push(@pred_objs, @{ $data });
		last unless $self->match_literal(';');
	}
	return \@pred_objs;
}

=begin private

=item C<parse_predicate_object>

Returns the parse tree for a predicate-objects following a triple subject.

=end private

=cut

sub parse_predicate_object {
	my $self	= shift;
	my $pred	= $self->parse_predicate;
	my $object	= $self->parse_object;
	if ($pred and $object) {
		my $optobj	= $self->parse_optional_objects;
		return [[$pred, $object], map { [$pred, @{$_}] } @{ $optobj }];
	} else {
		return [];
	}
}

=begin private

=item C<parse_collection>

Returns the parse tree for a collection.

=end private

=cut

sub parse_collection {
	my $self	= shift;
	if ($self->match_literal('(')) {
		my @objects	= $self->parse_object;
		while (my $obj = $self->parse_object) {
			push(@objects, $obj);
		}
		$self->match_literal(')');
	
		my @triples;
		my $id		= 'a' . ++$self->{blank_ids};
		my $subj	= $self->new_blank( $id );
		my $count	= scalar(@objects);
		foreach my $i (0 .. $#objects) {
			my $elem	= $objects[ $i ];
			push(@triples,
				[
					$self->new_blank( $id ),
					$self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#first'),
					$elem
				]
			);
			
			if ($i < $#objects) {
				my $oldid	= $id;
				$id			= 'a' . ++$self->{blank_ids};
				push(@triples,
					[
						$self->new_blank( $oldid ),
						$self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'),
						$self->new_blank( $id ),
					]
				);
			} else {
				push(@triples,
					[
						$self->new_blank( $id ),
						$self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'),
						$self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil'),
					]
				);
			}
		}
		
		return [ $subj, \@triples ];
	} else {
		return $self->fail('Expecting Collection definition');
	}
}

=begin private

=item C<parse_blanknode>

Returns the parse tree for a blank node containing optional triples
('[]' or '[ :pred ?obj ]').

=end private

=cut

sub parse_blanknode {
	my $self	= shift;
	if ($self->match_literal('[')) {
		my $predobj	= $self->parse_optional_predicate_objects;
		
		my $id		= 'a' . ++$self->{blank_ids};
		my $subj	= $self->new_blank( $id );
		my $triples	= [ map { $self->new_triple($subj, @$_) } (@$predobj) ];
		
		$self->set_commit;
		$self->match_literal(']');
		$self->unset_commit;
		
		return [ $subj, $triples ];
	} else {
		return $self->fail( 'Expecting a Blank node []' );
	}
}

=begin private

=item C<parse_blanknode_expr>

Returns a parse tree for an anonymous (empty) blank node ('[]').

=end private

=cut

sub parse_blanknode_expr {
	my $self	= shift;
	if ($self->match_literal('[')) {
		my $id		= 'a' . ++$self->{blank_ids};
		my $subj	= $self->new_blank( $id );
		
		$self->set_commit;
		$self->match_literal(']');
		$self->unset_commit;
		
		return $subj;
	} else {
		return $self->fail( 'Expecting a Blank node expression []' );
	}
}

=begin private

=item C<parse_filter>

Returns the parse tree for a FILTER declaration.

=end private

=cut

sub parse_filter {
	my $self	= shift;
	if ($self->match_literal('FILTER', 1)) {
		my $func	= $self->parse_bracketted_expression || $self->parse_built_in_call_expression || $self->parse_function_call;
		if ($func) {
			return [ 'FILTER', $func ];
		} else {
			$self->set_commit;
			return $self->fail( 'Expecting FILTER declaration' );
		}
	} else {
		return $self->fail( 'Expecting FILTER declaration' );
	}
}

=begin private

=item C<parse_expression>

Returns the parse tree for an expression (possibly multiple expressions joined
with a logical-or).

=end private

=cut

sub parse_expression {
	my $self	= shift;
	
	my @expressions;
	while (my $expr = $self->parse_conditional_and_expression) {
		push(@expressions, $expr);
		last unless $self->match_literal('||');
	}
	
	if (1 < @expressions) {
		return $self->new_logical_expression('||', @expressions);
	} else {
		return $expressions[0];
	}
}

=begin private

=item C<parse_conditional_and_expression>

Returns the parse tree for an expression (possibly multiple expressions joined
with a logical-and).

=end private

=cut

sub parse_conditional_and_expression {
	my $self	= shift;
	
	my @expressions;
	while (my $expr = $self->parse_value_logical) {
		push(@expressions, $expr);
		last unless $self->match_literal('&&');
	}
	
	if (1 < @expressions) {
		return $self->new_logical_expression('&&', @expressions);
	} else {
		return $expressions[0];
	}
}

=begin private

=item C<parse_value_logical>

Returns the parse tree for an expression (possibly multiple expressions joined
with a logical operator: equal, not-equal, less-than, less-than-or-equal,
greater-than, greater-than-or-equal).

=end private

=cut

sub parse_value_logical {
	my $self	= shift;
	my $expr1	= $self->parse_numeric_expression;
	
	if (my $op = $self->match_pattern(qr/(=|!=|<=?|>=?)/)) {
#		local($debug)	= 3;
		if (my $expr2 = $self->parse_numeric_expression) {
			$op		= '==' if ($op eq '=');
			return $self->new_binary_expression( $op, $expr1, $expr2 );
		} else {
			$self->set_commit;
			return $self->fail("Expecting numeric expression after '$op'");
		}
	} else {
		return $expr1;
	}
}

=begin private

=item C<parse_numeric_expression>

Returns the parse tree for an expression (possibly multiple expressions joined
with a numeric operator: plus, minus).

=end private

=cut

sub parse_numeric_expression {
	my $self	= shift;
	my $expr1	= $self->parse_multiplicative_expression;
	
	if (my $op = $self->match_pattern(qr/[-+]/)) {
		if (my $expr2 = $self->parse_multiplicative_expression) {
			return $self->new_binary_expression( $op, $expr1, $expr2 );
		} else {
			$self->set_commit;
			return $self->fail("Expecting multiplicative expression after '$op'");
		}
	} else {
		return $expr1;
	}
}

=begin private

=item C<parse_multiplicative_expression>

Returns the parse tree for an expression (possibly multiple expressions joined
with a numeric operator: multiply, divide).

=end private

=cut

sub parse_multiplicative_expression {
	my $self	= shift;
	my $expr1	= $self->parse_unary_expression;
	
	if (my $op = $self->match_pattern(qr#[*/]#)) {
		if (my $expr2 = $self->parse_unary_expression) {
			return $self->new_binary_expression( $op, $expr1, $expr2 );
		} else {
			$self->set_commit;
			return $self->fail("Expecting unary expression after '$op'");
		}
	} else {
		return $expr1;
	}
}

=begin private

=item C<parse_unary_expression>

Returns the parse tree for a unary expression (possibly with a unary operator:
not, negative, positive).

=end private

=cut

sub parse_unary_expression {
	my $self	= shift;
	
	if (my $op = $self->match_pattern(qr/[-!+]/)) {
		if (my $expr = $self->parse_primary_expression) {
			if ($op eq '+') {
				return $expr;
			} else {
				return $self->new_unary_expression( $op, $expr );
			}
		} else {
			$self->set_commit;
			return $self->fail("Expecting primary expression after '$op'");
		}
	} else {
		my $expr	= $self->parse_primary_expression;
		return $expr;
	}
}

=begin private

=item C<parse_primary_expression>

Returns the parse tree for a primary expression: bracketted expression,
built-in function call, blank QName, constant, blank node, variable, IRI, or
function call.

=end private

=cut

sub parse_primary_expression {
	my $self	= shift;
	
	my $expr;
	if ($expr = $self->parse_bracketted_expression) {
	} elsif ($expr = $self->parse_built_in_call_expression) {
	} elsif ($expr = $self->parse_blankQName) {
	} elsif ($expr = $self->parse_constant) {
	} elsif ($expr = $self->parse_blanknode_expr) {
	} elsif ($expr = $self->parse_variable) {
	} elsif ($expr = $self->parse_iriref_or_function) {
	}
	
	unless ($expr) {
		return $self->fail('Expecting a primary expression');
	}
	
	warn "got primary expr: " . Dumper($expr) if ($debug > 1);
	return $expr;
}

=begin private

=item C<parse_built_in_call_expression>

Returns the parse tree for a built-in function call: REGEX, LANGMATCHES, LANG,
DATATYPE, BOUND, isIRI, isURI, isBLANK, or isLITERAL.

=end private

=cut

sub parse_built_in_call_expression {
	my $self	= shift;
	if ($self->match_literal('REGEX', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		
		my $string	= $self->parse_expression;
		
		$self->set_commit;
		$self->match_literal(',');
		$self->unset_commit;
		
		my $pattern	= $self->parse_expression;
		
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_binary_expression( '~~', $string, $pattern );
	} elsif ($self->match_literal('LANGMATCHES', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $str		= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(',');
		$self->unset_commit;
		my $match	= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('sparql:langmatches'), $str, $match );
	} elsif ($self->match_literal('LANG', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $str	= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('sparql:lang'), $str );
	} elsif ($self->match_literal('DATATYPE', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $str		= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('sparql:datatype'), $str );
	} elsif ($self->match_literal('BOUND', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $var	= $self->parse_variable;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('sop:isBound'), $var );
	} elsif ($self->match_literal('isIRI', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $node	= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('XXX IS IRI'), $node );
	} elsif ($self->match_literal('isURI', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $node	= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('sop:isURI'), $node );
	} elsif ($self->match_literal('isBLANK', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $node	= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('sop:isBlank'), $node );
	} elsif ($self->match_literal('isLITERAL', 1)) {
		$self->set_commit;
		$self->match_literal('(');
		$self->unset_commit;
		my $node	= $self->parse_expression;
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $self->new_uri('sop:isLiteral'), $node );
	}
}

=begin private

=item C<parse_iriref_or_function>

Returns the parse tree for an IRI or function call.

=end private

=cut

sub parse_iriref_or_function {
	my $self	= shift;
#	Carp::cluck;
	if (my $iri = $self->parse_qURI) {
		my $uri		= $self->new_uri($iri);
		if ($self->match_literal('(')) {
			my $args	= $self->parse_arguments;
			$self->match_literal(')');
			$self->unset_commit;
			return $self->new_function_expression( $uri, @$args );
		} else {
			return $uri;
		}
	} elsif (my $uri = $self->parse_uri) {
		if ($self->match_literal('(')) {
			my $args	= $self->parse_arguments;
			$self->match_literal(')');
			$self->unset_commit;
			return $self->new_function_expression( $uri, @$args );
		} else {
			return $uri;
		}
	} else {
		return $self->fail( 'Expecting IRIRef or function call' );
	}
}

=begin private

=item C<parse_function_call>

Returns the parse tree for a function call.

=end private

=cut

sub parse_function_call {
	my $self	= shift;
	
	my $func	= $self->parse_uri;
	if ($func) {
		$self->set_commit;
		$self->match_literal('(');
		my $args	= $self->parse_arguments;
		$self->match_literal(')');
		$self->unset_commit;
		return $self->new_function_expression( $func, @$args );
	} else {
		return $self->fail( 'Expecting qURI of function' );
	}
}

=begin private

=item C<parse_bracketted_expression>

Returns the parse tree for a bracketted expression (C<parse_expression> surrounded
by parentheses).

=end private

=cut

sub parse_bracketted_expression {
	my $self	= shift;
	if ($self->match_literal('(')) {
		
		my $expr	= $self->parse_expression;
		
		$self->set_commit;
		$self->match_literal(')');
		$self->unset_commit;
		
		return $expr;
	} else {
		return $self->fail( 'Expecting a bracketted expression' );
	}
}

=begin private

=item C<parse_arguments>

Returns the parse tree for a function's argument list.

=end private

=cut

sub parse_arguments {
	my $self	= shift;
	
	my @args;
	while (my $arg = $self->parse_variable_or_uri_or_constant) {
		push(@args, $arg);
		last unless $self->match_literal(',');
	}
	return \@args;
}

=begin private

=item C<parse_predicate>

Returns the parse tree for a predicate. Either 'a' for rdf:type shortcut syntax
('?p a foaf:Person') or a variable or URI.

=end private

=cut

sub parse_predicate {
	my $self	= shift;
	if ($self->match_pattern(qr/a\b/)) {
		return $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type');
	} else {
		return $self->parse_variable_or_uri;
	}
}

=begin private

=item C<parse_variable_or_uri>

Returns the parse tree for a variable or URI.

=end private

=cut

sub parse_variable_or_uri {
	my $self	= shift;
	return $self->parse_variable || $self->parse_blankQName || $self->parse_uri;
}

=begin private

=item C<parse_variable_or_uri_or_constant>

Returns the parse tree for a variable, URI, or constant.

=end private

=cut

sub parse_variable_or_uri_or_constant {
	my $self	= shift;
	return $self->parse_variable || $self->parse_constant || $self->parse_uri;
}

=begin private

=item C<parse_constant>

Returns the parse tree for a constant. Either a quoted string (with optional data-
or language-typing), or a number.

=end private

=cut

sub parse_constant {
	my $self	= shift;
	
	if (my $quot = $self->match_pattern(qr/['"]/)) {
		my $str;
		if ($quot eq "'") {
			$str	= $self->match_pattern(qr/([^\'\x0a\x0d]|(\\[tbnrf\"'])|(\\[uU][0-9a-fA-F]{4}))*/);
			$self->match_literal("'")
		} else {
			$str	= $self->match_pattern(qr/([^\"\x0a\x0d]|(\\[tbnrf\"'])|(\\[uU][0-9a-fA-F]{4}))*/);
			$self->match_literal('"')
		}
		
		my ($lang, $dt);
		if ($self->match_literal('@')) {
			$lang	= $self->match_pattern(qr/[A-Za-z]+(-[A-Za-z]+)*/);
		} elsif ($self->match_literal('^^')) {
			$dt		= $self->parse_uri;
		}
		
		if ($lang) {
			return $self->new_literal( $str, $lang, undef );
		} elsif ($dt) {
			return $self->new_literal( $str, undef, $dt );
		} else {
			return $self->new_literal( $str );
		}
	} elsif (my $num = $self->match_pattern(qr/ [-+]?
												(
													(
														([0-9]+)
														([.][0-9]*)?
													)
													| ([.][0-9]+)
												)
												
												([eE] [-+]? [0-9]+)?
											/x)) {
		$num	=~ s/^[+]//;
		my $dt;
		if ($num =~ m/^[-+]?\d+$/) {
			$dt	= $self->new_uri( 'http://www.w3.org/2001/XMLSchema#integer' );
		} elsif ($num =~ /[.][^eE]+$/) {
			$dt	= $self->new_uri( 'http://www.w3.org/2001/XMLSchema#decimal' );
		} else {
			$dt	= $self->new_uri( 'http://www.w3.org/2001/XMLSchema#double' );
		}
		return $self->new_literal( $num, undef, $dt );
	} elsif (my $bool = $self->match_pattern(qr/true|false/)) {
		my $dt	= $self->new_uri( 'http://www.w3.org/2001/XMLSchema#boolean' );
		return $self->new_literal( $bool, undef, $dt );
	}
}

=begin private

=item C<parse_order_by>

Returns the parse tree for an ORDER BY clause.

=end private

=cut

sub parse_order_by {
	my $self	= shift;
	if ($self->match_literal('ORDER BY', 1)) {
		if (my $dir = $self->match_pattern(qr/ASC|DESC/i)) {
			if (my $expr = $self->parse_bracketted_expression) {
				return [ uc($dir), $expr ];
			} else {
				$self->set_commit;
				return $self->fail( 'Expecting ORDER BY expression' );
			}
		} elsif (my $expr = $self->parse_variable || $self->parse_function_call || $self->parse_bracketted_expression) {
			return [ 'ASC', $expr ];
		} else {
			$self->set_commit;
			return $self->fail( 'Expecting ORDER BY expression' );
		}
	} else {
		return $self->fail( 'Expecting ORDER BY clause' );
	}
}

=begin private

=item C<parse_limit>

Returns the parse tree for a LIMIT clause.

=end private

=cut

sub parse_limit {
	my $self	= shift;
	if ($self->match_literal('LIMIT', 1)) {
		my $count	= $self->match_pattern(qr/\d+/);
		return $count;
	} else {
		return $self->fail( 'Expecting LIMIT clause' );
	}
}

=begin private

=item C<parse_offset>

Returns the parse tree for an OFFSET clause.

=end private

=cut

sub parse_offset {
	my $self	= shift;
	if ($self->match_literal('OFFSET', 1)) {
		my $count	= $self->match_pattern(qr/\d+/);
		return $count;
	} else {
		return $self->fail( 'Expecting OFFSET clause' );
	}
}



######################################################################

=begin private

=item C<match_literal ( $literal, $case_insensitive_flag )>

Matches the supplied C<$literal> at the beginning of the reamining text.

If a match is found, returns the literal. Otherwise returns an error via
C<fail> (which might throw an exception if C<set_commit> has been called).

=end private

=cut

sub match_literal {
	my $self	= shift;
	my $literal	= shift;
	my $casei	= shift || 0;
	$self->whitespace;
	
# 	if ($debug > 2) {
# 		my $remaining	= substr($self->{remaining}, 0, 20);
# 		print STDERR "literal match: $literal (remaining: '$remaining...') ... ";
# 	}
	
	my $length	= length($literal);
	
	my $match	= substr($self->{remaining}, 0, $length);
	if ($casei) {
		$literal	= lc($literal);
		$match		= lc($match);
	}
	
	if ($match eq $literal) {
		$self->{position}	+= $length;
		my $match	= substr($self->{remaining}, 0, $length, '');
		
# 		warn "ok\n" if ($debug > 2);
		return $match;
	} else {
		my $error	= qq'Expecting "$literal"';
		$error		.= ' (case insensitive)' if ($casei);
		
# 		warn "failed\n" if ($debug > 2);
		return $self->fail($error);
	}
}

=begin private

=item C<match_pattern ( $pattern )>

Matches the supplied regular expression C<$pattern> at the beginning of the
reamining text.

If a match is found, returns the matching text. Otherwise returns an error via
C<fail> (which might throw an exception if C<set_commit> has been called).

=end private

=cut

sub match_pattern {
	my $self	= shift;
	my $pattern	= shift;
	
	$self->whitespace;
	
# 	if ($debug > 2) {
# 		my $remaining	= substr($self->{remaining}, 0, 20);
# 		print STDERR "pattern match: $pattern (remaining: '$remaining...') ... ";
# 	}
	
	if ($self->{remaining} =~ m/\A(${pattern})/xsm) {
		my $length	= length($1);
		$self->{position}	+= $length;
		my $match	= substr($self->{remaining}, 0, $length, '');
		
# 		warn "ok\n" if ($debug > 2);
		return $match;
	} else {
# 		warn "failed\n" if ($debug > 2);
#		Carp::cluck if ($debug > 2);
		return $self->fail(qq'Expecting pattern match /$pattern/');
	}
}

=begin private

=item C<whitespace>

Matches any whitespace at the beginning of the reamining text.

=end private

=cut

sub whitespace {
	my $self	= shift;
	my $ws		= 1;
	while ($ws) {
		if ($self->{remaining} =~ m#\A(\s+)#xsm) {
			my $length	= length($1);
			substr($self->{remaining}, 0, $length, '');
			$self->{position}	+= $length;
		} elsif ($self->{remaining} =~ m/^(#.*)/) {
			my $length	= length($1);
			substr($self->{remaining}, 0, $length, '');
			$self->{position}	+= $length;
		} else {
			$ws	= 0;
		}
	}
}

######################################################################

=begin private

=item C<set_input ( $input )>

Sets the query string for parsing.

=end private

=cut

sub set_input {
	my $self				= shift;
	my $query				= shift;
	$self->{input}			= $query;
	$self->{remaining}		= $query;
	$self->{position}		= 0;
	return 1;
}

		
=begin private

=item C<get_options ( $distinct, $order, $limit, $offset )>

Returns a HASH of result form arguments.

=end private

=cut

sub get_options {
	my $self	= shift;
	my $distinct	= shift;
	my $order		= shift;
	my $limit		= shift;
	my $offset		= shift;
	my %options;
	
	my $has_options	= 0;
	if ($distinct) {
		$options{distinct}	= 1;
		$has_options		= 1;
	}
	if ($order) {
		$options{orderby}	= [$order];
		$has_options		= 1;
	}
	if ($limit) {
		$options{limit}		= $limit;
		$has_options		= 1;
	}
	if ($offset) {
		$options{offset}	= $offset;
		$has_options		= 1;
	}
	
	if ($has_options) {
		return \%options;
	} else {
		return;
	}
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
