#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib qw(. t);
BEGIN { require "models.pl"; }

################################################################################
# Log::Log4perl::init( \q[
# 	log4perl.category.rdf.query.plan			= DEBUG, Screen
# 	log4perl.category.rdf.query.functions		= DEBUG, Screen
# 	log4perl.category.rdf.query.algebra.service	= DEBUG, Screen
# 	log4perl.appender.Screen					= Log::Log4perl::Appender::Screen
# 	log4perl.appender.Screen.stderr				= 0
# 	log4perl.appender.Screen.layout				= Log::Log4perl::Layout::SimpleLayout
# ] );
################################################################################

my $tests	= 25;
eval { require Bloom::Filter };
if ($@ or not(Bloom::Filter->can('freeze'))) {
	plan skip_all => "Bloom::Filter with serialization is not available";
	return;
} elsif (not exists $ENV{RDFQUERY_DEV_TESTS}) {
	plan skip_all => 'Developer tests. Set RDFQUERY_DEV_TESTS to run these tests.';
	return;
} elsif (not $ENV{RDFQUERY_NETWORK_TESTS}) {
	plan skip_all => 'No network. Set RDFQUERY_NETWORK_TESTS to run these tests.';
	return;
} else {
	plan qw(no_plan);	# XXX remove this when bnode joining is fixed (the TODO test below).
#	plan tests => $tests;
}

use RDF::Query;

{
	my $file	= URI::file->new_abs( 'data/bnode-person.rdf' );
	
	my $bf		= Bloom::Filter->new( capacity => 2, error_rate => $RDF::Query::Algebra::Service::BLOOM_FILTER_ERROR_RATE );
	### This filter contains greg and adam, identified by a primaryTopic page and an email sha1sum, respectively:
	$bf->add('!<http://xmlns.com/foaf/0.1/mbox_sha1sum>"26fb6400147dcccfda59717ff861db9cb97ac5ec"');
	$bf->add('^<http://xmlns.com/foaf/0.1/primaryTopic><http://kasei.us/>');
	my $filter	= $bf->freeze;
	$filter		=~ s/\n/\\n/g;
	
	my $sparql	= <<"END";
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
		PREFIX k: <http://kasei.us/code/rdf-query/functions/>
		SELECT DISTINCT *
		FROM <$file>
		WHERE {
			?p a foaf:Person ; foaf:name ?name .
			FILTER k:bloom( ?p, "${filter}" ) .
		}
END
	if (0){
		print "# bgp using default graph (local rdf) with k:bloom FILTER produces bnode identity hints in XML results\n";
		my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql11' );
		my $stream	= $query->execute();
		my $xml		= $stream->as_xml;
		like( $xml, qr#<link href="data:text/xml,%3Cextra%20name=%22bnode-map#sm, 'xml serialization has good looking bnode map' );
	}
	{
		print "# bgp using default graph (local rdf) with k:bloom FILTER\n";
		my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql11' );
		my $stream	= $query->execute();
		isa_ok( $stream, 'RDF::Trine::Iterator' );
		
		my $count	= 0;
		while (my $d = $stream->next) {
			isa_ok( $d->{name}, 'RDF::Query::Node::Literal' );
			like( $d->{name}->literal_value, qr/^(Adam Pisoni|Gregory Todd Williams)$/, 'expected name passed from person passing through bloom filter' );
			$count++;
		}
		is( $count, 2, 'expected result count' );
	}
	exit;
}

{
	print "# join using default graph (remote rdf) and remote SERVICE (kasei.us), joining on IRI\n";
	my $query	= RDF::Query->new( <<"END", undef, undef, 'sparql11' );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT DISTINCT *
		FROM <http://kasei.us/about/foaf.xrdf>
		WHERE {
			{
				?p a foaf:Person .
				FILTER( ISIRI(?p) )
			}
			SERVICE <http://kasei.us/sparql> {
				?p foaf:name ?name
			}
		}
END
	my $stream	= $query->execute();
	isa_ok( $stream, 'RDF::Trine::Iterator' );
	my $d	= $stream->next;
	isa_ok( $d, 'HASH' );
	isa_ok( $d->{p}, 'RDF::Trine::Node::Resource' );
	is( $d->{p}->uri_value, 'http://kasei.us/about/foaf.xrdf#greg', 'expected person uri' );
	isa_ok( $d->{name}, 'RDF::Trine::Node::Literal' );
	like( $d->{name}->literal_value, qr'Greg(ory Todd)? Williams', 'expected person name' );
}

TODO: {
	local($TODO)	= 'bnode joining based on bloom filter identities needs to be fixed in the plan generation code';
	print "# join using default graph (local rdf) and remote SERVICE (kasei.us), joining on bnode\n";
	my $file	= URI::file->new_abs( 'data/bnode-person.rdf' );
	my $query	= RDF::Query->new( <<"END", undef, undef, 'sparql11' );
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
		PREFIX k: <http://kasei.us/code/rdf-query/functions/>
		SELECT DISTINCT ?name ?nick
		FROM <$file>
		WHERE {
			?p a foaf:Person ; foaf:name ?name .
			SERVICE <http://kasei.us/sparql> {
				?p foaf:nick ?nick
				FILTER k:bloom( ?p, "AAAAAgAAAAoAAAACAAAAAwAAAAIAAAADrHIwUxHS+JHlnHcLrQAwLjE=\\n" ) .
			}
		}
END
	my $stream	= $query->execute();
	isa_ok( $stream, 'RDF::Trine::Iterator' );
	my $count	= 0;
	while (my $d = $stream->next) {
		isa_ok( $d->{nick}, 'RDF::Query::Node::Literal' );
		like( $d->{name}->literal_value, qr/^(Adam Pisoni)$/, 'got name from local file (joined on a bnode)' );
		like( $d->{nick}->literal_value, qr/^(wonko)$/, 'got nick from SERVICE (joined on a bnode)' );
		$count++;
	}
	is( $count, 1, 'expected result count' );
}

{
	print "# join using default graph (remote rdf) and remote SERVICE (dbpedia), joining on IRI\n";
	my $query	= RDF::Query->new( <<"END", undef, undef, 'sparql11' );
		PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
		SELECT DISTINCT *
		FROM <http://dbpedia.org/resource/Vancouver_Island>
		WHERE {
			{
				?thing rdfs:label ?label .
				FILTER( LANGMATCHES( LANG(?label), "en" ) )
			}
			SERVICE <http://dbpedia.org/sparql> {
				?thing a <http://dbpedia.org/class/yago/Island109316454>
				FILTER( REGEX( STR(?thing), "http://dbpedia.org/resource/V" ) ) .
			}
		}
END
	my $stream	= $query->execute();
	isa_ok( $stream, 'RDF::Trine::Iterator' );
	my $d	= $stream->next;
	isa_ok( $d, 'HASH' );
	isa_ok( $d->{label}, 'RDF::Trine::Node::Literal' );
	is( $d->{label}->literal_value, 'Vancouver Island', 'expected (island) name' );
	is( $d->{label}->literal_value_language, 'en', 'expected (island) name language' );
	isa_ok( $d->{thing}, 'RDF::Trine::Node::Resource' );
	is( $d->{thing}->uri_value, 'http://dbpedia.org/resource/Vancouver_Island', 'expected (island) uri' );
}
