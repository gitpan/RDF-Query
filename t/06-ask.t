#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 4;
use Data::Dumper;

use_ok( 'RDF::Query' );

SKIP: {
	eval "use RDF::Query::Model::Redland;";
	skip "Failed to load RDF::Redland", 3 if $@;
	
	my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf);
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	my $parser	= new RDF::Redland::Parser("rdfxml");
	$parser->parse_into_model($_, $_, $model) for (@data);
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			ASK { ?person foaf:name "Gregory Todd Williams" }
END
		my $stream	= $query->execute( $model );
		ok( $stream->is_boolean, "Stream is boolean result" );
		my $ok		= $stream->get_boolean();
		ok( $ok, 'Exists in model' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			ASK { ?person foaf:name "Rene Descartes" }
END
		my $stream	= $query->execute( $model );
		my $ok		= $stream->get_boolean();
		ok( not($ok), 'Not in model' );
	}
	
}
