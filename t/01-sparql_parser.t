#!/usr/bin/perl
use strict;
use warnings;

use Test::More tests => 91;

use YAML;
use Data::Dumper;
use Scalar::Util qw(reftype);


use_ok( 'RDF::Query::Parser::SPARQL' );
my $parser	= new RDF::Query::Parser::SPARQL (undef);
isa_ok( $parser, 'RDF::Query::Parser::SPARQL' );



my (@data)	= YAML::Load(do { local($/) = undef; <DATA> });
foreach (@data) {
	next unless (reftype($_) eq 'ARRAY');
	my ($name, $sparql, $correct)	= @$_;
	my $parsed	= $parser->parse( $sparql );
	my $r	= is_deeply( $parsed, $correct, $name );
	unless ($r) {
		warn $parser->error;
		die Dumper($parsed);
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

{
	my $sparql	= <<"END";
		FOO	?name
		WHERE	{
					?person a foaf:Person; foaf:name ?name
				}
		ORDER BY
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'bad query type expression' );
	like( $parser->error, qr/Expecting query type/, 'parse error' );
}

{
	my $sparql	= <<"END";
		SELECT	?name
		WHERE	{
					]
				}
		ORDER BY
END
	my $parsed	= $parser->parse( $sparql );
	is( $parsed, undef, 'bad triple pattern' );
	like( $parser->error, qr/Expecting "}"/, 'parse error' );
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
  			FILTER( isBLANK([  ]) ) .
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
        - FUNCTION
        -
          - URI
          - sop:isBlank
        -
          - BLANK
          - a1
  variables:
    -
      - VAR
      - person
    -
      - VAR
      - homepage
---
- filter with variable/blank-node equality
- |
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
          - person
        -
          - BLANK
          - foo
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
- single triple; no prefix
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
