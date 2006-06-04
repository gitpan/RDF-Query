#!/usr/bin/perl
use strict;
use Test::More;
use Test::Exception;
use Data::Dumper;

use RDF::Query;
use RDF::Query::Parser::SPARQL;

if ($ENV{RDFQUERY_DEV_MYSQL}) {
	plan 'no_plan';
} else {
	plan tests => 18;
}

use_ok( 'RDF::Query::Compiler::SQL' );

my $parser		= new RDF::Query::Parser::SPARQL (undef);


{
	my $uri	= 'http://xmlns.com/foaf/0.1/name';
	my $hash	= RDF::Query::Compiler::SQL->_mysql_node_hash( [ 'URI', $uri ] );
	is( $hash, '14911999128994829034', 'URI hash' );
}

{
	my $hash	= RDF::Query::Compiler::SQL->_mysql_node_hash( [ 'LITERAL', 'kasei', undef, undef ] );
	is( $hash, '12775641923308277283', 'literal hash' );
}

{
	my $hash	= RDF::Query::Compiler::SQL::_mysql_hash( 'LTom Croucher<en>' );
	is( $hash, '14336915341960534814', 'language-typed literal hash' );
}

{
	my $hash	= RDF::Query::Compiler::SQL->_mysql_node_hash( [ 'LITERAL', 'Tom Croucher', 'en', undef ] );
	is( $hash, '14336915341960534814', 'language-typed literal node hash 1' );
}

{
	my $hash	= RDF::Query::Compiler::SQL->_mysql_node_hash( [ 'LITERAL', 'RDF', 'en', undef ] );
	is( $hash, '16625494614570964497', 'language-typed literal node hash 2' );
}






{
	my $parsed	= $parser->parse(<<"END");
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?name
		WHERE	{
					?person foaf:name ?name .
				}
END
	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	isa_ok( $compiler, 'RDF::Query::Compiler::SQL' );
	
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s0.subject AS person, ljr0.URI AS person_URI, ljl0.Value AS person_Value, ljl0.Language AS person_Language, ljl0.Datatype AS person_Datatype, ljb0.Name AS person_Name, s0.object AS name, ljr1.URI AS name_URI, ljl1.Value AS name_Value, ljl1.Language AS name_Language, ljl1.Datatype AS name_Datatype, ljb1.Name AS name_Name FROM Statements s0 LEFT JOIN Resources ljr0 ON s0.subject = ljr0.ID LEFT JOIN Literals ljl0 ON s0.subject = ljl0.ID LEFT JOIN Bnodes ljb0 ON s0.subject = ljb0.ID LEFT JOIN Resources ljr1 ON s0.object = ljr1.ID LEFT JOIN Literals ljl1 ON s0.object = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.object = ljb1.ID WHERE s0.predicate = 14911999128994829034', "select people and names" );
}

{
	my $parsed	= $parser->parse(<<"END");
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?person ?name ?homepage
		WHERE	{
					?person foaf:name ?name ; foaf:homepage ?homepage
				}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s0.subject AS person, ljr0.URI AS person_URI, ljl0.Value AS person_Value, ljl0.Language AS person_Language, ljl0.Datatype AS person_Datatype, ljb0.Name AS person_Name, s0.object AS name, ljr1.URI AS name_URI, ljl1.Value AS name_Value, ljl1.Language AS name_Language, ljl1.Datatype AS name_Datatype, ljb1.Name AS name_Name, s1.object AS homepage, ljr2.URI AS homepage_URI, ljl2.Value AS homepage_Value, ljl2.Language AS homepage_Language, ljl2.Datatype AS homepage_Datatype, ljb2.Name AS homepage_Name FROM Statements s0 LEFT JOIN Resources ljr0 ON s0.subject = ljr0.ID LEFT JOIN Literals ljl0 ON s0.subject = ljl0.ID LEFT JOIN Bnodes ljb0 ON s0.subject = ljb0.ID LEFT JOIN Resources ljr1 ON s0.object = ljr1.ID LEFT JOIN Literals ljl1 ON s0.object = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.object = ljb1.ID, Statements s1 LEFT JOIN Resources ljr2 ON s1.object = ljr2.ID LEFT JOIN Literals ljl2 ON s1.object = ljl2.ID LEFT JOIN Bnodes ljb2 ON s1.object = ljb2.ID WHERE s0.predicate = 14911999128994829034 AND s1.subject = s0.subject AND s1.predicate = 9768710922987392204', "select people, names, and homepages" );
}

{
	my $parsed	= $parser->parse(<<"END");
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?x ?name
		FROM NAMED <file://data/named_graphs/alice.rdf>
		FROM NAMED <file://data/named_graphs/bob.rdf>
		WHERE {
			GRAPH <foo:bar> { ?x foaf:name ?name }
		}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s0.subject AS x, ljr0.URI AS x_URI, ljl0.Value AS x_Value, ljl0.Language AS x_Language, ljl0.Datatype AS x_Datatype, ljb0.Name AS x_Name, s0.object AS name, ljr1.URI AS name_URI, ljl1.Value AS name_Value, ljl1.Language AS name_Language, ljl1.Datatype AS name_Datatype, ljb1.Name AS name_Name FROM Statements s0 LEFT JOIN Resources ljr0 ON s0.subject = ljr0.ID LEFT JOIN Literals ljl0 ON s0.subject = ljl0.ID LEFT JOIN Bnodes ljb0 ON s0.subject = ljb0.ID LEFT JOIN Resources ljr1 ON s0.object = ljr1.ID LEFT JOIN Literals ljl1 ON s0.object = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.object = ljb1.ID WHERE s0.Context = 2618056589919804847 AND s0.predicate = 14911999128994829034', "select people and names of context-specific graph" );
}

{
	my $parsed	= $parser->parse(<<"END");
		PREFIX foaf: <http://xmlns.com/foaf/0.1/>
		SELECT ?src ?name
		FROM NAMED <file://data/named_graphs/alice.rdf>
		FROM NAMED <file://data/named_graphs/bob.rdf>
		WHERE {
			GRAPH ?src { ?x foaf:name ?name }
		}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s0.Context AS src, ljr0.URI AS src_URI, ljl0.Value AS src_Value, ljl0.Language AS src_Language, ljl0.Datatype AS src_Datatype, ljb0.Name AS src_Name, s0.object AS name, ljr1.URI AS name_URI, ljl1.Value AS name_Value, ljl1.Language AS name_Language, ljl1.Datatype AS name_Datatype, ljb1.Name AS name_Name, ljr2.URI AS x_URI, ljl2.Value AS x_Value, ljl2.Language AS x_Language, ljl2.Datatype AS x_Datatype, ljb2.Name AS x_Name FROM Statements s0 LEFT JOIN Resources ljr0 ON s0.Context = ljr0.ID LEFT JOIN Literals ljl0 ON s0.Context = ljl0.ID LEFT JOIN Bnodes ljb0 ON s0.Context = ljb0.ID LEFT JOIN Resources ljr1 ON s0.object = ljr1.ID LEFT JOIN Literals ljl1 ON s0.object = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.object = ljb1.ID LEFT JOIN Resources ljr2 ON s0.subject = ljr2.ID LEFT JOIN Literals ljl2 ON s0.subject = ljl2.ID LEFT JOIN Bnodes ljb2 ON s0.subject = ljb2.ID WHERE s0.predicate = 14911999128994829034', "select context of people and names" );
}

{
	my $parsed	= $parser->parse(<<"END");
		PREFIX rss: <http://purl.org/rss/1.0/>
		SELECT ?title
		WHERE {
			<http://kasei.us/> rss:title ?title .
		}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s0.object AS title, ljr0.URI AS title_URI, ljl0.Value AS title_Value, ljl0.Language AS title_Language, ljl0.Datatype AS title_Datatype, ljb0.Name AS title_Name FROM Statements s0 LEFT JOIN Resources ljr0 ON s0.object = ljr0.ID LEFT JOIN Literals ljl0 ON s0.object = ljl0.ID LEFT JOIN Bnodes ljb0 ON s0.object = ljb0.ID WHERE s0.subject = 1083049239652454081 AND s0.predicate = 17858988500659793691', "select rss:title of uri" );
}

{
	my $parsed	= $parser->parse(<<"END");
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?page
		WHERE	{
					?person foaf:name "Gregory Todd Williams" .
					?person foaf:homepage ?page .
				}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s1.object AS page, ljr0.URI AS page_URI, ljl0.Value AS page_Value, ljl0.Language AS page_Language, ljl0.Datatype AS page_Datatype, ljb0.Name AS page_Name, ljr1.URI AS person_URI, ljl1.Value AS person_Value, ljl1.Language AS person_Language, ljl1.Datatype AS person_Datatype, ljb1.Name AS person_Name FROM Statements s0 LEFT JOIN Resources ljr1 ON s0.subject = ljr1.ID LEFT JOIN Literals ljl1 ON s0.subject = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.subject = ljb1.ID, Statements s1 LEFT JOIN Resources ljr0 ON s1.object = ljr0.ID LEFT JOIN Literals ljl0 ON s1.object = ljl0.ID LEFT JOIN Bnodes ljb0 ON s1.object = ljb0.ID WHERE s0.predicate = 14911999128994829034 AND s0.object = 2782977400239829321 AND s1.subject = s0.subject AND s1.predicate = 9768710922987392204', "select homepage of person by name" );
}

{
	my $parsed	= $parser->parse(<<'END');
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?s ?p
		WHERE	{
					?s ?p "RDF"@en .
				}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s0.subject AS s, ljr0.URI AS s_URI, ljl0.Value AS s_Value, ljl0.Language AS s_Language, ljl0.Datatype AS s_Datatype, ljb0.Name AS s_Name, s0.predicate AS p, ljr1.URI AS p_URI, ljl1.Value AS p_Value, ljl1.Language AS p_Language, ljl1.Datatype AS p_Datatype, ljb1.Name AS p_Name FROM Statements s0 LEFT JOIN Resources ljr0 ON s0.subject = ljr0.ID LEFT JOIN Literals ljl0 ON s0.subject = ljl0.ID LEFT JOIN Bnodes ljb0 ON s0.subject = ljb0.ID LEFT JOIN Resources ljr1 ON s0.predicate = ljr1.ID LEFT JOIN Literals ljl1 ON s0.predicate = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.predicate = ljb1.ID WHERE s0.object = 16625494614570964497', "select s,p by language-tagged literal" );
}

{
	RDF::Query::Compiler::SQL->add_function( 'time:now', sub {
		my $self	= shift;
		my $parsed_vars	= shift;
		my $expr	= shift;
		my $level	= shift || \do{ my $a = 0 };
		my %queryvars	= map { $_->[1] => 1 } @$parsed_vars;
		return ({}, [], ['NOW()']);
	} );
	
	my $parsed	= $parser->parse(<<'END');
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		PREFIX	xsd: <http://www.w3.org/2001/XMLSchema#>
		PREFIX	time: <time:>
		SELECT	?point
		WHERE	{
					?point a geo:Point .
					FILTER( time:now() > "2006-01-01" )
				}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s0.subject AS point, ljr0.URI AS point_URI, ljl0.Value AS point_Value, ljl0.Language AS point_Language, ljl0.Datatype AS point_Datatype, ljb0.Name AS point_Name FROM Statements s0 LEFT JOIN Resources ljr0 ON s0.subject = ljr0.ID LEFT JOIN Literals ljl0 ON s0.subject = ljl0.ID LEFT JOIN Bnodes ljb0 ON s0.subject = ljb0.ID WHERE s0.predicate = 2982895206037061277 AND s0.object = 11045396790191387947 AND NOW() > "2006-01-01"', "select with function filter" );
}

{
	RDF::Query::Compiler::SQL->add_function( 'http://kasei.us/e/ns/geo#distance', sub {
		my $self	= shift;
		my $parsed_vars	= shift;
		my $level	= shift || \do{ my $a = 0 };
		my @args	= @_;
		my $vars	= $self->{vars};
		my (@from, @where);
		
		my %queryvars	= map { $_->[1] => 1 } @$parsed_vars;
		
		++$$level; my $sql_a	= $self->expr2sql( $args[0], $level );
		++$$level; my $sql_b	= $self->expr2sql( $args[1], $level );
		++$$level; my $sql_c	= $self->expr2sql( $args[1], $level );
		push(@where, "distance($sql_a, $sql_b, $sql_c)");
		return ($vars, \@from, \@where);
	} );
	
	my $parsed	= $parser->parse(<<'END');
		PREFIX	rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		PREFIX	dcterms: <http://purl.org/dc/terms/>
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		PREFIX	mygeo: <http://kasei.us/e/ns/geo#>
		PREFIX	xsd: <http://www.w3.org/2001/XMLSchema#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER( mygeo:distance(?point, +41.849331, -71.392) < "10"^^xsd:integer )
				}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s1.subject AS image, ljr0.URI AS image_URI, ljl0.Value AS image_Value, ljl0.Language AS image_Language, ljl0.Datatype AS image_Datatype, ljb0.Name AS image_Name, s0.subject AS point, ljr1.URI AS point_URI, ljl1.Value AS point_Value, ljl1.Language AS point_Language, ljl1.Datatype AS point_Datatype, ljb1.Name AS point_Name, s0.object AS lat, ljr2.URI AS lat_URI, ljl2.Value AS lat_Value, ljl2.Language AS lat_Language, ljl2.Datatype AS lat_Datatype, ljb2.Name AS lat_Name, ljr3.URI AS pred_URI, ljl3.Value AS pred_Value, ljl3.Language AS pred_Language, ljl3.Datatype AS pred_Datatype, ljb3.Name AS pred_Name FROM Statements s0 LEFT JOIN Resources ljr1 ON s0.subject = ljr1.ID LEFT JOIN Literals ljl1 ON s0.subject = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.subject = ljb1.ID LEFT JOIN Resources ljr2 ON s0.object = ljr2.ID LEFT JOIN Literals ljl2 ON s0.object = ljl2.ID LEFT JOIN Bnodes ljb2 ON s0.object = ljb2.ID, Statements s1 LEFT JOIN Resources ljr0 ON s1.subject = ljr0.ID LEFT JOIN Literals ljl0 ON s1.subject = ljl0.ID LEFT JOIN Bnodes ljb0 ON s1.subject = ljb0.ID LEFT JOIN Resources ljr3 ON s1.predicate = ljr3.ID LEFT JOIN Literals ljl3 ON s1.predicate = ljl3.ID LEFT JOIN Bnodes ljb3 ON s1.predicate = ljb3.ID WHERE s0.predicate = 5391429383543785584 AND s1.object = s0.subject AND distance(s0.subject, (0.0 + "41.849331"), (0.0 + "41.849331")) < (0 + "10")', "select images filterd by distance function comparison" );
}

{
	my $parsed	= $parser->parse(<<'END');
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT	?name
		WHERE	{
					?p a foaf:Person ; foaf:name ?name .
					FILTER REGEX(?name, "Greg") .
				}
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT s1.object AS name, ljr0.URI AS name_URI, ljl0.Value AS name_Value, ljl0.Language AS name_Language, ljl0.Datatype AS name_Datatype, ljb0.Name AS name_Name, ljr1.URI AS p_URI, ljl1.Value AS p_Value, ljl1.Language AS p_Language, ljl1.Datatype AS p_Datatype, ljb1.Name AS p_Name FROM Statements s0 LEFT JOIN Resources ljr1 ON s0.subject = ljr1.ID LEFT JOIN Literals ljl1 ON s0.subject = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.subject = ljb1.ID, Statements s1 LEFT JOIN Resources ljr0 ON s1.object = ljr0.ID LEFT JOIN Literals ljl0 ON s1.object = ljl0.ID LEFT JOIN Bnodes ljb0 ON s1.object = ljb0.ID WHERE s0.predicate = 2982895206037061277 AND s0.object = 3652866608875541952 AND s1.subject = s0.subject AND s1.predicate = 14911999128994829034 AND (ljl0.Value REGEXP "Greg" OR ljr0.URI REGEXP "Greg" OR ljb0.Name REGEXP "Greg")', "select people by regex-filtered name" );
}

{
	my $parsed	= $parser->parse(<<'END');
		PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
		SELECT DISTINCT	?name
		WHERE	{
					?p a foaf:Person ; foaf:name ?name .
					FILTER REGEX(?name, "Greg") .
				}
		LIMIT 1
END

	my $compiler	= RDF::Query::Compiler::SQL->new( $parsed );
	my $sql		= $compiler->compile();
	is( $sql, 'SELECT DISTINCT s1.object AS name, ljr0.URI AS name_URI, ljl0.Value AS name_Value, ljl0.Language AS name_Language, ljl0.Datatype AS name_Datatype, ljb0.Name AS name_Name, ljr1.URI AS p_URI, ljl1.Value AS p_Value, ljl1.Language AS p_Language, ljl1.Datatype AS p_Datatype, ljb1.Name AS p_Name FROM Statements s0 LEFT JOIN Resources ljr1 ON s0.subject = ljr1.ID LEFT JOIN Literals ljl1 ON s0.subject = ljl1.ID LEFT JOIN Bnodes ljb1 ON s0.subject = ljb1.ID, Statements s1 LEFT JOIN Resources ljr0 ON s1.object = ljr0.ID LEFT JOIN Literals ljl0 ON s1.object = ljl0.ID LEFT JOIN Bnodes ljb0 ON s1.object = ljb0.ID WHERE s0.predicate = 2982895206037061277 AND s0.object = 3652866608875541952 AND s1.subject = s0.subject AND s1.predicate = 14911999128994829034 AND (ljl0.Value REGEXP "Greg" OR ljr0.URI REGEXP "Greg" OR ljb0.Name REGEXP "Greg") LIMIT 1', "select people by regex-filtered name with DISTINCT and LIMIT" );
}




if ($ENV{RDFQUERY_DEV_MYSQL}) {
	eval "require Kasei::RDF::Common;";
	Kasei::RDF::Common->import('mysql_model');
	my @myargs	= Kasei::Common::mysql_upd();
	my $model	= mysql_model( 'db1', @myargs[ 2, 0, 1 ] );
	my $dsn		= [ Kasei::Common::mysql_dbi_args() ];
	
	{
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER(	geo:distance(?point) ) .
				}
END
		throws_ok {
			$query->execute( $model, dsn => $dsn, require_sql => 1 );
		} 'RDF::Query::Error::CompilationError', 'forced sql compilation (expected) failure';
	}
	
	{
		print "# FILTER rage test\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
		PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
		SELECT	?image ?point ?lat
		WHERE	{
					?point geo:lat ?lat .
					?image ?pred ?point .
					FILTER(	(?pred = <http://purl.org/dc/terms/spatial> || ?pred = <http://xmlns.com/foaf/0.1/based_near>)
						&&	?lat > 52
						&&	?lat < 53
					) .
				}
END
		my ($image, $point, $lat)	= $query->get( $model, dsn => $dsn );
		ok($query->bridge->isa_resource( $image ), 'image is resource');
		ok( $query->bridge->isa_resource($image), $image ? $query->bridge->as_string($image) : undef );
		my $latv	= ($lat) ? $query->bridge->literal_value( $lat ) : undef;
		cmp_ok( $latv, '>', 52, 'lat: ' . $latv );
		cmp_ok( $latv, '<', 53, 'lat: ' . $latv );
	}
	
	{
		print "# lots of points!\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT	?name
			WHERE	{
						?point a geo:Point; foaf:name ?name .
					}
END
		my $stream	= $query->execute( $model, dsn => $dsn );
		isa_ok( $stream, 'CODE', 'stream' );
		my $count;
		while (my $row = $stream->()) {
			my ($node)	= @{ $row };
			my $name	= $query->bridge->as_string( $node );
			ok( $name, $name );
		} continue { last if ++$count >= 100 };
	}
	
	{
		print "# foaf:Person ORDER BY name\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			SELECT	DISTINCT ?p ?name
			WHERE	{
						?p a foaf:Person; foaf:name ?name
					}
			ORDER BY ?name
END
		my $stream	= $query->execute( $model, dsn => $dsn );
		isa_ok( $stream, 'CODE', 'stream' );
		my ($count, $last);
		while (my $row = $stream->()) {
			my ($p, $node)	= @{ $row };
			my $name	= $query->bridge->as_string( $node );
			if (defined($last)) {
				cmp_ok( $name, 'ge', $last, "In order: $name (" . $query->bridge->as_string( $p ) . ")" );
			} else {
				ok( $name, "$name (" . $query->bridge->as_string( $p ) . ")" );
			}
			$last	= $name;
		} continue { last if ++$count >= 200 };
	}
	
	{
		print "\n" x 10;
		print "# geo:Point ORDER BY longitude\n";
		my $query	= new RDF::Query ( <<"END", undef, undef, 'sparql' );
			PREFIX	foaf: <http://xmlns.com/foaf/0.1/>
			PREFIX	geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
			PREFIX	xsd: <http://www.w3.org/2001/XMLSchema#>
			SELECT	DISTINCT ?name ?lat ?lon
			WHERE	{
						?point a geo:Point; foaf:name ?name; geo:lat ?lat; geo:long ?lon
					}
			ORDER BY DESC( xsd:decimal(?lon) )
END
		my $stream	= $query->execute( $model, dsn => $dsn );
		isa_ok( $stream, 'CODE', 'stream' );
		my ($count, $last);
		while (my $row = $stream->()) {
			my ($node, $lat, $long)	= @{ $row };
			my $name	= $query->bridge->as_string( $node );
			if (defined($last)) {
				cmp_ok( $query->bridge->as_string( $long ), '<=', $last, "In order: $name (" . $query->bridge->as_string( $long ) . ")" );
			} else {
				ok( $name, "$name (" . $query->bridge->as_string( $long ) . ")" );
			}
			$last	= $query->bridge->as_string( $long );
		} continue { last if ++$count >= 200 };
	}
	
}



# if ($ENV{RDFQUERY_DEV_POSTGRESQL}) {
# 	eval "require Kasei::RDF::Common;";
# 	$ENV{'POSTGRESQL_MODEL'}	= 'model';
# 	$ENV{'POSTGRESQL_DATABASE'}	= 'greg';
# 	$ENV{'POSTGRESQL_PASSWORD'}	= 'nrt26ack';
# 	
# 	Kasei::RDF::Common->import('postgresql_model');
# 	my $dbh		= postgresql_model();
# 	warn $dbh;
# 	
# 	my @myargs	= Kasei::Common::postgresql_upd();
# 	my $model	= postgresql_model( 'db1', @myargs[ 2, 0, 1 ] );
# 	my $dsn		= [ Kasei::Common::postgresql_dbi_args() ];
# 	
# 	warn $model;
# 	warn Dumper($dsn);
# 
# 
# }



__END__