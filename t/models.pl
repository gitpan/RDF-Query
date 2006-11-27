#!/usr/bin/perl

use strict;
use warnings;

use RDF::Query;
use File::Spec;
use URI::file;

sub test_models {
	my @models	= test_models_and_classes( @_ );
	return map { $_->{ bridge } } @models;
}

sub test_models_and_classes {
	my @files	= map { File::Spec->rel2abs( $_ ) } @_;
	my @uris	= map { URI::file->new_abs( $_ ) } @files;
	my @models;
	eval "use RDF::Query::Model::Redland;";
	if (not $@ and not $ENV{RDFQUERY_NO_REDLAND}) {
		require RDF::Query::Model::Redland;
		my @data	= map { RDF::Redland::URI->new( "$_" ) } @uris;
		my $storage	= new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory',contexts='yes'");
		my $model	= new RDF::Redland::Model($storage, "");
		my $parser	= new RDF::Redland::Parser("rdfxml");
		$parser->parse_into_model($_, $_, $model) for (@data);
		my $bridge	= RDF::Query::Model::Redland->new( $model );
		
		my $data	= {
						bridge		=> $model,
						class		=> 'RDF::Query::Model::Redland',
						model		=> 'RDF::Redland::Model',
						statement	=> 'RDF::Redland::Statement',
						node		=> 'RDF::Redland::Node',
						resource	=> 'RDF::Redland::Node',
						literal		=> 'RDF::Redland::Node',
						blank		=> 'RDF::Redland::Node',
					};
		push(@models, $data);
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
		my $data	= {
						bridge		=> $model,
						class		=> 'RDF::Query::Model::RDFCore',
						model		=> 'RDF::Core::Model',
						statement	=> 'RDF::Core::Statement',
						node		=> 'RDF::Core::Node',
						resource	=> 'RDF::Core::Resource',
						literal		=> 'RDF::Core::Literal',
						blank		=> 'RDF::Core::Node',
					};
		push(@models, $data);
	}
	
	if (0) {
		eval "use RDF::Query::Model::RDFBase;";
		if (not $@ and not $ENV{RDFQUERY_NO_RDFBASE}) {
			require RDF::Query::Model::RDFBase;
			my $s		= new RDF::Base::Storage::DBI;
			my $model	= new RDF::Base::Model ( storage => $s );
			my $parser	= RDF::Base::Parser->new( name => 'rdfxml' );
			my @data	= @uris;
			foreach my $uri (@data) {
				$parser->parse_into_model($uri, $uri, $model);
			}
			
			my $bridge	= RDF::Query::Model::RDFBase->new( $model );
			my $data	= {
							bridge		=> $model,
							class		=> 'RDF::Query::Model::RDFBase',
							model		=> 'RDF::Base::Model',
							statement	=> 'RDF::Base::Statement',
							node		=> 'RDF::Base::Node',
							resource	=> 'RDF::Base::Node::Resource',
							literal		=> 'RDF::Base::Node::Literal',
							blank		=> 'RDF::Base::Node::Blank',
						};
			push(@models, $data);
		}
	}
	
	eval "use RDF::Storage::DBI;";
	if (not $@ and not $ENV{RDFQUERY_NO_RDFSTORAGE}) {
		require RDF::Query::Model::SQL;
		my $model	= RDF::Storage::DBI->new();
		my $handler	= sub {
						my %args	= @_;
						my @triple;
						foreach my $type (qw(subject predicate object)) {
							if (my $uri = $args{"${type}_uri"}) {
								if ($uri =~ m#^_:(.*)$#) {
									push(@triple, RDF::Node::Blank->new( name => $1 ));
								} else {
									push(@triple, RDF::Node::Resource->new( uri => $uri ));
								}
							} elsif (defined(my $value = $args{"${type}_literal"})) {
								my %data	= ( value => $value );
								if (my $lang = $args{"${type}_lang"}) {
									$data{ language }	= $lang;
								} elsif (my $dt = $args{"${type}_datatype"}) {
									$data{ datatype }	= $dt;
								}
								push(@triple, RDF::Node::Literal->new( %data ));
							} else {
								use Data::Dumper;
								warn "unknown node type: " . Dumper(\%args);
							}
						}
						$model->add_statement( @triple );
					};
		foreach my $file (@files) {
			my $uri		= URI::file->new_abs( $file );
			my $parser	= RDF::Core::Parser->new(
							Assert		=> $handler,
							BaseURI		=> $uri,
							BNodePrefix	=> "r${file}r",
						);
			$parser->parseFile( $file );
		}
		my $data	= {
						bridge		=> $model,
						class		=> 'RDF::Query::Model::SQL',
						model		=> 'RDF::Storage::DBI',
						statement	=> 'RDF::Statement',
						node		=> 'RDF::Node',
						resource	=> 'RDF::Node::Resource',
						literal		=> 'RDF::Node::Literal',
						blank		=> 'RDF::Node::Blank',
					};
				
		push(@models, $data);
	}
	
	if (0) {
		require RDF::Query::Model::RDFCore;
		require RDF::Core::Storage::Mysql;
		my $dbh		= Kasei::Common::dbh();
		my $storage	= new RDF::Core::Storage::Mysql ( dbh => $dbh, Model => 'db1' );
		my $model	= new RDF::Core::Model (Storage => $storage);
		if ($storage and $model) {
			my $data	= {
							bridge	=> $model,
						};
			push(@models, $data);
		}
	}
	
	return @models;
}

1;
