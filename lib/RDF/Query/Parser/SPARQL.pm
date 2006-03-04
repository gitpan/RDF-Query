# RDF::Query::Parser::SPARQL
# -------------
# $Revision: 130 $
# $Date: 2006-03-03 14:50:45 -0500 (Fri, 03 Mar 2006) $
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
use LWP::Simple ();
use Digest::SHA1  qw(sha1_hex);
use Carp qw(carp croak confess);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 1;
	$VERSION	= do { my $REV = (qw$Revision: 130 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
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

# query
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

# namespaces
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

# identifier
sub parse_identifier {
	my $self	= shift;
	return $self->match_pattern(qr/(([a-zA-Z0-9_.-])+)/);
}

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

# variables
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

# SourceClause
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

# URI
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

sub parse_ncname_prefix {
	my $self		= shift;
	my $ncchar1p	= qr/[A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{02FF}\x{0370}-\x{037D}\x{037F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]/x;
	my $ncchar		= qr/${ncchar1p}|_|[0-9]|\x{00B7}|[\x{0300}-\x{036F}]|[\x{203F}-\x{2040}]/x;
	my $ncchar_p	= qr/${ncchar1p}((${ncchar}|[.])*${ncchar})?/x;
	return $self->match_pattern(qr/${ncchar_p}/);
}

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

# blankQName
sub parse_blankQName {
	my $self	= shift;
	if ($self->match_literal('_:')) {
		my $id	= $self->match_pattern(qr/([^ \t\r\n<>();,]+)/);
		return $self->new_blank($id);
	} else {
		return $self->fail( 'Expecting a blank identifier (QName)' );
	}
}

# triplepatterns
sub parse_triple_patterns {
	my $self	= shift;
	
	my $triples	= [];
	
	if ($self->match_literal('{')) {
		while (my $triple = $self->parse_triplepattern) {
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
			
			last unless $self->match_literal('.');
		}
		
		$self->set_commit;
		$self->match_literal('}');
		$self->unset_commit;
		
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

# triplepattern
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
			try {
				$pred		= $self->parse_predicate;
				if (my $data = $self->parse_collection) {
					($obj, my $collection_triples)	= @$data;
					push(@$triples, @{ $collection_triples });
				} else {
					$obj		= $self->parse_object;
				}
				$optobjs	= $self->parse_optional_objects;
				
				# triples from the subject position come before the main triple
				if ($pred and $obj) {
					push( @$triples, $self->new_triple($subj, $pred, $obj) );
				}
			} catch RDF::Query::Error::ParseError with {
				$self->unset_commit;
			};
		} else {
			$pred		= $self->parse_predicate;
			if (my $data = $self->parse_collection) {
				($obj, my $collection_triples)	= @$data;
				push(@$triples, @{ $collection_triples });
			} else {
				$obj		= $self->parse_object;
			}
			$optobjs	= $self->parse_optional_objects;
			
			# triples from the object position get bumped after the main triple
			if ($pred and $obj) {
				unshift( @$triples, $self->new_triple($subj, $pred, $obj) );
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

# Object
sub parse_object {
	my $self	= shift;
	if (my $object = $self->parse_variable_or_uri_or_constant) {
		return $object;
	} else {
		return $self->parse_collection;
	}
}

# OptObj
sub parse_optional_objects {
	my $self	= shift;
	
	my @objects;
	while ($self->match_literal(',')) {
		push(@objects, $self->parse_object);
	}
	return \@objects;
}

# OptPredObj
sub parse_optional_predicate_objects {
	my $self	= shift;
	
	my @pred_objs;
	while (my $data = $self->parse_predicate_object) {
		push(@pred_objs, @{ $data });
		last unless $self->match_literal(';');
	}
	return \@pred_objs;
}

# PredObj
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

# Collection
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

# blanknode
sub parse_blanknode {
	my $self	= shift;
	if ($self->match_literal('[')) {
		my $predobj	= $self->parse_optional_predicate_objects;
		
		my $id		= 'a' . ++$self->{blank_ids};
		my $subj	= $self->new_blank( $id );
		my $triples	= $predobj ? [ map { $self->new_triple($subj, @$_) } (@$predobj) ] : [];
		
		$self->set_commit;
		$self->match_literal(']');
		$self->unset_commit;
		
		return [ $subj, $triples ];
	} else {
		return $self->fail( 'Expecting a Blank node []' );
	}
}

# constraints
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

# Expression
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

sub parse_value_logical {
	my $self	= shift;
	my $expr1	= $self->parse_numeric_expression;
	
	if (my $op = $self->match_pattern(qr/(=|!=|<|>|<=|>=)/)) {
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

sub parse_primary_expression {
	my $self	= shift;
	
	my $expr;
	if ($expr = $self->parse_bracketted_expression) {
	} elsif ($expr = $self->parse_built_in_call_expression) {
	} elsif ($expr = $self->parse_blankQName) {
	} elsif ($expr = $self->parse_constant) {
	} elsif (my $data = $self->parse_blanknode) {
		(undef, $expr)	= @$data;
	} elsif ($expr = $self->parse_variable) {
	} elsif ($expr = $self->parse_iriref_or_function) {
	}
	
	unless ($expr) {
		return $self->fail('Expecting a primary expression');
	}
	
	warn "got primary expr: " . Dumper($expr) if ($debug > 1);
	return $expr;
}

# CallExpression
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
		return $self->new_function_expression( $self->new_uri('XXX DATATYPE'), $str );
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

# ArgList
sub parse_arguments {
	my $self	= shift;
	
	my @args;
	while (my $arg = $self->parse_variable_or_uri_or_constant) {
		push(@args, $arg);
		last unless $self->match_literal(',');
	}
	return \@args;
}

# PredVarUri
sub parse_predicate {
	my $self	= shift;
	if ($self->match_literal('a', 1)) {
		return $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type');
	} else {
		return $self->parse_variable_or_uri;
	}
}

# VarUri
sub parse_variable_or_uri {
	my $self	= shift;
	return $self->parse_variable || $self->parse_blankQName || $self->parse_uri;
}

# VarUriConst
sub parse_variable_or_uri_or_constant {
	my $self	= shift;
	return $self->parse_variable || $self->parse_constant || $self->parse_uri;
}

# CONST
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
		return $self->new_literal( $num );
	}
}

# OptOrderBy
sub parse_order_by {
	my $self	= shift;
	if ($self->match_literal('ORDER BY', 1)) {
		if (my $dir = $self->match_pattern(qr/ASC|DESC/i)) {
			if (my $expr = $self->parse_bracketted_expression) {
				return [ uc($dir), $expr ];
			} else {
				return $self->fail( 'Expecting ORDER BY expression' );
			}
		} else {
			my $expr	= $self->parse_variable || $self->parse_function_call || $self->parse_bracketted_expression;
			return [ 'ASC', $expr ];
		}
	} else {
		return $self->fail( 'Expecting ORDER BY clause' );
	}
}

# OptLimit
sub parse_limit {
	my $self	= shift;
	if ($self->match_literal('LIMIT', 1)) {
		my $count	= $self->match_pattern(qr/\d+/);
		return $count;
	} else {
		return $self->fail( 'Expecting LIMIT clause' );
	}
}

# OptOffset
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

sub match_literal {
	my $self	= shift;
	my $literal	= shift;
	my $casei	= shift || 0;
	$self->whitespace;
	
	if ($debug > 2) {
		my $remaining	= substr($self->{remaining}, 0, 20);
		print STDERR "literal match: $literal (remaining: '$remaining...') ... ";
	}
	
	my $length	= length($literal);
	
	my $match	= substr($self->{remaining}, 0, $length);
	if ($casei) {
		$literal	= lc($literal);
		$match		= lc($match);
	}
	
	if ($match eq $literal) {
		$self->{position}	+= $length;
		my $match	= substr($self->{remaining}, 0, $length, '');
		
		warn "ok\n" if ($debug > 2);
		return $match;
	} else {
		my $error	= qq'Expecting "$literal"';
		$error		.= ' (case insensitive)' if ($casei);
		
		warn "failed\n" if ($debug > 2);
		return $self->fail($error);
	}
}

sub match_pattern {
	my $self	= shift;
	my $pattern	= shift;
	
	if ($debug > 2) {
		my $remaining	= substr($self->{remaining}, 0, 20);
		print STDERR "pattern match: $pattern (remaining: '$remaining...') ... ";
	}
	
	$self->whitespace;
	if ($self->{remaining} =~ m#^(${pattern})#xsm) {
		my $length	= length($1);
		$self->{position}	+= $length;
		my $match	= substr($self->{remaining}, 0, $length, '');
		
		warn "ok\n" if ($debug > 2);
		return $match;
	} else {
		warn "failed\n" if ($debug > 2);
#		Carp::cluck if ($debug > 2);
		return $self->fail(qq'Expecting pattern match /$pattern/');
	}
}

sub whitespace {
	my $self	= shift;
	if ($self->{remaining} =~ m#^(\s*)#xsm) {
		my $length	= length($1);
		substr($self->{remaining}, 0, $length, '');
		$self->{position}	+= $length;
	}
}

######################################################################

sub set_input {
	my $self				= shift;
	my $query				= shift;
	$self->{input}			= $query;
	$self->{remaining}		= $query;
	$self->{position}		= 0;
	return 1;
}

		
sub get_options {
	my $self	= shift;
	my $distinct	= shift;
	my $order		= shift;
	my $limit		= shift;
	my $offset		= shift;
	my %options;
	
	if ($distinct) {
		$options{distinct}	= 1;
	}
	if ($order) {
		$options{orderby}	= [$order];
	}
	if ($limit) {
		$options{limit}		= $limit;
	}
	if ($offset) {
		$options{offset}	= $offset;
	}
	
	if (%options) {
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
