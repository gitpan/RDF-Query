#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 12;

use Data::Dumper;
use RDF::Redland;

use_ok( 'RDF::Query' );

my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf);
my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
my $model	= new RDF::Redland::Model($storage, "");
my $parser	= new RDF::Redland::Parser("rdfxml");
$parser->parse_into_model($_, $_, $model) for (@data);

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
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
	my ($person, $homepage)	= $query->get( $model );
 	ok( $query->bridge->isa_resource( $person ), 'Resource with regex match' );
 	is( $person->getLabel, 'http://kasei.us/about/foaf.xrdf#greg', 'Person uri' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT
				?person ?homepage
		WHERE
				(?person foaf:name "Gregory Todd Williams")
				(?person foaf:homepage ?homepage)
		AND
				?homepage ~~ /not_in_here/
		USING
				rdf FOR <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
				foaf FOR <http://xmlns.com/foaf/0.1/>,
				dcterms FOR <http://purl.org/dc/terms/>,
				geo FOR <http://www.w3.org/2003/01/geo/wgs84_pos#>
END
	my ($person, $homepage)	= $query->get( $model );
 	is( $person, undef, 'no result with regex match' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT
				?point ?lat ?lon
		WHERE
				(<http://kasei.us/pictures/2004/20040909-Ireland/images/DSC_5705.jpg> dcterms:spatial ?point)
				(?point geo:lat ?lat)
				(?point geo:long ?lon)
		AND
				?lat > 52.97,
				?lat < 53.036526
		USING
				rdf FOR <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
				foaf FOR <http://xmlns.com/foaf/0.1/>,
				dcterms FOR <http://purl.org/dc/terms/>,
				geo FOR <http://www.w3.org/2003/01/geo/wgs84_pos#>
END
	my ($point, $lat, $lon)	= $query->get( $model );
 	ok( $query->bridge->isa_node( $point ), 'Point isa Node' );
 	cmp_ok( abs( $lat->getLabel - 52.97277 ), '<', 0.001, 'latitude' );
 	cmp_ok( abs( $lon->getLabel + 9.430733 ), '<', 0.001, 'longitude' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT
				?point ?lat ?lon
		WHERE
				(<http://kasei.us/pictures/2004/20040909-Ireland/images/DSC_5705.jpg> dcterms:spatial ?point)
				(?point geo:lat ?lat)
				(?point geo:long ?lon)
		AND
				?lat > 52,
				?lat < 53
		USING
				rdf FOR <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
				foaf FOR <http://xmlns.com/foaf/0.1/>,
				dcterms FOR <http://purl.org/dc/terms/>,
				geo FOR <http://www.w3.org/2003/01/geo/wgs84_pos#>
END
	my ($point, $lat, $lon)	= $query->get( $model );
 	ok( $query->bridge->isa_node( $point ), 'Point isa Node' );
 	cmp_ok( abs( $lat->getLabel - 52.97277 ), '<', 0.001, 'latitude' );
 	cmp_ok( abs( $lon->getLabel + 9.430733 ), '<', 0.001, 'longitude' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
		SELECT
				?image ?point ?lat
		WHERE
				(?point geo:lat ?lat)
				(?image dcterms:spatial ?point)
		AND
				?lat > 52.972,
				?lat < 53
		USING
				rdf FOR <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
				foaf FOR <http://xmlns.com/foaf/0.1/>,
				dcterms FOR <http://purl.org/dc/terms/>,
				geo FOR <http://www.w3.org/2003/01/geo/wgs84_pos#>
END
	my ($image, $point, $lat)	= $query->get( $model );
 	ok( $query->bridge->isa_resource( $image ), 'Image isa Resource' );
 	is( $image->getLabel, 'http://kasei.us/pictures/2004/20040909-Ireland/images/DSC_5705.jpg', 'Image url' );
}


__END__
