#!/usr/bin/perl
use strict;
use Test::More tests => 79;
use Data::Dumper;

use_ok( 'RDF::Query::Parser::SPARQL' );
my $parser	= new RDF::Query::Parser::SPARQL (undef);
isa_ok( $parser, 'RDF::Query::Parser::SPARQL' );


{
	my $sparql	= <<"END";
		SELECT ?node
		WHERE {
			?node rdf:type <http://kasei.us/e/ns/mt/blog> .
		}
END
	my $correct	= {
					'method' => 'SELECT',
					'triples' => [
									[
										['VAR','node'],
										['URI',['rdf','type']],
										['URI','http://kasei.us/e/ns/mt/blog']
									]
								],
					'namespaces' => {},
					'sources' => [],
					'variables' => [['VAR','node']],
				};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "single triple; no prefix" );
}

{
	my $sparql	= <<"END";
		DESCRIBE ?node
		WHERE { ?node rdf:type <http://kasei.us/e/ns/mt/blog> }
END
	my $correct	= {'method' => 'DESCRIBE', 'triples' => [[['VAR','node'],['URI',['rdf','type']],['URI','http://kasei.us/e/ns/mt/blog']]],'namespaces' => {}, 'sources' => [],'variables' => [['VAR','node']]};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "simple DESCRIBE" );
}

{
	my $sparql	= <<"END";
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
	my $correct	= {'method' => 'SELECT', 'variables' => [['VAR','page']],'namespaces' => {'dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#'},'sources' => [],'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','page']]]};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'SELECT, WHERE, USING' );
}

{
	my $sparql	= <<'END';
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	$page
		WHERE	{
					$person foaf:name "Gregory Todd Williams" .
					$person foaf:homepage $page .
				}
END
	my $correct	= {'method' => 'SELECT', 'variables' => [['VAR','page']],'namespaces' => {'dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#'},'sources' => [],'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','page']]]};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'SELECT, WHERE, USING; variables with "$"' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER(
						(?pred = <http://purl.org/dc/terms/spatial> || ?pred = <http://xmlns.com/foaf/0.1/based_near>)
						&&		?lat > 52.988674
						&&		?lat < 53.036526
					) .
		}
END
	my $correct	= {
			'method'		=> 'SELECT', 
			'triples'		=> [
									[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],
									[['VAR','image'],['VAR','pred'],['VAR','point']],
									['FILTER', ['&&',
									   ['||',
										 ['==',
										   ['VAR','pred'],
										   ['URI','http://purl.org/dc/terms/spatial']
										 ],
										 ['==',
										   ['VAR','pred'],
										   ['URI','http://xmlns.com/foaf/0.1/based_near']
										 ]
									   ],
									   ['>',
										 ['VAR','lat'],
										 ['LITERAL','52.988674', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']]
									   ],
									   ['<',
										 ['VAR','lat'],
										 ['LITERAL','53.036526', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']]
									   ]
								   ]
							   ],
								],
			'sources'		=> [],
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'},
			'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'VarUri EQ OR constraint, numeric comparison constraint' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person foaf:homepage ?homepage .
					FILTER	REGEX(?homepage, "kasei")
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],
						[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']],
						['FILTER', ['~~',['VAR','homepage'],['LITERAL','kasei']]],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "regex constraint; no trailing '.'" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person ?pred ?homepage .
					FILTER( ?pred = func:homepagepred() ) .
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],
						[['VAR','person'],['VAR','pred'],['VAR','homepage']],
						['FILTER', ['==',['VAR','pred'],['FUNCTION',['URI', ['func', 'homepagepred']]]]],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with variable/function-call equality" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person ?pred ?homepage .
					FILTER( ?pred = <func:homepagepred>() ) .
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],
						[['VAR','person'],['VAR','pred'],['VAR','homepage']],
						['FILTER', ['==',['VAR','pred'],['FUNCTION',['URI', 'func:homepagepred']]]],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with variable/function-call equality" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person ?pred ?homepage .
					FILTER( isBLANK([]) ) .
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],
						[['VAR','person'],['VAR','pred'],['VAR','homepage']],
						['FILTER',['FUNCTION',['URI','sop:isBlank'],[]]],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with variable/function-call equality" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person ?pred ?homepage .
					FILTER( isBLANK([ a foaf:Person ]) ) .
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],
						[['VAR','person'],['VAR','pred'],['VAR','homepage']],
						['FILTER',['FUNCTION',['URI','sop:isBlank'],[[['BLANK','a1'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI',['foaf','Person']]]]]],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with variable/function-call equality" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person ?pred ?homepage .
					FILTER( ?person = _:foo ) .
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],
						[['VAR','person'],['VAR','pred'],['VAR','homepage']],
						['FILTER', ['==',['VAR','person'],['BLANK','foo']]],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with variable/blank-node equality" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name ?name .
					FILTER( LANG(?name) = 'en' ) .
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['VAR', 'name']],
						['FILTER',
							['==',
								['FUNCTION',['URI', 'sparql:lang'], ['VAR', 'name']],
								['LITERAL','en']
							]
						],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with LANG(?var)/literal equality" );
}

{
	my $sparql	= <<'END';
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name ?name .
					FILTER( LANGMATCHES(?name, "foo"@en ) ).
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['VAR', 'name']],
						['FILTER',
							['FUNCTION',
								['URI', 'sparql:langmatches'],
								['VAR', 'name'],
								['LITERAL', 'foo', 'en', undef],
							],
						],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with LANGMATCHES(?var, 'literal')" );
}

{
	my $sparql	= <<'END';
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name ?name .
					FILTER( isLITERAL(?name) ).
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['VAR', 'name']],
						['FILTER',
							['FUNCTION',
								['URI', 'sop:isLiteral'],
								['VAR', 'name'],
							],
						],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with isLITERAL(?var)" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name ?name .
					FILTER( DATATYPE(?name) = rdf:Literal ) .
				}
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [
						[['VAR','person'],['URI',['foaf','name']],['VAR', 'name']],
						['FILTER',
							['==',
								['FUNCTION',['URI', 'sparql:datatype'], ['VAR', 'name']],
								['URI', ['rdf', 'Literal']]
							]
						],
					],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
		'sources' => [],
		'variables' => [['VAR','person'],['VAR','homepage']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "filter with DATATYPE(?var)/URI equality" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gregory Todd Williams" ; foaf:homepage ?homepage .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','person'],['VAR','homepage']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "multiple attributes using ';'" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person
		WHERE	{
					?person foaf:name "Gregory Todd Williams", "Greg Williams" .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','name']],['LITERAL','Greg Williams']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','person']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "multiple objects using ','" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person
		WHERE	{
					?person <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> foaf:Person
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','person']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "predicate with full qURI" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person
		WHERE	{
					?person a foaf:Person .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','person']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "'a' rdf:type" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person ; foaf:name ?name .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]], [['VAR','person'],['URI',['foaf','name']],['VAR', 'name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','name']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "'a' rdf:type; multiple attributes using ';'" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?nick
		WHERE	{
					[ foaf:name "Gregory Todd Williams" ; foaf:nick ?nick ] .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','a1'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['BLANK','a1'],['URI',['foaf','nick']],['VAR','nick']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','nick']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "blank node; multiple attributes using ';'" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					[ a foaf:Person ] foaf:name ?name .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','a1'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI',['foaf','Person']]],[['BLANK','a1'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','name']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "blank node; using brackets '[...]'; 'a' rdf:type" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					[] foaf:name ?name .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','a1'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','name']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "blank node; empty brackets '[]'" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					_:abc foaf:name ?name .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','abc'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','name']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "blank node; using qName _:abc" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY ?name
END
	my $correct	= {
		'method' => 'SELECT',
		'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],
		'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},
		'sources' => [],
		'variables' => [['VAR','name']],
		'options'=>{orderby => [['ASC', ['VAR', 'name']]]},
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "select with ORDER BY" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	DISTINCT ?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
END
	my $correct	= {
					'method' => 'SELECT',
					'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],
					'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},
					'sources' => [],
					'variables' => [['VAR','name']],
					'options'=>{distinct => 1},
				};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "select with DISTINCT" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY asc( ?name )
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','name']],'options'=>{orderby => [['ASC', ['VAR', 'name']]]},};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "select with ORDER BY; asc()" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY DESC(?name)
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','name']],'options'=>{orderby => [['DESC', ['VAR', 'name']]]},};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "select with ORDER BY; DESC()" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY DESC(?name) LIMIT 10
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','name']],'options'=>{orderby => [['DESC', ['VAR', 'name']]], limit => 10},};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "select with ORDER BY; DESC(); with LIMIT" );
}

{
	my $sparql	= <<'END';
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX dc: <http://purl.org/dc/elements/1.1/>
		 select $pic $thumb $date 
		 WHERE { $pic foaf:thumbnail $thumb .
		 $pic dc:date $date } order by desc($date) limit 10
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','pic'],['URI',['foaf','thumbnail']],['VAR','thumb']],[['VAR','pic'],['URI',['dc','date']],['VAR','date']]],'sources' => [],'options' => {'orderby' => [['DESC',['VAR','date']]],'limit' => '10'},'variables' => [['VAR','pic'],['VAR','thumb'],['VAR','date']],'namespaces' => {'dc' => 'http://purl.org/dc/elements/1.1/','foaf' => 'http://xmlns.com/foaf/0.1/'}};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'select with ORDER BY; DESC(); with LIMIT; variables with "$"' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER( mygeo:distance(?point, +41.849331, -71.392) < 10 )
				}
END
	my $correct	= {
			'method'		=> 'SELECT', 
			'triples'		=> [
									[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],
									[['VAR','image'],['VAR','pred'],['VAR','point']],
									['FILTER',
										['<',
											['FUNCTION', ['URI', ['mygeo', 'distance']], ['VAR', 'point'], ['LITERAL', '41.849331', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']], ['LITERAL', '-71.392', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']]],
											['LITERAL','10', undef, [ 'URI', 'http://www.w3.org/2001/XMLSchema#integer' ]],
										]
									],
								],
			'sources'		=> [],
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'mygeo' => 'http://kasei.us/e/ns/geo#'},
			'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'FILTER function call' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER( mygeo:distance(?point, 41.849331, -71.392) < 5 + 5 )
				}
END
	my $correct	= {
			'method'		=> 'SELECT', 
			'triples'		=> [
									[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],
									[['VAR','image'],['VAR','pred'],['VAR','point']],
									['FILTER',
										['<',
											['FUNCTION', ['URI', ['mygeo', 'distance']], ['VAR', 'point'], ['LITERAL', '41.849331', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']], ['LITERAL', '-71.392', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']]],
											['+',
												['LITERAL','5', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']],
												['LITERAL','5', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']],
											]
										]
									],
								],
			'sources'		=> [],
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'mygeo' => 'http://kasei.us/e/ns/geo#'},
			'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'FILTER function call' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER( mygeo:distance(?point, 41.849331, -71.392) < 5 * 5 )
				}
END
	my $correct	= {
			'method'		=> 'SELECT', 
			'triples'		=> [
									[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],
									[['VAR','image'],['VAR','pred'],['VAR','point']],
									['FILTER',
										['<',
											['FUNCTION', ['URI', ['mygeo', 'distance']], ['VAR', 'point'], ['LITERAL', '41.849331', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']], ['LITERAL', '-71.392', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']]],
											['*',
												['LITERAL','5', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']],
												['LITERAL','5', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']],
											]
										]
									],
								],
			'sources'		=> [],
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'mygeo' => 'http://kasei.us/e/ns/geo#'},
			'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']]
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'FILTER function call' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?name
		WHERE	{
					?image dcterms:spatial ?point .
					?point foaf:name ?name .
					FILTER( mygeo:distance(?point, 41.849331, -71.392) < 10 ) .
					FILTER REGEX(?name, "Providence, RI")
				}
END
	my $correct	= {
			'method' => 'SELECT',
			'triples' => [
					[['VAR','image'],['URI',['dcterms','spatial']],['VAR','point']],
					[['VAR','point'],['URI',['foaf','name']],['VAR','name']],
					['FILTER', 
						[
							'&&',
							['<',['FUNCTION',['URI',['mygeo','distance']],['VAR','point'],['LITERAL','41.849331', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']],['LITERAL','-71.392', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#decimal']]],['LITERAL','10', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]],
							['~~',['VAR','name'],['LITERAL','Providence, RI']]
						]
					],
				],
			'sources' => [],
			'variables' => [['VAR','image'],['VAR','point'],['VAR','name']],
			'namespaces' => {'mygeo' => 'http://kasei.us/e/ns/geo#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','dcterms' => 'http://purl.org/dc/terms/'}
		};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'multiple FILTERs; with function call' );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?name ?mbox
		WHERE	{
					?person foaf:name ?name .
					OPTIONAL { ?person foaf:mbox ?mbox }
				}
END
	my $correct	= {
					'method'		=> 'SELECT',
					'triples'		=> [
										[
											['VAR','person'],
											['URI',['foaf','name']],
											['VAR','name']
										],
										['OPTIONAL',
											[
												[
													['VAR','person'],
													['URI',['foaf','mbox']],
													['VAR','mbox']
												]
											]
										]
									],
					'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/'},
					'sources'		=> [],
					'variables'		=> [['VAR','person'], ['VAR','name'], ['VAR','mbox']],
				};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "optional triple '{...}'" );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?name ?mbox ?nick
		WHERE	{
					?person foaf:name ?name .
					OPTIONAL {
						?person foaf:mbox ?mbox; foaf:nick ?nick
					}
				}
END
	my $correct	= {
					'method' => 'SELECT',
					'triples' => [[['VAR','person'],['URI',['foaf','name']],['VAR','name']],['OPTIONAL',[[['VAR','person'],['URI',['foaf','mbox']],['VAR','mbox']],[['VAR','person'],['URI',['foaf','nick']],['VAR','nick']]]]],
					'sources' => [],
					'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},
					'variables' => [['VAR','person'],['VAR','name'],['VAR','mbox'],['VAR','nick']]
				};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "optional triples '{...; ...}'" );
}

{
	my $sparql	= <<"END";
		PREFIX dc10:  <http://purl.org/dc/elements/1.1/>
		PREFIX dc11:  <http://purl.org/dc/elements/1.0/>
		SELECT	?title ?author
		WHERE	{
					{ ?book dc10:title ?title .  ?book dc10:creator ?author }
					UNION
					{ ?book dc11:title ?title .  ?book dc11:creator ?author }
				}
END
	my $correct = {
		  'method' => 'SELECT',
		  'triples' => [
		  				[
		  				   'UNION',
						   [
						     [
						       ['VAR','book'],
							   ['URI',['dc10','title']],
							   ['VAR','title']
							 ],
							 [
							   ['VAR','book'],
							   ['URI',['dc10','creator']],
							   ['VAR','author']
							 ]
						   ],
						   [
                             [
                               ['VAR','book'],
                               ['URI',['dc11','title']],
                               ['VAR','title']
                             ],
                             [
                               ['VAR','book'],
                               ['URI',['dc11','creator']],
                               ['VAR','author']
                             ]
                           ]
						]
					   ],
		  'sources' => [],
		  'variables' => [
						   ['VAR','title'],
						   ['VAR','author']
						 ],
		  'namespaces' => {
							'dc10' => 'http://purl.org/dc/elements/1.1/',
							'dc11' => 'http://purl.org/dc/elements/1.0/'
						  }
		};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "union; sparql 6.2" );
}


{
	my $sparql	= <<'END';
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gary Peck"@en ; foaf:homepage ?homepage .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gary Peck', 'en', undef]],[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','person'],['VAR','homepage']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'literal language tag @en' );
}

{
	my $sparql	= <<'END';
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?image
		WHERE	{
					?image dc:date "2005-04-07T18:27:56-04:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>
				}
END
	my $correct	= {
		  'method'		=> 'SELECT',
		  'triples'		=> [
							 [
							   ['VAR','image'],
							   ['URI',['dc','date']],
							   [
								 'LITERAL',
								 '2005-04-07T18:27:56-04:00',
								 undef,
								 ['URI','http://www.w3.org/2001/XMLSchema#dateTime']
							   ]
							 ]
						   ],
		  'sources'		=> [],
		  'variables'	=> [['VAR','image']],
		  'namespaces'	=> {
							'foaf' => 'http://xmlns.com/foaf/0.1/'
						}
		};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'typed literal ^^URI' );
}

{
	my $sparql	= <<'END';
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX  xs: <http://www.w3.org/2001/XMLSchema#>
		SELECT	?image
		WHERE	{
					?image dc:date "2005-04-07T18:27:56-04:00"^^xs:dateTime
				}
END
	my $correct	= {
		  'method'		=> 'SELECT',
		  'triples'		=> [
							 [
							   ['VAR','image'],
							   ['URI',['dc','date']],
							   [
								 'LITERAL',
								 '2005-04-07T18:27:56-04:00',
								 undef,
								 ['URI',['xs', 'dateTime']]
							   ]
							 ]
						   ],
		  'sources'		=> [],
		  'variables'	=> [['VAR','image']],
		  'namespaces'	=> {
							'foaf'	=> 'http://xmlns.com/foaf/0.1/',
							'xs'	=> 'http://www.w3.org/2001/XMLSchema#'
						}
		};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'typed literal ^^qName' );
}

{
	my $sparql	= <<"END";
		SELECT	?x
		WHERE	{ (1 ?x 3) }
END
	my $correct	= {
		  'method'		=> 'SELECT',
          'triples' => [
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','1', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a2']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['VAR','x']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a3']
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','3', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#nil']
                         ]
                       ],
          'sources' => [],
          'variables' => [
                           ['VAR','x']
                         ],
          'namespaces' => {}
        };
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'subject collection syntax' );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?x
		WHERE	{ (1 ?x 3) foaf:name "My Collection" }
END
	my $correct	= {
		  'method'		=> 'SELECT',
          'triples' => [
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','1', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a2']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['VAR','x']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a3']
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','3', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#nil']
                         ],
                         [
                         	['BLANK', 'a1'],
                         	['URI', ['foaf', 'name']],
                         	['LITERAL', 'My Collection'],
                         ]
                       ],
          'sources' => [],
          'variables' => [
                           ['VAR','x']
                         ],
          'namespaces' => { foaf => 'http://xmlns.com/foaf/0.1/' }
        };
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'subject collection syntax; with pred-obj.' );
}

{
	my $sparql	= <<"END";
		PREFIX dc: <http://purl.org/dc/elements/1.1/>
		SELECT	?x
		WHERE	{ (1 ?x 3) dc:subject (1 2 3) }
END
	my $correct	= {
		  'method'		=> 'SELECT',
          'triples' => [
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','1', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a2']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['VAR','x']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a3']
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','3', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#nil']
                         ],
                         [
                           ['BLANK','a4'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','1', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a4'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a5']
                         ],
                         [
                           ['BLANK','a5'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','2', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a5'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a6']
                         ],
                         [
                           ['BLANK','a6'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','3', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a6'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#nil']
                         ],
                         [
                         	['BLANK', 'a1'],
                         	['URI', ['dc', 'subject']],
                         	['BLANK', 'a4'],
                         ],
                       ],
          'sources' => [],
          'variables' => [
                           ['VAR','x']
                         ],
          'namespaces' => { dc => 'http://purl.org/dc/elements/1.1/' }
        };
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'subject collection syntax; object collection syntax' );
}

{
	my $sparql	= <<"END";
		PREFIX test: <http://kasei.us/e/ns/test#>
		SELECT	?x
		WHERE	{
					<http://kasei.us/about/foaf.xrdf#greg> test:mycollection (1 ?x 3) .
				}
END
	my $correct	= {
		  'method'		=> 'SELECT',
          'triples' => [
                         [
                           ['URI','http://kasei.us/about/foaf.xrdf#greg'],
                           ['URI',['test', 'mycollection']],
                           ['BLANK','a1']
                         ],
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','1', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a1'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a2']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['VAR','x']
                         ],
                         [
                           ['BLANK','a2'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['BLANK','a3']
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#first'],
                           ['LITERAL','3', undef, ['URI', 'http://www.w3.org/2001/XMLSchema#integer']]
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#nil']
                         ]
                       ],
          'sources' => [],
          'variables' => [
                           ['VAR','x']
                         ],
          'namespaces' => { test => 'http://kasei.us/e/ns/test#' }
        };
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'object collection syntax' );
}

{
	my $sparql	= <<"END";
		SELECT *
		WHERE { ?a ?a ?b . }
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','a'],['VAR','a'],['VAR','b']]],'namespaces' => {}, 'sources' => [],'variables' => ['*'],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "SELECT *" );
}

{
	my $sparql	= <<"END";
		PREFIX	: <http://xmlns.com/foaf/0.1/>
		SELECT	?person
		WHERE	{
					?person :name "Gregory Todd Williams", "Greg Williams" .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['__DEFAULT__','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['__DEFAULT__','name']],['LITERAL','Greg Williams']]],'namespaces' => {'__DEFAULT__' => 'http://xmlns.com/foaf/0.1/'},'sources' => [],'variables' => [['VAR','person']],};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "default prefix" );
}

{
	my $sparql	= <<"END";
			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
			SELECT ?src ?name
			FROM NAMED <file://data/named_graphs/alice.rdf>
			FROM NAMED <file://data/named_graphs/bob.rdf>
			WHERE {
				GRAPH ?src { ?x foaf:name ?name }
			}
END
	my $correct	= {
		'method' => 'SELECT',
		'sources' => [
						[
							'URI',
							'file://data/named_graphs/alice.rdf',
							'NAMED'
							
						],
						[
							'URI',
							'file://data/named_graphs/bob.rdf',
							'NAMED'
						]
					],
		'variables' => [
						[ 'VAR', 'src' ],
						[ 'VAR', 'name' ]
					],
		'triples' => [
						[
							'GRAPH',
							[ 'VAR', 'src' ],
							[
								[
								[ 'VAR', 'x' ],
								[ 'URI', ['foaf', 'name'] ],
								[ 'VAR', 'name' ]
								]
							]
						]
					],
		'namespaces' => {
							'foaf' => 'http://xmlns.com/foaf/0.1/'
						}
		};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "single triple; no prefix" );
}

{
	my $sparql	= <<"END";
				PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
				ASK {
					FILTER ( "1995-11-05"^^xsd:dateTime <= "1994-11-05T13:15:30Z"^^xsd:dateTime ) .
				}
END
	my $correct	= {
		'method'	=> 'ASK',
		'variables'	=> [],
		'triples'	=> [
						[
							'FILTER',
							[
								'<=',
								[
									'LITERAL',
									'1995-11-05',
									undef,
									[
										'URI',
										[
											'xsd',
											'dateTime'
										]
									]
								],
								[
									'LITERAL',
									'1994-11-05T13:15:30Z',
									undef,
									[
										'URI',
										[
											'xsd',
											'dateTime'
										]
									]
								]
							]
						]
					],
		'sources' => [],
		'namespaces' => {
		'xsd' => 'http://www.w3.org/2001/XMLSchema#'
		}
        };
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "ASK FILTER; using <= (shouldn't parse as '<')" );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	xsd: <http://www.w3.org/2001/XMLSchema#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
		}
		ORDER BY ASC( xsd:decimal( ?lat ) )
END
	my $correct	= {
			'method'		=> 'SELECT', 
			'triples'		=> [
									[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],
									[['VAR','image'],['VAR','pred'],['VAR','point']],
							   ],
			'sources'		=> [],
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'xsd' => 'http://www.w3.org/2001/XMLSchema#'},
			'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']],
			'options'		=> {
								'orderby' => [
												[
													'ASC',
													[
														'FUNCTION',
														['URI',['xsd','decimal']],
														['VAR','lat']
													]
												]
											]
		                       },
	};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, 'ORDER BY with expression' );
}

{
	my $sparql	= <<"END";
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX cyc: <http://www.cyc.com/2004/06/04/cyc#>
PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
SELECT ?place ?img ?date
WHERE {
	?region foaf:name "Maine" .
	?p cyc:inRegion ?region; foaf:name ?place .
	?img dcterms:spatial ?p .
	?img dc:date ?date;  rdf:type foaf:Image .
}
ORDER BY DESC(?date)
LIMIT 10
END
	my $correct	= {
		  'method' => 'SELECT',
		  'sources' => [],
		  'variables' => [
							['VAR','place'],
							['VAR','img'],
							['VAR','date']
						 ],
		  'triples' => [
						 [
							[ 'VAR', 'region' ],
							[ 'URI', [ 'foaf', 'name' ] ],
							[ 'LITERAL','Maine' ]
						 ],
						 [
							[ 'VAR', 'p' ],
							[ 'URI',['cyc','inRegion'] ],
							[ 'VAR', 'region' ]
						 ],
						 [
							[ 'VAR', 'p' ],
							[ 'URI',['foaf','name'] ],
							[ 'VAR', 'place' ]
						 ],
						 [
							[ 'VAR', 'img' ],
							[ 'URI',['dcterms','spatial'] ],
							[ 'VAR', 'p' ]
						 ],
						 [
							[ 'VAR', 'img' ],
							[ 'URI', ['dc','date'] ],
							[ 'VAR', 'date' ]
						 ],
						 [
							[ 'VAR', 'img' ],
							[ 'URI', ['rdf','type'] ],
							[ 'URI', ['foaf','Image'] ]
						 ]
					   ],
		  'options' => {
						'orderby' => [
										[
											'DESC',
											[
												'VAR',
												'date'
											]
										]
									],
						'limit' => '10'
					   },
		  'namespaces' => {
							'dc' => 'http://purl.org/dc/elements/1.1/',
							'cyc' => 'http://www.cyc.com/2004/06/04/cyc#',
							'foaf' => 'http://xmlns.com/foaf/0.1/',
							'rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
							'dcterms' => 'http://purl.org/dc/terms/'
						  }
		};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "triple pattern with trailing internal '.'" );
}

{
	my $sparql	= <<"END";
			PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX cyc: <http://www.cyc.com/2004/06/04/cyc#>
			PREFIX dcterms: <http://purl.org/dc/terms/>
			PREFIX dc: <http://purl.org/dc/elements/1.1/>
			PREFIX album: <http://kasei.us/e/ns/album#>
			PREFIX p: <http://www.usefulinc.com/picdiary/>
			SELECT ?img ?date
			WHERE {
				<http://kasei.us/pictures/parties/19991205-Tims_Party/> album:image ?img .
				?img dc:date ?date ; rdf:type foaf:Image .
			}
			ORDER BY DESC(?date)
END
	my $correct	= {
					'method' => 'SELECT',
					'triples' => [
									[
										['URI','http://kasei.us/pictures/parties/19991205-Tims_Party/'],
										['URI',['album','image']],
										['VAR','img']
									],
									[
										['VAR','img'],
										['URI',['dc','date']],
										['VAR','date']
									],
									[
										['VAR','img'],
										['URI',['rdf','type']],
										['URI',['foaf', 'Image']]
									]
								],
					'namespaces' => {
										p		=> 'http://www.usefulinc.com/picdiary/',
										album	=> 'http://kasei.us/e/ns/album#',
										dc		=> 'http://purl.org/dc/elements/1.1/',
										cyc		=> 'http://www.cyc.com/2004/06/04/cyc#',
										foaf	=> 'http://xmlns.com/foaf/0.1/',
										rdf		=> 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
										dcterms	=> 'http://purl.org/dc/terms/',
									},
					'sources' => [],
					'variables' => [['VAR','img'], ['VAR', 'date']],
					'options' => {orderby => [['DESC', ['VAR', 'date']]]},
				};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "[bug] query with predicate starting with 'a' (confused with { ?subj a ?type})" );
}


##### ERRORS

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		SELECT ?node
		WHERE {
			?node rdf:type <http://kasei.us/e/ns/mt/blog> .
		}
		extra stuff
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'extra input after query' );
	like( $parser->error, qr/^Remaining input/, 'got expected error' );
}

{
	my $sparql	= <<"END";
		PREFIX dc10:  <http://purl.org/dc/elements/1.1/>
		PREFIX dc11:  <http://purl.org/dc/elements/1.0/>
		SELECT	?title ?author
		WHERE	{
					{ ?book dc10:title ?title .  ?book dc10:creator ?author }
					UNION
					?foo
				}
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'missing union part' );
	like( $parser->error, qr/^Expecting triple pattern in second position of UNION/, 'got expected error' );
}

{
	my $sparql	= <<"END";
		PREFIX dc10:  <http://purl.org/dc/elements/1.1/>
		PREFIX dc11:  <http://purl.org/dc/elements/1.0/>
		SELECT	?title ?author
		WHERE	{
					?book dc10:title ?title .
					?book dc10:creator ?author .
					FILTER
				}
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'missing filter' );
	like( $parser->error, qr/^Expecting FILTER declaration/, 'got expected error' );
}

{
	my $sparql	= <<"END";
		PREFIX dc10:  <http://purl.org/dc/elements/1.1/>
		PREFIX dc11:  <http://purl.org/dc/elements/1.0/>
		SELECT	?title ?author
		WHERE	{
					?book dc10:title ?title .
					FILTER( ?title = ) .
				}
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'bad syntax in filter' );
	like( $parser->error, qr/^Expecting numeric expression/, 'got expected error' );
}

{
	my $sparql	= <<"END";
		PREFIX dc10:  <http://purl.org/dc/elements/1.1/>
		PREFIX dc11:  <http://purl.org/dc/elements/1.0/>
		SELECT	?title ?author
		WHERE	{
					?book dc10:title ?title .
					FILTER( ?title = foo ) .
				}
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'bad syntax in filter' );
	like( $parser->error, qr/^Expecting ":"/, 'got expected error' );
}

{
	my $sparql	= <<"END";
		PREFIX dc:  <http://purl.org/dc/elements/1.1/>
		SELECT	?title ?author
		WHERE	{
					?book dc:title ?title ; dc:identifier ?id .
					FILTER( ?id < 2 * ) .
				}
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'bad syntax in filter' );
	like( $parser->error, qr/^Expecting unary expression after '*'/, 'got expected error' );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?x
		WHERE	{ (1 2) foaf:name }
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'missing object' );
	like( $parser->error, qr/Expecting object after predicate/, 'parse error' );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?x
		WHERE	{ [] foaf:name }
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'missing object' );
	like( $parser->error, qr/Expecting object after predicate/, 'parse error' );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?x
		WHERE	{ ?x foaf:name }
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'missing object' );
	like( $parser->error, qr/Expecting object after predicate/, 'parse error' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					FILTER( 10 > ?lat + )
				}
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'missing multiplicative expression' );
	like( $parser->error, qr/Expecting multiplicative expression after '[+]'/, 'parse error' );
}

{
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					FILTER( ! )
				}
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'missing multiplicative expression' );
	like( $parser->error, qr/Expecting primary expression after '[!]'/, 'parse error' );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY ASC
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'bad ORDER BY expression' );
	like( $parser->error, qr/Expecting ORDER BY expression/, 'parse error' );
}

{
	my $sparql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'bad ORDER BY expression' );
	like( $parser->error, qr/Expecting ORDER BY expression/, 'parse error' );
}
