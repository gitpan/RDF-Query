#!/usr/bin/perl

use RDF::Query;

sub test_models {
	my @files	= @_;
	my @models;
	eval "use RDF::Query::Model::Redland;";
	if (not $@ and not $ENV{RDFQUERY_NO_REDLAND}) {
		require RDF::Query::Model::Redland;
		my @data	= map { RDF::Redland::URI->new( 'file://' . $_ ) } @files;
		my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory',contexts='yes'");
		my $model	= new RDF::Redland::Model($storage, "");
		my $parser	= new RDF::Redland::Parser("rdfxml");
		$parser->parse_into_model($_, $_, $model) for (@data);
		my $bridge	= RDF::Query::Model::Redland->new( $model );
		push(@models, $model);
	}
	
	eval "use RDF::Query::Model::RDFCore;";
	if (not $@ and not $ENV{RDFQUERY_NO_RDFCORE}) {
		require RDF::Query::Model::RDFCore;
		my $storage	= new RDF::Core::Storage::Memory;
		my $model	= new RDF::Core::Model (Storage => $storage);
		my $counter	= 0;
		foreach my $file (@files) {
			my $prefix	= 'r' . $counter++ . 'a';
			my $parser	= new RDF::Core::Model::Parser (
							Model		=> $model,
							Source		=> $file,
							SourceType	=> 'file',
							BaseURI		=> 'http://example.com/',
							BNodePrefix	=> $prefix,
						);
			$parser->parse;
		}
		my $bridge	= RDF::Query::Model::RDFCore->new( $model );
		push(@models, $model);
	}
	
	if ($ENV{RDFQUERY_USE_MYSQL}) {
		eval "use Kasei::Common;";
		if (not $@) {
			if ($ENV{RDFQUERY_USE_DBI_MODEL}) {
				require RDF::Query::Model::DBI;
				my $dbh	= Kasei::Common::dbh();
				push(@models, [$dbh, 'db1']);
			}
			
			{
				require RDF::Query::Model::RDFCore;
				require RDF::Core::Storage::Mysql;
				my $dbh		= Kasei::Common::dbh();
				my $storage	= new RDF::Core::Storage::Mysql ( dbh => $dbh, Model => 'db1' );
				my $model	= new RDF::Core::Model (Storage => $storage);
				if ($storage and $model) {
					push(@models, $model);
				}
			}
		}
	}
	
	return @models;
}

1;
