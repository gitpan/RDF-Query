#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 11;
use Data::Dumper;

use_ok( 'RDF::Query' );

my $file	= 'file://' . File::Spec->rel2abs( "data/foaf.xrdf" );

{
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT
			?page
		FROM
			<$file>
		WHERE
			(?person foaf:name "Gregory Todd Williams")
			(?person foaf:homepage ?page)
		USING
			foaf FOR <http://xmlns.com/foaf/0.1/>
END
	
	my @results	= $query->execute( $model );
	is( scalar(@results), 1, 'Got one result' );
	isa_ok( $results[0], 'ARRAY' );
	is( scalar(@{$results[0]}), 1, 'Got one field' );
	ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
	is( $results[0][0]->getLabel, 'http://kasei.us/', 'Got homepage url' );
}

{
	my $storage	= new RDF::Core::Storage::Memory;
	my $model	= new RDF::Core::Model (Storage => $storage);
	
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT
			?page
		FROM
			<$file>
		WHERE
			(?person foaf:name "Gregory Todd Williams")
			(?person foaf:homepage ?page)
		USING
			foaf FOR <http://xmlns.com/foaf/0.1/>
END
	my @results	= $query->execute( $model );
	is( scalar(@results), 1, 'Got one result' );
	isa_ok( $results[0], 'ARRAY' );
	is( scalar(@{$results[0]}), 1, 'Got one field' );
	ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
	is( $results[0][0]->getLabel, 'http://kasei.us/', 'Got homepage url' );
}
