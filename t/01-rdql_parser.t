#!/usr/bin/perl
use strict;
use Test::More tests => 5;
use Data::Dumper;

use_ok( 'RDF::Query::Parser::RDQL' );
my $parser	= new RDF::Query::Parser::RDQL (undef);
isa_ok( $parser, 'RDF::Query::Parser::RDQL' );

{
	my $rdql	= <<"END";
		SELECT
			?page
		WHERE
			(?person foaf:name "Gregory Todd Williams")
			(?person foaf:homepage ?page)
		USING
			rdf FOR <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
			foaf FOR <http://xmlns.com/foaf/0.1/>,
			dcterms FOR <http://purl.org/dc/terms/>,
			geo FOR <http://www.w3.org/2003/01/geo/wgs84_pos#>
END
	my $correct	= {'variables' => [['VAR','page']],'namespaces' => {'dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#'},'sources' => undef,'triples' => [[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],[['VAR','person'],['URI',['foaf','homepage']],['VAR','page']]]};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'SELECT, WHERE, USING' );
}

{
	my $rdql	= <<"END";
		SELECT
				?image ?point ?lat
		WHERE
				(?point geo:lat ?lat)
				(?image ?pred ?point)
		AND
				(?pred == <http://purl.org/dc/terms/spatial> || ?pred == <http://xmlns.com/foaf/0.1/based_near>)
		AND
				?lat > 52.988674,
				?lat < 53.036526
		USING
				rdf FOR <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
				foaf FOR <http://xmlns.com/foaf/0.1/>,
				dcterms FOR <http://purl.org/dc/terms/>,
				geo FOR <http://www.w3.org/2003/01/geo/wgs84_pos#>
END
	my $correct	= {
		'triples'		=> [
							[['VAR','point'],['URI',['geo','lat']],['VAR','lat']],
							[['VAR','image'],['VAR','pred'],['VAR','point']],
							['FILTER', ['&&',['||',['==',['VAR','pred'],['URI','http://purl.org/dc/terms/spatial']],['==',['VAR','pred'],['URI','http://xmlns.com/foaf/0.1/based_near']]],['>',['VAR','lat'],['LITERAL','52.988674']],['<',['VAR','lat'],['LITERAL','53.036526']]]]
						],
		'sources'		=> undef,
		'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'},
		'variables'		=> [['VAR','image'],['VAR','point'],['VAR','lat']]
	};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'VarUri EQ OR constraint, numeric comparison constraint' );
}


{
	my $rdql	= <<"END";
		SELECT
				?person ?homepage
		WHERE
				(?person foaf:name "Gregory Todd Williams")
				(?person foaf:homepage ?homepage)
		AND
				?homepage ~~ /kasei/
		USING
				rdf FOR <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
				foaf FOR <http://xmlns.com/foaf/0.1/>,
				dcterms FOR <http://purl.org/dc/terms/>,
				geo FOR <http://www.w3.org/2003/01/geo/wgs84_pos#>
END
	my $correct	= {
					'triples'		=> [
										[['VAR','person'],['URI',['foaf','name']],['LITERAL','Gregory Todd Williams']],
										[['VAR','person'],['URI',['foaf','homepage']],['VAR','homepage']],
										['FILTER', ['~~',['VAR','homepage'],['LITERAL','kasei']]],
									],
					'namespaces'	=> {'foaf' => 'http://xmlns.com/foaf/0.1/','rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#','dcterms' => 'http://purl.org/dc/terms/'},
					'sources'		=> undef,
					'variables'		=> [['VAR','person'],['VAR','homepage']]
				};
	my $parsed	= $parser->parse( $rdql );
	is_deeply( $parsed, $correct, 'regex constraint' );
}
