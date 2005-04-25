#!/usr/bin/perl
use strict;
use warnings;
use Test::More qw(no_plan);

use Data::Dumper;
use RDF::Redland;
use RDF::Query;

my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf);
my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
my $model	= new RDF::Redland::Model($storage, "");
my $parser	= new RDF::Redland::Parser("rdfxml");
$parser->parse_into_model($_, $_, $model) for (@data);

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
	while (not $stream->finished) {
		my ($node)	= $stream->binding_value( 0 );
		my $name	= $node->getLabel;
		ok( $name, $name );
	} continue {
		last if ++$count >= 100;
		$stream->next_result;
	};
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
		my ($node)	= $row->[0];
		my $name	= $node->getLabel;
		ok( $name, $name );
	} continue { last if ++$count >= 100 };
}

