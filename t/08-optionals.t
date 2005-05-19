#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 23;

use_ok( 'RDF::Query' );

my @data	= map { RDF::Redland::URI->new( 'file://' . File::Spec->rel2abs( "data/$_" ) ) } qw(about.xrdf foaf.xrdf);
my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
my $model	= new RDF::Redland::Model($storage, "");
my $parser	= new RDF::Redland::Parser("rdfxml");
$parser->parse_into_model($_, $_, $model) for (@data);

{
#	local($::RD_TRACE)	= 1;
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?nick
		WHERE	{
					?person foaf:name "Lauren Bradford" .
					OPTIONAL { ?person foaf:nick ?nick }
				}
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my $row		= $stream->current;
	isa_ok( $row, "ARRAY" );
	my ($p,$n)	= @{ $row };
	ok( $query->bridge->isa_node( $p ), 'isa_node' );
	is( $n, undef, 'missing nick' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?nick
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					OPTIONAL { ?person foaf:nick ?nick }
				}
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	while ($stream and not $stream->finished) {
		my $row		= $stream->current;
		isa_ok( $row, "ARRAY" );
		my ($p,$n)	= @{ $row };
		ok( $query->bridge->isa_node( $p ), 'isa_node' );
		ok( $query->bridge->isa_literal( $n ), 'isa_literal(nick)' );
		like( ($n and $n->getLabel), qr/kasei|The Samo Fool/, ($n and $n->getLabel) );
	} continue { $stream->next }
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dc: <http://purl.org/dc/elements/1.1/>
		SELECT	?person ?h
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					OPTIONAL {
						?person foaf:homepage ?h .
					}
				}
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my $row		= $stream->current;
	isa_ok( $row, "ARRAY" );
	my ($p,$h)	= @{ $row };
	ok( $query->bridge->isa_node( $p ), 'isa_node(person)' );
	ok( $query->bridge->isa_node( $h ), 'isa_node(homepage)' );
}

{
	my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dc: <http://purl.org/dc/elements/1.1/>
		SELECT	?person ?h ?title
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					OPTIONAL {
						?person foaf:homepage ?h .
						?h dc:title ?title
					}
				}
END
	my $stream	= $query->execute( $model );
	isa_ok( $stream, 'RDF::Query::Stream' );
	my $row		= $stream->current;
	isa_ok( $row, "ARRAY" );
	my ($p,$h,$t)	= @{ $row };
	ok( $query->bridge->isa_node( $p ), 'isa_node' );
	is( $h, undef, 'no homepage' );
	is( $t, undef, 'no homepage title' );
}

