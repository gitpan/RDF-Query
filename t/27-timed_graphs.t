#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Scalar::Util qw(refaddr);

use RDF::Query;

if ($ENV{RDFQUERY_TIMETEST}) {
	plan qw(no_plan);
} else {
	plan skip_all => 'Developer tests. Set RDFQUERY_TIMETEST to run these tests.';
	return;
}

use lib qw(. t);
BEGIN { require "models.pl"; }

my $debug	= 1;
my @files	= map { "data/$_" } (); #qw(temporal.rdf);
my @models	= test_models( @files );


my $tests	= 0;

foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n";
	SKIP: {
		skip "This model does not support named graphs", $tests unless RDF::Query->supports( $model, 'named_graph' );
		
		### IMPORT TEMPORAL DATA ###############################################
		my $head	= <<'END';
		@prefix : <http://kasei.us/foaf/about.xrdf#> .
		@prefix rdf: <http://www.w3.org/2000/01/rdf-schema#> .
		@prefix foaf: <http://xmlns.com/foaf/0.1/> .
		@prefix time: <http://www.w3.org/2006/09/time#> .
		@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
END
		my %data	= (
			''		=> <<'END',
					<http://kasei.us/e/time/all> rdf:type time:Interval .
					<http://kasei.us/e/time/all> rdfs:label "Perpetuity" .
					
					<http://kasei.us/e/time/D09CBCC0-1363-480A-9F7C-62ABB52F073F> rdf:type time:Interval .
					<http://kasei.us/e/time/D09CBCC0-1363-480A-9F7C-62ABB52F073F> time:begins "2006-09-01" .
					<http://kasei.us/e/time/D09CBCC0-1363-480A-9F7C-62ABB52F073F> time:ends "2007-08-31" .
					<http://kasei.us/e/time/D09CBCC0-1363-480A-9F7C-62ABB52F073F> time:inside "2007-01-01" .
					
					<http://kasei.us/e/time/5F9DFA61-5CFB-4525-9D19-7B29D2C2FD85> rdf:type time:Interval .
					<http://kasei.us/e/time/5F9DFA61-5CFB-4525-9D19-7B29D2C2FD85> time:begins "1996-09-18" .
					<http://kasei.us/e/time/5F9DFA61-5CFB-4525-9D19-7B29D2C2FD85> time:ends "2001-01-22" .
END
			'http://kasei.us/e/time/all'		=> <<'END',
					:greg rdf:type foaf:Person .
					:greg foaf:mbox <mailto:gwilliams@cpan.org> .
END
			'http://kasei.us/e/time/D09CBCC0-1363-480A-9F7C-62ABB52F073F'		=> <<'END',
					:greg rdf:type foaf:Person .
					:greg foaf:mbox <mailto:gtw@cs.umd.edu> .
END
			'http://kasei.us/e/time/5F9DFA61-5CFB-4525-9D19-7B29D2C2FD85'		=> <<'END',
					:greg rdf:type foaf:Person .
					:greg foaf:mbox <mailto:greg@cnation.com> .
END
		);
		
		my $bridge	= RDF::Query->get_bridge( $model );
		foreach my $graph (keys %data) {
			my $rdf		= $data{ $graph };
			my $string	= join("\n", $head, $rdf);
			if ($graph) {
				$bridge->add_string( $string, $graph, 1, 'turtle' );
			} else {
				$bridge->add_string( $string, 'http://kasei.us/e/projects/rdfquery/', 0, 'turtle' );
			}
		}
		
		
		
		
		{
			my $query	= new RDF::Query ( <<'END', undef, undef, 'tsparql' );
				# select all the email addresses ever held by the person
				# who held a given email address on 2007-01-01
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				PREFIX t: <http://www.w3.org/2006/09/time#>
				SELECT ?mbox WHERE {
					GRAPH ?time { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
					?time t:inside "2007-01-01" .
					?p foaf:mbox ?mbox .
				}
END
			my @results	= $query->execute( $model );
			ok( scalar(@results), 'got GRAPH result' );
			foreach my $r (@results) {
				no warnings 'uninitialized';
				my $e	= $query->bridge->as_string( $r->[0] );
				like( $e, qr/mailto:/, "email: $e" );
			}
		}

		{
			my $query	= new RDF::Query ( <<'END', undef, undef, 'tsparql' );
				# select all the email addresses ever held by the person
				# who held a given email address on 2007-01-01
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				PREFIX t: <http://www.w3.org/2006/09/time#>
				SELECT ?mbox WHERE {
					TIME [ t:inside "2007-01-01" ] { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
					?p foaf:mbox ?mbox .
				}
END
			my @results	= $query->execute( $model );
			ok( scalar(@results), 'got TIME result' );
			foreach my $r (@results) {
				no warnings 'uninitialized';
				my $e	= $query->bridge->as_string( $r->[0] );
				like( $e, qr/mailto:/, "email: $e" );
			}
		}

		{
			my $query	= new RDF::Query ( <<'END', undef, undef, 'tsparql' );
				# select all the email addresses ever held by the person
				# who held a given email address on 2006-01-01
				PREFIX foaf: <http://xmlns.com/foaf/0.1/>
				PREFIX t: <http://www.w3.org/2006/09/time#>
				SELECT ?mbox WHERE {
					TIME [ t:inside "2006-01-01" ] { ?p foaf:mbox <mailto:gtw@cs.umd.edu> } .
					?p foaf:mbox ?mbox .
				}
END
			my @results	= $query->execute( $model );
			is( scalar(@results), 0, 'expected no results' );
		}
	}
}

