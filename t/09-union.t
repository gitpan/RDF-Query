#!/usr/bin/perl
use strict;
use warnings;
use URI::file;
use Test::More tests => 26;
use_ok( 'RDF::Query' );

SKIP: {
	eval "use RDF::Query::Model::Redland;";
	skip "Failed to load RDF::Redland", 25 if $@;
	
	my @uris	= map { URI::file->new_abs( "data/$_" ) } qw(about.xrdf foaf.xrdf Flower-2.rdf);
	my @data	= map { RDF::Redland::URI->new( "$_" ) } @uris;
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	my $parser	= new RDF::Redland::Parser("rdfxml");
	$parser->parse_into_model($_, $_, $model) for (@data);
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	rdfs: <http://www.w3.org/2000/01/rdf-schema#>
			SELECT	DISTINCT ?thing ?name
			WHERE	{
						{ ?thing rdf:type foaf:Person; foaf:name ?name }
						UNION
						{ ?thing rdf:type rdfs:Class; rdfs:label ?name }
					}
END
		my $stream	= $query->execute( $model );
		isa_ok( $stream, 'RDF::Query::Stream' );
		while ($stream and not $stream->finished) {
			my $row		= $stream->current;
			my ($thing, $name)	= @{ $row };
			ok( $query->bridge->isa_node( $thing ), 'node: ' . $query->bridge->as_string( $thing ) );
			ok( $query->bridge->isa_literal( $name ), 'name: ' . $query->bridge->as_string( $name ) );
		} continue { $stream->next }
	}
}
