#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 65; # qw(no_plan);
use RDF::Redland;
use File::Spec;

use_ok( 'RDF::Query' );

my @files	= map { File::Spec->rel2abs( "data/$_" ) } qw(foaf.xrdf);
my @models;

{
	my @data	= map { RDF::Redland::URI->new( 'file://' . $_ ) } @files;
	my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= new RDF::Redland::Model($storage, "");
	my $parser	= new RDF::Redland::Parser("rdfxml");
	$parser->parse_into_model($_, $_, $model) for (@data);
	push(@models, $model);
} {
	my $storage	= new RDF::Core::Storage::Memory;
	my $model	= new RDF::Core::Model (Storage => $storage);
	foreach my $file (@files) {
		my $parser	= new RDF::Core::Model::Parser (
						Model		=> $model,
						Source		=> $file,
						SourceType	=> 'file',
						BaseURI		=> 'http://example.com/'
					);
		$parser->parse;
	}
	push(@models, $model);
}	

foreach my $model (@models) {
	print "\n#################################\n";
	print "### Using model: $model\n\n";
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:name "Gregory Todd Williams")
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# (?var qname literal)\n";
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, 'one result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
		is( $results[0][0]->getLabel, 'http://kasei.us/about/foaf.xrdf#greg', 'got person uri' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?person
			WHERE
				(?person foaf:homepage <http://kasei.us/>)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# (?var qname quri)\n";
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, 'one result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
		is( $results[0][0]->getLabel, 'http://kasei.us/about/foaf.xrdf#greg', 'got person uri' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?title
			WHERE
				(?person foaf:name "Gregory Todd Williams")
				(?desc foaf:maker ?person)
				(?desc dc:title ?title)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
				dc FOR <http://purl.org/dc/elements/1.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# multiple namespaces\n";
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, 'one result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( $query->bridge->isa_literal( $results[0][0] ), 'Literal' );
		is( $results[0][0]->getLabel, 'FOAF Description for Gregory Williams', 'got file title' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?page
			WHERE
				(?person foaf:name "Gregory Todd Williams")
				(?person foaf:homepage ?page)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# chained (name->person->homepage)\n";
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, 'one result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 1, 'got one field' );
		ok( $query->bridge->isa_resource( $results[0][0] ), 'Resource' );
		is( $results[0][0]->getLabel, 'http://kasei.us/', 'got homepage url' );
	}
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'rdql' );
			SELECT
				?name ?mbox
			WHERE
				(?person foaf:homepage <http://kasei.us/>)
				(?person foaf:name ?name)
				(?person foaf:mbox ?mbox)
			USING
				foaf FOR <http://xmlns.com/foaf/0.1/>
END
		isa_ok( $query, 'RDF::Query' );
		
		print "# chained (homepage->person->(name|mbox)\n";
		my @results	= $query->execute( $model );
		is( scalar(@results), 1, 'one result' );
		isa_ok( $results[0], 'ARRAY' );
		is( scalar(@{$results[0]}), 2, 'got two fields' );
		ok( $query->bridge->isa_literal( $results[0][0] ), 'Literal' );
		ok( $query->bridge->isa_resource( $results[0][1] ), 'Resource' );
		is( $results[0][0]->getLabel, 'Gregory Todd Williams', 'got name' );
		is( $results[0][1]->getLabel, 'mailto:greg@evilfunhouse.com', 'got mbox uri' );
	}
}