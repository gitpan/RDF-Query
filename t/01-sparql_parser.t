#!/usr/bin/perl
use strict;
use Test::More tests => 35;
use Data::Dumper;

use_ok( 'RDF::Query::Parser::SPARQL' );
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','node'],['URI',['rdf','type']],['URI','http://kasei.us/e/ns/mt/blog']]],'namespaces' => {}, 'sources' => undef,'variables' => [['VAR','node']], 'constraints' => []};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "single triple; no prefix" );
}

{
	my $rdql	= <<"END";
		DESCRIBE ?node
		WHERE { ?node rdf:type <http://kasei.us/e/ns/mt/blog> }
END
	my $correct	= {'method' => 'DESCRIBE', 'triples' => [[['VAR','node'],['URI',['rdf','type']],['URI','http://kasei.us/e/ns/mt/blog']]],'namespaces' => {}, 'sources' => undef,'variables' => [['VAR','node']], 'constraints' => [], 'constraints' => []};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "simple DESCRIBE" );
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
	my $correct	= {'method' => 'SELECT', 'variables' => [['VAR','page']],'namespaces' => {'dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#'},'sources' => undef,'constraints' => [],'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','page']]]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'SELECT, WHERE, USING' );
}

{
	my $rdql	= <<'END';
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
	my $correct	= {'method' => 'SELECT', 'variables' => [['VAR','page']],'namespaces' => {'dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#'},'sources' => undef,'constraints' => [],'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','page']]]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'SELECT, WHERE, USING; variables with "$"' );
}

{
	my $rdql	= <<"END";
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
									[['VAR','image'],['VAR','pred'],['VAR','point']]
								],
			'sources'		=> undef,
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'},
			'constraints'	=> ['&&',
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
									 ['LITERAL','52.988674']
								   ],
								   ['<',
									 ['VAR','lat'],
									 ['LITERAL','53.036526']
								   ]
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
					?person foaf:homepage ?homepage .
					FILTER	REGEX(?homepage, "kasei")
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},'constraints' => ['~~',['VAR','homepage'],['LITERAL','kasei']],'sources' => undef,'variables' => [['VAR','person'],['VAR','homepage']]};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person'],['VAR','homepage']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','name']],['LITERAL','Greg Williams']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]], [['VAR','person'],['URI',['foaf','name']],['VAR', 'name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']], 'constraints' => []};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "'a' rdf:type; multiple attributes using ';'" );
}



{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?nick
		WHERE	{
					[ foaf:name "Gregory Todd Williams" ; foaf:nick ?nick ] .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','a1'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['BLANK','a1'],['URI',['foaf','nick']],['VAR','nick']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','nick']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','a1'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI',['foaf','Person']]],[['BLANK','a1'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','a1'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['BLANK','abc'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']],'options'=>{orderby => [['ASC', ['VAR', 'name']]]}, 'constraints' => []};
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
	my $correct	= {
					'method' => 'SELECT',
					'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],
					'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},
					'sources' => undef,
					'variables' => [['VAR','name']],
					'options'=>{distinct => 1},
					'constraints' => []
				};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "select with DISTINCT" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY asc( ?name )
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']],'options'=>{orderby => [['ASC', ['VAR', 'name']]]}, 'constraints' => []};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "select with ORDER BY; asc()" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY DESC(?name)
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']],'options'=>{orderby => [['DESC', ['VAR', 'name']]]}, 'constraints' => []};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "select with ORDER BY; DESC()" );
}

{
	my $rdql	= <<"END";
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY DESC(?name) LIMIT 10
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#type'],['URI', ['foaf', 'Person']]],[['VAR','person'],['URI',['foaf','name']],['VAR','name']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','name']],'options'=>{orderby => [['DESC', ['VAR', 'name']]], limit => 10}, 'constraints' => []};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "select with ORDER BY; DESC(); with LIMIT" );
}

{
	my $rdql	= <<'END';
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX dc: <http://purl.org/dc/elements/1.1/>
		 select $pic $thumb $date 
		 WHERE { $pic foaf:thumbnail $thumb .
		 $pic dc:date $date } order by desc($date) limit 10
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','pic'],['URI',['foaf','thumbnail']],['VAR','thumb']],[['VAR','pic'],['URI',['dc','date']],['VAR','date']]],'constraints' => [],'sources' => undef,'options' => {'orderby' => [['DESC',['VAR','date']]],'limit' => '10'},'variables' => [['VAR','pic'],['VAR','thumb'],['VAR','date']],'namespaces' => {'dc' => 'http://purl.org/dc/elements/1.1/','foaf' => 'http://xmlns.com/foaf/0.1/'}};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'select with ORDER BY; DESC(); with LIMIT; variables with "$"' );
}

{
	my $rdql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER( mygeo:distance(?point, 41.849331, -71.392) < 10 )
				}
END
	my $correct	= {
			'method'		=> 'SELECT', 
			'triples'		=> [[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],[['VAR','image'],['VAR','pred'],['VAR','point']]],
			'sources'		=> undef,
			'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'mygeo' => 'http://kasei.us/e/ns/geo#'},
			'constraints'	=> ['<',
								['FUNCTION', ['URI', ['mygeo', 'distance']], ['VAR', 'point'], ['LITERAL', '41.849331'], ['LITERAL', '-71.392']],
								['LITERAL','10'],
							],
			'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']]
	};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'FILTER function call' );
}

{
	my $rdql	= <<"END";
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','image'],['URI',['dcterms','spatial']],['VAR','point']],[['VAR','point'],['URI',['foaf','name']],['VAR','name']]],'constraints' => ['&&',['<',['FUNCTION',['URI',['mygeo','distance']],['VAR','point'],['LITERAL','41.849331'],['LITERAL','-71.392']],['LITERAL','10']],['~~',['VAR','name'],['LITERAL','Providence, RI']]],'sources' => undef,'variables' => [['VAR','image'],['VAR','point'],['VAR','name']],'namespaces' => {'mygeo' => 'http://kasei.us/e/ns/geo#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','dcterms' => 'http://purl.org/dc/terms/'}};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'multiple FILTERs; with function call' );
}

{
	my $rdql	= <<"END";
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
					'sources'		=> undef,
					'variables'		=> [['VAR','person'], ['VAR','name'], ['VAR','mbox']],
					'constraints'	=> []
				};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, "optional triple '{...}'" );
}

{
	my $rdql	= <<"END";
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
					'constraints' => [],
					'sources' => undef,
					'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},
					'variables' => [['VAR','person'],['VAR','name'],['VAR','mbox'],['VAR','nick']]
				};
	my $parsed	= $parser->parse( $rdql );
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
		  'constraints' => [],
		  'sources' => undef,
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
	my $rdql	= <<'END';
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?homepage
		WHERE	{
					?person foaf:name "Gary Peck"@en ; foaf:homepage ?homepage .
				}
END
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gary Peck', 'en', undef]],[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']]],'namespaces' => {'foaf' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person'],['VAR','homepage']], 'constraints' => []};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'literal language tag @en' );
}

{
	my $rdql	= <<'END';
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
		  'constraints' => [],
		  'sources'		=> undef,
		  'variables'	=> [['VAR','image']],
		  'namespaces'	=> {
							'foaf' => 'http://xmlns.com/foaf/0.1/'
						}
		};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'typed literal ^^URI' );
}

{
	my $rdql	= <<'END';
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
		  'constraints' => [],
		  'sources'		=> undef,
		  'variables'	=> [['VAR','image']],
		  'namespaces'	=> {
							'foaf'	=> 'http://xmlns.com/foaf/0.1/',
							'xs'	=> 'http://www.w3.org/2001/XMLSchema#'
						}
		};
	my $parsed	= $parser->parse( $rdql );
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
                           ['LITERAL','1']
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
                           ['LITERAL','3']
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#nil']
                         ]
                       ],
          'constraints' => [],
          'sources' => undef,
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
                           ['LITERAL','1']
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
                           ['LITERAL','3']
                         ],
                         [
                           ['BLANK','a3'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'],
                           ['URI','http://www.w3.org/1999/02/22-rdf-syntax-ns#nil']
                         ]
                       ],
          'constraints' => [],
          'sources' => undef,
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','a'],['VAR','a'],['VAR','b']]],'namespaces' => {}, 'sources' => undef,'variables' => ['*'], 'constraints' => []};
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
	my $correct	= {'method' => 'SELECT', 'triples' => [[['VAR','person'],['URI',['__DEFAULT__','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['__DEFAULT__','name']],['LITERAL','Greg Williams']]],'namespaces' => {'__DEFAULT__' => 'http://xmlns.com/foaf/0.1/'},'sources' => undef,'variables' => [['VAR','person']], 'constraints' => []};
	my $parsed	= $parser->parse( $sparql );
	is_deeply( $parsed, $correct, "default prefix" );
}

