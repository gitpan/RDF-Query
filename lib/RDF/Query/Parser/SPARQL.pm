# RDF::Query::Parser::SPARQL
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Parser::SPARQL - A SPARQL parser for RDF::Query

=cut

package RDF::Query::Parser::SPARQL;

use strict;
use warnings;
use Carp qw(carp croak confess);

use Data::Dumper;
use LWP::Simple ();
use Parse::RecDescent;
use Digest::SHA1  qw(sha1_hex);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$::RD_TRACE	= undef;
	$::RD_HINT	= undef;
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$lang		= 'sparql';
	$languri	= 'http://www.w3.org/TR/rdf-sparql-query/';
}

our %blank_ids;
our($SPARQL_GRAMMAR);
BEGIN {
	our $SPARQL_GRAMMAR	= <<'END';
	query:			namespaces /SELECT|DESCRIBE/i <commit> OptDistinct(?) variables SourceClause(s?) (/WHERE/i)(?) triplepatterns OptOrderBy(?) OptLimit(?) OptOffset(?)
																	{
																		$return = {
																			method		=> uc($item[2]),
																			variables	=> $item{variables},
																			sources		=> $item[6],
																			triples		=> $item{triplepatterns}[0] || [],
																			constraints	=> $item{triplepatterns}[1] || [],
																			namespaces	=> $item{namespaces}
																		};
																		
																		$return->{options}{distinct}	= 1 if ($item{'OptDistinct(?)'}[0]);
																		if (@{ $item{'OptOrderBy(?)'} }) {
																			$return->{options}{orderby}	= $item{'OptOrderBy(?)'}[0];
																		}
																		if (@{ $item{'OptLimit(?)'} }) {
																			$return->{options}{limit}	= $item{'OptLimit(?)'}[0];
																		}
																		if (@{ $item{'OptOffset(?)'} }) {
																			$return->{options}{offset}	= $item{'OptOffset(?)'}[0];
																		}
																	}
	variables: '*'													{ $return = [ $item[1] ] }
	variables: variable Comma(?) variables							{ $return = [ $item[1], @{ $item[3] } ] }
	variables: variable												{ $return = [ $item[1] ] }
	query:			namespaces /CONSTRUCT/i <commit> triplepatterns SourceClause(s?) /WHERE/i triplepatterns OptOrderBy(?) OptLimit(?) OptOffset(?)
																	{
																		$return = {
																			method				=> 'CONSTRUCT',
																			variables			=> [],
																			construct_triples	=> $item[4][0] || [],
																			sources				=> $item[5],
																			triples				=> $item[7][0] || [],
																			constraints			=> $item[7][1] || [],
																			namespaces			=> $item{namespaces}
																		};
																		$return->{options}{distinct}	= 1;
																		if (@{ $item{'OptOrderBy(?)'} }) {
																			$return->{options}{orderby}	= $item{'OptOrderBy(?)'}[0];
																		}
																		if (@{ $item{'OptLimit(?)'} }) {
																			$return->{options}{limit}	= $item{'OptLimit(?)'}[0];
																		}
																		if (@{ $item{'OptOffset(?)'} }) {
																			$return->{options}{offset}	= $item{'OptOffset(?)'}[0];
																		}
																	}
	query:			namespaces /ASK/i <commit> SourceClause(s?) triplepatterns
																	{
																		$return = {
																			method		=> 'ASK',
																			variables	=> [],
																			sources		=> $item[4],
																			triples		=> $item{triplepatterns}[0] || [],
																			constraints	=> $item{triplepatterns}[1] || [],
																			namespaces	=> $item{namespaces}
																		};
																	}
	OptDistinct:				/DISTINCT/i										{ $return = 1 }
	OptLimit:					/LIMIT/i /(\d+)/								{ $return = $item[2] }
	OptOffset:					/OFFSET/i /(\d+)/								{ $return = $item[2] }
	OptOrderBy:					/ORDER BY/i OrderCondition(s)					{ $return = $item[2] }
	OrderCondition:				/ASC|DESC/i <commit> BrackettedExpression		{ $return = [uc($item[1]), $item{BrackettedExpression}] }
					|			variable										{ $return = ['ASC', $item[1]] }
					|			FunctionCall									{ $return = ['ASC', $item[1]] }
					|			BrackettedExpression							{ $return = ['ASC', $item[1]] }
	SourceClause:				/SOURCE|FROM/i Source							{ $return = $item[2] }
	SourceClause:				/FROM NAMED/i Source							{ $return = [ @{ $item[2] }, 'NAMED' ] }
	
	Source:						URI												{ $return = $item[1] }
	variable:					/[?\$]/ identifier								{ $return = [ 'VAR',$item{identifier} ] }
	triplepatterns:				'{' triplepattern moretriple(s?) OptDot(?) '}'	{
																					my @data	= (@{ $item[2] }, map { @{ $_ } } @{ $item[3] });
																					my @filters	= map { $_->[1] } grep { $_->[0] eq 'FILTER' } @data;
																					my @triples;
																					while (my $data = shift(@data)) {
																						if ($data->[0] eq 'TRIPLE') {
																							#############################################################################
																							### XXX What the hell is this for? Need to figure out why this was written...
																							if (ref($data->[1][2][0]) and eval { $data->[1][2][0][0] eq 'TRIPLE' } and not $@) {
																								my @new	= @{ $data->[1][2] };
																								push(@data, @new);
																								$data->[1][2]	= $data->[1][2][0][1][0];
																							}
																							#############################################################################
																							push(@triples, $data->[1]);
																						} elsif ($data->[0] eq 'OPTIONAL') {
																							push(@triples, $data);
																						} elsif ($data->[0] eq 'UNION') {
																							push(@triples, $data);
																						} elsif ($data->[0] eq 'GRAPH') {
																							#############################
																							### XXX $data->[2][1] contains FILTERS...
																							### XXX we're currently just ignoring them
																							### we need to start respecting them.
																							my $triples	= $data->[2][0];
																							$data->[2]	= $triples;
																							#############################
																							push(@triples, $data);
																						}
																					}
																					
																					my $filters	= scalar(@filters) <= 1
																								? $filters[0]
																								: [ '&&', @filters ];
																					$return = [ \@triples, $filters ];
																				}
	moretriple:					'.' triplepattern								{
																					$return = $item[2];
																				}
	triplepattern:				(VarUri|blanknode) PredVarUri Object OptObj(s?) OptPredObj(s?)	{
																					$return = [
																								['TRIPLE',
																									[@item[1,2,3]]],
																									map { ['TRIPLE', [$item[1], @{$_}]] }
																										(@{$item[5] || []}, map { [$item[2], $_] } @{$item[4] || []})
																								];
																				}
	triplepattern:				/OPTIONAL/i <commit> triplepatterns				{ $return = [[ 'OPTIONAL', ($item{triplepatterns}[0] || []) ]] }
	triplepattern:				/GRAPH/i <commit> VarUri triplepatterns			{ $return = [ [ 'GRAPH', $item{VarUri}, $item{triplepatterns} ] ]; }
	
	
	
	
	
	triplepattern:				triplepatterns /UNION/i <commit> triplepatterns	{ $return = [[ 'UNION', ($item[1][0] || []), ($item[4][0] || []) ]] }
	triplepattern:				constraints										{ $return = [[ 'FILTER', $item[1] ]] }
	triplepattern:				blanktriple PredObj(?)							{
																					my ($b,$t)	= @{ $item[1] };
																					$return = [ (map { ['TRIPLE', $_] } @$t), map { ['TRIPLE', [$b, @$_]] } @{ $item[2] } ];
																				}
	triplepattern:				triplepatterns									{ $return = $item[1] }
	triplepattern:				Collection PredVarObj(?)						{
																					my $collection	= $item[1][0][1];
																					my @triples		= @{ $item[1] };
																					foreach my $elem (@{ $item[2] || [] }) {
																						my @triple	= [ $collection, @{ $elem } ];
																						push(@triples, \@triple);
																					}
																					$return = \@triples;
																				}
	PredVarObj:					PredVarUri Object OptObj(s?) OptPredObj(s?)		{
																					$return = [
																						[@item[1,2]],
																						map { [@{$_}] }
																							(@{$item[4] || []}, map { [$item[1], $_] } @{$item[3] || []})
																					];
																				}
	Object:						VarUriConst										{ $return = $item[1] }
	Object:						Collection										{ $return = $item[1] }
	Collection:					'('  <commit> Object(s) ')'						{
																					my @triples;
																					my $id		= 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser };
																					my $count	= scalar(@{ $item[3] });
																					foreach my $i (0 .. $#{ $item[3] }) {
																						my $elem	= $item[3][ $i ];
																						push(@triples, 
																							[ 'TRIPLE',
																								[
																									[ 'BLANK', $id ],
																									[ 'URI', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#first' ],
																									$elem
																								]
																							]
																						);
																						if ($i < $#{ $item[3] }) {
																							my $oldid	= $id;
																							$id			= 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser };
																							push(@triples,
																								[ 'TRIPLE',
																									[
																										[ 'BLANK', $oldid ],
																										[ 'URI', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest' ],
																										[ 'BLANK', $id ],
																									]
																								]
																							);
																						} else {
																							push(@triples,
																								[ 'TRIPLE',
																									[
																										[ 'BLANK', $id ],
																										[ 'URI', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest' ],
																										[ 'URI', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#nil' ],
																									]
																								]
																							);
																						}
																					} 
																					$return = \@triples;
																				}
	blanknode:					'[' ']'											{ $return = ['BLANK', 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser }]; }
	blanktriple:				'[' PredObj OptPredObj(s?) ']'					{ my $b = ['BLANK', 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser }]; $return = [$b, [ [$b, @{ $item[2] }], map { [$b, @$_] } @{ $item[3] } ] ] }
	OptPredObj:					';' PredObj										{ $return = $item[2] }
	PredObj:					PredVarUri Object OptObj(s?)					{ $return = [@item[1,2], map { [$item[1], @{$_}] } @{$item[3] || []}] }
	OptObj:						',' Object										{ $return = $item[2] }
	constraints:				/FILTER/i BrackettedExpression					{ $return = $item{'BrackettedExpression'} }
	constraints:				/FILTER/i CallExpression						{ $return = $item{'CallExpression'} }
	
	OptDot:						'.'
	OptExpression:				(',' | /AND/i | '&&') Expression				{
																					$return = [ '&&', $item[2] ];
																				}
	BrackettedExpression:		'(' <commit> Expression ')'								{ $return = $item{'Expression'}; }
	Expression:					CondOrExpr										{
																					$return = $item[1]
																				}
	CondOrExpr:					CondAndExpr CondOrExprOrPart(?)					{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	CondOrExprOrPart:			'||' CondAndExpr								{ $return = [ @item[1,2] ] }
	CondAndExpr:				ValueLogical CondAndExprAndPart(s?)				{
																					if (scalar(@{ $item[2] })) {
																						$return = [ '&&', $item[1], map { $_->[1] } @{ $item[2] } ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	CondAndExprAndPart:			'&&' <commit> ValueLogical						{ $return = [ '&&', $item{ValueLogical} ] }
	ValueLogical:				StringEqualityExpression						{ $return = $item[1] }
	StringEqualityExpression:	NumericalLogical StrEqExprPart(s?)				{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	StrEqExprPart:				('=' | '!=' | '=~' | '~~') NumericalLogical	{ $return = [ (($item[1] eq '=') ? '==' : $item[1]), $item[2] ] }
	NumericalLogical:			InclusiveOrExpression							{ $return = $item[1] }
	InclusiveOrExpression:		ExclusiveOrExpression InclusiveOrExprPart(s?)	{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	InclusiveOrExprPart:		'|' ExclusiveOrExpression						{ $return = [ @item[1,2] ] }
	ExclusiveOrExpression:		AndExpression ExclusiveOrExprPart(s?)			{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], map { $_->[1] } @{ $item[2] } ];
																					} else {
																						$return = $item[1];
																					}
																				}
	ExclusiveOrExprPart:		'^' AndExpression								{ $return = [ @item[1,2] ] }
	AndExpression:				ArithmeticCondition AndExprPart(s?)				{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], map { $_->[1] } @{ $item[2] } ];
																					} else {
																						$return = $item[1];
																					}
																				}
	AndExprPart:				'&' ArithmeticCondition							{ $return = [ @item[1,2] ] }
	ArithmeticCondition:		EqualityExpression								{ $return = $item[1]; }
	EqualityExpression:			RelationalExpression EqualityExprPart(?)		{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	EqualityExprPart:			/(!?=)/ RelationalExpression					{ $return = [ (($item[1] eq '=') ? '==' : $item[1]), $item[2] ] }
	RelationalExpression:		NumericExpression RelationalExprPart(?)			{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	RelationalExprPart:			/(<|>|<=|>=)/ NumericExpression					{ $return = [ @item[1,2] ] }
	NumericExpression:			MultiplicativeExpression NumericExprPart(s?)	{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	NumericExprPart:			/([-+])/ MultiplicativeExpression				{ $return = [ @item[1,2] ] }
	MultiplicativeExpression:	UnaryExpression MultExprPart(s?)				{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0], $item[1], $item[2][1] ]
																					} else {
																						$return	= $item[1];
																					}
																				}
	MultExprPart:				/([\/*])/ UnaryExpression						{ $return = [ @item[1,2] ] }
	UnaryExpression:			UnaryExprNotPlusMinus							{ $return = $item[1] }
							|	/([-+])/ UnaryExpression						{ $return = [ @item[1,2] ] }
	UnaryExprNotPlusMinus:		PrimaryExpression								{ $return = $item[1] }
							|	/([~!])/ UnaryExpression						{ $return = [ @item[1,2] ] }
	PrimaryExpression:			BrackettedExpression							{ $return = $item[1] }
							|	CallExpression									{ $return = $item[1] }
							|	VarUriConst										{ $return = $item[1] }
	CallExpression:				'REGEX' '(' <commit> Expression ',' Expression ')'	{ $return	= [ '~~', $item[4], $item[6]] }
							|	FunctionCall									{ $return = $item[1] }
							|	'BOUND' '(' <commit> variable ')'				{ $return = [ 'FUNCTION', ['URI', 'sop:isBound'], $item{'variable'} ] }
							|	'isURI' '(' <commit> Expression ')'				{ $return = [ 'FUNCTION', ['URI', 'sop:isURI'], $item{'Expression'} ] }
							|	'isBLANK' '(' <commit> Expression ')'			{ $return = [ 'FUNCTION', ['URI', 'sop:isBlank'], $item{'Expression'} ] }
							|	'isLITERAL' '(' <commit> Expression ')'			{ $return = [ 'FUNCTION', ['URI', 'sop:isLiteral'], $item{'Expression'} ] }
							
	FunctionCall:				URI '(' <commit> ArgList ')'					{ $return = [ 'FUNCTION', $item[1], @{ $item[4] } ] }
	ArgList:					VarUriConst MoreArg(s)							{ $return = [ $item[1], @{ $item[2] } ] }
	
	
	
	
	MoreArg:					"," VarUriConst									{ $return = $item[2] }
	Literal:					(URI | CONST)									{ $return = $item[1] }
	URL:						qURI											{ $return = $item[1] }
	VarUri:						variable <commit>								{ $return = $item[1] }
	VarUri:						blankQName										{ $return = $item[1] }
	VarUri:						URI												{ $return = $item[1] }
	PredVarUri:					/a/i											{ $return = ['URI', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'] }
							|	VarUri											{ $return = $item[1] }
	VarUriConst:				(variable | CONST | URI)						{ $return = $item[1] }
	namespaces:					morenamespace(s?)								{ $return = { map { %{ $_ } } (@{ $item[1] }) } }
	morenamespace:				namespace										{ $return = $item[1] }
	namespace:					/PREFIX/i <commit> identifier(?) ':' qURI		{
																					my $ns;
																					if (@{$item[3]}) {
																						$ns	= $item[3][0];
																					} else {
																						$ns	= '__DEFAULT__';
																					}
																					$return = { $ns => $item{qURI}};
																				}
	OptComma:					',' | ''
	Comma:						','
	identifier:					/(([a-zA-Z0-9_.-])+)/							{ $return = $1 }
	URI:						(qURI | QName)									{ $return = ['URI',$item[1]] }
	qURI:						'<' /[A-Za-z0-9_.!~*'()%;\/?:@&=+,#\$-]+/ '>'	{ $return = $item[2] }
	blankQName:					'_:' /([^ \t\r\n<>();,]+)/						{ $return = ['BLANK', $item[2] ] }
	QName:						identifier(?) ':' /([^ \t\r\n<>();,]+)/			{
																					my $ns;
																					if (@{$item[1]}) {
																						$ns	= $item[1][0];
																					} else {
																						$ns	= '__DEFAULT__';
																					}
																					$return = [ $ns, $item[3] ];
																				}
	CONST:						Number											{ $return = [ 'LITERAL', $item[1] ] }
	CONST:						Text											{ $return = [ 'LITERAL', @{ $item[1] } ] }
	Number:						/([+-]?[0-9]+(\.[0-9]+)?)/						{ $return = $item[1] }
	Text:						Quoted StrLang									{ $return = [ $item[1], $item[2], undef ] }
	Text:						Quoted StrType									{ $return = [ $item[1], undef, $item[2] ] }
	Text:						Quoted											{ $return = [ $item[1] ] }
	Text:						Pattern											{ $return = [ $item[1] ] }
	StrLang:					'@' /[A-Za-z]+(-[A-Za-z]+)*/					{ $return = $item[2] }
	StrType:					'^^' URI										{ $return = $item[2] }
	Quoted:						(dQText | sQText)								{ $return = $item[1] }
	sQText:						"'" /([^']+)/ '"'								{ $return = $item[2] }
	dQText:						'"' /([^"]+)/ '"'								{ $return = $item[2] }
	Pattern:					'/' /([^\/]+(?:\\.[^\/]*)*)/ '/'				{ $return = $item[2] }
END
}

######################################################################

=head1 METHODS

=over 4

=item C<new ( $query_object ) >

Returns a new RDF::Query object.

=cut
{ my $parser;
sub new {
	my $class	= shift;
	$parser		||= new Parse::RecDescent ($SPARQL_GRAMMAR);
	my $self 	= bless( {
					parser		=> $parser
				}, $class );
	return $self;
} }


sub parse {
	my $self	= shift;
	my $query	= shift;
	my $parser	= $self->parser;
	my $parsed	= $parser->query( $query );
	delete $blank_ids{ $parser };
	return $parsed;
}

sub AUTOLOAD {
	my $self	= $_[0];
	my $class	= ref($_[0]) || return undef;
	our $AUTOLOAD;
	return if ($AUTOLOAD =~ /DESTROY$/);
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

 $Log$
 Revision 1.13  2006/01/11 06:08:26  greg
 - Added support for SELECT * in SPARQL queries.
 - Added support for default namespaces in SPARQL queries.

 Revision 1.12  2005/11/19 00:56:38  greg
 - Added SPARQL functions: BOUND, isURI, isBLANK, isLITERAL.
 - Updated SPARQL REGEX syntax.
 - Updated SPARQL FILTER syntax.
 - Added SPARQL RDF Collections syntactic forms.
 - Updated SPARQL grammar to make 'WHERE' token optional.
 - Added <commit> directives to SPARQL grammar.
 - Updated SPARQL 'ORDER BY' syntax to use parenthesis.
 - Fixed SPARQL FILTER logical-and support for more than two operands.
 - Fixed SPARQL FILTER equality operator syntax to use '=' instead of '=='.

 Revision 1.11  2005/07/27 00:35:59  greg
 - Added commit directives to some top-level non-terminals.
 - Started using the %item hash for more flexibility in parse rules.

 Following SPARQL Draft 2005.07.21:
 - ORDER BY arguments now use parenthesis.
 - ORDER BY operand may now be a variable, expression, or function call.

 Revision 1.10  2005/06/04 07:27:13  greg
 - Added support for typed literals.
   - (Redland support for datatypes is currently broken, however.)

 Revision 1.9  2005/06/02 19:36:22  greg
 - Added missing OFFSET grammar rules.

 Revision 1.8  2005/06/01 05:06:33  greg
 - Added SPARQL UNION support.
 - Broke OPTIONAL handling code off into a seperate method.
 - Added new debugging code to trace errors in the twisty web of closures.

 Revision 1.7  2005/05/18 23:05:53  greg
 - Added support for SPARQL OPTIONAL graph patterns.
 - Added binding_values and binding_names methods to Streams.

 Revision 1.6  2005/05/08 08:26:09  greg
 - Added initial support for SPARQL ASK, DESCRIBE and CONSTRUCT queries.
   - Added new test files for new query types.
 - Added methods to bridge classes for creating statements and blank nodes.
 - Added as_string method to bridge classes for getting string versions of nodes.
 - Broke out triple fixup code into fixup_triple_bridge_variables().
 - Updated FILTER test to use new Geo::Distance API.

 Revision 1.5  2005/04/26 04:22:13  greg
 - added constraints tests
 - URIs in constraints are now part of the fixup
 - parser is removed from the Redland bridge in DESTROY
 - SPARQL FILTERs are now properly part of the triple patterns (within the braces)
 - added FILTER tests

 Revision 1.4  2005/04/26 02:54:40  greg
 - added core support for custom function constraints support
 - added initial SPARQL support for custom function constraints
 - SPARQL variables may now begin with the '$' sigil
 - broke out URL fixups into its own method
 - added direction support for ORDER BY (ascending/descending)
 - added 'next', 'current', and 'end' to Stream API

 Revision 1.3  2005/04/25 00:59:29  greg
 - streams are now objects usinig the Redland QueryResult API
 - RDF namespace is now always available in queries
 - row() now uses a stream when calling execute()
 - check_constraints() now copies args for recursive calls (instead of pass-by-ref)
 - added ORDER BY support to RDQL parser
 - SPARQL constraints now properly use the 'FILTER' keyword
 - SPARQL constraints can now use '&&' as an operator
 - SPARQL namespace declaration is now optional

 Revision 1.2  2005/04/21 05:24:54  greg
 - execute now returns an iterator
 - added core support for DISTINCT, LIMIT, OFFSET
 - added initial core support for ORDER BY (only works on one column right now)
 - added SPARQL support for DISTINCT and ORDER BY
 - added stress test for large queries and sorting on local scutter model

 Revision 1.1  2005/04/21 02:21:44  greg
 - major changes (resurecting the project)
 - broke out the query parser into it's own RDQL class
 - added initial support for a SPARQL parser
   - added support for blank nodes
   - added lots of syntactic sugar (with blank nodes, multiple predicates and objects)
 - moved model-specific code into RDF::Query::Model::*
 - cleaned up the model-bridge code
 - moving over to redland's query API (pass in the model when query is executed)


=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
