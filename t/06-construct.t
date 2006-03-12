#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 16;
use Data::Dumper;

use_ok( 'RDF::Query' );

SKIP: {
	eval "use RDF::Query::Model::Redland;";
	skip "Failed to load RDF::Redland", 15 if $@;
	
	my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf);
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	my $parser	= new RDF::Redland::Parser("rdfxml");
	$parser->parse_into_model($_, $_, $model) for (@data);
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			CONSTRUCT { ?person foaf:name ?name }
			WHERE	{ ?person foaf:firstName ?name }
END
		my $stream	= $query->execute( $model );
		isa_ok( $stream, 'CODE', 'stream' );
		while (my $stmt = $stream->()) {
			my $s	= $stmt->as_string;
			ok( $s, $s );
		}
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	dc: <http://purl.org/dc/elements/1.1/>
			CONSTRUCT	{ _:somebody foaf:name ?name; foaf:made ?thing }
			WHERE		{ ?thing dc:creator ?name }
END
		my $stream	= $query->execute( $model );
		isa_ok( $stream, 'RDF::Query::Stream' );
		isa_ok( $stream, 'CODE', 'stream' );
		while (my $stmt = $stream->()) {
			my $s	= $stmt->as_string;
			like( $s, qr#foaf/0.1/(name|made)#, "predicate looks good: $s" );
		}
	}
}
