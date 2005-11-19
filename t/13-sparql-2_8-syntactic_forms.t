#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;

use lib qw(. t);
BEGIN { require "models.pl"; }

my @files	= map { File::Spec->rel2abs( "data/$_" ) } qw(about.xrdf foaf.xrdf);
my @models	= test_models( @files );

use Test::More;
plan tests => 1 + (10 * scalar(@models));

use_ok( 'RDF::Query' );
foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n";
	
	
# 	my $s	= $model->as_stream;
# 	while ($s and not $s->end) {
# 		my $st = $s->current;
# 		warn $st->as_string;
# 	} continue { $s->next }
	
	
	# - Collections: (1 ?x 3)
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			SELECT	?x
			WHERE	{
						?a1 rdf:first "1"; rdf:rest ?a2 .
						?a2 rdf:first ?x; rdf:rest ?a3 .
						?a3 rdf:first "3"; rdf:rest rdf:nil .
					}
END
		my ($x)	= $query->get( $model );
		ok( $x, 'got collection element' );
		is( $query->bridge->as_string( $x ), 2 );
	}

	# - Collections: (1 ?x 3)
	{
#		local($::RD_TRACE)	= 1;
#		local($::RD_HINT)	= 1;
#		local($RDF::Query::debug)	= 1;
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			SELECT	?x
			WHERE	{
						(1 ?x 3)
					}
END
		my ($x)	= $query->get( $model );
		ok( $x, 'got collection element' );
		is( $query->bridge->as_string( $x ), 2 );
	}

	# - Object Lists: ?x foaf:nick "kasei", "kasei_" .
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT	?name
			WHERE	{
						?x foaf:nick "kasei", "The Samo Fool" .
						?x foaf:name ?name
					}
END
		my ($name)	= $query->get( $model );
		ok( $name, 'got name' );
		is( $query->bridge->literal_value( $name ), 'Gregory Todd Williams', 'Gregory Todd Williams' );
	}

	# - Blank Nodes: [ :p "v" ] and [] :p "v" .
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT	?name
			WHERE	{
						[ rdf:type geo:Point; geo:lat "52.972770"; foaf:name ?name ]
					}
END
		my ($name)	= $query->get( $model );
		ok( $name, 'got name' );
		is( $query->bridge->literal_value( $name ), 'Cliffs of Moher, Ireland', 'Cliffs of Moher, Ireland' );
	}

	# - 'a': ?x a :Class . [ a :myClass ] :p "v" .
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT	?name
			WHERE	{
						[ a geo:Point; geo:lat "52.972770"; foaf:name ?name ]
					}
END
		my ($name)	= $query->get( $model );
		ok( $name, 'got name' );
		is( $query->bridge->literal_value( $name ), 'Cliffs of Moher, Ireland', 'Cliffs of Moher, Ireland' );
	}
}
