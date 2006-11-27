#!/usr/bin/perl
use strict;
use warnings;
use URI::file;

use lib qw(. t);
BEGIN { require "models.pl"; }

my @files	= map { "data/$_" } qw(foaf.xrdf);
my @models	= test_models( @files );

use Test::More;
plan tests => 1 + (32 * scalar(@models));

use_ok( 'RDF::Query' );
foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n\n";
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:name "Gregory Todd Williams")
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# (?var qname literal)\n";
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
		is( $query->bridge->uri_value( $results[0][0] ), 'http://kasei.us/about/foaf.xrdf#greg', 'got person uri' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:homepage <http://kasei.us/>)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# (?var qname quri)\n";
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
		is( $query->bridge->uri_value( $results[0][0] ), 'http://kasei.us/about/foaf.xrdf#greg', 'got person uri' );
	}
	
	{
		print "# multiple namespaces\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX dc: <http://purl.org/dc/elements/1.1/>
			SELECT
				?title
			WHERE {
				?desc rdf:type foaf:PersonalProfileDocument .
				?desc foaf:maker ?person .
				?person foaf:name "Gregory Todd Williams" .
				?desc dc:title ?title .
			}
END
		isa_ok( $query, 'RDF::Query' );
		
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( ref($results[0]) && $query->bridge->isa_literal( $results[0][0] ), 'Literal' );
		is( ref($results[0]) && $query->bridge->literal_value( $results[0][0] ), 'FOAF Description for Gregory Williams', 'got file title' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?page
			WHERE
				(?person foaf:name "Gregory Todd Williams")
				(?person foaf:homepage ?page)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# chained (name->person->homepage)\n";
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
		is( $query->bridge->uri_value( $results[0][0] ), 'http://kasei.us/', 'got homepage url' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?name ?mbox
			WHERE
				(?person foaf:homepage <http://kasei.us/>)
				(?person foaf:name ?name)
				(?person foaf:mbox ?mbox)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# chained (homepage->person->(name|mbox)\n";
		my @results	= $query->execute( $model );
		ok( scalar(@results), 'got result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 2, 'got two fields' );
		ok( $query->bridge->isa_literal( $results[0][0] ), 'Literal' );
		ok( $query->bridge->isa_resource( $results[0][1] ), 'Resource' );
		is( $query->bridge->literal_value( $results[0][0] ), 'Gregory Todd Williams', 'got name' );
		is( $query->bridge->uri_value( $results[0][1] ), 'mailto:greg@evilfunhouse.com', 'got mbox uri' );
	}
}
