#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 32;
use Data::Dumper;

use_ok( 'RDF::Query' );

my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf);
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
	isa_ok( $stream, 'CODE', 'stream' );
	while (my $stmt = $stream->()) {
		my $s	= $stmt->as_string;
		ok( $s, $s );
	}
}

