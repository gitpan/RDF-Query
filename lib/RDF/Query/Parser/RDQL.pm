# RDF::Query::Parser::RDQL
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Parser::RDQL - An RDQL parser for RDF::Query

=cut

package RDF::Query::Parser::RDQL;

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
	$debug		= 1;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$lang		= 'rdql';
	$languri	= 'http://jena.hpl.hp.com/2003/07/query/RDQL';
}

our($RDQL_GRAMMAR);
BEGIN {
	our $RDQL_GRAMMAR	= <<'END';
	query:			'SELECT' variable(s) SourceClause(?) 'WHERE' triplepattern(s) constraints(?) OptOrderBy(?) 'USING' namespaces
																	{
																		$return = {
																			variables	=> $item[2],
																			sources		=> $item[3][0],
																			triples		=> $item[5],
																			constraints	=> ($item[6][0] || []),
																			namespaces	=> $item[9]
																		};
																		if (@{ $item[7] }) {
																			$return->{options}{orderby}	= $item[9][0];
																		}
																	}
	OptOrderBy:					'ORDER BY' orderbyvariable(s)					{ $return = $item[2] }
	orderbyvariable:			variable										{ $return = ['ASC', $item[1]] }
					|			/ASC|DESC/i '[' variable ']'					{ $return = [uc($item[1]), $item[3]] }
	SourceClause:				('SOURCE' | 'FROM') Source(s)					{ $return = $item[2] }
	Source:						URI												{ $return = $item[1] }
	variable:					'?' identifier									{ $return = ['VAR',$item[2]] }
	triplepattern:				'(' VarUri VarUri VarUriConst ')'				{ $return = [ @item[2,3,4] ] }
	constraints:				'AND' Expression OptExpression(s?)				{
																					if (scalar(@{ $item[3] })) {
																						$return = [ $item[3][0][0], $item[2], map { $_->[1] } @{ $item[3] } ];
																					} else {
																						$return	= $item[2];
																					}
																				}
	OptExpression:				(',' | 'AND') Expression						{
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
	VarUri:						(variable | URI)								{ $return = $item[1] }
	VarUriConst:				(variable | CONST | URI)						{ $return = $item[1] }
	namespaces:					namespace morenamespace(s?)						{ $return = { map { %{ $_ } } ($item[1], @{ $item[2] }) } }
	morenamespace:				OptComma namespace								{ $return = $item[2] }
	namespace:					identifier 'FOR' qURI							{ $return = {@item[1,3]} }
	OptComma:					',' | ''
	identifier:					/(([a-zA-Z0-9_.-])+)/							{ $return = $1 }
	URI:						(qURI | QName)									{ $return = ['URI',$item[1]] }
	qURI:						'<' /[A-Za-z0-9_.!~*'()%;\/?:@&=+,#\$-]+/ '>'	{ $return = $item[2] }
	QName:						identifier ':' /([^ \t<>()]+)/					{ $return = [@item[1,3]] }
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
	$parser		||= new Parse::RecDescent ($RDQL_GRAMMAR);
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
 Revision 1.5  2006/01/11 06:03:45  greg
 - Removed use of Data::Dumper::Simple.

 Revision 1.4  2005/05/08 08:26:09  greg
 - Added initial support for SPARQL ASK, DESCRIBE and CONSTRUCT queries.
   - Added new test files for new query types.
 - Added methods to bridge classes for creating statements and blank nodes.
 - Added as_string method to bridge classes for getting string versions of nodes.
 - Broke out triple fixup code into fixup_triple_bridge_variables().
 - Updated FILTER test to use new Geo::Distance API.

 Revision 1.3  2005/04/26 02:54:40  greg
 - added core support for custom function constraints support
 - added initial SPARQL support for custom function constraints
 - SPARQL variables may now begin with the '$' sigil
 - broke out URL fixups into its own method
 - added direction support for ORDER BY (ascending/descending)
 - added 'next', 'current', and 'end' to Stream API

 Revision 1.2  2005/04/25 00:59:29  greg
 - streams are now objects usinig the Redland QueryResult API
 - RDF namespace is now always available in queries
 - row() now uses a stream when calling execute()
 - check_constraints() now copies args for recursive calls (instead of pass-by-ref)
 - added ORDER BY support to RDQL parser
 - SPARQL constraints now properly use the 'FILTER' keyword
 - SPARQL constraints can now use '&&' as an operator
 - SPARQL namespace declaration is now optional

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
