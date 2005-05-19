#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 7;

use Data::Dumper;
use RDF::Redland;
use RDF::Query;
use Encode;

my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf Flower-2.rdf);
my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
my $model	= new RDF::Redland::Model($storage, "");
my $parser	= new RDF::Redland::Parser("rdfxml");
$parser->parse_into_model($_, $_, $model) for (@data);

SKIP: {
	eval "use Geo::Distance 0.09;";
	skip( "Need Geo::Distance 0.09 or higher to run these tests.", 3 ) if ($@);
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		SELECT	?image ?point ?name ?lat ?long
		WHERE	{
					?image rdf:type foaf:Image .
					?image dcterms:spatial ?point .
					?point foaf:name ?name .
					?point geo:lat ?lat .
					?point geo:long ?long .
					FILTER mygeo:distance(?point, 41.849331, -71.392) < 10 .
				}
END
	my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
	$query->add_function( 'http://kasei.us/e/ns/geo#distance', sub {
		my $query	= shift;
		my $geo		= new Geo::Distance;
		my $point	= shift;
		my $plat	= get_first_literal( $model, $point, 'http://www.w3.org/2003/01/geo/wgs84_pos#lat' );
		my $plon	= get_first_literal( $model, $point, 'http://www.w3.org/2003/01/geo/wgs84_pos#long' );
		my ($lat, $lon)	= @_;
		my $dist	= $geo->distance(
						'kilometer',
						$lon,
						$lat,
						$plon,
						$plat
					);
		# warn "\t-> ${dist} kilometers from Providence";
		return $dist;
	} );
	my $stream	= $query->execute( $model );
	while (my $row = $stream->()) {
		my ($image, $point, $pname, $lat, $lon)	= @{ $row };
		my $url		= $image->uri->as_string;
		my $name	= $pname->literal_value;
		like( $name, qr/, (RI|MA|CT)$/, "$name ($url)" );
	}
};

{
	RDF::Query->add_function( 'http://kasei.us/e/ns/rdf#isa', sub {
		my $query	= shift;
		my $node	= shift;
		my $ntype	= RDF::Redland::Node->new_from_uri( shift );
		my $model	= $query->{model};
		my $p_type	= RDF::Redland::Node->new_from_uri( 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' );
		my $p_sub	= RDF::Redland::Node->new_from_uri( 'http://www.w3.org/2000/01/rdf-schema#subClassOf' );
		my @types	= $model->targets( $node, $p_type );
		my %seen;
		while (my $type = shift @types) {
			if ($type->equals($ntype)) {
				return 1;
			} else {
				next if ($seen{$type->as_string}++);
				push( @types, $model->targets( $type, $p_sub ) );
			}
		}
		return 0;
	} );
	
	my $sparql	= <<"END";
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	rdfs: <http://www.w3.org/2000/01/rdf-schema#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	myrdf: <http://kasei.us/e/ns/rdf#>
		PREFIX	wn: <http://xmlns.com/wordnet/1.6/>
		SELECT	?image ?thing ?type ?name
		WHERE	{
					?image foaf:depicts ?thing .
					?thing rdf:type ?type .
					?type rdfs:label ?name .
					FILTER myrdf:isa(?thing, wn:Object) .
				}
END
	my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
	my $count	= 0;
	my $stream	= $query->execute( $model );
	while (my $row = $stream->()) {
		my ($image, $thing, $ttype, $tname)	= @{ $row };
		my $url		= $image->uri->as_string;
		my $node	= $thing->as_string;
		my $name	= $tname->literal_value;
		my $type	= $ttype->as_string;
		ok( $name, "$node is a $name (${type} isa wn:Object)" );
		$count++;
	}
	is( $count, 3, "3 object depictions found" );
}


######################################################################

sub get_first_literal {
	my $node	= get_first_obj( @_ );
	return $node ? decode('utf8', $node->literal_value) : undef;
}

sub get_first_obj {
	my $model	= shift;
	my $node	= shift;
	my $uri		= shift;
	my @uris	= UNIVERSAL::isa($uri, 'ARRAY') ? @{ $uri } : ($uri);
	my @preds	= map { ref($_) ? $_ : RDF::Redland::Node->new_from_uri( $_ ) } @uris;
	foreach my $pred (@preds) {
		my $targets	= $model->targets_iterator( $node, $pred );
		while ($targets and !$targets->end) {
			my $node	= $targets->current;
			return $node if ($node);
		} continue { $targets->next }
	}
}
