#!/usr/bin/perl
use strict;
use warnings;
no warnings 'redefine';

use lib qw(. t);
BEGIN { require "models.pl"; }

use Test::Exception;
use Test::More tests => 24;

use_ok( 'RDF::Query' );

################################################################################
### AS_SPARQL TESTS
{
	my $rdql	= qq{SELECT ?person WHERE (?person foaf:name "Gregory Todd Williams") USING foaf FOR <http://xmlns.com/foaf/0.1/>};
	my $query	= new RDF::Query ( $rdql, undef, undef, 'rdql' );
	my $string	= $query->as_sparql;
	$string		=~ s/\s+/ /gms;
	is( $string, 'PREFIX foaf: <http://xmlns.com/foaf/0.1/> PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> SELECT * WHERE { ?person foaf:name "Gregory Todd Williams" . }', 'rdql to sparql' );
}

{
	my $sparql	= "PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { ?person a foaf:Person; foaf:name ?name } ORDER BY ?name";
	my $query	= new RDF::Query ( $sparql );
	my $string	= $query->as_sparql;
	$string		=~ s/\s+/ /gms;
	is( $string, "PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { ?person a foaf:Person . ?person foaf:name ?name . } ORDER BY ?name", 'sparql to sparql' );
}

{
	my $sparql	= 'PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?p WHERE { ?p a foaf:Person ; foaf:homepage ?homepage . FILTER( REGEX( STR(?homepage), "^http://www.rpi.edu/.+") ) }';
	my $query	= new RDF::Query ( $sparql );
	my $string	= $query->as_sparql;
	$string		=~ s/\s+/ /gms;
	is( $string, 'PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?p WHERE { ?p a foaf:Person . ?p foaf:homepage ?homepage . FILTER REGEX( STR( ?homepage ), "^http://www.rpi.edu/.+" ) . }', 'sparql to sparql with regex filter' );
};

{
	my $sparql	= "PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { ?person a foaf:Person; foaf:name ?name . FILTER( ?name < 'Greg' ) }";
	my $query	= new RDF::Query ( $sparql );
	my $string	= $query->as_sparql;
	$string		=~ s/\s+/ /gms;
	is( $string, 'PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { ?person a foaf:Person . ?person foaf:name ?name . FILTER (?name < "Greg") . }', 'sparql to sparql with less-than filter' );
}

{
	my $sparql	= "PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { ?person a foaf:Person; foaf:name ?name } ORDER BY ?name LIMIT 5 OFFSET 5";
	my $query	= new RDF::Query ( $sparql );
	my $string	= $query->as_sparql;
	$string		=~ s/\s+/ /gms;
	is( $string, "PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { ?person a foaf:Person . ?person foaf:name ?name . } ORDER BY ?name OFFSET 5 LIMIT 5", 'sparql to sparql with slice' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT ?person
		WHERE (?person foaf:name "Gregory Todd Williams")
		USING foaf FOR <http://xmlns.com/foaf/0.1/>
END
	my $sparql	= $query->as_sparql;
	my $again	= RDF::Query->new( $sparql )->as_sparql;
	is( $sparql, $again, 'as_sparql: rdql round trip: select' );
}

{
	my $rquery	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT ?person
		WHERE (?person foaf:name "Gregory Todd Williams")
		USING foaf FOR <http://xmlns.com/foaf/0.1/>
END
	my $squery	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		SELECT ?person
		WHERE { ?person foaf:name "Gregory Todd Williams" }
END
	is( $squery->as_sparql, $rquery->as_sparql, 'as_sparql: rdql-sparql equality' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		CONSTRUCT { ?p foaf:name ?name }
		WHERE  { ?p foaf:firstname ?name }
END
	my $sparql	= $query->as_sparql;
	my $again	= RDF::Query->new( $sparql )->as_sparql;
	is( $sparql, $again, 'as_sparql: sparql round trip: construct' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		DESCRIBE ?p
		WHERE  { ?p foaf:name ?name }
END
	my $sparql	= $query->as_sparql;
	my $again	= RDF::Query->new( $sparql )->as_sparql;
	is( $sparql, $again, 'as_sparql: sparql round trip: describe' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		ASK
		WHERE  { [ foaf:name "Gregory Todd Williams" ] }
END
	my $sparql	= $query->as_sparql;
	my $again	= RDF::Query->new( $sparql )->as_sparql;
	is( $sparql, $again, 'as_sparql: sparql round trip: ask' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?name
		FROM NAMED <http://example.com/>
		WHERE  {
			GRAPH ?g {
				[ foaf:name "Gregory Todd Williams" ]
			}
		}
END
	my $sparql	= $query->as_sparql;
	my $again	= RDF::Query->new( $sparql )->as_sparql;
	is( $sparql, $again, 'as_sparql: sparql round trip: select with named graph' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparqlp' );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT *
		WHERE {
			{ ?person foaf:name ?name } UNION { ?person foaf:nick ?name }
		}
END
	my $sparql	= $query->as_sparql;
	my $again	= RDF::Query->new( $sparql )->as_sparql;
	is( $sparql, $again, 'as_sparql: union' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?person
		WHERE {
			?person foaf:name ?name .
			FILTER( !BOUND(?name) )
		}
END
	my $sparql	= $query->as_sparql;
	my $again	= RDF::Query->new( $sparql )->as_sparql;
	is( $sparql, $again, 'as_sparql: select with filter !BOUND' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT DISTINCT ?name
		WHERE {
			?person foaf:name ?name .
		}
END
	my $sparql	= $query->as_sparql;
	my $qagain	= RDF::Query->new( $sparql );
	my $again	= $qagain->as_sparql;
	is( $sparql, $again, 'as_sparql: select DISTINCT' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparqlp' );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT COUNT(?person)
		WHERE {
			?person foaf:name ?name .
		}
END
	throws_ok {
		$query->as_sparql;
	} 'RDF::Query::Error::SerializationError';
}

################################################################################
### SSE TESTS

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?person
		WHERE { ?person foaf:name "Gregory Todd Williams" }
END
	my $sse	= $query->sse;
	is( $sse, '(join (bgp (triple ?person foaf:name "Gregory Todd Williams")))', 'sse: select' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?name
		FROM NAMED <http://example.com/>
		WHERE  {
			GRAPH ?g {
				[ foaf:name "Gregory Todd Williams" ]
			}
		}
END
	my $sse	= $query->sse;
	is( $sse, '(join (namedgraph ?g (join (bgp (quad _:a1 foaf:name "Gregory Todd Williams" ?g)))))', 'sse: select with named graph' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX dc: <http://purl.org/dc/elements/1.1/>
		SELECT ?name
		WHERE  {
			{ [ foaf:name ?name ] }
			UNION
			{ [ dc:title ?name ] }
		}
END
	my $sse	= $query->sse;
	is( $sse, '(join (union (join (bgp (triple _:a1 foaf:name ?name))) (join (bgp (triple _:a2 dc:title ?name)))))', 'sse: select with union' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?person
		WHERE {
			?person foaf:name ?name .
			FILTER( ?name < "Greg" )
		}
END
	my $sse		= $query->sse;
	is( $sse, '(filter (< ?name "Greg") (join (bgp (triple ?person foaf:name ?name))))', 'sse: select with filter <' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?person
		WHERE {
			?person foaf:name ?name .
			FILTER( !BOUND(?name) )
		}
END
	my $sse		= $query->sse;
	is( $sse, '(filter (! (function <sparql:bound> ?name)) (join (bgp (triple ?person foaf:name ?name))))', 'sse: select with filter !BOUND' );
}

{
	my $query	= new RDF::Query ( <<"END" );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?person
		WHERE {
			?person foaf:name ?name .
			FILTER( REGEX(?name, "Greg") )
		}
END
	my $sse		= $query->sse;
	is( $sse, '(filter (sparql:regex ?name "Greg") (join (bgp (triple ?person foaf:name ?name))))', 'sse: select with filter regex' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparqlp' );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT *
		WHERE {
			{ ?person foaf:name ?name } UNION { ?person foaf:nick ?name }
		}
END
	my $sse		= $query->sse;
	is( $sse, '(join (union (join (bgp (triple ?person foaf:name ?name))) (join (bgp (triple ?person foaf:nick ?name)))))', 'sse: select with filter regex' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparqlp' );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT COUNT(?person)
		WHERE {
			?person foaf:name ?name .
		}
END
	my $sse		= $query->sse;
	is( $sse, '(join (aggregate (join (bgp (triple ?person foaf:name ?name))) (alias "COUNT(?person)" (COUNT ?person)) ))', 'sse: aggregate count(?person)' );
}


__END__
