#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use Data::Dumper;
use RDF::Redland;
use RDF::Query;

if ($ENV{RDFQUERY_BIGTEST}) {
	plan qw(no_plan);
} else {
	plan skip_all => 'Developer test';
}

require Kasei::RDF::Common;
Kasei::RDF::Common->import('mysql_model');
my $model	= mysql_model();

{
	local $TODO = "Need to fix constraints parsing.";
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
	PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
	SELECT	?image ?point ?lat
	WHERE	{
				?point geo:lat ?lat .
				?image ?pred ?point .
			}
	FILTER	(?pred == <http://purl.org/dc/terms/spatial> || ?pred == <http://xmlns.com/foaf/0.1/based_near>)
	&&		?lat > 52
	&&		?lat < 53
END
	my ($image, $point, $lat)	= $query->get( $model );
	isa_ok($image, 'RDF::Redland::Node');
	ok( $query->bridge->isa_resource($image), $image ? $image->as_string : undef );
	my $latv	= ($lat) ? $lat->literal_value : undef;
	cmp_ok( $latv, '>', 52, 'lat: ' . $latv );
	cmp_ok( $latv, '<', 53, 'lat: ' . $latv );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?name
		WHERE	{
					[ a geo:Point; foaf:name ?name ]
				}
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'CODE', 'stream' );
	my $count;
	while (my $row = $stream->()) {
		my ($node)	= @{ $row };
		my $name	= $node->getLabel;
		ok( $name, $name );
	} continue { last if ++$count >= 100 };
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	DISTINCT ?p ?name
		WHERE	{
					?p a foaf:Person; foaf:name ?name
				}
		ORDER BY ?name
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'CODE', 'stream' );
	my ($count, $last);
	while (my $row = $stream->()) {
		my ($p, $node)	= @{ $row };
		my $name	= $node->getLabel;
		if (defined($last)) {
			cmp_ok( $name, 'ge', $last, "In order: $name(" . $p->getLabel . ")" );
		} else {
			ok( $name, "$name (" . $p->getLabel . ")" );
		}
		$last	= $name;
	} continue { last if ++$count >= 200 };
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	DISTINCT ?name ?lat ?long
		WHERE	{
					[ a geo:Point; foaf:name ?name; geo:lat ?lat; geo:long ?long ]
				}
		ORDER BY ?long
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'CODE', 'stream' );
	my ($count, $last);
	while (my $row = $stream->()) {
		my ($node, $lat, $long)	= @{ $row };
		my $name	= $node->getLabel;
		if (defined($last)) {
			cmp_ok( $long->getLabel, '>=', $last, "In order: $name (" . $long->getLabel . ")" );
		} else {
			ok( $name, "$name (" . $long->getLabel . ")" );
		}
		$last	= $long->getLabel;
	} continue { last if ++$count >= 200 };
}
