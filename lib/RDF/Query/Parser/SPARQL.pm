# RDF::Query::Parser::SPARQL
# -------------
# $Revision: 1.9 $
# $Date: 2005/06/02 19:36:22 $
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
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.9 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$lang		= 'sparql';
	$languri	= 'http://www.w3.org/TR/rdf-sparql-query/';
}

our %blank_ids;
our($SPARQL_GRAMMAR);
BEGIN {
	our $SPARQL_GRAMMAR	= <<'END';
	query:			namespaces /SELECT|DESCRIBE/i OptDistinct(?) variable(s) SourceClause(?) /WHERE/i triplepatterns OptOrderBy(?) OptLimit(?) OptOffset(?)
																	{
																		$return = {
																			method		=> uc($item[2]),
																			variables	=> $item[4],
																			sources		=> $item[5][0],
																			triples		=> $item[7][0] || [],
																			constraints	=> $item[7][1] || [],
																			namespaces	=> $item[1]
																		};
																		$return->{options}{distinct}	= 1 if ($item[3][0]);
																		if (@{ $item[8] }) {
																			$return->{options}{orderby}	= $item[8][0];
																		}
																		if (@{ $item[9] }) {
																			$return->{options}{limit}	= $item[9][0];
																		}
																		if (@{ $item[10] }) {
																			$return->{options}{offset}	= $item[10][0];
																		}
																	}
	query:			namespaces /CONSTRUCT/i triplepatterns SourceClause(?) /WHERE/i triplepatterns OptOrderBy(?) OptLimit(?) OptOffset(?)
																	{
																		$return = {
																			method				=> 'CONSTRUCT',
																			variables			=> [],
																			construct_triples	=> $item[3][0] || [],
																			sources				=> $item[4][0],
																			triples				=> $item[6][0] || [],
																			constraints			=> $item[6][1] || [],
																			namespaces			=> $item[1]
																		};
																		$return->{options}{distinct}	= 1;
																		if (@{ $item[7] }) {
																			$return->{options}{orderby}	= $item[7][0];
																		}
																		if (@{ $item[8] }) {
																			$return->{options}{limit}	= $item[8][0];
																		}
																		if (@{ $item[9] }) {
																			$return->{options}{offset}	= $item[9][0];
																		}
																	}
	query:			namespaces /ASK/i SourceClause(?) triplepatterns
																	{
																		$return = {
																			method		=> 'ASK',
																			variables	=> [],
																			sources		=> $item[3][0],
																			triples		=> $item[4][0] || [],
																			constraints	=> [],
																			namespaces	=> $item[1]
																		};
																	}
	OptDistinct:				/DISTINCT/i										{ $return = 1 }
	OptLimit:					/LIMIT/i /(\d+)/								{ $return = $item[2] }
	OptOffset:					/OFFSET/i /(\d+)/								{ $return = $item[2] }
	OptOrderBy:					/ORDER BY/i orderbyvariable(s)					{ $return = $item[2] }
	orderbyvariable:			variable										{ $return = ['ASC', $item[1]] }
					|			/ASC|DESC/i '[' variable ']'					{ $return = [uc($item[1]), $item[3]] }
	SourceClause:				(/SOURCE/i | /FROM/i) Source(s)					{ $return = $item[2] }
	Source:						URI												{ $return = $item[1] }
	variable:					('?' | '$') identifier							{ $return = ['VAR',$item[2]] }
	triplepatterns:				'{' triplepattern moretriple(s?) OptDot(?) '}'	{
																					my @data	= (@{ $item[2] }, map { @{ $_ } } @{ $item[3] });
																					my @triples	= (
																									(map { $_->[1] } grep { $_->[0] eq 'TRIPLE' } @data),
																									(grep { $_->[0] eq 'OPTIONAL' } @data),
																									(grep { $_->[0] eq 'UNION' } @data)
																								);
																					
																					my @filters	= map { $_->[1] } grep { $_->[0] eq 'FILTER' } @data;
																					my $filters	= scalar(@filters) <= 1
																								? $filters[0]
																								: [ '&&', @filters ];
																					$return = [ \@triples, $filters ];
																				}
	moretriple:					'.' triplepattern								{
																					$return = $item[2];
																				}
	triplepattern:				(VarUri|blanknode) PredVarUri VarUriConst OptObj(s?) OptPredObj(s?)	{
																					$return = [ ['TRIPLE', [@item[1,2,3]]], map { ['TRIPLE', [$item[1], @{$_}]] } (@{$item[5] || []}, map { [$item[2], $_] } @{$item[4] || []}) ];
																				}
	triplepattern:				/OPTIONAL/i triplepatterns						{ $return = [[ 'OPTIONAL', ($item[2][0] || []) ]] }
	triplepattern:				triplepatterns /UNION/i triplepatterns			{ $return = [[ 'UNION', ($item[1][0] || []), ($item[3][0] || []) ]] }
	triplepattern:				constraints										{ $return = [[ 'FILTER', $item[1] ]] }
	triplepattern:				blanktriple PredObj(?)							{
																					my ($b,$t)	= @{ $item[1] };
																					$return = [ (map { ['TRIPLE', $_] } @$t), map { ['TRIPLE', [$b, @$_]] } @{ $item[2] } ];
																				}
	triplepattern:				triplepatterns									{ $return = $item[1] }
	blanknode:					'[' ']'											{ $return = ['BLANK', 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser }]; }
	blanktriple:				'[' PredObj OptPredObj(s?) ']'					{ my $b = ['BLANK', 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser }]; $return = [$b, [ [$b, @{ $item[2] }], map { [$b, @$_] } @{ $item[3] } ] ] }
	OptPredObj:					';' PredObj										{ $return = $item[2] }
	PredObj:					PredVarUri VarUriConst OptObj(s?)				{ $return = [@item[1,2], map { [$item[1], @{$_}] } @{$item[3] || []}] }
	OptObj:						',' VarUriConst									{ $return = $item[2] }
	constraints:				/FILTER/i Expression OptExpression(s?)			{
																					if (scalar(@{ $item[3] })) {
																						$return = [ $item[3][0][0], $item[2], map { $_->[1] } @{ $item[3] } ];
																					} else {
																						$return	= $item[2];
																					}
																				}
	OptDot:						'.'
	OptExpression:				(',' | /AND/i | '&&') Expression					{
																					$return = [ '&&', $item[2] ];
																				}
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
	CondAndExpr:				ValueLogical CondAndExprAndPart(?)				{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	CondAndExprAndPart:			'&&' ValueLogical								{ $return = [ @item[1,2] ] }
	ValueLogical:				StringEqualityExpression						{ $return = $item[1] }
	StringEqualityExpression:	NumericalLogical StrEqExprPart(s?)				{
																					if (scalar(@{ $item[2] })) {
																						$return = [ $item[2][0][0], $item[1], $item[2][0][1] ];
																					} else {
																						$return	= $item[1];
																					}
																				}
	StrEqExprPart:				('==' | '!=' | '=~' | '~~') NumericalLogical	{ $return = [ @item[1,2] ] }
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
	EqualityExprPart:			/(==|!=)/ RelationalExpression					{ $return = [ @item[1,2] ] }
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
	UnaryExprNotPlusMinus:		/([~!])/ UnaryExpression						{ $return = [ @item[1,2] ] }
							|	PrimaryExpression								{ $return = $item[1] }
	PrimaryExpression:			(FunctionCall | VarUriConst)					{ $return = $item[1] }
							|	'(' Expression ')'								{
																					$return = $item[2];
																				}
	FunctionCall:				URI '(' ArgList ')'								{ $return = [ 'FUNCTION', $item[1], @{ $item[3] } ] }
	ArgList:					VarUriConst MoreArg(s)							{ $return = [ $item[1], @{ $item[2] } ] }
	
	
	
	
	MoreArg:					"," VarUriConst									{ $return = $item[2] }
	Literal:					(URI | CONST)									{ $return = $item[1] }
	URL:						qURI											{ $return = $item[1] }
	VarUri:						(variable | blankQName | URI)					{ $return = $item[1] }
	PredVarUri:					/a/i											{ $return = ['URI', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'] }
							|	VarUri											{ $return = $item[1] }
	VarUriConst:				(variable | CONST | URI)						{ $return = $item[1] }
	namespaces:					morenamespace(s?)								{ $return = { map { %{ $_ } } (@{ $item[1] }) } }
	morenamespace:				namespace										{ $return = $item[1] }
	namespace:					/PREFIX/i identifier ':' qURI					{ $return = {@item[2,4]} }
	OptComma:					',' | ''
	identifier:					/(([a-zA-Z0-9_.-])+)/							{ $return = $1 }
	URI:						(qURI | QName)									{ $return = ['URI',$item[1]] }
	qURI:						'<' /[A-Za-z0-9_.!~*'()%;\/?:@&=+,#\$-]+/ '>'	{ $return = $item[2] }
	blankQName:					'_:' /([^ \t\r\n<>();,]+)/						{ $return = ['BLANK', $item[2] ] }
	QName:						identifier ':' /([^ \t\r\n<>();,]+)/			{ $return = [@item[1,3]] }
	CONST:						(Text | Number)									{ $return = ['LITERAL',$item[1]] }
	Number:						/([+-]?[0-9]+(\.[0-9]+)?)/							{ $return = $item[1] }
	Text:						dQText | sQText | Pattern						{ $return = $item[1] }
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

 $Log: SPARQL.pm,v $
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
