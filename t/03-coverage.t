#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 81;

use_ok( 'RDF::Query' );

my @files	= map { File::Spec->rel2abs( "data/$_" ) } qw(about.xrdf foaf.xrdf);
my @models;

{
	my @data	= map { RDF::Redland::URI->new( 'file://' . $_ ) } @files;
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	my $parser	= new RDF::Redland::Parser("rdfxml");
	$parser->parse_into_model($_, $_, $model) for (@data);
	my $bridge	= RDF::Query::Model::Redland->new( $model );
	isa_ok( $bridge->model, 'RDF::Redland::Model' );
	push(@models, $model);
} {
	my $storage	= new RDF::Core::Storage::Memory;
	my $model	= new RDF::Core::Model (Storage => $storage);
	foreach my $file (@files) {
		my $parser	= new RDF::Core::Model::Parser (
						Model		=> $model,
						Source		=> $file,
						SourceType	=> 'file',
						BaseURI		=> 'http://example.com/'
					);
		$parser->parse;
	}
	my $bridge	= RDF::Query::Model::RDFCore->new( $model );
	isa_ok( $bridge->model, 'RDF::Core::Model' );
	push(@models, $model);
}	

foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n";
	
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
		is( scalar(@results), 1, 'one result' );
	}

	{
		print "# using SPARQL language URI\n";
		my $query	= new RDF::Query ( <<"END", undef, 'http://www.w3.org/TR/rdf-sparql-query/', undef );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			SELECT	?person
			WHERE	{ ?person foaf:name "Gregory Todd Williams" }
END
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, 'one result' );
	}

	{
		print "# SPARQL query\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			SELECT	?person ?homepage
			WHERE	{
						?person foaf:name "Gregory Todd Williams" .
						?person foaf:homepage ?homepage
					}
			AND		?homepage ~~ /kasei/
END
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'results' );
		my $row		= $results[0];
		my ($p,$h)	= @{ $row };
		ok( $query->bridge->isa_node( $p ), 'isa_node' );
		ok( $query->bridge->isa_resource( $h ), 'isa_resource(resource)' );
		is( $h->getLabel, 'http://kasei.us/', 'http://kasei.us/' );
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
		is( $name->getLabel, 'Cliffs of Moher, Ireland', 'Cliffs of Moher, Ireland' );
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
		is( $person->getLabel, 'http://kasei.us/about/foaf.xrdf#greg', 'Person uri' );
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
		is( $name->getLabel, 'Gregory Todd Williams', 'Person name' );
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
		is( $results[0][0]->getLabel, 'http://kasei.us/about/foaf.xrdf#greg', 'Person uri' );
		is( $results[0][1]->getLabel, 'Gregory Todd Williams', 'Person name' );
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
		is( $results[0][0]->getLabel, 'http://kasei.us/about/foaf.xrdf#greg', 'Person uri' );
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
		is( scalar(@results), 6, 'one triple, two variables (query call)' );
	
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
		my @results	= $query->execute( $model );
		is( $results[0], undef, 'Error (undef row) on no triples (query call)' );
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
		my $query	= new RDF::Query ();
		print "# AUTOLOAD tests\n";
		eval { $query->unimplemented; };
		like( $@, qr/Can't locate object method "unimplemented" via package/, 'AUTOLOAD avoiding bogus instance data' );
		is( RDF::Query->unimplemented, undef, 'AUTOLOAD avoiding class method calls' );
	}
	
	{
		print "# SPARQL getting foaf:aimChatID by foaf:nick\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
			SELECT ?aim WHERE { ?p foaf:nick "kasei"; foaf:aimChatID ?aim }
END
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, '1 result' );
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
		my $stream	= $query->get( $model );
		is( $stream, undef );
	}
}
