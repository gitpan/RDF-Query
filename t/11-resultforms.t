#!/usr/bin/perl
use strict;
use warnings;
use Test::More qw(no_plan);

use_ok( 'RDF::Query' );

my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf);
my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
my $model	= new RDF::Redland::Model($storage, "");
my $parser	= new RDF::Redland::Parser("rdfxml");
$parser->parse_into_model($_, $_, $model) for (@data);

my %seen;
{
	print "# foaf:Person ORDER BY name with LIMIT\n";
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?p ?name
		WHERE	{
					?p a foaf:Person; foaf:name ?name
				}
		ORDER BY ?name
		LIMIT 2
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my ($count, $last);
	while (my $row = $stream->()) {
		my ($p, $node)	= @{ $row };
		my $name	= $node->literal_value;
		$seen{ $name }++;
		if (defined($last)) {
			cmp_ok( $name, 'ge', $last, "In order: $name (" . $p->getLabel . ")" );
		} else {
			ok( $name, "First: $name (" . $p->getLabel . ")" );
		}
		$last	= $name;
	} continue { ++$count };
	is( $count, 2, 'good LIMIT' );
}

{
	print "# foaf:Person ORDER BY name with LIMIT and OFFSET\n";
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?p ?name
		WHERE	{
					?p a foaf:Person; foaf:name ?name
				}
		ORDER BY ?name
		LIMIT 2
		OFFSET 2
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my ($count, $last);
	while (my $row = $stream->()) {
		my ($p, $node)	= @{ $row };
		my $name	= $node->literal_value;
		is( exists($seen{ $name }), '', "not seen before with offset" );
		if (defined($last)) {
			cmp_ok( $name, 'ge', $last, "In order: $name (" . $p->getLabel . ")" );
		} else {
			ok( $name, "First: $name (" . $p->getLabel . ")" );
		}
		$last	= $name;
	} continue { ++$count };
	is( $count, 2, 'good LIMIT' );
}

{
	print "# foaf:Person with LIMIT\n";
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?p ?name
		WHERE	{
					?p a foaf:Person; foaf:name ?name
				}
		LIMIT 2
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my ($count);
	while (my $row = $stream->()) {
		my ($p, $node)	= @{ $row };
		my $name	= $node->literal_value;
		ok( $name, "First: $name (" . $query->bridge->as_string( $p ) . ")" );
	} continue { ++$count };
	is( $count, 2, 'good LIMIT' );
}

{
	print "# foaf:Person with ORDER BY and OFFSET\n";
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	DISTINCT ?p ?name
		WHERE	{
					?p a foaf:Person; foaf:nick ?nick; foaf:name ?name
				}
		ORDER BY ?name
		OFFSET 1
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my ($count);
	while (my $row = $stream->()) {
		my ($p, $node)	= @{ $row };
		my $name	= $node->literal_value;
		ok( $name, "Got person with nick: $name (" . $query->bridge->as_string( $p ) . ")" );
	} continue { ++$count };
	is( $count, 1, "Good DISTINCT with OFFSET" );
}

{
	print "# foaf:Image with ORDER BY and OFFSET [2]\n";
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	exif: <http://www.kanzaki.com/ns/exif#>
		PREFIX	dc: <http://purl.org/dc/elements/1.1/>
		SELECT	DISTINCT ?name ?camera
		WHERE	{
					?img a foaf:Image .
					?img dc:creator ?name .
					?img exif:model ?camera
				}
		OFFSET 1
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my ($count);
	while (my $row = $stream->()) {
		my ($n, $c)	= @{ $row };
		my $name	= $n->literal_value;
		ok( $name, "Got image creator: $name" );
	} continue { ++$count };
	is( $count, 1, "Good DISTINCT with LIMIT" );
}

