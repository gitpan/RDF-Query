#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;

use lib qw(. t);
BEGIN { require "models.pl"; }

my @files	= map { File::Spec->rel2abs( "data/$_" ) } qw(about.xrdf foaf.xrdf);
my @models	= test_models( @files );

use Test::More;
plan tests => 1 + (55 * scalar(@models));

use_ok( 'RDF::Query' );
foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n";
	
	{
		print "# bridge object accessors\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://jena.hpl.hp.com/2003/07/query/RDQL', undef );
			SELECT ?person
			WHERE (?person foaf:name "Gregory Todd Williams")
			USING foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my $stream	= $query->execute( $model );
		is( $model, $query->bridge->model, 'model accessor' );
	}

	{
		print "# using RDQL language URI\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://jena.hpl.hp.com/2003/07/query/RDQL', undef );
			SELECT
				?person
			WHERE
				(?person foaf:name "Gregory Todd Williams")
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
	}

	{
		print "# using SPARQL language URI\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			SELECT	?person
			WHERE	{ ?person foaf:name "Gregory Todd Williams" }
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
	}

	{
		print "# SPARQL query\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			SELECT	?person ?homepage
			WHERE	{
						?person foaf:name "Gregory Todd Williams" .
						?person foaf:homepage ?homepage .
						FILTER REGEX(?homepage, "kasei")
					}
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'results' );
		my $row		= $results[0];
		my ($p,$h)	= @{ $row };
		ok( $query->bridge->isa_node( $p ), 'isa_node' );
		ok( $query->bridge->isa_resource( $h ), 'isa_resource(resource)' );
		is( $query->bridge->uri_value( $h ), 'http://kasei.us/', 'http://kasei.us/' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT	?name
			WHERE	{
						[ a geo:Point; geo:lat "52.972770"; foaf:name ?name ]
					}
END
		my ($name)	= $query->get( $model );
		ok( $name, 'got name' );
		is( $query->bridge->literal_value( $name ), 'Cliffs of Moher, Ireland', 'Cliffs of Moher, Ireland' );
	}
	
	{
		print "# RDQL query\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:name "Gregory Todd Williams")
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my ($person)	= $query->get( $model );
		ok( $query->bridge->isa_resource( $person ), 'Resource' );
		is( $query->bridge->uri_value( $person ), 'http://kasei.us/about/foaf.xrdf#greg', 'Person uri' );
	}
	
	{
		print "# Triple with QName subject\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?name
			WHERE
				(kasei:greg foaf:name ?name)
			USING
				kasei FOR <http://kasei.us/about/foaf.xrdf#>
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my ($name)	= $query->get( $model );
		ok( $query->bridge->isa_literal( $name ), 'Literal' );
		is( $query->bridge->literal_value( $name ), 'Gregory Todd Williams', 'Person name' );
	}
	
	{
		print "# Early triple with multiple unbound variables\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person ?name
			WHERE
				(?person foaf:name ?name)
				(?person foaf:homepage <http://kasei.us/>)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my @results	= $query->execute( $model );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Person Resource' );
		ok( $query->bridge->isa_literal( $results[0][1] ), 'Name Resource' );
		is( $query->bridge->uri_value( $results[0][0] ), 'http://kasei.us/about/foaf.xrdf#greg', 'Person uri' );
		is( $query->bridge->literal_value( $results[0][1] ), 'Gregory Todd Williams', 'Person name' );
		is( $query->bridge->literal_value($results[0][1]), 'Gregory Todd Williams', 'Person name #2' );
		is( $query->bridge->as_string($results[0][1]), 'Gregory Todd Williams', 'Person name #3' );
	}
	
	{
		print "# Triple with no variable, present in data\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:name "Gregory Todd Williams")
				(<http://kasei.us/about/foaf.xrdf#greg> foaf:homepage <http://kasei.us/>)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my @results	= $query->execute( $model );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Person Resource' );
		is( $query->bridge->uri_value( $results[0][0] ), 'http://kasei.us/about/foaf.xrdf#greg', 'Person uri' );
	}
	
	{
		print "# Triple with no variable, not present in data\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:name "Gregory Todd Williams")
				(<http://localhost/greg> foaf:homepage <http://kasei.us/>)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my @results	= $query->execute( $model );
		is( scalar(@results), 0, 'No data returned for bogus triple' );
	}
	
	{
		print "# Query with one triple, two variables\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:name ?name)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'one triple, two variables (query call)' );
	
		my ($person)	= $query->get( $model );
		ok( $query->bridge->isa_node($person), 'one triple, two variables (get call)' );
	}
	
	{
		print "# Broken query triple (variable with missing '?')\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(person foaf:name "Gregory Todd Williams")
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		is( $query, undef, 'Error (undef row) on no triples (query call)' );
	}
	
	{
		print "# Backend tests\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?name ?homepage
			WHERE
				(kasei:greg foaf:name ?name)
				(kasei:greg foaf:homepage ?homepage)
			USING
				kasei FOR <http://kasei.us/about/foaf.xrdf#>
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
	
		my ($name,$homepage)	= $query->get( $model );
		ok( !$query->bridge->isa_resource( 0 ), 'isa_resource(0)' );
		ok( !$query->bridge->isa_resource( $name ), 'isa_resource(literal)' );
		ok( $query->bridge->isa_resource( $homepage ), 'isa_resource(resource)' );
	
		ok( !$query->bridge->isa_literal( 0 ), 'isa_literal(0)' );
		ok( !$query->bridge->isa_literal( $homepage ), 'isa_literal(resource)' );
		ok( $query->bridge->isa_literal( $name ), 'isa_literal(literal)' );
	}
	
	{
		print "# SPARQL getting foaf:aimChatID by foaf:nick\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
			SELECT ?aim WHERE { ?p foaf:nick "kasei"; foaf:aimChatID ?aim }
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
		my $row		= $results[0];
		my ($aim)	= @{ $row };
		ok( $query->bridge->isa_literal( $aim ), 'isa_literal' );
		is( $query->bridge->as_string($aim), 'samofool', 'got string' );
	}
	
	{
		print "# SPARQL getting foaf:aimChatID by foaf:nick on non-existant person\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
			SELECT ?aim WHERE { ?p foaf:nick "libby"; foaf:aimChatID ?aim }
END
		my @results	= $query->execute( $model );
		is( scalar(@results), 0, '0 results' );
	}
	
	{
		print "# SPARQL getting blank nodes (geo:Points) and sorting by genid\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT ?p
			WHERE { ?p a geo:Point }
			ORDER BY ?p
			LIMIT 2
END
		my $stream	= $query->execute( $model );
		my $count;
		while (my $row = $stream->()) {
			my ($p)	= @{ $row };
			ok( $p, $query->bridge->as_string( $p ) );
		} continue { ++$count };
	}

	{
		print "# broken query with get call\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			break me
END
		is( $query, undef );
	}

	{
		print "# SPARQL query with missing (optional) WHERE\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			SELECT	?person { ?person foaf:name "Gregory Todd Williams" }
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
	}

	{
		print "# SPARQL query with SELECT *\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
		SELECT *
		WHERE { ?a ?a ?b . }
END
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, 'got one result' );
		my $result	= $results[0];
		is( $query->bridge->uri_value( $result->[0] ), 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' );
		is( $query->bridge->uri_value( $result->[1] ), 'http://www.w3.org/1999/02/22-rdf-syntax-ns#Property' );
		
	}
	
	{
		print "# SPARQL query with default namespace\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
			PREFIX	: <http://xmlns.com/foaf/0.1/>
			SELECT	?person
			WHERE	{ ?person :name "Gregory Todd Williams" }
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
	}

	{
		print "# SPARQL query; blank node results\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	wn: <http://xmlns.com/wordnet/1.6/>
			SELECT	?thing
			WHERE	{
				?image a foaf:Image ;
					foaf:depicts ?thing .
				?thing a wn:Flower-2 .
			}
END
		my $stream	= $query->execute( $model );
		my $count	= 0;
		while (my $row = $stream->()) {
			my $thing	= $row->[0];
			ok( $query->bridge->isa_blank( $thing ) );
			
			my $id		= $query->bridge->blank_identifier( $thing );
			ok( length($id), 'blank identifier' );
			$count++;
		}
		is( $count, 3, '3 result' );
	}

	{
		print "# SPARQL query; language-typed literal\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			SELECT	?name
			WHERE	{
				?p a foaf:Person ;
					foaf:mbox_sha1sum "2057969209f1dfdad832de387cf13e6ff8c93b12" ;
					foaf:name ?name .
			}
END
		my ($name)	= $query->get( $model );
		my $bridge	= $query->bridge;
		my $lang	= $bridge->literal_value_language( $name );
		is ($lang, 'en', 'language');
	}

	{
		print "# SPARQL query; Stream accessors\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
			PREFIX	: <http://xmlns.com/foaf/0.1/>
			SELECT	?person
			WHERE	{ ?person :name "Gregory Todd Williams" }
END
		my $stream	= $query->execute( $model );
		my $value	= $stream->binding_value_by_name('person');
		is( $value, $stream->binding_value( 0 ), 'binding_value' );
		ok( $query->bridge->isa_node( $value ), 'binding_value_by_name' );
		is_deeply( ['person'], [$stream->binding_names], 'binding_names' );
		my @values	= $stream->binding_values;
		ok( $query->bridge->isa_node( $values[0] ), 'binding_value_by_name' );
		
	}

}

