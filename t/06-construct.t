#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib qw(. t);
require "models.pl";

my @files	= map { "data/$_" } qw(about.xrdf foaf.xrdf Flower-2.rdf);
my @models	= test_models( @files );
my $tests	= 1 + (scalar(@models) * 14);
plan tests => $tests;

use_ok( 'RDF::Query' );
foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n\n";

	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			CONSTRUCT { ?person foaf:name ?name }
			WHERE	{ ?person foaf:firstName ?name }
END
		my $stream	= $query->execute( $model );
		my $bridge	= $query->bridge;
		isa_ok( $stream, 'RDF::Query::Stream', 'stream' );
		while (my $stmt = $stream->next()) {
			my $p	= $bridge->predicate( $stmt );
			my $s	= $bridge->as_string( $p );
			ok( $s, "person with firstName: $s" );
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
		my $bridge	= $query->bridge;
		isa_ok( $stream, 'RDF::Query::Stream', 'stream' );
		while (my $stmt = $stream->()) {
			my $p	= $bridge->predicate( $stmt );
			my $s	= $bridge->as_string( $p );
			like( $s, qr#foaf/0.1/(name|made)#, "predicate looks good: $s" );
		}
	}
}
