# RDF::Query::Parser::SPARQL
# -------------
# $Revision: 1.3 $
# $Date: 2005/04/25 00:59:29 $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Parser::SPARQL - A SPARQL parser for RDF::Query

=cut

package RDF::Query::Parser::SPARQL;

use strict;
use warnings;
use Carp qw(carp croak confess);

use Data::Dumper::Simple;
use LWP::Simple ();
use Tie::Cache::LRU;
use Parse::RecDescent;
use Digest::SHA1  qw(sha1_hex);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$::RD_TRACE	= undef;
	$::RD_HINT	= undef;
	$debug		= 0;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.3 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$lang		= 'sparql';
	$languri	= 'http://www.w3.org/TR/rdf-sparql-query/';
}

our %blank_ids;
our($SPARQL_GRAMMAR);
BEGIN {
	our $SPARQL_GRAMMAR	= <<'END';
	query:			namespaces 'SELECT' OptDistinct(?) variable(s) SourceClause(?) 'WHERE' triplepatterns constraints(?) OptOrderBy(?)
																	{
																		$return = {
																			variables	=> $item[4],
																			sources		=> $item[5][0],
																			triples		=> $item[7],
																			constraints	=> ($item[8][0] || []),
																			namespaces	=> $item[1]
																		};
																		$return->{options}{distinct}	= 1 if ($item[3][0]);
																		if (@{ $item[9] }) {
																			$return->{options}{orderby}	= $item[9][0];
																		}
																	}
	OptDistinct:				'DISTINCT'										{ $return = 1 }
	OptOrderBy:					'ORDER BY' variable(s)							{ $return = $item[2] }
	SourceClause:				('SOURCE' | 'FROM') Source(s)					{ $return = $item[2] }
	Source:						URI												{ $return = $item[1] }
	variable:					'?' identifier									{ $return = ['VAR',$item[2]] }
	triplepatterns:				'{' triplepattern moretriple(s?) OptDot(?) '}'	{ $return = [ @{ $item[2] }, map { @{ $_ } } @{ $item[3] } ] }
	moretriple:					'.' triplepattern								{ $return = $item[2] }
	triplepattern:				(VarUri|blanknode) PredVarUri VarUriConst OptObj(s?) OptPredObj(s?)	{ $return = [ [@item[1,2,3]], map { [$item[1], @{$_}] } (@{$item[5] || []}, map { [$item[2], $_] } @{$item[4] || []}) ] }
	triplepattern:				blanktriple PredObj(?)							{
																					my ($b,$t)	= @{ $item[1] };
																					$return = [ @$t, map { [$b, @$_] } @{ $item[2] } ]
																				}
	triplepattern:				triplepatterns									{ $return = $item[1] }
	blanknode:					'[' ']'											{ $return = ['BLANK', 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser }]; }
	blanktriple:				'[' PredObj OptPredObj(s?) ']'					{ my $b = ['BLANK', 'a' . ++$RDF::Query::Parser::SPARQL::blank_ids{ $thisparser }]; $return = [$b, [ [$b, @{ $item[2] }], map { [$b, @$_] } @{ $item[3] } ] ] }
	OptPredObj:					';' PredObj										{ $return = $item[2] }
	PredObj:					PredVarUri VarUriConst OptObj(s?)				{ $return = [@item[1,2], map { [$item[1], @{$_}] } @{$item[3] || []}] }
	OptObj:						',' VarUriConst									{ $return = $item[2] }
	constraints:				'FILTER' Expression OptExpression(s?)			{
																					if (scalar(@{ $item[3] })) {
																						$return = [ $item[3][0][0], $item[2], map { $_->[1] } @{ $item[3] } ];
																					} else {
																						$return	= $item[2];
																					}
																				}
	OptDot:						'.'
	OptExpression:				(',' | 'AND' | '&&') Expression					{
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
	PrimaryExpression:			(VarUriConst | FunctionCall)					{ $return = $item[1] }
							|	'(' Expression ')'								{
																					$return = $item[2];
																				}
	FunctionCall:				identifier '(' ArgList ')'						{ $return = [ 'function', map { @{ $_ } } @item[1,3] ] }
	ArgList:					VarUriConst MoreArg(s)							{ $return = [ $item[1], @{ $item[2] } ] }
	
	
	
	
	MoreArg:					"," VarUriConst									{ $return = $item[2] }
	Literal:					(URI | CONST)									{ $return = $item[1] }
	URL:						qURI											{ $return = $item[1] }
	VarUri:						(variable | blankQName | URI)					{ $return = $item[1] }
	PredVarUri:					'a'												{ $return = ['URI', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'] }
							|	VarUri											{ $return = $item[1] }
	VarUriConst:				(variable | CONST | URI)						{ $return = $item[1] }
	namespaces:					morenamespace(s?)								{ $return = { map { %{ $_ } } (@{ $item[1] }) } }
	morenamespace:				namespace										{ $return = $item[1] }
	namespace:					'PREFIX' identifier ':' qURI					{ $return = {@item[2,4]} }
	OptComma:					',' | ''
	identifier:					/(([a-zA-Z0-9_.-])+)/							{ $return = $1 }
	URI:						(qURI | QName)									{ $return = ['URI',$item[1]] }
	qURI:						'<' /[A-Za-z0-9_.!~*'()%;\/?:@&=+,#\$-]+/ '>'	{ $return = $item[2] }
	blankQName:					'_:' /([^ \t\r\n<>();,]+)/						{ $return = ['BLANK', $item[2] ] }
	QName:						identifier ':' /([^ \t\r\n<>();,]+)/			{ $return = [@item[1,3]] }
	CONST:						(Text | Number)									{ $return = ['LITERAL',$item[1]] }
	Number:						/([0-9]+(\.[0-9]+)?)/							{ $return = $item[1] }
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
