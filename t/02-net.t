#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 7;
use RDF::Redland;

use_ok( 'RDF::Query' );

my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
my $model	= new RDF::Redland::Model($storage, "");

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT
			?page
		FROM
			<http://kasei.us/about/foaf.xrdf>
		WHERE
			(?person foaf:name "Gregory Todd Williams")
			(?person foaf:homepage ?page)
		USING
			foaf FOR <http://xmlns.com/foaf/0.1/>
END
	isa_ok( $query, 'RDF::Query' );
	my @results	= $query->execute( $model );
	is( scalar(@results), 1, 'Got one result' );
	isa_ok( $results[0], 'ARRAY' );
	is( scalar(@{$results[0]}), 1, 'Got one field' );
	ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
	is( $results[0][0]->getLabel, 'http://kasei.us/', 'Got homepage url' );
}
