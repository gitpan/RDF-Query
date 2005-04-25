#!/usr/bin/perl
use strict;
use Test::More qw(no_plan);
use Data::Dumper;

use_ok( 'RDF::Query::Parser::SPARQL' );
local($::RD_HINT)	= 1;
my $parser	= new RDF::Query::Parser::SPARQL (undef);
isa_ok( $parser, 'RDF::Query::Parser::SPARQL' );

{
	my $rdql	= <<"END";
		SELECT
				?node
		WHERE
				{
				?node rdf:type <http://kasei.us/e/ns/mt/blog> .
				}
END
	my $correct	= {'triples' => [[['VAR','node'],['URI',['rdf','type']],['URI','http://kasei.us/e/ns/mt/blog']]],'namespaces' => {}, 'sources' => undef,'variables' => [['VAR','node']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "single triple; no prefix" );
}

{
	my $rdql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?page
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person foaf:homepage ?page .
				}
END
	my $correct	= {'variables' => [['VAR','page']],'namespaces' => {'dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#'},'sources' => undef,'constraints' => [],'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','page']]]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'SELECT, WHERE, USING' );
}

{
	local $TODO = "Need to fix constraints parsing.";
	my $rdql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
				}
		FILTER	(?pred == <http://purl.org/dc/terms/spatial> || ?pred == <http://xmlns.com/foaf/0.1/based_near>)
		&&		?lat > 52.988674
		&&		?lat < 53.036526
END
#	my $correct	= {'triples' => [[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],[['VAR','image'],['VAR','pred'],['VAR','point']]],'sources' => undef,'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'},'constraints' => ['&&',['||',['==',['VAR','pred'],['URI','http://purl.org/dc/terms/spatial']],['==',['VAR','pred'],['URI','http://xmlns.com/foaf/0.1/based_near']]],['>',['VAR','lat'],['LITERAL','52.988674']],['<',['VAR','lat'],['LITERAL','53.036526']]],'variables' => [['VAR','image'],['VAR','point'],['VAR','lat']]};
	my $correct	= {
			'triples'		=> [[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],[['VAR','image'],['VAR','pred'],['VAR','point']]],
			'sources'		=> undef,
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'},
			'constraints'	=> ['&&',
								['||',
									['==',['VAR','pred'],['URI','http://purl.org/dc/terms/spatial']],
									['==',['VAR','pred'],['URI','http://xmlns.com/foaf/0.1/based_near']]
								],
								['>',['VAR','lat'],['LITERAL','52.988674']],
								['<',['VAR','lat'],['LITERAL','53.036526']]
							],
			'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']]
	};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'VarUri EQ OR constraint, numeric comparison constraint' );
}

{
	my $rdql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person foaf:homepage ?homepage
				}
		FILTER	?homepage ~~ /kasei/
END
	my $correct	= {'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},'constraints' => ['~~',['VAR','homepage'],['LITERAL','kasei']],'sources' => undef,'variables' => [['VAR','person'],['VAR','homepage']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "regex constraint; no trailing '.'" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" ; foaf:homepage ?homepage .
				}
END
	my $correct	= {'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person'],['VAR','homepage']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "multiple attributes using ';'" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person
		WHERE	{
					?person foaf:name "Gregory Todd Williams", "Greg Williams" .
				}
END
	my $correct	= {'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','name']],['LITERAL','Greg Williams']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "multiple objects using ','" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person
		WHERE	{
					?person <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> foaf:Person
				}
END
	my $correct	= {'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "predicate with full qURI" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person
		WHERE	{
					?person a foaf:Person .
				}
END
	my $correct	= {'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "'a' rdf:type" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person ; foaf:name ?name .
				}
END
	my $correct	= {'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]], [['VAR','person'],['URI',['foaf','name']],['VAR', 'name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "'a' rdf:type; multiple attributes using ';'" );
}



{
#local($::RD_TRACE)	= 1;
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?nick
		WHERE	{
					[ foaf:name "Gregory Todd Williams" ; foaf:nick ?nick ] .
				}
END
	my $correct	= {'triples' => [[['BLANK','a1'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['BLANK','a1'],['URI',['foaf','nick']],['VAR','nick']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','nick']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "blank node; multiple attributes using ';'" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					[ a foaf:Person ] foaf:name ?name .
				}
END
	my $correct	= {'triples' => [[['BLANK','a1'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI',['foaf','Person']]],[['BLANK','a1'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "blank node; using brackets '[...]'; 'a' rdf:type" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					[] foaf:name ?name .
				}
END
	my $correct	= {'triples' => [[['BLANK','a1'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "blank node; empty brackets '[]'" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					_:abc foaf:name ?name .
				}
END
	my $correct	= {'triples' => [[['BLANK','abc'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "blank node; using qName _:abc" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY ?name
END
	my $correct	= {'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']],'options'=>{orderby => [['VAR', 'name']]}};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "select with ORDER BY" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	DISTINCT ?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
END
	my $correct	= {'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']],'options'=>{distinct => 1}};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "select with ORDER BY" );
}

{
	local $TODO = "Triple grouping for OPTIONAL patterns not yet implemented";
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?name ?mbox
		WHERE	{
					{ ?person foaf:name ?name }
					OPTIONAL { ?person foaf:mbox ?mbox }
				}
END
	my $correct	= {'triples' => [[['VAR','person'],['URI',['foaf','name']],['VAR','name']]], optional => [[['VAR','person'],['URI',['foaf','mbox']],['VAR','mbox']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person'], ['VAR','name'], ['VAR','mbox']]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "optional triples '{...}'" );
}
