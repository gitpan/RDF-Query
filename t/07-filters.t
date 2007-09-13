#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 40;

use URI::file;
use Data::Dumper;
use RDF::Query;

SKIP: {
	eval "use RDF::Query::Model::Redland;";
	skip "Failed to load RDF::Redland", 40 if $@;
	
	my @uris	= map { URI::file->new_abs( "data/$_" ) } qw(about.xrdf foaf.xrdf Flower-2.rdf);
	my @data	= map { RDF::Redland::URI->new( "$_" ) } @uris;
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	my $parser	= new RDF::Redland::Parser("rdfxml");
	$parser->parse_into_model($_, $_, $model) for (@data);
	
	
	{
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
						FILTER(REGEX(STR(?type),"Flower")) .
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
			like( $type, qr/Flower/, "$node is a Flower" );
			$count++;
		}
		is( $count, 3, "3 object depictions found" );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	dc: <http://purl.org/dc/elements/1.1/>
			SELECT	?person ?name
			WHERE	{
						?person rdf:type foaf:Person .
						?person foaf:name ?name .
						FILTER isBLANK(?person) .
					}
END
		my $stream	= $query->execute( $model );
		isa_ok( $stream, 'RDF::Query::Stream' );
		while (my $row = $stream->()) {
			isa_ok( $row, "ARRAY" );
			my ($p,$n)	= @{ $row };
			ok( $query->bridge->isa_node( $p ), $query->bridge->as_string( $p ) . ' is a node' );
			like( $query->bridge->as_string( $n ), qr/^Gary Peck/, 'name' );
		}
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	dc: <http://purl.org/dc/elements/1.1/>
			SELECT	?person ?name
			WHERE	{
						?person rdf:type foaf:Person .
						?person foaf:name ?name .
						FILTER isURI(?person) .
					}
END
		my $stream	= $query->execute( $model );
		isa_ok( $stream, 'RDF::Query::Stream' );
		while (my $row = $stream->()) {
			isa_ok( $row, "ARRAY" );
			my ($p,$n)	= @{ $row };
			ok( $query->bridge->isa_node( $p ), $query->bridge->as_string( $p ) . ' is a node' );
			like( $query->bridge->as_string( $n ), qr/^(Greg|Liz|Lauren)/, 'name' );
		}
	}
	
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
						FILTER( mygeo:distance(?point, 41.849331, -71.392) < 10 ) .
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

	{
		my $sparql	= <<"END";
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	jena: <java:com.hp.hpl.jena.query.function.library.>
			SELECT	?p
			WHERE	{
				?p foaf:mbox ?mbox .
				FILTER ( jena:sha1sum( ?mbox ) = 'f80a0f19d2a0897b89f48647b2fb5ca1f0bc1cb8' ) .
			}
END
		my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
		
		my $count	= 0;
		my $stream	= $query->execute( $model );
		while (my $row = $stream->()) {
			my ($node)	= @{ $row };
			my $uri	= $query->bridge->uri_value( $node );
			is( $uri, 'http://kasei.us/about/foaf.xrdf#greg', 'jena:sha1sum' );
			$count++;
		}
		is( $count, 1, "jena:sha1sum: 1 object found" );
	}

	{
		my $sparql	= <<"END";
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	xpath: <http://www.w3.org/2005/04/xpath-functions>
			SELECT	?p
			WHERE	{
				?p foaf:mbox ?mbox .
				FILTER ( xpath:matches(?p, "^http://kasei.us", "") ) .
			}
END
		my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
		
		my $count	= 0;
		my $stream	= $query->execute( $model );
		while (my $row = $stream->()) {
			my ($node)	= @{ $row };
			my $uri	= $query->bridge->uri_value( $node );
			is( $uri, 'http://kasei.us/about/foaf.xrdf#greg', 'xpath:matches' );
			$count++;
		}
		is( $count, 1, "xpath:matches: 1 object found" );
	}

	{
		my $sparql	= <<"END";
			PREFIX	ldodds: <java:com.ldodds.sparql.>
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	dcterms: <http://purl.org/dc/terms/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT	?image ?point ?name ?lat ?long
			WHERE	{
						?image a foaf:Image .
						?image dcterms:spatial ?point .
						?point foaf:name ?name .
						?point geo:lat ?lat .
						?point geo:long ?long .
						FILTER( ldodds:Distance(?lat, ?long, 41.849331, -71.392) < 10 ) .
					}
END
		my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
		my $stream	= $query->execute( $model );
		my $count	= 0;
		while (my $row = $stream->()) {
			my ($image, $point, $pname, $lat, $lon)	= @{ $row };
			my $url		= $image->uri->as_string;
			my $name	= $pname->literal_value;
			like( $name, qr/, (RI|MA|CT)$/, "$name ($url)" );
			$count++;
		}
		is( $count, 3, "ldodds:Distance: 3 objects found" );
	}

	{
		my $sparql	= <<"END";
			PREFIX	jfn: <java:com.hp.hpl.jena.query.function.library.>
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	dcterms: <http://purl.org/dc/terms/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			PREFIX test: <http://kasei.us/e/ns/test#>
			PREFIX kasei: <http://kasei.us/about/foaf.xrdf#>
			SELECT	?data
			WHERE	{
					kasei:greg test:mycollection ?col .
					?list rdf:first ?data .
					FILTER( jfn:listMember( ?col, ?data ) ) .
			}
END
		my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
		my $stream	= $query->execute( $model );
		my $count	= 0;
		my %expect	= map {$_=>1} (1..3);
		while (my $row = $stream->()) {
			my ($data)	= @{ $row };
			ok( $query->bridge->isa_literal( $data ), "literal list member" );
			ok( exists($expect{ $query->bridge->literal_value( $data ) }), , "expected literal value" );
			delete $expect{ $query->bridge->literal_value( $data ) };
			$count++;
		}
		is( $count, 3, "jfn:listMember: 3 objects found" );
	}
}

######################################################################

sub get_first_literal {
	my $node	= get_first_obj( @_ );
	return $node ? $node->literal_value : undef;
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
