#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use YAML;
use Data::Dumper;
use Scalar::Util qw(reftype);

if ($ENV{RDFQUERY_TIMETEST}) {
	plan tests => 95;
} else {
	plan skip_all => 'Developer tests. Set RDFQUERY_TIMETEST to run these tests.';
	return;
}

use_ok( 'RDF::Query::Parser::tSPARQL' );
my $parser	= new RDF::Query::Parser::tSPARQL ();
isa_ok( $parser, 'RDF::Query::Parser::tSPARQL' );



my (@data)	= YAML::Load(do { local($/) = undef; <DATA> });
foreach (@data) {
	next unless (reftype($_) eq 'ARRAY');
	my ($name, $sparql, $correct)	= @$_;
	my $parsed	= $parser->parse( $sparql );
	my $r	= is_deeply( $parsed, $correct, $name );
	unless ($r) {
		warn 'PARSE ERROR: ' . $parser->error;
		warn Dumper($parsed);
	}
}


sub _____ERRORS______ {}

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
	like( $parser->error, qr/Remaining input/, 'got expected error' );
}


__END__
---
- single triple; no prefix
- |
  SELECT ?node
  WHERE {
    ?node rdf:type <http://kasei.us/e/ns/mt/blog> .
  }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      -
        - VAR
        - node
      -
        - URI
        -
          - rdf
          - type
      -
        - URI
        - http://kasei.us/e/ns/mt/blog
  variables:
    -
      - VAR
      - node
---
- simple DESCRIBE
- |
  DESCRIBE ?node
  WHERE { ?node rdf:type <http://kasei.us/e/ns/mt/blog> }
- method: DESCRIBE
  namespaces: {}
  sources: []
  triples:
    -
      -
        - VAR
        - node
      -
        - URI
        -
          - rdf
          - type
      -
        - URI
        - http://kasei.us/e/ns/mt/blog
  variables:
    -
      - VAR
      - node
---
- SELECT, WHERE, USING
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?page
  WHERE	{
  			?person foaf:name "Gregory Todd Williams" .
  			?person foaf:homepage ?page .
  		}
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - homepage
      -
        - VAR
        - page
  variables:
    -
      - VAR
      - page
---
- SELECT, WHERE, USING; variables with "$"
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	$page
  WHERE	{
  			$person foaf:name "Gregory Todd Williams" .
  			$person foaf:homepage $page .
  		}
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - homepage
      -
        - VAR
        - page
  variables:
    -
      - VAR
      - page
---
- VarUri EQ OR constraint, numeric comparison constraint
- |
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - image
      -
        - VAR
        - pred
      -
        - VAR
        - point
    -
      - FILTER
      -
        - '&&'
        -
          - '||'
          -
            - ==
            -
              - VAR
              - pred
            -
              - URI
              - http://purl.org/dc/terms/spatial
          -
            - ==
            -
              - VAR
              - pred
            -
              - URI
              - http://xmlns.com/foaf/0.1/based_near
        -
          - '>'
          -
            - VAR
            - lat
          -
            - LITERAL
            - 52.988674
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
        -
          - <
          -
            - VAR
            - lat
          -
            - LITERAL
            - 53.036526
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - lat
---
- regex constraint; no trailing '.'
- |
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - homepage
      -
        - VAR
        - homepage
    -
      - FILTER
      -
        - '~~'
        -
          - VAR
          - homepage
        -
          - LITERAL
          - kasei
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- filter with variable/function-call equality
- |
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - VAR
        - pred
      -
        - VAR
        - homepage
    -
      - FILTER
      -
        - ==
        -
          - VAR
          - pred
        -
          - FUNCTION
          -
            - URI
            -
              - func
              - homepagepred
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- filter with variable/function-call equality
- |
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - VAR
        - pred
      -
        - VAR
        - homepage
    -
      - FILTER
      -
        - ==
        -
          - VAR
          - pred
        -
          - FUNCTION
          -
            - URI
            - func:homepagepred
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- filter with LANG(?var)/literal equality
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?person ?homepage
  WHERE	{
  			?person foaf:name ?name .
  			FILTER( LANG(?name) = 'en' ) .
  		}
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - FILTER
      -
        - ==
        -
          - FUNCTION
          -
            - URI
            - sparql:lang
          -
            - VAR
            - name
        -
          - LITERAL
          - en
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- filter with LANGMATCHES(?var, 'literal')
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?person ?homepage
  WHERE	{
  			?person foaf:name ?name .
  			FILTER( LANGMATCHES(?name, "foo"@en ) ).
  		}
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - FILTER
      -
        - FUNCTION
        -
          - URI
          - sparql:langmatches
        -
          - VAR
          - name
        -
          - LITERAL
          - foo
          - en
          - ~
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- filter with isLITERAL(?var)
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?person ?homepage
  WHERE	{
  			?person foaf:name ?name .
  			FILTER( isLITERAL(?name) ).
  		}
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - FILTER
      -
        - FUNCTION
        -
          - URI
          - sop:isLiteral
        -
          - VAR
          - name
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- filter with DATATYPE(?var)/URI equality
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?person ?homepage
  WHERE	{
  			?person foaf:name ?name .
  			FILTER( DATATYPE(?name) = rdf:Literal ) .
  		}
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - FILTER
      -
        - ==
        -
          - FUNCTION
          -
            - URI
            - sparql:datatype
          -
            - VAR
            - name
        -
          - URI
          -
            - rdf
            - Literal
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- multiple attributes using ';'
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?person ?homepage
  WHERE	{
  			?person foaf:name "Gregory Todd Williams" ; foaf:homepage ?homepage .
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - homepage
      -
        - VAR
        - homepage
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- predicate with full qURI
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?person
  WHERE	{
  			?person foaf:name "Gregory Todd Williams", "Greg Williams" .
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Greg Williams
  variables:
    -
      - VAR
      - person
---
- "'a' rdf:type"
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?person
  WHERE	{
  			?person <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> foaf:Person
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
  variables:
    -
      - VAR
      - person
---
- "'a' rdf:type; multiple attributes using ';'"
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  			?person a foaf:Person ; foaf:name ?name .
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- "blank node subject; multiple attributes using ';'"
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?nick
  WHERE	{
  			[ foaf:name "Gregory Todd Williams" ; foaf:nick ?nick ] .
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - foaf
          - nick
      -
        - VAR
        - nick
  variables:
    -
      - VAR
      - nick
---
- "blank node subject; using brackets '[...]'; 'a' rdf:type"
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  			[ a foaf:Person ] foaf:name ?name .
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- "blank node subject; empty brackets '[]'"
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  			[] foaf:name ?name .
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- blank node object
- |
  PREFIX dao: <http://kasei.us/ns/dao#>
  PREFIX dc: <http://purl.org/dc/elements/1.1/>
  PREFIX beer: <http://www.csd.abdn.ac.uk/research/AgentCities/ontologies/beer#>
  
  SELECT ?name
  WHERE {
  	?me dao:consumed [ a beer:Ale ; beer:name ?name ] .
  }
- method: SELECT
  namespaces:
    beer: http://www.csd.abdn.ac.uk/research/AgentCities/ontologies/beer#
    dao: http://kasei.us/ns/dao#
    dc: http://purl.org/dc/elements/1.1/
  sources: []
  triples:
    -
      -
        - VAR
        - me
      -
        - URI
        -
          - dao
          - consumed
      -
        - BLANK
        - a1
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - beer
          - Ale
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - beer
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- blank node; using qName _:abc
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  			_:abc foaf:name ?name .
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - BLANK
        - abc
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- select with ORDER BY
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  			?person a foaf:Person; foaf:name ?name
  		}
  ORDER BY ?name
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  options:
    orderby:
      -
        - ASC
        -
          - VAR
          - name
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- select with DISTINCT
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	DISTINCT ?name
  WHERE	{
  			?person a foaf:Person; foaf:name ?name
  		}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  options:
    distinct: 1
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- select with ORDER BY; asc()
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  			?person a foaf:Person; foaf:name ?name
  		}
  ORDER BY asc( ?name )
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  options:
    orderby:
      -
        - ASC
        -
          - VAR
          - name
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- select with ORDER BY; DESC()
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		SELECT	?name
  		WHERE	{
  					?person a foaf:Person; foaf:name ?name
  				}
  		ORDER BY DESC(?name)
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  options:
    orderby:
      -
        - DESC
        -
          - VAR
          - name
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- select with ORDER BY; DESC(); with LIMIT
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		SELECT	?name
  		WHERE	{
  					?person a foaf:Person; foaf:name ?name
  				}
  		ORDER BY DESC(?name) LIMIT 10
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  options:
    limit: 10
    orderby:
      -
        - DESC
        -
          - VAR
          - name
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- select with ORDER BY; DESC(); with LIMIT; variables with "$"
- |2
  		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  		PREFIX dc: <http://purl.org/dc/elements/1.1/>
  		 select $pic $thumb $date 
  		 WHERE { $pic foaf:thumbnail $thumb .
  		 $pic dc:date $date } order by desc($date) limit 10
- method: SELECT
  namespaces:
    dc: http://purl.org/dc/elements/1.1/
    foaf: http://xmlns.com/foaf/0.1/
  options:
    limit: 10
    orderby:
      -
        - DESC
        -
          - VAR
          - date
  sources: []
  triples:
    -
      -
        - VAR
        - pic
      -
        - URI
        -
          - foaf
          - thumbnail
      -
        - VAR
        - thumb
    -
      -
        - VAR
        - pic
      -
        - URI
        -
          - dc
          - date
      -
        - VAR
        - date
  variables:
    -
      - VAR
      - pic
    -
      - VAR
      - thumb
    -
      - VAR
      - date
---
- FILTER function call
- |2
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    mygeo: http://kasei.us/e/ns/geo#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - image
      -
        - VAR
        - pred
      -
        - VAR
        - point
    -
      - FILTER
      -
        - <
        -
          - FUNCTION
          -
            - URI
            -
              - mygeo
              - distance
          -
            - VAR
            - point
          -
            - LITERAL
            - 41.849331
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
          -
            - LITERAL
            - -71.392
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
        -
          - LITERAL
          - 10
          - ~
          -
            - URI
            - http://www.w3.org/2001/XMLSchema#integer
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - lat
---
- FILTER function call
- |2
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    mygeo: http://kasei.us/e/ns/geo#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - image
      -
        - VAR
        - pred
      -
        - VAR
        - point
    -
      - FILTER
      -
        - <
        -
          - FUNCTION
          -
            - URI
            -
              - mygeo
              - distance
          -
            - VAR
            - point
          -
            - LITERAL
            - 41.849331
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
          -
            - LITERAL
            - -71.392
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
        -
          - +
          -
            - LITERAL
            - 5
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#integer
          -
            - LITERAL
            - 5
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#integer
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - lat
---
- FILTER function call
- |2
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    mygeo: http://kasei.us/e/ns/geo#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - image
      -
        - VAR
        - pred
      -
        - VAR
        - point
    -
      - FILTER
      -
        - <
        -
          - FUNCTION
          -
            - URI
            -
              - mygeo
              - distance
          -
            - VAR
            - point
          -
            - LITERAL
            - 41.849331
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
          -
            - LITERAL
            - -71.392
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#decimal
        -
          - '*'
          -
            - LITERAL
            - 5
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#integer
          -
            - LITERAL
            - 5
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#integer
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - lat
---
- multiple FILTERs; with function call
- |2
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    mygeo: http://kasei.us/e/ns/geo#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - image
      -
        - URI
        -
          - dcterms
          - spatial
      -
        - VAR
        - point
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - FILTER
      -
        - '&&'
        -
          - <
          -
            - FUNCTION
            -
              - URI
              -
                - mygeo
                - distance
            -
              - VAR
              - point
            -
              - LITERAL
              - 41.849331
              - ~
              -
                - URI
                - http://www.w3.org/2001/XMLSchema#decimal
            -
              - LITERAL
              - -71.392
              - ~
              -
                - URI
                - http://www.w3.org/2001/XMLSchema#decimal
          -
            - LITERAL
            - 10
            - ~
            -
              - URI
              - http://www.w3.org/2001/XMLSchema#integer
        -
          - '~~'
          -
            - VAR
            - name
          -
            - LITERAL
            - 'Providence, RI'
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - name
---
- "optional triple '{...}'"
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		SELECT	?person ?name ?mbox
  		WHERE	{
  					?person foaf:name ?name .
  					OPTIONAL { ?person foaf:mbox ?mbox }
  				}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - OPTIONAL
      -
        -
          -
            - VAR
            - person
          -
            - URI
            -
              - foaf
              - mbox
          -
            - VAR
            - mbox
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - name
    -
      - VAR
      - mbox
---
- "optional triples '{...; ...}'"
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		SELECT	?person ?name ?mbox ?nick
  		WHERE	{
  					?person foaf:name ?name .
  					OPTIONAL {
  						?person foaf:mbox ?mbox; foaf:nick ?nick
  					}
  				}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - OPTIONAL
      -
        -
          -
            - VAR
            - person
          -
            - URI
            -
              - foaf
              - mbox
          -
            - VAR
            - mbox
        -
          -
            - VAR
            - person
          -
            - URI
            -
              - foaf
              - nick
          -
            - VAR
            - nick
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - name
    -
      - VAR
      - mbox
    -
      - VAR
      - nick
---
- union; sparql 6.2
- |2
  		PREFIX dc10:  <http://purl.org/dc/elements/1.1/>
  		PREFIX dc11:  <http://purl.org/dc/elements/1.0/>
  		SELECT	?title ?author
  		WHERE	{
  					{ ?book dc10:title ?title .  ?book dc10:creator ?author }
  					UNION
  					{ ?book dc11:title ?title .  ?book dc11:creator ?author }
  				}
- method: SELECT
  namespaces:
    dc10: http://purl.org/dc/elements/1.1/
    dc11: http://purl.org/dc/elements/1.0/
  sources: []
  triples:
    -
      - UNION
      -
        -
          -
            - VAR
            - book
          -
            - URI
            -
              - dc10
              - title
          -
            - VAR
            - title
        -
          -
            - VAR
            - book
          -
            - URI
            -
              - dc10
              - creator
          -
            - VAR
            - author
      -
        -
          -
            - VAR
            - book
          -
            - URI
            -
              - dc11
              - title
          -
            - VAR
            - title
        -
          -
            - VAR
            - book
          -
            - URI
            -
              - dc11
              - creator
          -
            - VAR
            - author
  variables:
    -
      - VAR
      - title
    -
      - VAR
      - author
---
- literal language tag @en
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		SELECT	?person ?homepage
  		WHERE	{
  					?person foaf:name "Gary Peck"@en ; foaf:homepage ?homepage .
  				}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gary Peck
        - en
        - ~
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - homepage
      -
        - VAR
        - homepage
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- typed literal ^^URI
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		SELECT	?image
  		WHERE	{
  					?image dc:date "2005-04-07T18:27:56-04:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>
  				}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - image
      -
        - URI
        -
          - dc
          - date
      -
        - LITERAL
        - 2005-04-07T18:27:56-04:00
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#dateTime
  variables:
    -
      - VAR
      - image
---
- typed literal ^^qName
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		PREFIX  xs: <http://www.w3.org/2001/XMLSchema#>
  		SELECT	?image
  		WHERE	{
  					?image dc:date "2005-04-07T18:27:56-04:00"^^xs:dateTime
  				}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
    xs: http://www.w3.org/2001/XMLSchema#
  sources: []
  triples:
    -
      -
        - VAR
        - image
      -
        - URI
        -
          - dc
          - date
      -
        - LITERAL
        - 2005-04-07T18:27:56-04:00
        - ~
        -
          - URI
          -
            - xs
            - dateTime
  variables:
    -
      - VAR
      - image
---
- subject collection syntax
- |2
  		SELECT	?x
  		WHERE	{ (1 ?x 3) }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a2
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - VAR
        - x
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a3
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 3
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
  variables:
    -
      - VAR
      - x
---
- subject collection syntax; with pred-obj.
- |2
  		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  		SELECT	?x
  		WHERE	{ (1 ?x 3) foaf:name "My Collection" }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a2
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - VAR
        - x
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a3
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 3
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - My Collection
  variables:
    -
      - VAR
      - x
---
- subject collection syntax; object collection syntax
- |2
  		PREFIX dc: <http://purl.org/dc/elements/1.1/>
  		SELECT	?x
  		WHERE	{ (1 ?x 3) dc:subject (1 2 3) }
- method: SELECT
  namespaces:
    dc: http://purl.org/dc/elements/1.1/
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a2
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - VAR
        - x
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a3
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 3
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
    -
      -
        - BLANK
        - a4
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a4
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a5
    -
      -
        - BLANK
        - a5
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 2
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a5
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a6
    -
      -
        - BLANK
        - a6
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 3
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a6
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - dc
          - subject
      -
        - BLANK
        - a4
  variables:
    -
      - VAR
      - x
---
- object collection syntax
- |2
  		PREFIX test: <http://kasei.us/e/ns/test#>
  		SELECT	?x
  		WHERE	{
  					<http://kasei.us/about/foaf.xrdf#greg> test:mycollection (1 ?x 3) .
  				}
- method: SELECT
  namespaces:
    test: http://kasei.us/e/ns/test#
  sources: []
  triples:
    -
      -
        - URI
        - http://kasei.us/about/foaf.xrdf#greg
      -
        - URI
        -
          - test
          - mycollection
      -
        - BLANK
        - a1
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a2
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - VAR
        - x
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a3
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 3
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a3
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
  variables:
    -
      - VAR
      - x
---
- SELECT *
- |2
  		SELECT *
  		WHERE { ?a ?a ?b . }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      -
        - VAR
        - a
      -
        - VAR
        - a
      -
        - VAR
        - b
  variables:
    - '*'
---
- default prefix
- |2
  		PREFIX	: <http://xmlns.com/foaf/0.1/>
  		SELECT	?person
  		WHERE	{
  					?person :name "Gregory Todd Williams", "Greg Williams" .
  				}
- method: SELECT
  namespaces:
    __DEFAULT__: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - __DEFAULT__
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - __DEFAULT__
          - name
      -
        - LITERAL
        - Greg Williams
  variables:
    -
      - VAR
      - person
---
- select from named; single triple; no prefix
- |2
  			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  			SELECT ?src ?name
  			FROM NAMED <file://data/named_graphs/alice.rdf>
  			FROM NAMED <file://data/named_graphs/bob.rdf>
  			WHERE {
  				GRAPH ?src { ?x foaf:name ?name }
  			}
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources:
    -
      - URI
      - file://data/named_graphs/alice.rdf
      - NAMED
    -
      - URI
      - file://data/named_graphs/bob.rdf
      - NAMED
  triples:
    -
      - GRAPH
      -
        - VAR
        - src
      -
        -
          -
            - VAR
            - x
          -
            - URI
            -
              - foaf
              - name
          -
            - VAR
            - name
  variables:
    -
      - VAR
      - src
    -
      - VAR
      - name
---
- ASK FILTER; using <= (shouldn't parse as '<')
- |2
  				PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
  				ASK {
  					FILTER ( "1995-11-05"^^xsd:dateTime <= "1994-11-05T13:15:30Z"^^xsd:dateTime ) .
  				}
- method: ASK
  namespaces:
    xsd: http://www.w3.org/2001/XMLSchema#
  sources: []
  triples:
    -
      - FILTER
      -
        - <=
        -
          - LITERAL
          - 1995-11-05
          - ~
          -
            - URI
            -
              - xsd
              - dateTime
        -
          - LITERAL
          - 1994-11-05T13:15:30Z
          - ~
          -
            - URI
            -
              - xsd
              - dateTime
  variables: []
---
- ORDER BY with expression
- |2
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
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
    xsd: http://www.w3.org/2001/XMLSchema#
  options:
    orderby:
      -
        - ASC
        -
          - FUNCTION
          -
            - URI
            -
              - xsd
              - decimal
          -
            - VAR
            - lat
  sources: []
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - image
      -
        - VAR
        - pred
      -
        - VAR
        - point
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - lat
---
- triple pattern with trailing internal '.'
- |
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
- method: SELECT
  namespaces:
    cyc: http://www.cyc.com/2004/06/04/cyc#
    dc: http://purl.org/dc/elements/1.1/
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  options:
    limit: 10
    orderby:
      -
        - DESC
        -
          - VAR
          - date
  sources: []
  triples:
    -
      -
        - VAR
        - region
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Maine
    -
      -
        - VAR
        - p
      -
        - URI
        -
          - cyc
          - inRegion
      -
        - VAR
        - region
    -
      -
        - VAR
        - p
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - place
    -
      -
        - VAR
        - img
      -
        - URI
        -
          - dcterms
          - spatial
      -
        - VAR
        - p
    -
      -
        - VAR
        - img
      -
        - URI
        -
          - dc
          - date
      -
        - VAR
        - date
    -
      -
        - VAR
        - img
      -
        - URI
        -
          - rdf
          - type
      -
        - URI
        -
          - foaf
          - Image
  variables:
    -
      - VAR
      - place
    -
      - VAR
      - img
    -
      - VAR
      - date
---
- "[bug] query with predicate starting with 'a' (confused with { ?subj a ?type})"
- |2
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
- method: SELECT
  namespaces:
    album: http://kasei.us/e/ns/album#
    cyc: http://www.cyc.com/2004/06/04/cyc#
    dc: http://purl.org/dc/elements/1.1/
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    p: http://www.usefulinc.com/picdiary/
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  options:
    orderby:
      -
        - DESC
        -
          - VAR
          - date
  sources: []
  triples:
    -
      -
        - URI
        - http://kasei.us/pictures/parties/19991205-Tims_Party/
      -
        - URI
        -
          - album
          - image
      -
        - VAR
        - img
    -
      -
        - VAR
        - img
      -
        - URI
        -
          - dc
          - date
      -
        - VAR
        - date
    -
      -
        - VAR
        - img
      -
        - URI
        -
          - rdf
          - type
      -
        - URI
        -
          - foaf
          - Image
  variables:
    -
      - VAR
      - img
    -
      - VAR
      - date
---
- dawg/simple/01
- |2
  		PREFIX : <http://example.org/data/>
  		
  		SELECT *
  		WHERE { :x ?p ?q . }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/data/
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - x
      -
        - VAR
        - p
      -
        - VAR
        - q
  variables:
    - '*'
---
- single triple with comment; dawg/data/part1
- |2
  		# Get name, and optionally the mbox, of each person
  		
  		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  		
  		SELECT ?name ?mbox
  		WHERE
  		  { ?person foaf:name ?name .
  			OPTIONAL { ?person foaf:mbox ?mbox}
  		  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      - OPTIONAL
      -
        -
          -
            - VAR
            - person
          -
            - URI
            -
              - foaf
              - mbox
          -
            - VAR
            - mbox
  variables:
    -
      - VAR
      - name
    -
      - VAR
      - mbox
---
- ask query
- |
  ASK {
    ?node rdf:type <http://kasei.us/e/ns/mt/blog> .
  }
- method: ASK
  namespaces: {}
  sources: []
  triples:
    -
      -
        - VAR
        - node
      -
        - URI
        -
          - rdf
          - type
      -
        - URI
        - http://kasei.us/e/ns/mt/blog
  variables: []
---
- blank-pred-blank
- |
  PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  SELECT ?name
  WHERE {
    [ foaf:name ?name ] foaf:maker []
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - foaf
          - maker
      -
        - BLANK
        - a2
  variables:
    -
      - VAR
      - name
---
- Filter with unary-plus
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?image ?point ?lat
  WHERE	{
  			?point geo:lat ?lat .
  			?image ?pred ?point .
  			FILTER( ?lat > +52 )
  }
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - image
      -
        - VAR
        - pred
      -
        - VAR
        - point
    -
      - FILTER
      -
        - '>'
        -
          - VAR
          - lat
        -
          - LITERAL
          - 52
          - ~
          -
            - URI
            - http://www.w3.org/2001/XMLSchema#integer
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - lat
---
- Filter with isIRI
- |
  PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	dcterms: <http://purl.org/dc/terms/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?image ?point ?lat
  WHERE	{
  			?point geo:lat ?lat .
  			?image ?pred ?point .
  			FILTER( isIRI(?image) )
  }
- method: SELECT
  namespaces:
    dcterms: http://purl.org/dc/terms/
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - image
      -
        - VAR
        - pred
      -
        - VAR
        - point
    -
      - FILTER
      -
        - FUNCTION
        -
          - URI
          - sop:isIRI
        -
          - VAR
          - image
  variables:
    -
      - VAR
      - image
    -
      - VAR
      - point
    -
      - VAR
      - lat
---
- 'xsd:double'
- |
  PREFIX dc:  <http://purl.org/dc/elements/1.1/>
  SELECT ?node
  WHERE {
    ?node dc:identifier 1e4 .
  }
- method: SELECT
  namespaces:
    dc: http://purl.org/dc/elements/1.1/
  sources: []
  triples:
    -
      -
        - VAR
        - node
      -
        - URI
        -
          - dc
          - identifier
      -
        - LITERAL
        - 1e4
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#double
  variables:
    -
      - VAR
      - node
---
- boolean literal
- |
  PREFIX dc:  <http://purl.org/dc/elements/1.1/>
  SELECT ?node
  WHERE {
    ?node dc:identifier true .
  }
- method: SELECT
  namespaces:
    dc: http://purl.org/dc/elements/1.1/
  sources: []
  triples:
    -
      -
        - VAR
        - node
      -
        - URI
        -
          - dc
          - identifier
      -
        - LITERAL
        - true
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#boolean
  variables:
    -
      - VAR
      - node
---
- select with ORDER BY function call
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  			?person a foaf:Person; foaf:name ?name
  		}
  ORDER BY :foo(?name)
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  options:
    orderby:
      -
        - ASC
        -
          - FUNCTION
          - 
            - URI
            -
              - __DEFAULT__
              - foo
          -
            - VAR
            - name
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- select with bnode object as second pred-obj
- |
  PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  SELECT ?name
  WHERE {
    ?r foaf:name ?name ; foaf:maker [ a foaf:Person ]
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - r
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      -
        - VAR
        - r
      -
        - URI
        -
          - foaf
          - maker
      -
        - BLANK
        - a1
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
  variables:
    -
      - VAR
      - name
---
- select with qname with '-2' suffix
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	wn: <http://xmlns.com/wordnet/1.6/>
  SELECT	?thing
  WHERE	{
  	?image a foaf:Image ;
  		foaf:depicts ?thing .
  	?thing a wn:Flower-2 .
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
    wn: http://xmlns.com/wordnet/1.6/
  sources: []
  triples:
    -
      -
        - VAR
        - image
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Image
    -
      -
        - VAR
        - image
      -
        - URI
        -
          - foaf
          - depicts
      -
        - VAR
        - thing
    -
      -
        - VAR
        - thing
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - wn
          - Flower-2
  variables:
    -
      - VAR
      - thing
---
- select with qname with underscore
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?name
  WHERE	{
  	?p a foaf:Person ;
  		foaf:mbox_sha1sum "2057969209f1dfdad832de387cf13e6ff8c93b12" ;
  		foaf:name ?name .
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - p
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - p
      -
        - URI
        -
          - foaf
          - mbox_sha1sum
      -
        - LITERAL
        - 2057969209f1dfdad832de387cf13e6ff8c93b12
    -
      -
        - VAR
        - p
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
  variables:
    -
      - VAR
      - name
---
- construct with one construct triple
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  CONSTRUCT { ?person foaf:name ?name }
  WHERE	{ ?person foaf:firstName ?name }
- method: CONSTRUCT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - firstName
      -
        - VAR
        - name
  construct_triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
---
- construct with two construct triples
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  CONSTRUCT { ?person foaf:name ?name . ?person a foaf:Person }
  WHERE	{ ?person foaf:firstName ?name }
- method: CONSTRUCT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - firstName
      -
        - VAR
        - name
  construct_triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
---
- construct with three construct triples
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  CONSTRUCT { ?person a foaf:Person  . ?person foaf:name ?name . ?person foaf:firstName ?name }
  WHERE	{ ?person foaf:firstName ?name }
- method: CONSTRUCT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - firstName
      -
        - VAR
        - name
  construct_triples:
    -
      -
        - VAR
        - person
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - foaf
          - Person
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - VAR
        - name
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - firstName
      -
        - VAR
        - name
---
- select with triple-optional-triple
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  SELECT	?person ?nick ?page
  WHERE	{
  	?person foaf:name "Gregory Todd Williams" .
  	OPTIONAL { ?person foaf:nick ?nick } .
  	?person foaf:homepage ?page
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
  sources: []
  triples:
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - name
      -
        - LITERAL
        - Gregory Todd Williams
    -
      - OPTIONAL
      -
        -
          -
            - VAR
            - person
          -
            - URI
            -
              - foaf
              - nick
          -
            - VAR
            - nick
    -
      -
        - VAR
        - person
      -
        - URI
        -
          - foaf
          - homepage
      -
        - VAR
        - page
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - nick
    -
      - VAR
      - page
---
- select with FROM
- |
  PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  SELECT	?lat ?long
  FROM	<http://homepage.mac.com/samofool/rdf-query/test-data/greenwich.rdf>
  WHERE	{
  	?point a geo:Point ;
  		geo:lat ?lat ;
  		geo:long ?long .
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
    geo: http://www.w3.org/2003/01/geo/wgs84_pos#
  sources:
    -
      - URI
      - http://homepage.mac.com/samofool/rdf-query/test-data/greenwich.rdf
  triples:
    -
      -
        - VAR
        - point
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - geo
          - Point
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - lat
      -
        - VAR
        - lat
    -
      -
        - VAR
        - point
      -
        - URI
        -
          - geo
          - long
      -
        - VAR
        - long
  variables:
    -
      - VAR
      - lat
    -
      - VAR
      - long
---
- select with graph-triple-triple
- |
  # select all the email addresses ever held by the person
  # who held a given email address on 2007-01-01
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX t: <http://www.w3.org/2006/09/time#>
  SELECT ?mbox WHERE {
  	GRAPH ?time { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
  	?time t:inside "2007-01-01" .
  	?p foaf:mbox ?mbox .
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
    t: http://www.w3.org/2006/09/time#
  sources: []
  triples:
    -
      - GRAPH
      -
        - VAR
        - time
      -
        -
          -
            - VAR
            - p
          -
            - URI
            -
              - foaf
              - mbox
          -
            - URI
            - mailto:gtw@cs.umd.edu
    -
      -
        - VAR
        - time
      -
        - URI
        -
          - t
          - inside
      -
        - LITERAL
        - 2007-01-01
    -
      -
        - VAR
        - p
      -
        - URI
        -
          - foaf
          - mbox
      -
        - VAR
        - mbox
  variables:
    -
      - VAR
      - mbox
---
- (DAWG) syn-leading-digits-in-prefixed-names.rq
- |
  PREFIX dob: <http://placetime.com/interval/gregorian/1977-01-18T04:00:00Z/P> 
  PREFIX t: <http://www.ai.sri.com/daml/ontologies/time/Time.daml#>
  PREFIX dc: <http://purl.org/dc/elements/1.1/>
  SELECT ?desc
  WHERE  { 
    dob:1D a t:ProperInterval;
           dc:description ?desc.
  }
- method: SELECT
  namespaces:
    dob: http://placetime.com/interval/gregorian/1977-01-18T04:00:00Z/P
    t: http://www.ai.sri.com/daml/ontologies/time/Time.daml#
    dc: http://purl.org/dc/elements/1.1/
  sources: []
  triples:
    -
      -
        - URI
        -
          - dob
          - 1D
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#type
      -
        - URI
        -
          - t
          - ProperInterval
    -
      -
        - URI
        -
          - dob
          - 1D
      -
        - URI
        -
          - dc
          - description
      -
        - VAR
        - desc
  variables:
    -
      - VAR
      - desc
---
- (DAWG) syn-07.rq
- |
  # Trailing ;
  PREFIX :   <http://example/ns#>
  SELECT * WHERE
  { :s :p :o ; FILTER(?x) }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example/ns#
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - s
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - URI
        -
          - __DEFAULT__
          - o
    -
      - FILTER
      -
        - VAR
        - x
  variables:
    - '*'
---
- (DAWG) syn-08.rq
- |
  # Broken ;
  PREFIX :   <http://example/ns#>
  SELECT * WHERE
  { :s :p :o ; . }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example/ns#
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - s
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - URI
        -
          - __DEFAULT__
          - o
  variables:
    - '*'
---
- (DAWG) syn-11.rq
- |
  PREFIX : <http://example.org/>
  SELECT *
  WHERE
  {
    _:a ?p ?v .  FILTER(true) . [] ?q _:a
  }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/
  sources: []
  triples:
    -
      -
        - BLANK
        - a
      -
        - VAR
        - p
      -
        - VAR
        - v
    -
      - FILTER
      -
        - LITERAL
        - true
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#boolean
    -
      -
        - BLANK
        - a1
      -
        - VAR
        - q
      -
        - BLANK
        - a
  variables:
    - '*'
---
- (DAWG) syntax-form-describe01.rq
- |
  DESCRIBE <u>
- method: DESCRIBE
  namespaces: {}
  sources: []
  triples: []
  variables:
    -
      - URI
      - u
---
- (DAWG) syntax-form-construct04.rq
- |
  PREFIX  rdf:    <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  CONSTRUCT { [] rdf:subject ?s ;
                 rdf:predicate ?p ;
                 rdf:object ?o . }
  WHERE {?s ?p ?o}
- method: CONSTRUCT
  namespaces:
    rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns#
  sources: []
  triples:
    -
      -
        - VAR
        - s
      -
        - VAR
        - p
      -
        - VAR
        - o
  construct_triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - rdf
          - subject
      -
        - VAR
        - s
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - rdf
          - predicate
      -
        - VAR
        - p
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - rdf
          - object
      -
        - VAR
        - o
---
- (DAWG) syntax-lists-02.rq
- |
  PREFIX : <http://example.org/ns#> 
  SELECT * WHERE { ?x :p ( ?z ) }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/ns#
  sources: []
  triples:
    -
      -
        - VAR
        - x
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - BLANK
        - a1
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - VAR
        - z
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
  variables:
    - '*'
---
- (DAWG) syntax-qname-03.rq
- |
  PREFIX : <http://example.org/ns#> 
  SELECT *
  WHERE { :_1 :p.rdf :z.z . }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/ns#
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - _1
      -
        - URI
        -
          - __DEFAULT__
          - p.rdf
      -
        - URI
        -
          - __DEFAULT__
          - z.z
  variables:
    - '*'
---
- (DAWG) syntax-qname-08.rq
- |
  BASE   <http://example.org/>
  PREFIX :  <#>
  PREFIX x.y:  <x#>
  SELECT *
  WHERE { :a.b  x.y:  : . }
- method: SELECT
  namespaces:
    __DEFAULT__: #
    x.y: x#
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - a.b
      -
        - URI
        -
          - x.y
          - ''
      -
        - URI
        -
          - __DEFAULT__
          - ''
  base:
    - URI
    - http://example.org/
  variables:
    - '*'
---
- (DAWG) syntax-lit-07.rq
- |
  BASE   <http://example.org/>
  PREFIX :  <#> 
  SELECT * WHERE { :x :p 123 }
- method: SELECT
  namespaces:
    __DEFAULT__: #
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - x
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - 123
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
  base:
    - URI
    - http://example.org/
  variables:
    - '*'
---
- (DAWG) syntax-lit-08.rq
- |
  BASE   <http://example.org/>
  PREFIX :  <#> 
  SELECT * WHERE { :x :p 123. . }
- method: SELECT
  namespaces:
    __DEFAULT__: #
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - x
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - 123.
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#decimal
  base:
    - URI
    - http://example.org/
  variables:
    - '*'
---
- (DAWG) syntax-lit-12.rq
- |
  BASE   <http://example.org/>
  PREFIX :  <#> 
  SELECT * WHERE { :x :p '''Long''\'Literal''' }
- method: SELECT
  namespaces:
    __DEFAULT__: #
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - x
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - Long'''Literal
  base:
    - URI
    - http://example.org/
  variables:
    - '*'
---
- (DAWG) syntax-lit-13.rq
- |
  BASE   <http://example.org/>
  PREFIX :  <#> 
  SELECT * WHERE { :x :p """Long\"""Literal""" }
- method: SELECT
  namespaces:
    __DEFAULT__: #
  sources: []
  triples:
    -
      -
        - URI
        -
          - __DEFAULT__
          - x
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - Long"""Literal
  base:
    - URI
    - http://example.org/
  variables:
    - '*'
---
- (DAWG) syntax-general-07.rq
- |
  SELECT * WHERE { <a><b>+1.0 }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      -
        - URI
        - a
      -
        - URI
        - b
      -
        - LITERAL
        - 1.0
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#decimal
  variables:
    - '*'
---
- (DAWG) syntax-general-09.rq
- |
  SELECT * WHERE { <a><b>1.0e0 }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      -
        - URI
        - a
      -
        - URI
        - b
      -
        - LITERAL
        - 1.0e0
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#double
  variables:
    - '*'
---
- (DAWG) syntax-general-10.rq
- |
  SELECT * WHERE { <a><b>+1.0e+1 }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      -
        - URI
        - a
      -
        - URI
        - b
      -
        - LITERAL
        - 1.0e+1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#double
  variables:
    - '*'
---
- (DAWG) syntax-lists-03.rq
- |
  PREFIX : <http://example.org/>
  SELECT * WHERE { ( 
  ) :p 1 }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/
  sources: []
  triples:
    -
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
  variables:
    - '*'
---
- (DAWG) syntax-lists-04.rq
- |
  PREFIX : <http://example.org/>
  SELECT * WHERE { ( 1 2
  ) :p 1 }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a2
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 2
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
  variables:
    - '*'
---
- (DAWG) syntax-lists-02.rq
- |
  PREFIX : <http://example.org/>
  SELECT * WHERE { ( ) :p 1 }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/
  sources: []
  triples:
    -
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
  variables:
    - '*'
---
- (DAWG) syntax-lists-04.rq
- |
  PREFIX : <http://example.org/>
  SELECT * WHERE { ( 1 2
  ) :p 1 }
- method: SELECT
  namespaces:
    __DEFAULT__: http://example.org/
  sources: []
  triples:
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a1
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - BLANK
        - a2
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#first
      -
        - LITERAL
        - 2
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
    -
      -
        - BLANK
        - a2
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#rest
      -
        - URI
        - http://www.w3.org/1999/02/22-rdf-syntax-ns#nil
    -
      -
        - BLANK
        - a1
      -
        - URI
        -
          - __DEFAULT__
          - p
      -
        - LITERAL
        - 1
        - ~
        -
          - URI
          - http://www.w3.org/2001/XMLSchema#integer
  variables:
    - '*'
---
- temporal query with time variable
- |
  # select the person who held a given email address on 2007-01-01
  SELECT ?t ?p WHERE {
      TIME ?t { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
  }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      - TIME
      -
        - VAR
        - t
      -
        -
          -
            - VAR
            - p
          -
            - URI
            -
              - foaf
              - mbox
          -
            - URI
            - mailto:gtw@cs.umd.edu
  variables:
    -
      - VAR
      - t
    -
      - VAR
      - p
---
- temporal query with empty time bNode
- |
  # select the person who held a given email address on 2007-01-01
  SELECT ?p WHERE {
      TIME [] { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
  }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      - TIME
      -
        - BLANK
        - a1
      -
        -
          -
            - VAR
            - p
          -
            - URI
            -
              - foaf
              - mbox
          -
            - URI
            - mailto:gtw@cs.umd.edu
  variables:
    -
      - VAR
      - p
---
- temporal query with time bNode
- |
  # select the person who held a given email address on 2007-01-01
  SELECT ?p WHERE {
      TIME [ :inside "2007-01-01" ] { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
  }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      - TIME
      -
        - VAR
        - _____rdfquery_private_0
      -
        -
          -
            - VAR
            - p
          -
            - URI
            -
              - foaf
              - mbox
          -
            - URI
            - mailto:gtw@cs.umd.edu
    -
      -
        - VAR
        - _____rdfquery_private_0
      -
        - URI
        -
          - __DEFAULT__
          - inside
      -
        - LITERAL
        - 2007-01-01
  variables:
    -
      - VAR
      - p
---
- temporal query with time bNode and extra triple
- |
  # select all the email addresses ever held by the person
  # who held a given email address on 2007-01-01
  SELECT ?mbox WHERE {
      TIME [ :inside "2007-01-01" ] { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
      ?p foaf:mbox ?mbox
  }
- method: SELECT
  namespaces: {}
  sources: []
  triples:
    -
      - TIME
      -
        - VAR
        - _____rdfquery_private_1
      -
        -
          -
            - VAR
            - p
          -
            - URI
            -
              - foaf
              - mbox
          -
            - URI
            - mailto:gtw@cs.umd.edu
    -
      -
        - VAR
        - _____rdfquery_private_1
      -
        - URI
        -
          - __DEFAULT__
          - inside
      -
        - LITERAL
        - 2007-01-01
    -
      -
        - VAR
        - p
      -
        - URI
        -
          - foaf
          - mbox
      -
        - VAR
        - mbox
  variables:
    -
      - VAR
      - mbox
---
- select with TIME
- |
  PREFIX t: <http://www.w3.org/2006/09/time#>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  SELECT ?name WHERE {
  	TIME [ t:begins "2000-01-01" ] { ?p foaf:name ?name . }
  }
- method: SELECT
  namespaces:
    foaf: http://xmlns.com/foaf/0.1/
    t: http://www.w3.org/2006/09/time#
  sources: []
  triples:
    -
      - TIME
      -
        - VAR
        - _____rdfquery_private_2
      -
        -
          -
            - VAR
            - p
          -
            - URI
            -
              - foaf
              - name
          -
            - VAR
            - name
    -
      -
        - VAR
        - _____rdfquery_private_2
      -
        - URI
        -
          - t
          - begins
      -
        - LITERAL
        - 2000-01-01
  variables:
    -
      - VAR
      - name
