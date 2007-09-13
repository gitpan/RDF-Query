# RDF::Query::Parser::tSPARQL
# -------------
# $Revision: 194 $
# $Date: 2007-04-18 22:26:36 -0400 (Wed, 18 Apr 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Parser::tSPARQL - A temporal-extended SPARQL parser for RDF::Query

=cut

package RDF::Query::Parser::tSPARQL;

use strict;
use warnings;
use base qw(RDF::Query::Parser);

use RDF::Query::Error qw(:try);

use Data::Dumper;
use Parse::Eyapp;
use File::Slurp qw( slurp );
use Carp qw(carp croak confess);
use Scalar::Util qw(reftype blessed);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 0 || $RDF::Query::Parser::debug;
	$VERSION	= do { my $REV = (qw$Revision: 194 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$lang		= 'tsparql';
	$languri	= '--';
	
	my $sgrammar	= <<'__END';
	%tree
	%%
	
	Query:	Prologue SelectQuery		{ { method => 'SELECT', %{ $_[1] }, %{ $_[2] } } }
			| Prologue ConstructQuery	{ { method => 'CONSTRUCT', %{ $_[1] }, %{ $_[2] } } }
			| Prologue DescribeQuery	{ { method => 'DESCRIBE', %{ $_[1] }, %{ $_[2] } } }
			| Prologue AskQuery			{ { method => 'ASK', %{ $_[1] }, %{ $_[2] } } }
			;
	
	Prologue:	BaseDecl? PrefixDecl*	{
											my $ret	= +{
														namespaces	=> { map {%$_} @{$_[2]{children}} },
														map { %$_ } (@{$_[1]{children}})
													};
											$ret;
										};
	
	BaseDecl:	'BASE' IRI_REF					{ +{ 'base' => $_[2] } };
	
	PrefixDecl:	'PREFIX' PNAME_NS IRI_REF		{ +{ $_[2] => $_[3][1] } };
	
	SelectQuery:	'SELECT' SelectModifier? SelectVars DatasetClause* WhereClause SolutionModifier
					{
						my $sel_modifier	= $_[2]{children}[0];
						my $sol_modifier	= $_[6];
						my $ret	= +{
							variables	=> $_[3],
							sources		=> $_[4]{children},
							triples		=> $_[5],
						};
						
						if (my $o = $sol_modifier->{orderby}){
							$ret->{options}{orderby}	= $o;
						}
						if (my $l = $sol_modifier->{limitoffset}) {
							my %data	= @$l;
							while (my($k,$v) = each(%data)) {
								$ret->{options}{$k}	= $v;
							}
						}
						
						if (ref($sel_modifier) and Scalar::Util::reftype($sel_modifier) eq 'ARRAY') {
							my %data	= @$sel_modifier;
							while (my($k,$v) = each(%data)) {
								$ret->{options}{$k}	= $v;
							}
						}
						
						return $ret;
					} ;
	
	SelectModifier: 'DISTINCT'	{ [ distinct => 1 ] }
		| 'REDUCED'				{ [ reduced => 1 ] };
	
	SelectVars: Var+			{ $_[1]{children} }
		| '*'					{ ['*'] };
	
	ConstructQuery:	'CONSTRUCT' ConstructTemplate DatasetClause* WhereClause SolutionModifier
					{
						my $template	= $_[2];
						my $ret	= +{
							construct_triples	=> $template,
							sources				=> $_[3]{children},
							triples				=> $_[4],
						};
						
						return $ret;
					} ;
	
	DescribeQuery:	'DESCRIBE' DescribeVars DatasetClause* WhereClause? SolutionModifier
					{
						my $modifier	= $_[5];
						my $ret	= +{
							variables	=> $_[2],
							sources		=> $_[3]{children},
							triples		=> ${ $_[4]{children} || [] }[0],
						};
						$ret->{triples}	= [] if (not defined($ret->{triples}));
						if (my $o = $modifier->{orderby}){
							$ret->{orderby}	= $o;
						}
						$ret;
					} ;
	DescribeVars: VarOrIRIref+	{ $_[1]{children} }
		| '*'					{ '*' };
	
	AskQuery:	'ASK' DatasetClause* WhereClause
		{
			my $ret	= +{
				sources		=> $_[2]{children},
				triples		=> $_[3],
				variables	=> [],
			};
			return $ret;
		};
	
	DatasetClause:	'FROM' DefaultGraphClause					{ $_[2] }
		| 'FROM NAMED' NamedGraphClause							{ $_[2] }
		;
	
	DefaultGraphClause:	SourceSelector							{ $_[1] };
	
	NamedGraphClause: SourceSelector							{ [ @{ $_[1] }, 'NAMED' ] };
	
	SourceSelector:	IRIref										{ $_[1] };
	
	WhereClause:	'WHERE'? GroupGraphPattern					{
																	my $ggp	= $_[2];
																	shift(@$ggp);
																	$ggp;
																};
	
	SolutionModifier:	OrderClause? LimitOffsetClauses?
		{
			return +{ orderby => $_[1]{children}[0], limitoffset => $_[2]{children}[0] };
		};
	
	LimitOffsetClauses:	LimitClause OffsetClause?				{ [ @{$_[1]}, @{ $_[2]{children}[0] || [] } ] }
		| OffsetClause LimitClause?								{ [ @{$_[1]}, @{ $_[2]{children}[0] || [] } ] }
		;
	
	OrderClause:	'ORDER BY' OrderCondition+
		{
			my $order	= $_[2]{children};
			return $order;
		};
	
	OrderCondition:	OrderDirection BrackettedExpression			{ [ $_[1], $_[2] ] }
		| Constraint											{ [ 'ASC', $_[1] ] }
		| Var													{ [ 'ASC', $_[1] ] }
		;
	OrderDirection: 'ASC'										{ 'ASC' }
		| 'DESC'												{ 'DESC' }
		;
	
	LimitClause:	'LIMIT' INTEGER								{ [ limit => $_[2] ] };
	
	OffsetClause:	'OFFSET' INTEGER							{ [ offset => $_[2] ] };
	
	GroupGraphPattern:	'{' TriplesBlock? ( GGPAtom '.'? TriplesBlock? )* '}'
						{
							my @ggp	= ( @{ $_[2]{children}[0] || [] } );
							if (@{ $_[3]{children} }) {
								my $opt				= $_[3]{children};
								
								my $index	= 0;
								for ($index = 0; $index < $#{$opt}; $index += 3) {
									my $ggpatom			= $opt->[ $index ][0];
									my $ggpatom_triples	= $opt->[ $index ][1];	# XXX
									my $triplesblock	= $opt->[ $index + 2 ];
									my @data			= ($ggpatom);
									
									my @triples;
									if (@$ggpatom_triples) {
										push(@triples, @$ggpatom_triples);
									}
									if (@{ $triplesblock->{children} || [] }) {
										my ($triples)	= @{ $triplesblock->{children} || [] };
										push(@triples, @$triples);
									}
									if (@triples) {
										push(@data, @triples);
									}
									push(@ggp, @data);
								}
							}
							
							if (scalar(@ggp) > 1) {
								for (my $i = $#ggp; $i > 0; $i--) {
									if ($ggp[$i][0] eq 'FILTER' and $ggp[$i-1][0] eq 'FILTER') {
										my ($filter)	= splice(@ggp, $i, 1, ());
										my $expr2		= $filter->[1];
										my $expr1		= $ggp[$i-1][1];
										$ggp[$i-1][1]	= [ '&&', $expr1, $expr2 ];
									}
								}
							}
							
							return [ 'GGP', @ggp ];
						};
	
	GGPAtom: GraphPatternNotTriples									{ $_[1] }
		| Filter													{ [ [ 'FILTER', $_[1] ], [] ] }
		;
	
	TriplesBlock:	TriplesSameSubject ( '.' TriplesBlock? )?
		{
			my @triples	= @{ $_[1] };
			if (@{ $_[2]{children} }) {
				foreach my $child (@{ $_[2]{children} }) {
					foreach my $data (@{ $child->{children} }) {
						push(@triples, @$data);
					}
				}
			}
			
			
			\@triples;
		}
		;
	
	GraphPatternNotTriples:
		OptionalGraphPattern										{ [$_[1],[]] }
		| GroupOrUnionGraphPattern									{ [$_[1],[]] }
		| GraphGraphPattern											{ [$_[1],[]] }
		| TimeGraphPattern
			{
				my $time	= $_[1];
				if (@$time == 3) { # no extra triples from inside the TIME constraint
					return [$time, []];
				} else {			# triples inside the TIME constraint
					my $triples	= pop(@{ $time });
					return [ $time, $triples ];
				}
			}	# XXX
		;
	
	TimeGraphPattern:	'TIME' GraphNode GroupGraphPattern
		{
			my $self				= $_[0];
			my ($node, $triples)	= @{ $_[2] };
			my $ggp	= $_[3];
			shift(@$ggp);
			if (scalar(@$triples)) {		# we can only get triples if the GraphNode is a bNode
				my $blank	= $node->[1];
				my $var		= $self->new_variable();
				foreach my $trip (@$triples) {
					if ($trip->[0][1] eq $blank) {
						$trip->[0] = $var;
					}
				}
				$node		= $var;
				return ['TIME', $node, $ggp, $triples]
			} else {
				return ['TIME', $node, $_[3]]
			}
		};
	
	OptionalGraphPattern:	'OPTIONAL' GroupGraphPattern			{
																		my $ggp	= $_[2];
																		shift(@$ggp);
																		return ['OPTIONAL', $ggp]
																	};
	
	GraphGraphPattern:	'GRAPH' VarOrIRIref GroupGraphPattern		{
																		my $ggp	= $_[3];
																		shift(@$ggp);
																		['GRAPH', $_[2], $ggp]
																	};
	
	GroupOrUnionGraphPattern:	GroupGraphPattern ( 'UNION' GroupGraphPattern )*
		{
			if (@{ $_[2]{children} }) {
				my $total	= $#{ $_[2]{children} };
				my @ggp		= map { [ @{ $_ }[ 1 .. $#{ $_ } ] ] }
							map { $_[2]{children}[$_] } grep { $_ % 2 == 1 } (0 .. $total);
				my $ggp	= $_[1];
				shift(@$ggp);
				my $data	= [
					'UNION',
					$ggp,
					@ggp
				];
				return $data;
			} else {
				return $_[1];
			}
		};
	
	Filter:	'FILTER' Constraint	{
#									warn 'FILTER CONSTRAINT: ' . Dumper($_[2]);
									$_[2]
								} ;
	
	Constraint:	BrackettedExpression								{ $_[1] }
		| BuiltInCall												{ $_[1] }
		| FunctionCall												{ $_[1] }
		;
	
	FunctionCall:	IRIref ArgList
		{
			$_[0]->new_function_expression( $_[1], @{ $_[2] } )
		};
	
	ArgList: '(' Expression ( ',' Expression )* ')'
			{
				my $args	= [
					$_[2],
					map { $_ } @{ $_[3]{children} }
				];
				
				$args;
			}
		| NIL										{ [] };
	
	ConstructTemplate:	'{' ConstructTriples? '}'
	{
		if (@{ $_[2]{children} }) {
			return $_[2]{children}[0];
		} else {
			return {};
		}
	};
	
	ConstructTriples:	TriplesSameSubject ( '.' ConstructTriples? )?
		{
			my @triples	= @{ $_[1] };
			if (@{ $_[2]{children} }) {
				my $triples	= $_[2]{children}[0]{children}[0];
				push(@triples, @{ $triples || [] });
			}
			return \@triples;
		};
	
	TriplesSameSubject:	VarOrTerm PropertyListNotEmpty		{
																my ($props, $triples)	= @{ $_[2] };
																my $subj	= $_[1];
																
																my @triples;
																push(@triples, map { [ $subj, @{$_} ] } @$props);
																push(@triples, @{ $triples });
																return \@triples;
															}
		| TriplesNode PropertyList							{
																my ($node, $triples)	= @{ $_[1] };
																my @triples				= @$triples;
																
																my ($props, $prop_triples)	= @{ $_[2] };
																if (@$props) {
																	push(@triples, @{ $prop_triples });
																	foreach my $child (@$props) {
																		push(@triples, [ $node, @$child ]);
																		
																	}
																}
																
																return \@triples;
															}
		;
	
	PropertyListNotEmpty:	Verb ObjectList ( ';' ( Verb ObjectList )? )*
															{
																my $objectlist	= $_[2];
																my @objects		= @{ $objectlist->[0] };
																my @triples		= @{ $objectlist->[1] };
																
																my $prop = [
																	(map { [ $_[1], $_ ] } @objects),
																	(map {
																		my $o = $_;
																		my @objects	= (ref($_->{children}[1][0]) and reftype($_->{children}[1][0]) eq 'ARRAY')
																					? @{ $_->{children}[1][0] }
																					: ();
																		push(@triples, @{ $_->{children}[1][1] || [] });
																		map {
																			[
																				$o->{children}[0], $_
																			]
																		} @objects;
																	} @{$_[3]{children}})
																];
																return [ $prop, \@triples ];
															};
	
	PropertyList:	PropertyListNotEmpty?
		{
			if (@{ $_[1]{children} }) {
				return $_[1]{children}[0];
			} else {
				return [ [], [] ];
			}
		} ;
	
	ObjectList:	Object ( ',' Object )*
		{
			my @objects	= ($_[1][0], map { $_->[0] } @{ $_[2]{children} });
			my @triples	= (@{ $_[1][1] }, map { @{ $_->[1] } } @{ $_[2]{children} });
			my $data	= [ \@objects, \@triples ];
			return $data;
		};
	
	Object:	GraphNode			{ $_[1] };	# XXX currently ignoring the triples that might come up from an object (like "[ :p ?o ]")
	
	Verb:	VarOrIRIref			{ $_[1] }
		| 'a'					{ $_[0]->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type') }
		;
	
	TriplesNode:	Collection	{ return $_[1] }	# XXX ?
		| BlankNodePropertyList	{ return $_[1] }
		;
	
	BlankNodePropertyList:	'[' PropertyListNotEmpty ']'
		{
			my $node	= $_[0]->new_blank();
			my ($props, $triples)	= @{ $_[2] };
			my @triples	= @$triples;
			
			push(@triples, map { [$node, @$_] } @$props);
			return [ $node, \@triples ];
		};
	
	Collection:	'(' GraphNode+ ')'
		{
			my $self		= $_[0];
			my @children	= @{ $_[2]{children}};
			my @triples;
			
			my $node;
			my $last_node;
			while (my $child = shift(@children)) {
				my $p_first		= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#first');
				my $p_rest		= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#rest');
				my $cur_node	= $self->new_blank();
				if (defined($last_node)) {
					push(@triples, [ $last_node, $p_rest, $cur_node ]);
				}
				
				my ($child_node, $triples)	= @$child;
				push(@triples, [ $cur_node, $p_first, $child_node ]);
				unless (defined($node)) {
					$node	= $cur_node;
				}
				$last_node	= $cur_node;
				push(@triples, @$triples);
			}
			
			my $p_rest		= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#rest');
			my $nil			= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil');
			push(@triples, [ $last_node, $p_rest, $nil ]);
			return [ $node, \@triples ];
		};
	
	GraphNode:	VarOrTerm		{ [$_[1], []] }
		| TriplesNode			{ $_[1] }
		;
	
	VarOrTerm:	Var				{ $_[1] }
		| GraphTerm				{ $_[1] }
		;
	
	VarOrIRIref:	Var			{ $_[1] }
		| IRIref				{ $_[1] }
		;
	
	Var:	VAR1				{ $_[1] }
		| VAR2					{ $_[1] }
		;
	
	GraphTerm:	IRIref 			{ $_[1] }
		| RDFLiteral			{ $_[1] }
		| NumericLiteral		{ $_[1] }
		| BooleanLiteral		{ $_[1] }
		| BlankNode				{ $_[1] }
		| NIL					{ $_[1] }
		;
	
	Expression:	ConditionalOrExpression	{ $_[1] };
	
	ConditionalOrExpression:	ConditionalAndExpression ( '||' ConditionalAndExpression )*
		{
			my $expr	= $_[1];
			if (@{ $_[2]{children} }) {
				$expr	= [ '||', $expr, @{ $_[2]{children} } ];
			}
			$expr;
		};
	
	ConditionalAndExpression:	ValueLogical ( '&&' ValueLogical )*
		{
			my $expr	= $_[1];
			if (@{ $_[2]{children} }) {
				$expr	= [ '&&', $expr, @{ $_[2]{children} } ];
			}
			$expr;
		};
	
	ValueLogical:	RelationalExpression	{ $_[1] };
	
	RelationalExpression:	NumericExpression RelationalExpressionExtra?
		{
			my $expr	= $_[1];
			if (@{ $_[2]{children} }) {
				my $more	= $_[2]{children}[0];
				$expr	= [ $more->[0], $expr, $more->[1] ];
			}
			$expr;
		};
	RelationalExpressionExtra:
		'=' NumericExpression				{ [ '==', $_[2] ] }
		| '!=' NumericExpression			{ [ '!=', $_[2] ] }
		| '<' NumericExpression				{ [ '<', $_[2] ] }
		| '>' NumericExpression				{ [ '>', $_[2] ] }
		| '<=' NumericExpression			{ [ '<=', $_[2] ] }
		| '>=' NumericExpression			{ [ '>=', $_[2] ] }
		;
	
	NumericExpression:	AdditiveExpression	{ $_[1] };
	
	AdditiveExpression:	MultiplicativeExpression AdditiveExpressionExtra*
		{
			my $expr	= $_[1];
			foreach my $extra (@{ $_[2]{children} }) {
				$expr	= [ $extra->[0], $expr, $extra->[1] ];
			}
			return $expr
		};
	AdditiveExpressionExtra: '+' MultiplicativeExpression					{ ['+',$_[2]] }
		| '-' MultiplicativeExpression				{ ['-',$_[2]] }
		| NumericLiteralPositive					{ $_[1] }
		| NumericLiteralNegative					{ $_[1] }
		;
	
	MultiplicativeExpression:	UnaryExpression MultiplicativeExpressionExtra*
	{
			my $expr	= $_[1];
			foreach my $extra (@{ $_[2]{children} }) {
				 $expr	= [ $extra->[0], $expr, $extra->[1] ];
			}
			$expr
	};
	MultiplicativeExpressionExtra: '*' UnaryExpression	{ [ '*', $_[2] ] }
		| '/' UnaryExpression							{ [ '/', $_[2] ] };
	
	UnaryExpression:	'!' PrimaryExpression		{ ['!', $_[2]] } 
		| '+' PrimaryExpression 					{ $_[2] } 
		| '-' PrimaryExpression 					{ ['-', $_[2]] } 
		| PrimaryExpression							{ $_[1] }
		;
	
	PrimaryExpression:	BrackettedExpression 		{ $_[1] }
		| BuiltInCall								{ $_[1] }
		| IRIrefOrFunction							{ $_[1] }
		| RDFLiteral								{ $_[1] }
		| NumericLiteral							{ $_[1] }
		| BooleanLiteral							{ $_[1] }
		| Var										{ $_[1] }
		;
	
	BrackettedExpression:	'(' Expression ')'		{ $_[2] };
	
	BuiltInCall:	STR '(' Expression ')'					{ $_[0]->new_function_expression( $_[0]->new_uri('sop:str'), $_[3] ) }
		| LANG '(' Expression ')' 							{ $_[0]->new_function_expression( $_[0]->new_uri('sparql:lang'), $_[3] ) }
		| LANGMATCHES '(' Expression ',' Expression ')' 	{ $_[0]->new_function_expression( $_[0]->new_uri('sparql:langmatches'), $_[3], $_[5] ) }
		| DATATYPE '(' Expression ')' 						{ $_[0]->new_function_expression( $_[0]->new_uri('sparql:datatype'), $_[3] ) }
		| BOUND '(' Var ')' 								{ $_[0]->new_function_expression( $_[0]->new_uri('sop:isBound'), $_[3] ) }
		| SAMETERM '(' Expression ',' Expression ')' 		{ $_[0]->new_function_expression( $_[0]->new_uri('sparql:sameTerm'), $_[3], $_[5] ) }
		| ISIRI '(' Expression ')' 							{ $_[0]->new_function_expression( $_[0]->new_uri('sop:isIRI'), $_[3] ) }
		| ISURI '(' Expression ')' 							{ $_[0]->new_function_expression( $_[0]->new_uri('sop:isURI'), $_[3] ) }
		| ISBLANK '(' Expression ')' 						{ $_[0]->new_function_expression( $_[0]->new_uri('sop:isBlank'), $_[3] ) }
		| ISLITERAL '(' Expression ')' 						{ $_[0]->new_function_expression( $_[0]->new_uri('sop:isLiteral'), $_[3] ) }
		| RegexExpression									{ $_[1] }	# XXX ^^^^^^^^
		;
	
	RegexExpression:	'REGEX' '(' Expression ',' Expression ( ',' Expression )? ')'
		{
			my @data	= ('~~', $_[3], $_[5]);
			if (scalar(@{ $_[6]->{children} })) {
				push(@data, $_[6]->{children}[0]);
			}
			return \@data;
		} ;
	
	IRIrefOrFunction:	IRIref ArgList?
		{
			my $self	= $_[0];
			my $uri		= $_[1];
			my $args	= $_[2]{children}[0];
			
			if (defined($args)) {
				return $self->new_function_expression( $uri, @$args )
			} else {
				return $uri;
			}
		};
	
	RDFLiteral:	STRING LiteralExtra?		{
												my $self	= $_[0];
												my %extra	= @{ $_[2]{children}[0] || [] };
												$self->new_literal( $_[1], @extra{'lang','datatype'} );
											};
	
	LiteralExtra: LANGTAG					{ [ lang => $_[1] ] }
		| '^^' IRIref						{ [ datatype => $_[2] ] }
		;
	
	NumericLiteral:	NumericLiteralUnsigned	{ my $self = $_[0]; my ($value, $type) = @{$_[1]}; $self->new_literal( $value, undef, $self->new_uri($type) ) }
		| NumericLiteralPositive			{ my $self = $_[0]; my ($value, $type) = @{$_[1]}; $self->new_literal( $value, undef, $self->new_uri($type) ) }
		| NumericLiteralNegative			{ my $self = $_[0]; my ($value, $type) = @{$_[1]}; $self->new_literal( $value, undef, $self->new_uri($type) ) }
		;
	
	NumericLiteralUnsigned:	INTEGER			{ [$_[1], 'http://www.w3.org/2001/XMLSchema#integer'] }
		| DECIMAL							{ [$_[1], 'http://www.w3.org/2001/XMLSchema#decimal'] }
		| DOUBLE							{ [$_[1], 'http://www.w3.org/2001/XMLSchema#double'] }
		;
	
	NumericLiteralPositive:
		INTEGER_POSITIVE					{ [$_[1], 'http://www.w3.org/2001/XMLSchema#integer'] }
		| DECIMAL_POSITIVE					{ [$_[1], 'http://www.w3.org/2001/XMLSchema#decimal'] }
		| DOUBLE_POSITIVE					{ [$_[1], 'http://www.w3.org/2001/XMLSchema#double'] }
		;
	
	NumericLiteralNegative:
		INTEGER_NEGATIVE					{ [$_[1], 'http://www.w3.org/2001/XMLSchema#integer'] }
		| DECIMAL_NEGATIVE					{ [$_[1], 'http://www.w3.org/2001/XMLSchema#decimal'] }
		| DOUBLE_NEGATIVE					{ [$_[1], 'http://www.w3.org/2001/XMLSchema#double'] }
		;
	
	BooleanLiteral:	'TRUE'					{ $_[0]->new_literal( 'true', undef, $_[0]->new_uri( 'http://www.w3.org/2001/XMLSchema#boolean' ) ) }
		| 'FALSE'							{ $_[0]->new_literal( 'false', undef, $_[0]->new_uri( 'http://www.w3.org/2001/XMLSchema#boolean' ) ) }
		;
	
	# String:	STRING_LITERAL1 | STRING_LITERAL2 | STRING_LITERAL_LONG1 | STRING_LITERAL_LONG2;
	
	IRIref:	IRI_REF							{ $_[1] }
		| PrefixedName						{ $_[1] }
		;
	
	PrefixedName:	PNAME_LN				{ $_[1] }
		| PNAME_NS							{ $_[0]->new_uri([$_[1],'']) }
		;
	
	BlankNode:	BLANK_NODE_LABEL			{ $_[1] }
		| ANON								{ $_[1] }
		;
	
	IRI_REF: URI 							{ $_[0]->new_uri($_[1]) };
	
	PNAME_NS:
		NAME ':'
			{
				return $_[1];
			}
		| ':'
			{
				return '__DEFAULT__';
			}
		;
	
	PNAME_LN:	PNAME_NS PN_LOCAL			{
		return $_[0]->new_uri([$_[1], $_[2]]);
	};
	
	BLANK_NODE_LABEL:	'_:' PN_LOCAL		{
												my $self	= $_[0];
												my $name	= $_[2];
												$self->register_blank_node( $name );
												return $self->new_blank( $name );
											};
	
	PN_LOCAL: VARNAME PN_LOCAL_EXTRA			# XXX PN_LOCAL_EXTRA should have kleene star, but YAPP seems to be broken
			{
				my $name	= $_[1];
				my $extra	= $_[2];
				return join('',$name,$extra);
			}
		| INTEGER VARNAME PN_LOCAL_EXTRA		{
				my $int		= $_[1];
				my $name	= $_[2];
				my $extra	= $_[3];
				return join('',$int,$name,$extra);
			}
		| INTEGER VARNAME						{
				my $int		= $_[1];
				my $name	= $_[2];
				return join('',$int,$name);
			}
		| VARNAME								{ $_[1] }
		;
	
	PN_LOCAL_EXTRA: INTEGER_NO_WS			{ return $_[1] }
		| '-' NAME							{ return "-$_[2]" }
		| '_' NAME							{ return "_$_[2]" }
		;
		
	VAR1:	'?' VARNAME						{ ['VAR',$_[2]] };
	
	VAR2:	'$' VARNAME						{ ['VAR',$_[2]] };
	
	LANGTAG:	'@' NAME ('-' NAME+)* 		{ join('-', $_[2], map { $_->{children}[0]{attr} } @{ $_[3]{children} }) };
#	DECIMAL:	INTEGER '.' INTEGER?		{ my $frac = $_[3]{children}[0]{attr} || 0; eval "$_[1].$frac" }
#		| '.' INTEGER						{ my $frac = $_[2]{children}[0]{attr} || 0; eval "0.$frac" }
#		;
	INTEGER_POSITIVE:	'+' INTEGER			{ $_[2] } ;
	DOUBLE_POSITIVE:	'+' DOUBLE			{ $_[2] } ;
	DECIMAL_POSITIVE:	'+' DECIMAL			{ $_[2] } ;
#	INTEGER_NEGATIVE:	'-' INTEGER			{ -$_[2]{attr} } ;
#	DECIMAL_NEGATIVE:	'-' DECIMAL			{ -$_[2]{attr} } ;
#	DOUBLE_NEGATIVE:	'-' DOUBLE			{ -$_[2]{attr} } ;
	
	VARNAME: NAME 							{ $_[1] }
		| a									{ $_[1] }
		|	ASC								{ $_[1] }
		|	ASK								{ $_[1] }
		|	BASE							{ $_[1] }
		|	BOUND							{ $_[1] }
		|	CONSTRUCT						{ $_[1] }
		|	DATATYPE						{ $_[1] }
		|	DESCRIBE						{ $_[1] }
		|	DESC							{ $_[1] }
		|	DISTINCT						{ $_[1] }
		|	FILTER							{ $_[1] }
		|	FROM							{ $_[1] }
		|	GRAPH							{ $_[1] }
		|	LANGMATCHES						{ $_[1] }
		|	LANG							{ $_[1] }
		|	LIMIT							{ $_[1] }
		|	NAMED							{ $_[1] }
		|	OFFSET							{ $_[1] }
		|	OPTIONAL						{ $_[1] }
		|	PREFIX							{ $_[1] }
		|	REDUCED							{ $_[1] }
		|	REGEX							{ $_[1] }
		|	SELECT							{ $_[1] }
		|	STR								{ $_[1] }
		|	TIME							{ $_[1] }
		|	UNION							{ $_[1] }
		|	WHERE							{ $_[1] }
		|	ISBLANK							{ $_[1] }
		|	ISIRI							{ $_[1] }
		|	ISLITERAL						{ $_[1] }
		|	ISURI							{ $_[1] }
		|	SAMETERM						{ $_[1] }
		|	TRUE							{ $_[1] }
		|	FALSE							{ $_[1] }
		;
	
	NIL:	'(' WS* ')'						{ $_[0]->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil') };
	
	ANON:	'[' WS* ']' 					{ $_[0]->new_blank() };
	
	
	
	INTEGER:	INTEGER_WS					{ $_[1] }
		|		INTEGER_NO_WS				{ $_[1] }
		;
	
	
	# INTEGER:	[0-9]+ ;
	# DOUBLE:	INTEGER '.' INTEGER? EXPONENT | '.' INTEGER EXPONENT | INTEGER EXPONENT ;
	#STRING_LITERAL1:	'\'' ( ([^#x27#x5C#xA#xD]) | ECHAR )* '\'' ;
	#STRING_LITERAL2:	'"' ( ([^#x22#x5C#xA#xD]) | ECHAR )* '"' ;
	#STRING_LITERAL_LONG1:	"'''" ( ( "'" | "''" )? ( [^'\] | ECHAR ) )* "'''" ;
	#STRING_LITERAL_LONG2:	'"""' ( ( '"' | '""' )? ( [^"\] | ECHAR ) )* '"""' ;
	# ECHAR:	'\' [tbnrf\"'] ;
	
	
	%%
	use Data::Dumper;
	
	{
	my $last;
	sub _Lexer {
		my $self	= shift;
		my ($type,$value)	= __Lexer( $self, $last );
	#	warn "$type\t=> $value\n";
	#	warn "pos => " . pos($self->YYData->{INPUT}) . "\n";
	#	warn "len => " . length($self->YYData->{INPUT}) . "\n";
		$last	= [$type,$value];
		no warnings 'uninitialized';
		return ($type,"$value");
	}
	}
	
	sub __new_value {
		my $parser	= shift;
		my $value	= shift;
		my $ws		= shift;
		return $value;
#		return RDF::Query::Parser::SPARQL::Value->new( $token, $value );
	}
	
	sub _literal_escape {
		my $value	= shift;
		for ($value) {
			s/\\t/\t/g;
			s/\\n/\n/g;
			s/\\r/\r/g;
			s/\\b/\b/g;
			s/\\f/\f/g;
			s/\\"/"/g;
			s/\\'/'/g;
			s/\\\\/\\/g;
		}
		return $value;
	}
	
	sub __Lexer {
		my $parser	= shift;
		my $last	= shift;
		my $lasttok	= $last->[0];
		
		for ($parser->YYData->{INPUT}) {
			my $index	= pos($_) || -1;
			return if ($index == length($parser->YYData->{INPUT}));
			
			my $ws	= 0;
	#		warn "lexing at: " . substr($_,$index,20) . " ...\n";
			while (m{\G\s+}gc or m{\G#(.*)}gc) {	# WS and comments
				$ws	= 1;
			}
				
	#		m{\G(\s*|#(.*))}gc and return('WS',$1);	# WS and comments
			
			m{\G(
					ASC\b
				|	ASK\b
				|	BASE\b
				|	BOUND\b
				|	CONSTRUCT\b
				|	DATATYPE\b
				|	DESCRIBE\b
				|	DESC\b
				|	DISTINCT\b
				|	FILTER\b
				|	FROM[ ]NAMED\b
				|	FROM\b
				|	GRAPH\b
				|	LANGMATCHES\b
				|	LANG\b
				|	LIMIT\b
				|	NAMED\b
				|	OFFSET\b
				|	OPTIONAL\b
				|	ORDER[ ]BY\b
				|	PREFIX\b
				|	REDUCED\b
				|	REGEX\b
				|	SELECT\b
				|	STR\b
				|	TIME\b
				|	UNION\b
				|	WHERE\b
				|	isBLANK\b
				|	isIRI\b
				|	isLITERAL\b
				|	isURI\b
				|	sameTerm\b
				|	true\b
				|	false\b
			)}xigc and return(uc($1), $parser->__new_value( $1, $ws ));
			m{\G(
					a(?=(\s|[#]))\b
			
			)}xgc and return($1,$parser->__new_value( $1, $ws ));
			
			
			m{\G'''((?:('|'')?(\\([tbnrf\\"'])|[^'\x92]))*)'''}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
			m{\G"""((?:(?:"|"")?(?:\\(?:[tbnrf\\"'])|[^"\x92]))*)"""}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
			m{\G'((([^\x27\x5C\x0A\x0D])|\\([tbnrf\\"']))*)'}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
			m{\G"((([^\x22\x5C\x0A\x0D])|\\([tbnrf\\"']))*)"}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
			
			
			m{\G<([^<>"{}|^`\x92]*)>}gc and return('URI',$parser->__new_value( $1, $ws ));
			
			m{\G(
					!=
				|	&&
				|	<=
				|	>=
				|	\Q||\E
				|	\Q^^\E
				|	_:
			)}xgc and return($1,$parser->__new_value( $1, $ws ));
			
			m{\G([_A-Za-z][._A-Za-z0-9]*)}gc and return('NAME',$parser->__new_value( $1, $ws ));
			m{\G([_A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{02FF}\x{0370}-\x{037D}\x{037F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]+)}gc and return('NAME',$parser->__new_value( $1, $ws ));
			
			
			m{\G([-]?(\d+)?[.](\d+)[eE][+-]?[0-9]+)}gc and return('DOUBLE',$parser->__new_value( $1, $ws ));
			m{\G([-]?\d+[eE][+-]?[0-9]+)}gc and return('DOUBLE',$parser->__new_value( $1, $ws ));
			m{\G([-]?(\d+[.]\d*|[.]\d+))}gc and return('DECIMAL',$parser->__new_value( $1, $ws ));
			if ($ws) {
				m{\G([-]?\d+)}gc and return('INTEGER_WS',$parser->__new_value( $1, $ws ));
			} else {
				m{\G([-]?\d+)}gc and return('INTEGER_NO_WS',$parser->__new_value( $1, $ws ));
			}
			
			
			m{\G([@!$()*+,./:;<=>?\{\}\[\]\\-])}gc and return($1,$parser->__new_value( $1, $ws ));
			
			my $p	= pos();
			my $l	= length();
			if ($p < $l) {
				warn "uh oh! input = '" . substr($_, $p, 10) . "'";
			}
			return ('', undef);
		}
	};
	
	sub Run {
		my($self)=shift;
		for ($self->YYData->{INPUT}) {
			s/\\u([0-9a-fA-F]{4})/chr(hex($1))/ge;
			s/\\U([0-9a-fA-F]{8})/chr(hex($1))/ge;
		}
		$self->YYParse(
			yylex	=> \&_Lexer,
			yyerror	=> \&_Error,
			yydebug	=> 0,#0x01 | 0x04, #0x01 | 0x04,	# XXX
		);
	}
	
	sub _Error {
		my $parser	= shift;
		my($token)=$parser->YYCurval;
		my($what)	= $token ? "input: '$token'" : "end of input";
		my @expected = $parser->YYExpect();
		
		my $error;
		if (scalar(@expected) == 1 and $expected[0] eq '') {
			$error	= "Syntax error; Remaining input";
		} else {
			our %EXPECT_DESC;
			if (exists $EXPECT_DESC{ $expected[0] }) {
				my @expect	= @EXPECT_DESC{ @expected };
				if (@expect > 1) {
					my $a	= pop(@expect);
					my $b	= pop(@expect);
					no warnings 'uninitialized';
					push(@expect, "$a or $b");
				}
				
				my $expect	= join(', ', @expect);
				if ($expect eq 'DESCRIBE, ASK, CONSTRUCT or SELECT') {
					$expect	= 'query type';
				}
				$error	= "Syntax error; Expecting $expect near $what";
			} else {
				use utf8;
				$error	= "Syntax error; Expected one of the following terminals (near $what): " . join(', ', map {"«$_»"} @expected);
			}
		}
		
		$parser->{error}	= $error;
		Carp::confess $error;
	}
	
__END
	Parse::Eyapp->new_grammar( # Create the parser package/class
		input		=>  $sgrammar,
		classname	=> 'RDF::Query::Parser::tSPARQL', # The name of the package containing the parser
		firstline	=> 37       # String $grammar starts at line 37 (for error diagnostics)
	);
}


######################################################################

=head1 METHODS

=over 4

=cut

our %EXPECT_DESC	= (
	'{'			=> 'GroupGraphPattern or ConstuctTemplate',
	'('			=> 'ArgList, Collection, BrackettedExpression or NIL',
	map { $_ => $_ } qw(SELECT ASK DESCRIBE CONSTRUCT FILTER GRAPH OPTIONAL),
);


=item C<< new () >>

Returns a new SPARQL parser object.

=begin private

=item C<< Run >>

Internal Parse::Eyapp method.

=end private



=item C<< parse ( $query ) >>

Parses the supplied SPARQL query string, returning a parse tree.

=cut

sub parse {
	my $self	= shift;
	my $query	= shift;
	undef $self->{error};
	$self->YYData->{INPUT} = $query;
	$self->{blank_ids}		= 1;
	my $t = eval { $self->Run };                    # Parse it!
	
	if ($@) {
#		warn $@;	# XXX
		return;
	} else {
		my $ok	= $self->fixup_triples( $t->{triples} );
#		warn "fixup ok? <$ok>\n";
		return unless $ok;
		return $t;
	}
}

=begin private

=item C<< fixup_triples ( \@triples ) >>

Checks all triples recursively for proper use of blank node labels (the same
labels cannot be re-used across different BGPs). Returns true if the blank
node label use is proper, false otherwise.

=end private

=cut

sub fixup_triples {
	my $self	= shift;
	my $triples	= shift;
	my $block	= $triples;
	my $part	= 1;
	unless (reftype($triples) eq 'ARRAY') {
		confess Dumper($triples);
	}
	
	foreach my $triple (@$triples) {
		my $context	= join('', $block, $part);
		my $type	= $self->fixup( $context, $triple );
		return unless $type;
		$part++ if ($type =~ /OPTIONAL|GRAPH|UNION|GGP|TIME/);
	}
	return 1;
}

=begin private

=item C<< fixup ( $context, $triple ) >>

Takes a triple or parse-tree atom, and returns true if the triple conforms
to the SPARQL spec regarding the re-use of blank node labels.
C<<$context>> is an opaque string representing the enclosing BGP of the triple.

=end private

=cut

sub fixup {
	my $self	= shift;
	my $context	= shift;
	my $triple	= shift;
	
	Carp::confess Dumper($triple) unless (reftype($triple) eq 'ARRAY');
	my $type	= $triple->[0];
	if (ref($type)) {
		my ($s,$p,$o)	= @$triple;
		foreach my $node ($s,$p,$o) {
			no warnings 'uninitialized';
			if (reftype($node) eq 'ARRAY') {
				if ($node->[0] eq 'BLANK' and $self->{__blank_nodes}{$node->[1]}) {
					my $name	= $node->[1];
#					warn "GOT A BLANK NODE ($name) in context: $context!";
					if (not exists ($self->{__registered_blank_nodes}{$name})) {
#						warn "\thaven't seen this blank node before\n";
						$self->{__registered_blank_nodes}{$name}	= "$context";
					}
					
					if ($self->{__registered_blank_nodes}{$name} ne "$context") {
#						warn "\tblank node conflicts with previous use\n";
						$self->{error}	= "Syntax error; Same blank node identifier ($name) used in more than one basic graph pattern.";
						return;
					}
				}
			} else {
				warn "unknown fixup type: " . Dumper($node);
			}
		}
		return 'TRIPLE';
	} else {
		no warnings 'uninitialized';
		if ($triple->[0] =~ /^(VAR|URI|LITERAL)$/) {
			return 1;
		} elsif ($triple->[0] eq 'GGP') {
			return unless $self->fixup( $triple->[1], $triple->[1] );
			return 'GGP';
		} elsif ($triple->[0] eq 'OPTIONAL') {
			return unless $self->fixup_triples( $triple->[1] );
			return 'OPTIONAL';
		} elsif ($triple->[0] eq 'GRAPH') {
			return unless $self->fixup_triples( $triple->[2] );
			return 'GRAPH';
		} elsif ($triple->[0] eq 'TIME') {
			return unless $self->fixup_triples( $triple->[2] );
			return 'TIME';
		} elsif ($triple->[0] eq 'FILTER') {
			return unless $self->fixup( $context, $triple->[1] );
			return 'FILTER';
		} elsif ($triple->[0] eq 'UNION') {
			return unless $self->fixup_triples( $triple->[1] );
			return unless $self->fixup_triples( $triple->[2] );
			return 'UNION';
		} elsif ($triple->[0] =~ qr#^[=~<>!&|*/+-]# || $triple->[0] eq 'FUNCTION') {
			return unless $self->fixup_triples([ @{$triple}[1..$#{$triple}] ]);
			return 1;
		} else {
			warn "unrecognized triple: " . Dumper($triple);
			return 0;
		}
	}
}

=begin private

=item C<< register_blank_node ( $name ) >>

Used during parsing, this method registers the names of blank nodes that are
used in the query so that they may be checked after the parse.

=end private

=cut

sub register_blank_node {
	my $self	= shift;
	my $name	= shift;
	no warnings 'uninitialized';
	$self->{__blank_nodes}{$name}++;
}



=item C<< error >>

Returns the latest parse error string.

=cut

sub error {
	my $self	= shift;
	if (defined($self->{error})) {
		return $self->{error};
	} else {
		return;
	}
}


# package RDF::Query::Parser::SPARQL::Value;
# 
# use overload '""' => sub { $_[0][0] };
# 
# sub new {
# 	my $class	= shift;
# 	my $data	= [ @_ ];
# 	return bless($data, $class);
# }


1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
