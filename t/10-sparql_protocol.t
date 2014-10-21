#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;

use lib qw(. t);
require "models.pl";

my @files	= map { File::Spec->rel2abs( "data/$_" ) } qw(about.xrdf foaf.xrdf Flower-2.rdf);
my @models	= test_models( @files );

use Test::More;

eval "use Test::JSON; use JSON;";
my $run_json_tests	= (not $@) ? 1 : 0;
my $tests_per_model	= 7 + ($run_json_tests ? 6 : 0);

plan tests => 1 + ($tests_per_model * scalar(@models));

use_ok( 'RDF::Query' );
foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n";
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			SELECT	?person ?homepage
			WHERE	{
						?person foaf:name "Gregory Todd Williams" .
						?person foaf:homepage ?homepage .
						FILTER REGEX(?homepage, "kasei")
					}
			LIMIT 1
END
		my $stream	= $query->execute( $model );
		ok( $stream->is_bindings, 'Bindings result' );
		my $xml		= $stream->as_xml;
		is( $xml, <<"END", 'XML Bindings Results formatting' );
<?xml version="1.0"?>
<sparql xmlns="http://www.w3.org/2001/sw/DataAccess/rf1/result2">
<head>
	<variable name="person"/>
	<variable name="homepage"/>
</head>
<results>
		<result>
			<binding name="person"><uri>http://kasei.us/about/foaf.xrdf#greg</uri></binding>
			<binding name="homepage"><uri>http://kasei.us/</uri></binding>
		</result>
</results>
</sparql>
END
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			ASK { ?person foaf:name "Gregory Todd Williams" }
END
		my $stream	= $query->execute( $model );
		ok( $stream->is_boolean, 'Boolean result' );
		my $xml		= $stream->as_xml;
		like( $xml, qr%<boolean>true</boolean>%sm, 'XML Boolean Results formatting' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX dc: <http://purl.org/dc/elements/1.1/>
			CONSTRUCT	{ _:somebody foaf:name ?name; foaf:made ?thing }
			WHERE		{ ?thing dc:creator ?name }
END
		my $stream	= $query->execute( $model );
		ok( $stream->is_graph, 'Graph result' );
				
		my $xml		= $stream->as_xml;
		like( $xml, qr%:name.*?>Greg Williams<%ms, 'XML Results formatting' );
		like( $xml, qr%:made\s+.*?rdf:resource="http://kasei\.us/pictures/2004/20040909-Ireland/images/DSC_5705\.jpg"%ms, 'XML Results formatting' );
	}
	
	### JSON Tests
	
	sub JSON::True;
	sub JSON::False;
	
	if ($run_json_tests) {
		{
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
				SELECT ?person ?homepage
				WHERE	{
							?person foaf:name "Gregory Todd Williams" .
							?person foaf:homepage ?homepage .
							FILTER REGEX(?homepage, "kasei")
						}
				ORDER BY ?homepage
				LIMIT 1
END
			my $stream	= $query->execute( $model );
			ok( $stream->is_bindings, 'Bindings result' );
			my $js		= $stream->as_json();
			my $expect	= {
							head	=> { vars => [qw(person homepage)] },
							results	=> {
								ordered 	=> JSON::True,
								distinct	=> JSON::False,
								bindings	=> [
									{
										person		=> { type => 'uri', value => 'http://kasei.us/about/foaf.xrdf#greg' },
										homepage	=> { type => 'uri', value => 'http://kasei.us/' },
									}
								],
							}
						};
			is_valid_json( $js, 'valid json syntax' );
			is_json( $js, objToJson($expect), 'expected json results' );
		}
	
		{
			my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
				PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
				ASK { ?person foaf:name "Gregory Todd Williams" }
END
			my $stream	= $query->execute( $model );
			ok( $stream->is_boolean, 'Boolean result' );
			my $js		= $stream->as_json;
			my $expect	= {
							head	=> { vars => [] },
							boolean	=> JSON::True,
						};
			is_valid_json( $js, 'valid json syntax' );
			is_json( $js, objToJson($expect), 'expected json results' );
		}
	}
}
