#!/usr/bin/perl
use strict;
use warnings;
use URI::file;

use lib qw(. t);
BEGIN { require "models.pl"; }

use Test::More;

my $tests	= 36;
my @models	= test_models();
plan tests => 1 + ($tests * scalar(@models));

my $alice	= URI::file->new_abs( 'data/named_graphs/alice.rdf' );
my $bob		= URI::file->new_abs( 'data/named_graphs/bob.rdf' );
my $meta	= URI::file->new_abs( 'data/named_graphs/meta.rdf' );

use_ok( 'RDF::Query' );
foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n";
	SKIP: {
		skip "This model does not support named graphs", $tests unless RDF::Query->supports( $model, 'named_graph' );
		
		{
			print "# variable named graph\n";
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?src ?name
				FROM NAMED <${alice}>
				WHERE {
					GRAPH ?src { ?x foaf:name ?name }
				}
END
			my ($src, $name)	= $query->get( $model );
			ok( $src, 'got source' );
			
			ok( $name, 'got name' );		
			is( $query->bridge->uri_value( $src ), $alice, 'graph uri' );
			is( $query->bridge->literal_value( $name ), 'Alice', 'name literal' );
		}
		
		{
			print "# uri named graph (fail: graph)\n";
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?name
				FROM NAMED <${alice}>
				WHERE {
					GRAPH <foo:bar> { ?x foaf:name ?name }
				}
END
			my $stream	= $query->execute( $model );
			my $row		= $stream->();
			is( $row, undef, 'no results' );
		}
		
		{
			print "# uri named graph (fail: pattern)\n";
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?src ?name
				FROM NAMED <${alice}>
				WHERE {
					GRAPH ?src { ?x <foo:bar> ?name }
				}
END
			my $stream	= $query->execute( $model );
			my $row		= $stream->();
			is( $row, undef, 'no results' );
		}
		
		{
			print "# uri named graph with multiple graphs\n";
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?mbox
				FROM NAMED <${alice}>
				FROM NAMED <${bob}>
				WHERE {
					GRAPH <$bob> { ?x foaf:mbox ?mbox } .
				}
END
			
			my $count	= 0;
			my $stream	= $query->execute( $model );
			while (my $row = $stream->()) {
				isa_ok( $row, 'ARRAY' );
				
				my $mbox	= $row->[0];
				ok( $mbox, 'got mbox' );
				
				my $uri	= $query->bridge->uri_value( $mbox );
				is( $uri, 'mailto:bob@oldcorp.example.org', "mbox uri: $uri" );
				$count++;
			}
			
			is( $count, 1, 'one result' );
		}
		
		{
			print "# variable named graph with multiple graphs; select from one\n";
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?src ?mbox
				FROM NAMED <${alice}>
				FROM NAMED <${bob}>
				WHERE {
					GRAPH ?src { ?x foaf:name "Alice"; foaf:mbox ?mbox } .
				}
END
			my ($src, $mbox)	= $query->get( $model );
			ok( $src, 'got source' );
			ok( $mbox, 'got mbox' );		
			is( $query->bridge->uri_value( $src ), $alice, 'graph uri' );
			is( $query->bridge->uri_value( $mbox ), 'mailto:alice@work.example', 'mbox uri' );
		}
		
		
		{
			print "# variable named graph with multiple graphs; select from both\n";
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?g ?name
				FROM NAMED <${alice}>
				FROM NAMED <${bob}>
				FROM <${meta}>
				WHERE {
					GRAPH ?g { ?x foaf:name ?name } .
				}
END
			
			my %expected	= (
								$alice	=> "Alice",
								$bob	=> "Bob",
							);
			
			my $count	= 0;
			my $stream	= $query->execute( $model );
			while (my $row = $stream->current) {
				$stream->next;
				isa_ok( $row, 'ARRAY' );
				
				my ($graph, $name)	= @{ $row };
				my $uri	= $query->bridge->uri_value( $graph );
				
				ok( exists $expected{ $uri }, "Known GRAPH: $uri" );
				
				my $expect	= $expected{ $uri };
				
				ok( $name, 'got name' );
				
				my $l_name	= $query->bridge->literal_value( $name );
				is( $l_name, $expect, "got name: $l_name" );
				$count++;
			}
			
			is( $count, 2, 'got results' );
		}
		
		{
			print "# variable named graph with multiple graphs; non-named graph triples\n";
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?g ?name ?topic
				FROM NAMED <${alice}>
				FROM NAMED <${bob}>
				FROM <${meta}>
				WHERE {
					GRAPH ?g { ?x foaf:name ?name } .
					?g foaf:topic ?topic .
				}
END
			
			my %expected	= (
								$alice	=> "Alice",
								$bob	=> "Bob",
							);
			
			my $count	= 0;
			my $stream	= $query->execute( $model );
			while (my $row = $stream->()) {
				isa_ok( $row, 'ARRAY' );
				
				my ($graph, $name, $topic)	= @{ $row };
				my $uri	= $query->bridge->uri_value( $graph );
				
				ok( exists $expected{ $uri }, "Known GRAPH: $uri" );
				
				my $expect	= $expected{ $uri };
				
				ok( $name, 'got name' );
				ok( $topic, 'got topic' );
				
				my $l_name	= $query->bridge->literal_value( $name );
				my $l_topic	= $query->bridge->literal_value( $topic );
				is( $l_name, $expect, "got name: $l_name" );
				is( $l_topic, $expect, "got topic: $l_topic" );
				$count++;
			}
			
			is( $count, 2, 'got results' );
		}
	}
}
