#!/usr/bin/perl
use strict;
use warnings;
use URI::file;
use Test::More tests => 73;
use Data::Dumper;

use_ok( 'RDF::Query' );

SKIP: {
	eval "use RDF::Query::Model::Redland;";
	skip "Failed to load RDF::Redland", 72 if $@;
	
	my @uris	= map { URI::file->new_abs( "data/$_" ) } qw(about.xrdf foaf.xrdf);
	my @data	= map { RDF::Redland::URI->new( "$_" ) } @uris;
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	my $parser	= new RDF::Redland::Parser("rdfxml");
	$parser->parse_into_model($_, $_, $model) for (@data);
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			DESCRIBE ?person
			WHERE	{ ?person foaf:name "Gregory Todd Williams" }
END
		my $stream	= $query->execute( $model );
		ok( $stream->is_graph, "Stream is graph result" );
		isa_ok( $stream, 'CODE', 'stream' );
		my $count	= 0;
		while (my $stmt = $stream->()) {
			my $s	= $stmt->as_string;
			ok( $s, $s );
			++$count;
		}
		is( $count, 33 );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			DESCRIBE ?person
			WHERE {
				?image a foaf:Image ; foaf:maker ?person .
			}
END
		my $stream	= $query->execute( $model );
		ok( $stream->is_graph, "Stream is graph result" );
		isa_ok( $stream, 'CODE', 'stream' );
		my $count	= 0;
		while (my $stmt = $stream->()) {
			my $s	= $stmt->as_string;
			ok( $s, $s );
			++$count;
		}
		is( $count, 33 );
	}
}
