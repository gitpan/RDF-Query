# RDF::Query
# -------------
# $Revision: 235 $
# $Date: 2007-09-13 13:31:06 -0400 (Thu, 13 Sep 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query - An RDF query implementation of SPARQL/RDQL in Perl for use with RDF::Redland and RDF::Core.

=head1 VERSION

This document describes RDF::Query version 1.044.

=head1 SYNOPSIS

 my $query = new RDF::Query ( $rdql, undef, undef, 'rdql' );
 my @rows = $query->execute( $model );
 
 my $query = new RDF::Query ( $sparql, undef, undef, 'sparql' );
 my $iterator = $query->execute( $model );
 while (my $row = $iterator->()) {
   ...
 }

=head1 DESCRIPTION

RDF::Query allows RDQL and SPARQL queries to be run against an RDF model, returning rows
of matching results.

See L<http://www.w3.org/TR/rdf-sparql-query/> for more information on SPARQL.
See L<http://www.w3.org/Submission/2004/SUBM-RDQL-20040109/> for more information on RDQL.

=head1 REQUIRES

L<RDF::Redland|RDF::Redland> or L<RDF::Core|RDF::Core>

L<Parse::RecDescent|Parse::RecDescent> (for RDF::Core)

L<LWP::Simple|LWP::Simple>

L<DateTime::Format::W3CDTF|DateTime::Format::W3CDTF>

L<Scalar::Util|Scalar::Util>

=cut

package RDF::Query;

use strict;
use warnings;
use Carp qw(carp croak confess);

use URI::Fetch;
use Data::Dumper;
use Storable qw(dclone);
use List::Util qw(first);
use Scalar::Util qw(blessed reftype looks_like_number);
use DateTime::Format::W3CDTF;

use RDF::Query::Stream;
use RDF::Query::Parser::RDQL;
use RDF::Query::Parser::SPARQL;
# use RDF::Query::Parser::tSPARQL;	# XXX temporal extensions
use RDF::Query::Compiler::SQL;
use RDF::Query::Error qw(:try);

#use RDF::Query::Optimizer::Multiget;
use RDF::Query::Optimizer::Peephole::Naive;
use RDF::Query::Optimizer::Peephole::Cost;

######################################################################

our ($REVISION, $VERSION, $debug, $js_debug, $DEFAULT_PARSER);
use constant DEBUG	=> 0;
BEGIN {
	$debug		= DEBUG;
	$js_debug	= 0;
	$REVISION	= do { my $REV = (qw$Revision: 235 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$VERSION	= '1.044';
	$ENV{RDFQUERY_NO_RDFBASE}	= 1;	# XXX Not ready for release
	$DEFAULT_PARSER		= 'sparql';
}

my $KEYWORD_RE	= qr/^(OPTIONAL|GRAPH|FILTER|TIME)$/;

######################################################################

=head1 METHODS

=over 4

=item C<new ( $query, $baseuri, $languri, $lang )>

Returns a new RDF::Query object for the query specified.
The query language used will be set if $languri or $lang
is passed as the URI or name of the query language, otherwise
the query defaults to SPARQL.

=cut
sub new {
	my $class	= shift;
	my ($query, $baseuri, $languri, $lang, %options)	= @_;
	$class->clear_error;
	
	my $f	= DateTime::Format::W3CDTF->new;
	no warnings 'uninitialized';
	
	my %names	= (
					rdql	=> 'RDF::Query::Parser::RDQL',
					sparql	=> 'RDF::Query::Parser::SPARQL',
					tsparql	=> 'RDF::Query::Parser::tSPARQL'
				);
	my %uris	= (
					'http://jena.hpl.hp.com/2003/07/query/RDQL'	=> 'RDF::Query::Parser::RDQL',
					'http://www.w3.org/TR/rdf-sparql-query/'	=> 'RDF::Query::Parser::SPARQL',
				);
	
	
	my $pclass	= $names{ $lang } || $uris{ $languri } || $names{ $DEFAULT_PARSER };
	my $parser	= $pclass->new();
#	my $parser	= ($lang eq 'rdql' or $languri eq 'http://jena.hpl.hp.com/2003/07/query/RDQL')
#				? RDF::Query::Parser::RDQL->new()
#				: RDF::Query::Parser::SPARQL->new();
	my $parsed		= $parser->parse( $query );
	my $self 	= bless( {
					dateparser	=> $f,
					parser		=> $parser,
					parsed		=> $parsed,
					parsed_orig	=> $parsed,
				}, $class );
	unless ($parsed->{'triples'}) {
		$class->set_error( $parser->error );
		warn $parser->error if ($debug);
		return;
	}
	
	if ($options{net_filters}) {
		require JavaScript;
		$self->{options}{net_filters}++;
	}
	if ($options{trusted_keys}) {
		require Crypt::GPG;
		$self->{options}{trusted_keys}	= $options{trusted_keys};
	}
	if ($options{gpg}) {
		$self->{_gpg_obj}	= delete $options{gpg};
	}
	if (defined $options{keyring}) {
		$self->{options}{keyring}	= $options{keyring};
	}
	if (defined $options{secretkey}) {
		$self->{options}{secretkey}	= $options{secretkey};
	}
	
	$self->{parsed}{namespaces}{rdf}	= 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
	return $self;
}

=item C<get ( $model )>

Executes the query using the specified model,
and returns the first row found.

=cut
sub get {
	my $self	= shift;
	my $stream	= $self->execute( @_ );
	my $row		= $stream->();
	if (ref($row)) {
		return @{ $row };
	} else {
		return undef;
	}
}

=item C<execute ( $model, %args )>

Executes the query using the specified model. If called in a list
context, returns an array of rows, otherwise returns an iterator.

=cut
sub execute {
	my $self	= shift;
	my $model	= shift;
	my %args	= @_;
	
	
	$self->{parsed}	= dclone( $self->{parsed_orig} );
	my $parsed	= $self->{parsed};
	
	my $stream;
	$self->{model}		= $model;
	
	if (my $dsn = $args{'dsn'}) {
		require DBI;
		try {
			my $dbh			= DBI->connect( @$dsn );
			$self->{dbh}	= $dbh;
		};
	} elsif (blessed($model) and $model->isa('DBI::db')) {
		$self->{dbh}	= $model;
	}
	
	my %bound	= ($args{ 'bind' }) ? %{ $args{ 'bind' } } : ();
	if (my $dbh = $self->{'dbh'} || $args{'dbh'}) {
		try {
			if (%bound) {
				throw RDF::Query::Error::CompilationError ( -text => 'SQL compilation does not yet support pre-bound query variables.' );
			}
			my $compiler	= RDF::Query::Compiler::SQL->new( dclone($parsed), $args{'model'} );
			my $sql			= $compiler->compile();
			try {
				$dbh->{FetchHashKeyName}	= 'NAME_lc';
				my $sth			= $dbh->prepare( $sql );
				$sth->execute;
				if (my $err = $sth->errstr) {
					throw RDF::Query::Error::CompilationError ( -text => $err );
				}
				$self->{sql}	= $sql;
				$self->{sth}	= $sth;
			} catch RDF::Query::Error::CompilationError with {
				my $err	= shift;
				my $text	= $err->text;
				throw RDF::Query::Error::CompilationError ( -text => "$text : $sql" );
			};
		} catch RDF::Query::Error::CompilationError with {
			my $err	= shift;
			if ($args{'require_sql'}) {
				throw $err;
			} else {
				warn $err->text;
				delete $self->{'dbh'};
				delete $self->{'sql'};
			}
		};
	}
	
	my $bridge	= $self->get_bridge( $model, %args );
	if ($bridge) {
		$self->{bridge}		= $bridge;
	} else {
		throw RDF::Query::Error::ModelError ( -text => "Could not create a model object." );
	}
	
	if (my $sth = $self->{sth}) {
		$stream	= $bridge->stream( $parsed, $sth );
	} elsif ($args{'require_sql'}) {
		throw RDF::Query::Error::CompilationError ( -text => 'Failed to compile query to SQL' );
	} else {
		unless ($self->{optimized}{'peephole'}++) {
			my $opt		= RDF::Query::Optimizer::Peephole->new( $self, $bridge );
			my $cost	= $opt->optimize;
		}
		
#		unless ($self->{optimized}{'multi_get'}++) {
#			if ($bridge->supports('multi_get')) {
#				my $mopt	= RDF::Query::Optimizer::Multiget->new( $self, $bridge, size => 3 );
#				$mopt->optimize;
#			}
#		}
		
		$parsed		= $self->fixup( $self->{parsed} );
		my @vars	= $self->variables( $parsed );
		$stream		= $self->query_more( bound => \%bound, triples => [@{ $parsed->{'triples'} }], variables => \@vars );
		
		_debug( "got stream: $stream" );
		my $sorted		= $self->sort_rows( $stream, $parsed );
		my $projected	= sub {
			my $bound	= $sorted->();
			return unless ref($bound);
			my @values	= map { $bound->{$_} } @vars;
			return \@values;
		};
	
		$stream		= RDF::Query::Stream->new(
						$projected,
						'bindings',
						\@vars,
						bridge	=> $bridge
					);
		
	}
	
	
	if ($parsed->{'method'} eq 'DESCRIBE') {
		$stream	= $self->describe( $stream );
	} elsif ($parsed->{'method'} eq 'CONSTRUCT') {
		$stream	= $self->construct( $stream, $parsed );
	} elsif ($parsed->{'method'} eq 'ASK') {
		$stream	= $self->ask( $stream );
	}
	
	if (wantarray) {
		return $stream->get_all();
	} else {
		return $stream;
	}
}

=begin private

=item C<describe ( $stream )>

Takes a stream of matching statements and constructs a DESCRIBE graph.

=end private

=cut

sub describe {
	my $self	= shift;
	my $stream	= shift;
	my $bridge	= $self->bridge;
	my @nodes;
	my %seen;
	while ($stream and not $stream->finished) {
		my $row	= $stream->current;
		foreach my $node (@$row) {
			push(@nodes, $node) unless ($seen{ $bridge->as_string( $node ) }++);
		}
	} continue {
		$stream->next;
	}
	
	my @streams;
	$self->{'describe_nodes'}	= [];
	foreach my $node (@nodes) {
		push(@{ $self->{'describe_nodes'} }, $node);
		push(@streams, $bridge->get_statements( $node, undef, undef ));
		push(@streams, $bridge->get_statements( undef, undef, $node ));
	}
	
	my $ret	= sub {
		while (@streams) {
			my $val	= $streams[0]->current;
			if (defined $val) {
				$streams[0]->next;
				return $val;
			} else {
				shift(@streams);
				return undef if (not @streams);
			}
		}
	};
	return RDF::Query::Stream->new( $ret, 'graph', undef, bridge => $bridge );
}

=begin private

=item C<construct ( $stream )>

Takes a stream of matching statements and constructs a result graph matching the
uery's CONSTRUCT graph patterns.

=end private

=cut

sub construct {
	my $self	= shift;
	my $stream	= shift;
	my $parsed	= shift;
	my $bridge	= $self->bridge;
	my @streams;
	
	my %seen;
	my %variable_map;
	my %blank_map;
	foreach my $var_count (0 .. $#{ $parsed->{'variables'} }) {
		$variable_map{ $parsed->{'variables'}[ $var_count ][1] }	= $var_count;
	}
	
	while ($stream and not $stream->finished) {
		my $row	= $stream->current;
		my @triples;	# XXX move @triples out of the while block, and only push one stream below (just before the continue{})
		foreach my $triple (@{ $parsed->{'construct_triples'} }) {
			my @triple	= @{ $triple };
			for my $i (0 .. 2) {
				if (reftype($triple[$i]) eq 'ARRAY') {
					if ($triple[$i][0] eq 'VAR') {
						$triple[$i]	= $row->[ $variable_map{ $triple[$i][1] } ];
					} elsif ($triple[$i][0] eq 'BLANK') {
						unless (exists($blank_map{ $triple[$i][1] })) {
							$blank_map{ $triple[$i][1] }	= $self->bridge->new_blank();
						}
						$triple[$i]	= $blank_map{ $triple[$i][1] };
					}
				}
			}
			my $st	= $bridge->new_statement( @triple );
			push(@triples, $st);
		}
		push(@streams, RDF::Query::Stream->new( sub { shift(@triples) } ));
	} continue {
		$stream->next;
	}
	
	
	my $ret	= sub {
		while (@streams) {
			if ($streams[0]->open and $streams[0]->finished) {
				shift(@streams);
			} else {
				$streams[0]->next;
				my $val	= $streams[0]->current;
				return $val if (defined $val);
			}
		}
		return undef;
	};
	return RDF::Query::Stream->new( $ret, 'graph', undef, bridge => $bridge );
}

=begin private

=item C<ask ( $stream )>

Takes a stream of matching statements and returns a boolean query result stream.

=end private

=cut

sub ask {
	my $self	= shift;
	my $stream	= shift;
	return RDF::Query::Stream->new( $stream, 'boolean', undef, bridge => $self->bridge );
}

######################################################################

=begin private

=item C<supports ( $model, $feature )>

Returns a boolean value representing the support of $feature for the given model.

=end private

=cut

sub supports {
	my $self	= shift;
	my $model	= shift;
	my $bridge	= $self->get_bridge( $model );
	return $bridge->supports( @_ );
}

=begin private

=item C<set_named_graph_query ()>

Makes appropriate changes for the current query to use named graphs.
This entails creating a new context-aware bridge (and model) object.

=end private

=cut

sub set_named_graph_query {
	my $self	= shift;
	my $bridge	= $self->new_bridge();
	_debug( "Replacing model bridge with a new (empty) one for a named graph query" );
	$self->{bridge}	= $bridge;
}

=begin private

=item C<loadable_bridge_class ()>

Returns the class name of a model backend that is present and loadable on the system.

=end private

=cut

sub loadable_bridge_class {
	my $self	= shift;
	
	if (not $ENV{RDFQUERY_NO_RDFBASE}) {
		eval "use RDF::Query::Model::RDFBase;";
		if (RDF::Query::Model::RDFBase->can('new')) {
			return 'RDF::Query::Model::RDFBase';
		} else {
			warn "RDF::Query::Model::RDFBase didn't load cleanly" if ($debug);
		}
	} else { warn "RDF::Base supressed" unless ($ENV{RDFQUERY_SILENT}) }
	
	if (not $ENV{RDFQUERY_NO_REDLAND}) {
		eval "use RDF::Query::Model::Redland;";
		if (RDF::Query::Model::Redland->can('new')) {
			return 'RDF::Query::Model::Redland';
		} else {
			warn "RDF::Query::Model::Redland didn't load cleanly" if ($debug);
		}
	} else { warn "RDF::Redland supressed" unless ($ENV{RDFQUERY_SILENT}) }
	
# 	if (0) {
# 		eval "use RDF::Query::Model::SQL;";
# 		if (RDF::Query::Model::SQL->can('new')) {
# 			return 'RDF::Query::Model::SQL';
# 		} else {
# 			warn "RDF::Query::Model::SQL didn't load cleanly" if ($debug);
# 		}
# 	} else { warn "Native SQL model supressed" unless ($ENV{RDFQUERY_SILENT}) }
	
	if (not $ENV{RDFQUERY_NO_RDFCORE}) {
		eval "use RDF::Query::Model::RDFCore;";
		if (RDF::Query::Model::RDFCore->can('new')) {
			return 'RDF::Query::Model::RDFCore';
		} else {
			warn "RDF::Query::Model::RDFCore didn't load cleanly" if ($debug);
		}
	} else { warn "RDF::Core supressed" unless ($ENV{RDFQUERY_SILENT}) }
	
	return undef;
}

=begin private

=item C<new_bridge ()>

Returns a new bridge object representing a new, empty model.

=end private

=cut

sub new_bridge {
	my $self	= shift;
	
	my $bridge_class	= $self->loadable_bridge_class;
	if ($bridge_class) {
		return $bridge_class->new();
	} else {
		return undef;
	}
}

=begin private

=item C<get_bridge ( $model )>

Returns a bridge object for the specified model object.

=end private

=cut

sub get_bridge {
	my $self	= shift;
	my $model	= shift;
	my %args	= @_;
	
	my $parsed	= ref($self) ? $self->{parsed} : undef;
	
#	warn Dumper($model);
	
	my $bridge;
	if (not $model) {
		$bridge	= $self->new_bridge();
	} elsif (blessed($model) and $model->isa('DBD')) {
		require RDF::Query::Model::SQL;
		my $storage	= RDF::Base::Storage::DBI->new( $model, $args{'model'} );
		$bridge	= RDF::Query::Model::SQL->new( $storage, parsed => $parsed );
	} elsif (my $dbh = (ref($self) ? $self->{'dbh'} : undef) || $args{'dbh'}) {
		require RDF::Query::Model::SQL;
		no warnings 'uninitialized';
		if (not length($args{'model'})) {
			throw RDF::Query::Error::ExecutionError ( -text => 'No model specified for DBI-based triplestore' );
		}
		
		my $storage	= RDF::Base::Storage::DBI->new( $dbh, $args{'model'} );
		$bridge	= RDF::Query::Model::SQL->new( $storage, parsed => $parsed );
	} elsif (blessed($model) and ($model->isa('RDF::Base::Model') or $model->isa('RDF::Base::Storage'))) {
		if ($model->isa('RDF::Base::Storage')) {
			$model	= RDF::Base::Model->new( storage => $model );
		}
		require RDF::Query::Model::RDFBase;
		$bridge	= RDF::Query::Model::RDFBase->new( $model, parsed => $parsed );
#		Carp::cluck 'using RDF::Base';
	} elsif (blessed($model) and $model->isa('RDF::Redland::Model')) {
		require RDF::Query::Model::Redland;
		$bridge	= RDF::Query::Model::Redland->new( $model, parsed => $parsed );
#	} elsif (reftype($model) eq 'ARRAY' and blessed($model->[0]) and $model->[0]->isa('DBI::db')) {
#		require RDF::Query::Model::DBI;
#		$bridge	= RDF::Query::Model::DBI->new( $model );
	} else {
		require RDF::Query::Model::RDFCore;
		$bridge	= RDF::Query::Model::RDFCore->new( $model, parsed => $parsed );
	}
	
	return $bridge;
}

=begin private

=item C<fixup ()>

Does last-minute fix-up on the parse tree. This involves:

	* Loading any external files into the model.
	* Converting URIs and strings to model-specific objects.
	* Fixing variable list in the case of 'SELECT *' queries.

=end private

=cut

sub fixup {
	my $self		= shift;
	my $orig		= shift;
	my $bridge		= $self->{bridge};
	my $parsed		= dclone( $orig );
	
	my %known_variables;
	
	## LOAD ANY EXTERNAL RDF FILES
	my $sources	= $parsed->{'sources'};
	if (ref($sources) and reftype($sources) eq 'ARRAY') {
		my $named_query	= 0;
		foreach my $source (@{ $sources }) {
			my $named_source	= (3 == @{$source} and $source->[2] eq 'NAMED');
			if ($named_source and not $named_query) {
				$named_query++;
#				$self->set_named_graph_query();
				$bridge		= $self->{bridge};
				unless ($bridge->supports( 'named_graph' )) {
					throw RDF::Query::Error::ModelError ( -text => "This RDF model does not support named graphs." );
				}
			}
			
			$self->parse_url( $source->[1], $named_source );
		}
		$self->run_hook( 'http://kasei.us/code/rdf-query/hooks/post-create-model', $self->bridge );
	}
	
	## CONVERT URIs to Resources, and strings to Literals
	my @triples	= @{ $parsed->{'triples'} || [] };
	while (my $triple = shift(@triples)) {
		if ($triple->[0] eq 'OPTIONAL') {
			push(@triples, @{$triple->[1]});
		} elsif ($triple->[0] eq 'GRAPH') {
			push(@triples, @{$triple->[2]});
			if ($triple->[1][0] eq 'URI') {
				$triple->[1]	= $bridge->new_resource( $triple->[1][1] );
			}
		} elsif ($triple->[0] eq 'TIME') {
			push(@triples, @{$triple->[2]});
			if ($triple->[1][0] eq 'URI') {
				$triple->[1]	= $bridge->new_resource( $triple->[1][1] );
			}
		} elsif ($triple->[0] eq 'UNION') {
			push(@triples, @{$triple->[1]});
			push(@triples, @{$triple->[2]});
		} elsif ($triple->[0] eq 'FILTER') {
			my @constraints	= ($triple->[1]);
			while (my $data = shift @constraints) {
				_debug( "FIXING CONSTRAINT DATA: " . Dumper($data), 2 ) if (DEBUG);
				if (reftype($data) eq 'ARRAY') {
					my ($op, @rest)	= @$data;
					if ($op eq 'URI') {
						$data->[1]	= $self->qualify_uri( $data );
						_debug( "FIXED: " . $data->[1], 2 );
					} elsif ($op eq 'LITERAL') {
						no warnings 'uninitialized';
						if (reftype($data->[3]) eq 'ARRAY' and $data->[3][0] eq 'URI') {
							$data->[3][1]	= $self->qualify_uri( $data->[3] );
						}
					} elsif ($op !~ /^(VAR|LITERAL)$/) {
						push(@constraints, @rest);
					}
				}
			}
		} elsif ($triple->[0] eq 'MULTI') {
			warn "MULTI: " . Dumper($triple) if ($debug);
			foreach my $i (1 .. $#{ $triple }) {
				push(@triples, $triple->[ $i ]);
			}
		} else {
			my @vars	= map { $_->[1] }
							grep { ref($_) and reftype($_) eq 'ARRAY' and $_->[0] eq 'VAR' }
								@{ $triple };
			foreach my $var (@vars) {
				$known_variables{ $var }++
			}
			
			$self->fixup_triple_bridge_variables( $triple );
		}
	}
	
	## SELECT * implies selecting all known variables
	no warnings 'uninitialized';
	$self->{known_variables}	= [ map { ['VAR', $_] } (keys %known_variables) ];
	if ($parsed->{variables}[0] eq '*') {
		$parsed->{variables}	= $self->{known_variables};
	}
	
	
	## DEFAULT METHOD TO 'SELECT'
	$parsed->{'method'}	||= 'SELECT';
	
	## CONSTRUCT HAS IMPLICIT VARIABLES
	if ($parsed->{'method'} eq 'CONSTRUCT') {
		my %seen;
		foreach my $triple (@{ $parsed->{'construct_triples'} }) {
			$self->fixup_triple_bridge_variables( $triple );
		}
		foreach my $triple (@{ $parsed->{'triples'} }) {
			my @nodes	= @{ $triple };
			foreach my $node (@nodes) {
				if (reftype($node) eq 'ARRAY' and $node->[0] eq 'VAR') {
					push(@{ $parsed->{'variables'} }, ['VAR', $node->[1]]) unless ($seen{$node->[1]}++);
				}
			}
		}
	}
	
	return $parsed;
}

=begin private

=item C<fixup_triple_bridge_variables ()>

Called by C<fixup()> to replace URIs and strings with model-specific objects.

=end private

=cut

sub fixup_triple_bridge_variables {
	my $self	= shift;
	my $triple	= shift;
	my ($sub,$pred,$obj)	= @{ $triple };
	
	Carp::cluck "No predicate in triple passed to fixup_triple_bridge_variable: " . Dumper($triple) unless ref($pred);
	
	if (reftype($pred) eq 'ARRAY' and $pred->[0] eq 'URI') {
		my $preduri		= $self->qualify_uri( $pred );
		$triple->[1]	= $self->bridge->new_resource($preduri);
	}
	
	if (reftype($sub) eq 'ARRAY' and $sub->[0] eq 'URI') {
		my $resource	= $self->qualify_uri( $sub );
		$triple->[0]	= $self->bridge->new_resource($resource);
#	} elsif (reftype($sub) eq 'ARRAY' and $sub->[0] eq 'BLANK') {
#		my $blank		= $self->bridge->new_blank($sub->[1]);
#		$triple->[0]	= $blank;
	}
	
# XXX THIS CONDITIONAL SHOULD ALWAYS BE TRUE ... ? (IT IS IN ALL TEST CASES)
#	if (ref($obj)) {
		if (reftype($obj) eq 'ARRAY' and $obj->[0] eq 'LITERAL') {
			no warnings 'uninitialized';
			if (reftype($obj->[3]) eq 'ARRAY' and $obj->[3][0] eq 'URI') {
				$obj->[3]	= $self->qualify_uri( $obj->[3] );
			}
			my $literal		= $self->bridge->new_literal(@{$obj}[ 1 .. $#{$obj} ]);
			$triple->[2]	= $literal;
		} elsif (reftype($obj) eq 'ARRAY' and $obj->[0] eq 'URI') {
			my $resource	= $self->qualify_uri( $obj );
			$triple->[2]	= $self->bridge->new_resource($resource);
		}
#	} else {
#		warn "Object not a reference: " . Dumper($obj) . ' ';
#	}
}

=begin private

=item C<query_more ( bound => $bound, triples => \@triples )>

Internal recursive query function to bind pivot variables until only result
variables are left and found from the RDF store. Called from C<query>.

=end private

=cut
sub query_more {
	my $self	= shift;
	my %args	= @_;
	
	my $bound		= delete($args{bound});
	my $triples		= delete($args{triples});
	my $context		= $args{context};
	my $variables	= $args{variables};
	
	my @triples		= @{$triples};
# 	if ($debug > 0.1) {
# 		warn 'query_more: ' . Data::Dumper->Dump([\@triples, $bound], [qw(triples bound)]);
# 		warn "with context: " . Dumper($context) if ($context);
# 	}
	our $indent;

	my $parsed		= $self->parsed;
	my $bridge		= $self->bridge;
	
	if (@triples) {
		if ($triples[0][0] eq 'GGP') {
			return $self->groupgraphpattern( bound => $bound, triples => \@triples, %args );
		} elsif ($triples[0][0] eq 'OPTIONAL') {
			return $self->optional( bound => $bound, triples => \@triples, %args );
		} elsif ($triples[0][0] eq 'GRAPH') {
			if ($context) {
				throw RDF::Query::Error::QueryPatternError ( -text => "Can't use nested named graphs" );
			} else {
				return $self->named_graph( bound => $bound, triples => \@triples, variables => $variables );
			}
		} elsif ($triples[0][0] eq 'TIME') {
			$triples[0][0]	= 'GRAPH';
			return $self->named_graph( bound => $bound, triples => \@triples, variables => $variables );
		} elsif ($triples[0][0] eq 'FILTER') {
			my $data	= shift(@triples);
			my $filter	= [ 'FUNCTION', ['URI', 'sop:boolean'], $data->[1] ];
			
			my $filter_value	= $self->check_constraints( $bound, $filter );
			
			if ($filter_value) {
				return $self->query_more( bound => $bound, triples => \@triples, variables => $variables );
			} else {
				return sub { undef };
			}
		} elsif ($triples[0][0] eq 'UNION') {
			return $self->union( bound => $bound, triples => \@triples, %args );
#		} elsif ($triples[0][0] eq 'MULTI') {
#			return $self->multi( bound => $bound, triples => \@triples, %args );
		}
	} else {
		# no more triples. return what we've got.
#		my @values	= map { $bound->{$_} } @$variables;
#		my @rows	= [@values];
		my @rows	= {%$bound};
		return sub { shift(@rows) };
	}
	
	
# 	if ($bridge->supports('multi_get') and scalar(@triples) == 4) {
# 		try {
# 			my $iter	= $bridge->multi_get( triples => [@triples] );
# 			warn $iter;
# 		} catch RDF::Query::Error::SimpleQueryPatternError with {
# 			my $e	= shift;
# #			warn "caught $e";
# 		};
# 	}
	
	
	my $triple		= shift(@triples);
	my @triple		= @{ $triple };
	
	no warnings 'uninitialized';
	if (DEBUG) {
		_debug( "${indent}query_more: " . join(' ', map { (($bridge->is_node($_)) ? '<' . $bridge->as_string($_) . '>' : (reftype($_) eq 'ARRAY') ? $_->[1] : Dumper($_)) } @triple) . "\n" );
		_debug( "${indent}-> with " . scalar(@triples) . " triples to go\n" );
		_debug( "${indent}-> more: " . (($_->[0] =~ $KEYWORD_RE) ? "$1 block" : join(' ', map { $bridge->is_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
	}
	
	my $vars	= 0;
	my ($var, $method);
	my (@vars, @methods);
	
	my @methodmap	= $bridge->statement_method_map;
	for my $idx (0 .. 2) {
		_debug( "looking at triple " . $methodmap[ $idx ] );
		my $data	= $triple[$idx];
		if (reftype($data) eq 'ARRAY') {	# and $data->[0] eq 'VAR'
			if ($data->[0] eq 'VAR' or $data->[0] eq 'BLANK') {
				my $tmpvar	= ($data->[0] eq 'VAR') ? $data->[1] : '_' . $data->[1];
				my $val		= $bound->{ $tmpvar };
				if ($bridge->is_node($val)) {
					_debug( "${indent}-> already have value for $tmpvar: " . $bridge->as_string( $val ) . "\n" );
					$triple[$idx]	= $val;
				} else {
					++$vars;
					_debug( "${indent}-> found variable $tmpvar (we've seen $vars variables already)\n" );
					$triple[$idx]	= undef;
					$vars[$idx]		= $tmpvar;
					$methods[$idx]	= $methodmap[ $idx ];
				}
			}
		}
	}
	
	if (DEBUG) {
		_debug( "${indent}getting: " . join(', ', grep defined, @vars) . "\n" );
		_debug( 'query_more triple: ' . Dumper([map { blessed($_) ? $bridge->as_string($_) : ($_) ? Dumper($_) : 'undef' } (@triple, (($bridge->is_node($context)) ? $context : ()))]) );
	}
	
	my @graph;
	if (ref($context) and reftype($context) eq 'ARRAY' and ($context->[0] eq 'VAR')) {
		# if we're in a GRAPH ?var {} block...
		my $context_var	= $context->[1];
		my $graph		= $bound->{ $context_var };
		if ($graph) {
			# and ?var has already been bound, get the bound value and pass that on
			@graph	= $graph;
		}
	} elsif ($bridge->is_node( $context )) {
		# if we're in a GRAPH <uri> {} block, just pass it on
		@graph	= $context;
	}
	
	my $stream;
	my @streams;
	
	my $statments	= $bridge->get_statements( @triple, @graph );
	if ($statments) {
		push(@streams, sub {
			my $result;
			_debug_closure( $statments );
			my $stmt	= $statments->current();
			unless ($stmt) {
				_debug( 'no more statements' );
				$statments	= undef;
				return undef;
			}
			
			my $context_var;
			if (ref($context) and reftype($context) eq 'ARRAY' and ($context->[0] eq 'VAR')) {
				# if we're in a GRAPH ?var {} block, bind the current context to ?var
				warn "Trying to get context of current statement..." if ($debug);
				my $graph	= $statments->context;
				if ($graph) {
					$context_var				= $context->[1];
					$bound->{ $context_var }	= $graph;
					_debug( "Got context ($context_var) from iterator: " . $bridge->as_string( $graph ) );
				} else {
					_debug( "No context returned by iterator." );
				}
			}
			
			$statments->next;
			if ($vars) {
				my %private_bound;
				foreach (0 .. $#vars) {
					_debug( "looking at variable $_" );
					next unless defined($vars[$_]);
					my $var		= $vars[ $_ ];
					my $method	= $methods[ $_ ];
					_debug( "${indent}-> got variable $var = " . $bridge->as_string( $stmt->$method() ) . "\n" );
					if (defined($private_bound{$var})) {
						_debug( "${indent}-> uh oh. $var has been defined more than once.\n" );
						if ($bridge->as_string( $stmt->$method() ) eq $bridge->as_string( $private_bound{$var} )) {
							_debug( "${indent}-> the two values match. problem avoided.\n" );
						} else {
							_debug( "${indent}-> the two values don't match. this triple won't work.\n" );
							_debug( "${indent}-> the existing value is" . $bridge->as_string( $private_bound{$var} ) . "\n" );
							return ();
						}
					} else {
						$private_bound{ $var }	= $stmt->$method();
					}
				}
				@{ $bound }{ keys %private_bound }	= values %private_bound;
			} else {
				_debug( "${indent}-> triple with no variable. ignoring.\n" );
			}
			
			if (scalar(@triples)) {
				if (DEBUG) {
					_debug( "${indent}-> now for more triples...\n" );
					_debug( "${indent}-> more: " . (($_->[0] =~ $KEYWORD_RE) ? "$1 block" : join(' ', map { $bridge->is_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
					_debug( "${indent}-> " . Dumper(\@triples) );
				}
				
				$indent	.= '  ';
				_debug( 'adding a new stream for more triples' );
				unshift(@streams, $self->query_more( bound => { %{ $bound } }, triples => [@triples], variables => $variables, ($context ? (context => $context ) : ()) ) );
			} else {
				my @values	= map { $bound->{$_} } @$variables;
				_debug( "${indent}-> no triples left: result: " . join(', ', map {$bridge->as_string($_)} grep defined, @values) . "\n" );
				$result	= {%$bound};
			}
			
			foreach my $var (@vars) {
				if (defined($var)) {
					_debug( "deleting value for $var" );
					delete $bound->{ $var };
				}
			}
			
			if ($context_var) {
				_debug( "deleting context value for $context_var" );
				delete $bound->{ $context_var };
			}
			
			if ($result) {
				if (DEBUG) {
					local($Data::Dumper::Indent)	= 0;
					_debug( 'found a result: ' . Dumper($result) );
				}
				
				return ($result);
			} else {
				_debug( 'no results yet...' );
				return ();
			}
		} );
	}
	
	substr($indent, -2, 2)	= '';
	
	return sub {
		_debug( 'query_more closure with ' . scalar(@streams) . ' streams' );
		while (@streams) {
			_debug( '-> fetching from stream ' . $streams[0] );
			_debug_closure( $streams[0] );
			
			my @val	= $streams[0]->();
			_debug( '-> ' . (@val ? 'got' : 'no') . ' value' );
			if (@val) {
				_debug( '-> "' . $val[0] . '"', 1, 1);
				if (defined $val[0]) {
					return $val[0];
				}
			} else {
				_debug( '-> no value returned from stream. using next stream.', 1);
				next;
			}
			shift(@streams);
		}

		_debug( '-> no more streams.', 1);
		return undef;
	};	
}

=begin private

=item C<union ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle UNION queries.
Calls C<query_more()> with each UNION branch, and returns an aggregated data stream.

=end private

=cut

sub union {
	my $self		= shift;
	my %args	= @_;
	
	my $bound	= delete($args{bound});
	my $triples	= delete($args{triples});
	my $context	= $args{context};
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my $parsed		= $self->parsed;
	my @streams;
	foreach my $u_triples (@{ $triple }[1 .. $#{$triple}]) {
		my $stream	= $self->query_more( bound => { %{ $bound } }, triples => [@{ $u_triples }, @triples], %args );
		push(@streams, $stream);
	}
	return sub {
		while (@streams) {
			_debug_closure( $streams[0] );
			my @val	= $streams[0]->();
			if (@val) {
				return $val[0] if defined($val[0]);
			} else {
				next;
			}
			shift(@streams);
		}
		return undef;
	};	
}

# =begin private
# 
# =item C<multi ( bound => \%bound, triples => \@triples )>
# 
# Called by C<query_more()> to handle multi-get queries (where multiple triples
# have been combined into one functional unit). Returns by calling C<query_more()>
# with any remaining triples.
# 
# =end private
# 
# =cut
# 
# sub multi {
# 	my $self		= shift;
# 	my %args	= @_;
# 	
# 	my $bound	= delete($args{bound});
# 	my $triples	= delete($args{triples});
# 	my $context	= $args{context};
# 	
# 	my @triples	= @{$triples};
# 	my $multi	= shift(@triples);
# 	
# 	my $bridge	= $self->bridge;
# 	my $stream	= $bridge->multi_get( triples => [ @{ $multi }[ 1 .. $#{ $multi } ] ] );
# 	
# 	my $closed	= 0;
# 	my $more_stream;
# 	my $multi_bindings; #	= $stream->next;
# 	return sub {
# 		while (1) {
# 			if (not($more_stream)) {
# 				$multi_bindings	= $stream->next;
# 				if ($multi_bindings) {
# 					$more_stream	= $self->query_more( bound => { %{ $bound }, %{ $multi_bindings } }, triples => [@triples], %args );
# 				} else {
# 					$closed	= 1;
# 					undef $stream;
# 				}
# 			}
# 			
# 			return undef if ($closed);
# 			my $value	= $more_stream->();
# 			if ($value) {
# 				return $value;
# 			} else {
# 				undef $more_stream;
# 			}
# 		}
# 	};
# }

=begin private

=item C<optional ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle OPTIONAL query patterns.
Calls C<query_more()> with the OPTIONAL pattern, binding variables if the
pattern succeeds. Returns by calling C<query_more()> with any remaining triples.

=end private

=cut

sub optional {
	my $self	= shift;
	my %args	= @_;

	my $bound		= delete($args{bound});
	my $triples		= delete($args{triples});
	my $variables	= delete $args{variables};
	my $context		= $args{context};
	
	my @triples		= @{$triples};
	my $triple		= shift(@triples);
	
	my $parsed		= $self->parsed;
	
	my @triple		= @{ $triple };
	my @opt_triples	= @{ $triple[1] };
	
	my @known		= $self->all_variables;
	my $ostream		= $self->query_more( bound => { %{ $bound } }, triples => [@opt_triples], variables => \@known, %args );
	$ostream		= RDF::Query::Stream->new(
					$ostream,
					'bindings',
					\@known,
					bridge => $self->bridge
				);
	
	if ($ostream->current) {
		my $substream;
		my $current;
		my $stream	= sub {
			my %local_bound	= %$bound;
			until ($ostream->finished and not $ostream->current and not $substream) {
				if ($substream) {
					my $data	= $substream->();
					return $data if (defined $data);
					undef $substream;
				}
				
				$current	= $ostream->current;
				last unless ($current);
				$ostream->next;
				foreach my $i (0 .. $#known) {
					my $name	= $known[ $i ];
					my $value	= $current->{ $name };
					if (defined $value) {
						if (not exists $bound->{ $name }) {
							$local_bound{ $name }	= $value;
							_debug( "Setting $name = " . $value->as_string . "\n" );
						} else {
							_debug( "Existing value for $name = " . $bound->{ $name }->as_string . "\n" );
						}
					} else {
	#						warn "$name wasn't defined\n";
					}
				}
				$substream	= $self->query_more( bound => { %local_bound }, triples => [@triples], variables => $variables, %args );
			}
			
			return undef;
		};
		return $stream;
	} else {
		return $self->query_more( bound => { %{ $bound } }, triples => [@triples], variables => $variables, %args );
	}
}


=begin private

=item C<groupgraphpattern ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle GroupGraphPattern query patterns (groups
of triples surrounded by '{ }'). Calls C<query_more()> with the GGP.
Returns by calling C<query_more()> with any remaining triples.

=end private

=cut

sub groupgraphpattern {
	my $self		= shift;
	my %args		= @_;
	
	my $bound		= { %{ delete($args{bound}) } };
	my $triples		= delete($args{triples});
	my $variables	= $args{variables};
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my $parsed		= $self->parsed;
	
	my (undef, $ggp_triples)	= @{ $triple };
	my @ggp_triples	= @{ $ggp_triples };
	
	my $ggpstream	= $self->query_more( bound => $bound, triples => \@ggp_triples, variables => $variables, %args );
	if (@triples) {
		_debug( "with more triples to match." );
		my $stream;
		return sub {
			while ($ggpstream or $stream) {
				if (ref($stream)) {
					my $data	= $stream->();
					if ($data) {
						return $data;
					} else {
						undef $stream;
					}
				}
				
				if ($ggpstream) {
					my $data	= $ggpstream->();
					if ($data) {
						foreach my $i (0 .. $#{ $variables }) {
							my $name	= $variables->[ $i ];
							my $value	= $data->{ $name };
							if (defined $value) {
								$bound->{ $name }	= $value;
								_debug( "Setting $name from named graph = $value\n" );
							}
						}
						$stream	= $self->query_more( bound => $bound, triples => \@triples, variables => $variables );
					} else {
						undef $ggpstream;
					}
				}
			}
			return undef;
		};
	} else {
		_debug( "No more triples. Returning NAMED stream." );
		return $ggpstream;
	}
}


=begin private

=item C<named_graph ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle NAMED graph query patterns.
Matches graph context (binding the graph to a variable if applicable).
Returns by calling C<query_more()> with any remaining triples.

=end private

=cut

sub named_graph {
	my $self		= shift;
	my %args		= @_;
	
	my $bound		= { %{ delete($args{bound}) } };
	my $triples		= delete($args{triples});
	my $variables	= $args{variables};
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my $parsed		= $self->parsed;
	
	my (undef, $context, $named_triples)	= @{ $triple };
	my @named_triples	= @{ $named_triples };
	
	_debug( 'named triples: ' . Dumper(\@named_triples), 1 ) if (DEBUG);
	my $nstream	= $self->query_more( bound => $bound, triples => \@named_triples, variables => $variables, context => $context );
	
	_debug( 'named stream: ' . $nstream, 1 );
	_debug_closure( $nstream );
	
	_debug( 'got named stream' );
	if (@triples) {
		_debug( "with more triples to match." );
		my $stream;
		return sub {
			while ($nstream or $stream) {
				if (ref($stream)) {
					my $data	= $stream->();
					if ($data) {
						return $data;
					} else {
						undef $stream;
					}
				}
				
				if ($nstream) {
					my $data	= $nstream->();
					if ($data) {
						foreach my $i (0 .. $#{ $variables }) {
							my $name	= $variables->[ $i ];
							my $value	= $data->{ $name };
							if (defined $value) {
								$bound->{ $name }	= $value;
								_debug( "Setting $name from named graph = $value\n" );
							}
						}
						$stream	= $self->query_more( bound => $bound, triples => \@triples, variables => $variables );
					} else {
						undef $nstream;
					}
				}
			}
			return undef;
		};
	} else {
		_debug( "No more triples. Returning NAMED stream." );
		return $nstream;
	}
}

=begin private

=item C<qualify_uri ( [ 'URI', [ $prefix, $localPart ] ] )>

=item C<qualify_uri ( [ 'URI', $uri )>

Returns a full URI given the URI data structure passed as an argument.
For already-qualified URIs, simply returns the URI.
For QNames, looks up the QName prefix in the parse-tree namespaces, and
concatenates with the QName local part.

=end private

=cut

sub qualify_uri {
	my $self	= shift;
	my $data	= shift;
	if (ref($data) and reftype($data) eq 'ARRAY') {
		if ($data->[0] ne 'URI') {
			$data	= ['URI',$data];
		}
	}
	
	my $parsed	= $self->{parsed};
	my $uri;
	if (ref($data)) {
		if (reftype($data) eq 'ARRAY' and ref($data->[1])) {
			my $prefix	= $data->[1][0];
			unless (exists($parsed->{'namespaces'}{$data->[1][0]})) {
				_debug( "No namespace defined for prefix '${prefix}'" );
			}
			my $ns	= $parsed->{'namespaces'}{$prefix};
			$uri	= join('', $ns, $data->[1][1]);
		} else {
			$uri	= $data->[1];
		}
	} else {
		$uri	= $data;
	}
	return $uri;
}

=begin private

=item C<check_constraints ( \%bound, \@data )>

Returns the value returned by evaluating the expression structures in C<@data>
with the bound variables in C<%bound>.

=end private

=cut

{
our %functions;
no warnings 'numeric';
my %dispatch	= (
					VAR		=> sub {
								my ($self, $values, $data) = @_;
								my $value	= $values->{ $data->[0] };
								return $value;
							},
					URI		=> sub { my ($self, $values, $data) = @_; return $data->[0] },
					LITERAL	=> sub {
								my ($self, $values, $data) = @_;
								if (defined($data->[2])) {
									my $uri		= $data->[2];
									my $literal	= $data->[0];
									local($self->{options}{net_filters})	= 0;
									my $func	= $self->get_function( $self->qualify_uri( $uri ) );
									if ($func) {
										my $funcdata	= [ 'FUNCTION', $uri, [ 'LITERAL', $literal ] ];
										return $self->check_constraints( $values, $funcdata );
									} else {
										warn "no conversion function found for " . $self->qualify_uri( $uri ) if ($debug);	# XXX
									}
								}
								return $data->[0];
							},
					'~~'	=> sub {
								my ($self, $values, $data) = @_;
								my $bridge	= $self->bridge;
								my $text	= $self->check_constraints( $values, $data->[0] );
								my $pattern	= $self->check_constraints( $values, $data->[1] );
								if (scalar(@$data) == 3) {
									my $flags	= $self->get_value( $self->check_constraints( $values, $data->[2] ) );
									if ($flags !~ /^[smix]*$/) {
										throw RDF::Query::Error::FilterEvaluationError ( -text => 'REGEX() called with unrecognized flags' );
									}
									$pattern	= qq[(?${flags}:$pattern)];
								}
								if ($bridge->is_literal($text)) {
									$text	= $bridge->literal_value( $text );
								} elsif (blessed($text)) {
									throw RDF::Query::Error::TypeError ( -text => 'REGEX() called with non-string data' );
								}
								
								return ($text =~ /$pattern/)
							},
					'=='	=> sub {
								my ($self, $values, $data) = @_;
								my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data };
								my $eq	= ncmp($operands[0], $operands[1]) == 0;
								return $eq;
							},
					'!='	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data }; return ncmp($operands[0], $operands[1]) != 0 },
					'<'		=> sub {
								my ($self, $values, $data) = @_;
								my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data };
								return ncmp($operands[0], $operands[1]) == -1;
							},
					'>'		=> sub {
								my ($self, $values, $data) = @_;
								my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data };
								return ncmp($operands[0], $operands[1]) == 1;
							},
					'<='	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data }; return ncmp($operands[0], $operands[1]) != 1 },
					'>='	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data }; return ncmp($operands[0], $operands[1]) != -1 },
					'&&'	=> sub {
								my ($self, $values, $data) = @_;
								my @results;
								foreach my $part (@{ $data }) {
									my $error;
									my $value;
									try {
										$value	= $functions{'sop:boolean'}->( $self, $self->check_constraints( $values, $part ) );
										push(@results, $value);
									} catch RDF::Query::Error::FilterEvaluationError with {
										$error	= shift;
										push(@results, $error);
									};
									return 0 if (not $error and not $value);
								}
								
								if ($results[0] and $results[1]) {
									return 1;
								} else {
									foreach my $r (@results) {
										throw $r if (ref($r) and $r->isa('RDF::Query::Error'));
									}
									throw RDF::Query::Error::FilterEvaluationError;
								}
							},
					'||'	=> sub {
								my ($self, $values, $data) = @_;
								my $error;
								foreach my $part (@{ $data }) {
									my $value;
									try {
										$value	= $functions{'sop:boolean'}->( $self, $self->check_constraints( $values, $part ) );
									} catch RDF::Query::Error::FilterEvaluationError with {
										$error	= shift;
										$value	= 0;
									};
									
									return 1 if ($value);
								}
								
								if ($error) {
									throw $error;
								} else {
									return 0;
								}
							},
					'*'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $functions{'sop:numeric'}->( $self, $self->check_constraints( $values, $_ ) ) } @{ $data }; return $operands[0] * $operands[1] },
					'/'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $functions{'sop:numeric'}->( $self, $self->check_constraints( $values, $_ ) ) } @{ $data }; return $operands[0] / $operands[1] },
					'+'		=> sub { my ($self, $values, $data) = @_; my @operands = map { $functions{'sop:numeric'}->( $self, $self->check_constraints( $values, $_ ) ) } @{ $data }; return $operands[0] + $operands[1] },
					'-'		=> sub {
								my ($self, $values, $data) = @_;
								my @operands	= map { $functions{'sop:numeric'}->( $self, $self->check_constraints( $values, $_ ) ) } @{ $data };
								if (1 == @operands) {
									return -1 * $operands[0];
								} else {
									return $operands[0] - $operands[1]
								}
							},
					'!'		=> sub {
								my ($self, $values, $data) = @_;
								my $value	= $self->check_constraints( $values, $data->[0] );
								if (defined $value) {
									return not $functions{'sop:boolean'}->( $self, $value );
								} else {
									throw RDF::Query::Error::TypeError ( -text => 'Cannot negate an undefined value' );
								}
							},
					'FUNCTION'	=> sub {
						our %functions;
						my ($self, $values, $data) = @_;
						my $uri		= $self->qualify_uri( $data->[0][1] );
						my $func	= $self->get_function( $uri );
						if ($func) {
							$self->{'values'}	= $values;
							my @args	= map {
												($_->[0] eq 'VAR')
													? $values->{ $_->[1] }
													: $self->check_constraints( $values, $_ )
											} @{ $data }[1..$#{ $data }];
							my $value	= $func->(
											$self,
											@args
										);
							{ no warnings 'uninitialized';
								_debug( "function <$uri> -> $value" );
							}
							return $value;
						} else {
							warn "No function defined for <${uri}>\n";
							Carp::cluck if ($::counter++ > 5);
							return undef;
						}
					},
				);
sub check_constraints {
	my $self	= shift;
	my $values	= shift;
	my $data	= shift;
	
	_debug( 'check_constraints: ' . Dumper($data), 2 ) if (DEBUG);
	return 1 unless scalar(@$data);
	my $op		= $data->[0];
	my $code	= $dispatch{ $op };
	
	if ($code) {
#		local($Data::Dumper::Indent)	= 0;
		my $result;
		try {
			$result	= $code->( $self, $values, [ @{$data}[1..$#{$data}] ] );
		} catch RDF::Query::Error::FilterEvaluationError with {
			$result	= undef;
		} catch RDF::Query::Error::TypeError with {
			$result	= undef;
		};
		_debug( "OP: $op -> " . Dumper($data), 2 ) if (DEBUG);
#		warn "RESULT: " . $result . "\n\n";
		return $result;
	} else {
		confess "OPERATOR $op NOT IMPLEMENTED!";
	}
}
}

=begin private

=item C<get_value ( $value )>

Returns the scalar value (string literal, URI value, or blank node identifier)
for the specified model-specific node object.

=end private

=cut

sub get_value {
	my $self	= shift;
	my $value	= shift;
	my $bridge	= $self->bridge;
	if (ref($value) and $value->isa('DateTime')) {
		return $value;
		return $self->{dateparser}->format_datetime($value);
	} elsif ($bridge->is_resource($value)) {
		return $bridge->uri_value( $value );
	} elsif ($bridge->is_literal($value)) {
		my $literal	= $bridge->literal_value( $value );
		if (my $dt = $bridge->literal_datatype( $value )) {
			return [$literal, undef, $dt]
		} elsif (my $lang = $bridge->literal_value_language( $value )) {
			return [$literal, $lang, undef];
		} else {
			return $literal;
		}
	} elsif ($bridge->is_blank($value)) {
		return $bridge->blank_identifier( $value );
	} else {
		return $value;
	}
}

=item C<add_function ( $uri, $function )>

Associates the custom function C<$function> (a CODE reference) with the
specified URI, allowing the function to be called by query FILTERs.

=cut

sub add_function {
	my $self	= shift;
	my $uri		= shift;
	my $code	= shift;
	if (ref($self)) {
		$self->{'functions'}{$uri}	= $code;
	} else {
		our %functions;
		$RDF::Query::functions{ $uri }	= $code;
	}
}

=begin private

=item C<get_function ( $uri )>

If C<$uri> is associated with a query function, returns a CODE reference
to the function. Otherwise returns C<undef>.

=end private

=cut

sub get_function {
	my $self	= shift;
	my $uri		= shift;
	warn "trying to get function from $uri" if ($debug);
	
	my $func	= $self->{'functions'}{$uri}
				|| $RDF::Query::functions{ $uri };
	if ($func) {
		return $func;
	} elsif ($self->{options}{net_filters}) {
		return $self->net_filter_function( $uri );
	}
	return;
}


=item C<< net_filter_function ( $uri ) >>

Takes a URI specifying the location of a javascript implementation.
Returns a code reference implementing the javascript function.

If the 'trusted_keys' option is set, a GPG signature at ${uri}.asc is
retrieved and verified against the arrayref of trusted key fingerprints.
A code reference is returned only if a trusted signature is found.

=cut

sub net_filter_function {
	my $self	= shift;
	my $uri		= shift;
	warn "fetching $uri\n" if ($debug);
	
	my $bridge	= $self->new_bridge();
	$bridge->add_uri( $uri );
	
	my $subj	= $bridge->new_resource( $uri );
	
	my $func	= do {
		my $pred	= $bridge->new_resource('http://www.mindswap.org/~gtw/sparql#function');
		my $stream	= $bridge->get_statements( $subj, $pred, undef );
		my $st		= $stream->();
		my $obj		= $bridge->object( $st );
		my $func	= $bridge->literal_value( $obj );
	};
	
	my $impl	= do {
		my $pred	= $bridge->new_resource('http://www.mindswap.org/~gtw/sparql#source');
		my $stream	= $bridge->get_statements( $subj, $pred, undef );
		my $st		= $stream->();
		my $obj		= $bridge->object( $st );
		my $impl	= $bridge->uri_value( $obj );
	};
	
	my $resp	= URI::Fetch->fetch( $impl ) or die URI::Fetch->errstr;
	unless ($resp->is_success) {
		warn "No content available from $uri";
		return;
	}
	my $content	= $resp->content;
	
	if ($self->{options}{trusted_keys}) {
		my $gpg		= $self->{_gpg_obj} || new Crypt::GPG;
		$gpg->gpgbin('/sw/bin/gpg');
		$gpg->secretkey($self->{options}{secretkey} || $ENV{GPG_KEY} || '0xCAA8C82D');
		my $keyring	= exists($self->{options}{keyring})
					? $self->{options}{keyring}
					: File::Spec->catfile($ENV{HOME}, '.gnupg', 'pubring.gpg');
		$gpg->gpgopts("--lock-multiple --keyring " . $keyring);
		
		my $sigresp	= URI::Fetch->fetch( "${impl}.asc" );
		if (not $sigresp) {
			throw RDF::Query::Error::ExecutionError -text => "Required signature not found: ${impl}.asc\n";
		} elsif ($sigresp->is_success) {
			my $sig		= $sigresp->content;
			my $ok	= $self->_is_trusted( $gpg, $content, $sig, $self->{options}{trusted_keys} );
			unless ($ok) {
				throw RDF::Query::Error::ExecutionError -text => "Not a trusted signature";
			}
		} else {
			throw RDF::Query::Error::ExecutionError -text => "Could not retrieve required signature: ${uri}.asc";
			return;
		}
	}

	my ($rt, $cx)	= $self->new_javascript_engine();
	my $r		= $cx->eval( $content );
	
#	die "Requested function URL does not match the function's URI" unless ($meta->{uri} eq $url);
	return sub {
		my $query	= shift;
		warn "Calling javascript function $func with: " . Dumper(\@_) if ($debug);
		my $value	= $cx->call( $func, @_ );
		warn "--> $value\n" if ($debug);
		return $value;
	};
}

sub _is_trusted {
	my $self	= shift;
	my $gpg		= shift;
	my $file	= shift;
	my $sigfile	= shift;
	my $trusted	= shift;
	
	my (undef, $sig)	= $gpg->verify($sigfile, $file);
	
	return 0 unless ($sig->validity eq 'GOOD');
	
	my $id		= $sig->keyid;
	
	my @keys	= $gpg->keydb($id);
	foreach my $key (@keys) {
		my $fp	= $key->{Fingerprint};
		$fp		=~ s/ //g;
		return 1 if (first { s/ //g; $_ eq $fp } @$trusted);
	}
	return 0;
}



=begin private

=item C<new_javascript_engine ()>

Returns a new JavaScript Runtime and Context object for running network FILTER
functions.

=end private

=cut

sub new_javascript_engine {
	my $self	= shift;
	my $rt		= JavaScript::Runtime->new();
	my $cx		= $rt->create_context();
	my $bridge	= $self->bridge;
	my $meta	= $bridge->meta;
	$cx->bind_function( 'warn' => sub { warn @_ if ($debug || $js_debug) } );
	$cx->bind_function( '_warn' => sub { warn @_ } );
	$cx->bind_function( 'makeTerm' => sub {
		my $term	= shift;
#		warn 'makeTerm: ' . Dumper($term);
		if (not blessed($term)) {
			my $node	= $bridge->new_literal( $term );
			return $node;
		} else {
			return $term;
		}
	} );
	
	my $toString	= sub {
		my $string	= $bridge->as_string( @_ ) . '';
		return $string;
	};
	
	$cx->bind_class(
		name		=> 'RDFNode',
		constructor	=> sub {},
		'package'	=> $meta->{node},
		'methods'	=> {
						is_literal	=> sub { return $bridge->is_literal( $_[0] ) },
						is_resource	=> sub { return $bridge->is_resource( $_[0] ) },
						is_blank	=> sub { return $bridge->is_blank( $_[0] ) },
						toString	=> $toString,
					},
		ps			=> {
						literal_value			=> [sub { return $bridge->literal_value($_[0]) }],
						literal_datatype		=> [sub { return $bridge->literal_datatype($_[0]) }],
						literal_value_language	=> [sub { return $bridge->literal_value_language($_[0]) }],
						uri_value				=> [sub { return $bridge->uri_value($_[0]) }],
						blank_identifier		=> [sub { return $bridge->blank_identifier($_[0]) }],
					},
	);

	if ($meta->{literal} ne $meta->{node}) {
		$cx->bind_class(
			name		=> 'RDFLiteral',
			constructor	=> sub {},
			'package'	=> $bridge->meta->{literal},
			'methods'	=> {
							is_literal	=> sub { return 1 },
							is_resource	=> sub { return 0 },
							is_blank	=> sub { return 0 },
							toString	=> $toString,
						},
			ps			=> {
							literal_value			=> [sub { return $bridge->literal_value($_[0]) }],
							literal_datatype		=> [sub { return $bridge->literal_datatype($_[0]) }],
							literal_value_language	=> [sub { return $bridge->literal_value_language($_[0]) }],
						},
		);
#		$cx->eval( 'RDFLiteral.prototype.__proto__ = RDFNode.prototype;' );
	}
	if ($meta->{resource} ne $meta->{node}) {
		$cx->bind_class(
			name		=> 'RDFResource',
			constructor	=> sub {},
			'package'	=> $bridge->meta->{resource},
			'methods'	=> {
							is_literal	=> sub { return 0 },
							is_resource	=> sub { return 1 },
							is_blank	=> sub { return 0 },
							toString	=> $toString,
						},
			ps			=> {
							uri_value				=> [sub { return $bridge->uri_value($_[0]) }],
						},
		);
#		$cx->eval( 'RDFResource.prototype.__proto__ = RDFNode.prototype;' );
	}
	if ($meta->{blank} ne $meta->{node}) {
		$cx->bind_class(
			name		=> 'RDFBlank',
			constructor	=> sub {},
			'package'	=> $bridge->meta->{blank},
			'methods'	=> {
							is_literal	=> sub { return 0 },
							is_resource	=> sub { return 0 },
							is_blank	=> sub { return 1 },
							toString	=> $toString,
						},
			ps			=> {
							blank_identifier		=> [sub { return $bridge->blank_identifier($_[0]) }],
						},
		);
#		$cx->eval( 'RDFBlank.prototype.__proto__ = RDFNode.prototype;' );
	}
	
	
	return ($rt, $cx);
}

=item C<add_hook ( $uri, $function )>

Associates the custom function C<$function> (a CODE reference) with the
RDF::Query code hook specified by C<$uri>. Each function that has been
associated with a particular hook will be called (in the order they were
registered as hooks) when the hook event occurs. See L</"Defined Hooks">
for more information.

=cut

sub add_hook {
	my $self	= shift;
	my $uri		= shift;
	my $code	= shift;
	if (ref($self)) {
		push(@{ $self->{'hooks'}{$uri} }, $code);
	} else {
		our %hooks;
		push(@{ $RDF::Query::hooks{ $uri } }, $code);
	}
}

=begin private

=item C<get_hooks ( $uri )>

If C<$uri> is associated with any query callback functions ("hooks"),
returns an ARRAY reference to the functions. If no hooks are associated
with C<$uri>, returns a reference to an empty array.

=end private

=cut

sub get_hooks {
	my $self	= shift;
	my $uri		= shift;
	my $func	= $self->{'hooks'}{$uri}
				|| $RDF::Query::hooks{ $uri }
				|| [];
	return $func;
}

=begin private

=item C<run_hook ( $uri, @args )>

Calls any query callback functions associated with C<$uri>. Each callback
is called with the query object as the first argument, followed by any
caller-supplied arguments from C<@args>.

=end private

=cut

sub run_hook {
	my $self	= shift;
	my $uri		= shift;
	my @args	= @_;
	my $hooks	= $self->get_hooks( $uri );
	foreach my $hook (@$hooks) {
		$hook->( $self, @args );
	}
}

=begin private

=item C<ncmp ( $value )>

General-purpose sorting function for both numbers and strings.

=end private

=cut

sub ncmp ($$) {
	my ($a, $b)	= @_;
#	for ($a, $b) {
#		throw RDF::Query::Error::FilterEvaluationError ( -text => 'Cannot sort undefined values' ) unless defined($_);
#	}
	
	my $get_value	= sub {
		my $node	= shift;
		if (ref($node) and reftype($node) eq 'ARRAY') {
			return $node->[0];
		} else {
			return $node;
		}
	};
	
	my $get_type	= sub {
		my $node	= shift;
		if (ref($node) and reftype($node) eq 'ARRAY') {
			return $node->[2];
		} else {
			return;
		}
	};
	
	no warnings 'uninitialized';
	my $numeric	= sub { my $val = $get_value->($_[0]); return (blessed($val)) ? $val->isa('DateTime') : (is_numeric_type($get_type->($_[0])) or looks_like_number($val)); };
	my $num_cmp	= ($numeric->($a) and $numeric->($b));
	my $cmp		= ($num_cmp)
				? ($get_value->($a) <=> $get_value->($b))
				: ($get_value->($a) cmp $get_value->($b));
	return $cmp;
}

=begin private

=item C<is_numeric_type ( $type )>

Returns true if the specified C<$type> URI represents a numeric type.
This includes XSD numeric, double and integer types.
	
=end private

=cut

sub is_numeric_type {
	my $type	= shift || '';
	return $type =~ m<^http://www.w3.org/2001/XMLSchema#(numeric|double|integer)>;
}

=begin private

=item C<sort_rows ( $nodes, $parsed )>

Called by C<execute> to handle result forms including:
	* Sorting results
	* Distinct results
	* Limiting result count
	* Offset in result set
	
=end private

=cut

sub sort_rows {
	my $self	= shift;
	my $nodes	= shift;
	my $parsed	= shift;
	my $bridge	= $self->bridge;
	my $args		= $parsed->{options} || {};
	my $limit		= $args->{'limit'};
	my $unique		= $args->{'distinct'};
	my $orderby		= $args->{'orderby'};
	my $offset		= $args->{'offset'} || 0;
	my @variables	= $self->variables( $parsed );
	my %colmap		= map { $variables[$_] => $_ } (0 .. $#variables);
	
	if ($unique or $orderby or $offset or $limit) {
		_debug( 'sort_rows column map: ' . Dumper(\%colmap) ) if (DEBUG);
	}
	
	if ($unique) {
		my %seen;
		my $old	= $nodes;
		$nodes	= sub {
			while (my $row = $old->()) {
				no warnings 'uninitialized';
				my $key	= join($;, map {$bridge->as_string( $_ )} map { $row->{$_} } @variables);
				next if $seen{ $key }++;
				return $row;
			}
		};
	}
	
	if ($orderby) {
		my $cols		= $args->{'orderby'};
		my ($dir, $data)	= @{ $cols->[0] };
#		warn Dumper($data);
		if ($dir ne 'ASC' and $dir ne 'DESC') {
			warn "Direction of sort not recognized: $dir";
			$dir	= 'ASC';
		}
		
		my $col				= $data;
		my $colmap_value	= $colmap{$col};
		_debug( "ordering by $col" );
		
		my @nodes;
		while (my $node = $nodes->()) {
			_debug( "node for sorting: " . Dumper($node) ) if (DEBUG);
			push(@nodes, $node);
		}
		
		no warnings 'numeric';
		@nodes	= map {
					my $node	= $_;
					Carp::cluck if (reftype($node) eq 'ARRAY');
					my %data	= %$node;
#					my %data	= map { $_ => $node->[ $colmap{$_} ] } (keys %colmap);
#					warn "data: " . Dumper(\%data, $data);
					my $result	= $self->check_constraints( \%data, $data );
					my $value	= $self->get_value( $result );
					[ $node, $value ]
				} @nodes;
		
		@nodes	= sort { ncmp($a->[1], $b->[1]) } @nodes;
						
		@nodes	= reverse @nodes if ($dir eq 'DESC');
		
		@nodes	= map { $_->[0] } @nodes;
		$nodes	= sub {
			my $row	= shift(@nodes);
			return $row;
		};
	}
	
	if ($offset) {
		$nodes->() while ($offset--);
	}
	
	if ($limit) {
		my $old	= $nodes;
		$nodes	= sub {
			return undef unless ($limit);
			$limit--;
			return $old->();
		};
	}
	
	return $nodes;
}

=begin private

=item C<parse_url ( $url, $named )>

Retrieve a remote file by URL, and parse RDF into the RDF store.
If $named is TRUE, associate all parsed triples with a named graph.

=end private

=cut
sub parse_url {
	my $self	= shift;
	my $url		= shift;
	my $named	= shift;
	my $bridge	= $self->bridge;
	
	$bridge->add_uri( $url, $named );
}

=begin private

=item C<variables ()>

Returns a list of the ordered variables the query is selecting.
	
=end private

=cut

sub variables {
	my $self	= shift;
	my $parsed	= shift || $self->parsed;
	my @vars	= map { $_->[1] } @{ $parsed->{'variables'} };
	return @vars;
}

=begin private

=item C<all_variables ()>

Returns a list of all variables referenced in the query.
	
=end private

=cut

sub all_variables {
	my $self	= shift;
	my $parsed	= $self->parsed;
	my @vars	= map { $_->[1] } @{ $self->{'known_variables'} };
	return @vars;
}


=item C<parsed ()>

Returns the parse tree.

=cut

sub parsed {
	my $self	= shift;
	if (@_) {
		$self->{parsed}	= shift;
	}
	return $self->{parsed};
}

=item C<error ()>

Returns the last error the parser experienced.

=cut

sub error {
	my $self	= shift;
	if (blessed($self)) {
		return $self->{error};
	} else {
		our $_ERROR;
		return $_ERROR;
	}
}

=begin private

=item C<set_error ( $error )>

Sets the object's error variable.

=end private

=cut

sub set_error {
	my $self	= shift;
	my $error	= shift;
	if (blessed($self)) {
		$self->{error}	= $error;
	}
	our $_ERROR	= $error;
}

=begin private

=item C<clear_error ()>

Clears the object's error variable.

=end private

=cut

sub clear_error {
	my $self	= shift;
	if (blessed($self)) {
		$self->{error}	= undef;
	}
	our $_ERROR;
	undef $_ERROR;
}


=begin private

=item C<_debug_closure ( $code )>

Debugging function to print out a deparsed (textual) version of a closure.
	
=end private

=cut

sub _debug_closure {
	return unless ($debug > 1);
	my $closure	= shift;
	require B::Deparse;
	my $deparse	= B::Deparse->new("-p", "-sC");
	my $body	= $deparse->coderef2text($closure);
	warn "--- --- CLOSURE --- ---\n";
	Carp::cluck $body;
}

=begin private

=item C<_debug ( $message, $level, $trace )>

Debugging function to print out C<$message> at or above the specified debugging
C<$level>, with an optional stack C<$trace>.
	
=end private

=cut

sub _debug {
	my $mesg	= shift;
	my $level	= shift	|| 1;
	my $trace	= shift || 0;
	my ($package, $filename, $line, $sub, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask)	= caller(1);
	
	$sub		=~ s/^.*://;
	chomp($mesg);
	my $output	= join(' ', $mesg, 'at', $filename, $line); # . "\n";
	if ($debug >= $level) {
		carp $output;
		if ($trace) {
			unless ($filename =~ m/Redland/) {
				warn Carp::longmess();
			}
		}
	}
}

sub AUTOLOAD {
	my $self	= $_[0];
	my $class	= ref($_[0]) || return undef;
	our $AUTOLOAD;
	return if ($AUTOLOAD =~ /:DESTROY$/);
	my $method		= $AUTOLOAD;
	$method			=~ s/^.*://;
	
	if (exists($self->{ $method })) {
		no strict 'refs';
		*$AUTOLOAD	= sub {
			my $self        = shift;
			my $class       = ref($self);
			return $self->{ $method };
		};
		goto &$method;
	} else {
		croak qq[Can't locate object method "$method" via package $class];
	}
}


our %functions;

### XSD CASTING FUNCTIONS

$functions{"http://www.w3.org/2001/XMLSchema#integer"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $value	= $bridge->literal_value( $node );
		return int($value);
	} elsif (looks_like_number($node)) {
		return int($node);
	} else {
		return 0;
	}
};

$functions{"http://www.w3.org/2001/XMLSchema#boolean"}	= sub {
	my $query	= shift;
	my $node	= shift;
	return 1 if ($node eq 'true');
	return 0 if ($node eq 'false');
	throw RDF::Query::Error::FilterEvaluationError ( -text => "'$node' is not a boolean type (true or false)" );
};

$functions{"sop:boolean"}	= sub {
	my $query	= shift;
	my $node	= shift;
	return 0 if not defined($node);
	
	if (ref($node)) {
		my $bridge	= $query->bridge;
		if ($bridge->is_literal($node)) {
			my $value	= $bridge->literal_value( $node );
			my $type	= $bridge->literal_datatype( $node );
			if ($type) {
				if ($type eq 'http://www.w3.org/2001/XMLSchema#boolean') {
#					warn "boolean-typed: $value";
					return 0 if ($value eq 'false');
					return 1 if ($value eq 'true');
					throw RDF::Query::Error::FilterEvaluationError ( -text => "'$value' is not a boolean type (true or false)" );
				} elsif ($type eq 'http://www.w3.org/2001/XMLSchema#string') {
#					warn "string-typed: $value";
					return 0 if (length($value) == 0);
					return 1;
				} elsif (is_numeric_type( $type )) {
#					warn "numeric-typed: $value";
					return ($value == 0) ? 0 : 1;
				} else {
#					warn "unknown-typed: $value";
					throw RDF::Query::Error::TypeError ( -text => "'$value' cannot be coerced into a boolean value" );
				}
			} else {
				no warnings 'numeric';
#				warn "not-typed: $value";
				return 0 if (length($value) == 0);
				if (looks_like_number($value) and $value == 0) {
					return 0;
				} else {
					return 1;
				}
			}
		}
		throw RDF::Query::Error::TypeError;
	} else {
		return $node ? 1 : 0;
	}
};

$functions{"sop:numeric"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $value	= $bridge->literal_value( $node );
		my $type	= $bridge->literal_datatype( $node );
		if ($type and $type eq 'http://www.w3.org/2001/XMLSchema#integer') {
			return int($value)
		}
		return +$value;
	} elsif (looks_like_number($node)) {
		return $node;
	} else {
		return 0;
	}
};

$functions{"sop:str"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $value	= $bridge->literal_value( $node );
		my $type	= $bridge->literal_datatype( $node );
		return $value;
	} elsif ($bridge->is_resource($node)) {
		return $bridge->uri_value($node);
	} elsif (not defined reftype($node)) {
		return $node;
	} else {
		return '';
	}
};

$functions{"sop:lang"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $lang	= $bridge->literal_value_language( $node );
		return $lang;
	}
	return '';
};

$functions{"sop:datatype"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	if ($bridge->is_literal($node)) {
		my $type	= $bridge->literal_datatype( $node );
		return $type;
	}
	return '';
};

$functions{"sop:date"}	= 
$functions{"http://www.w3.org/2001/XMLSchema#dateTime"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $f		= $query->{dateparser};
	my $date	= $functions{'sop:str'}->( $query, $node );
	my $dt		= eval { $f->parse_datetime( $date ) };
	if ($@) {
		warn $@;
	}
	return $dt;
};


# sop:logical-or
$functions{"sop:logical-or"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:boolean';
	return ($functions{$cast}->( $query, $nodea ) || $functions{$cast}->( $query, $nodeb ));
};

# sop:logical-and
$functions{"sop:logical-and"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:boolean';
	return ($functions{$cast}->( $query, $nodea ) && $functions{$cast}->( $query, $nodeb ));
};

# sop:isBound
$functions{"sop:isBound"}	= sub {
	my $query	= shift;
	my $node	= shift;
	return ref($node) ? 1 : 0;
};

# sop:isURI
$functions{"sop:isURI"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	return $bridge->is_resource( $node );
};

# sop:isBlank
$functions{"sop:isBlank"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	return $bridge->is_blank( $node );
};

# sop:isLiteral
$functions{"sop:isLiteral"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	return $bridge->is_literal( $node );
};


$functions{"sparql:lang"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	my $lang	= $bridge->literal_value_language( $node ) || '';
	return $lang;
};

$functions{"sparql:langmatches"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $match	= shift;
	my $bridge	= $query->bridge;
	my $lang	= $query->get_value( $node );
	return unless ($lang);
	return (lc($lang) eq lc($match));
};

$functions{"sparql:datatype"}	= sub {
	my $query	= shift;
	my $node	= shift;
	my $bridge	= $query->bridge;
	return $bridge->literal_datatype( $node );
};



# op:dateTime-equal
$functions{"op:dateTime-equal"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:date';
	return ($functions{$cast}->( $query, $nodea ) == $functions{$cast}->( $query, $nodeb ));
};

# op:dateTime-less-than
$functions{"op:dateTime-less-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:date';
	return ($functions{$cast}->( $query, $nodea ) < $functions{$cast}->( $query, $nodeb ));
};

# op:dateTime-greater-than
$functions{"op:dateTime-greater-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:date';
	return ($functions{$cast}->($query, $nodea) > $functions{$cast}->($query, $nodeb));
};

# op:numeric-equal
$functions{"op:numeric-equal"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($query, $nodea) == $functions{$cast}->($query, $nodeb));
};

# op:numeric-less-than
$functions{"op:numeric-less-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($query, $nodea) < $functions{$cast}->($query, $nodeb));
};

# op:numeric-greater-than
$functions{"op:numeric-greater-than"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($query, $nodea) > $functions{$cast}->($query, $nodeb));
};

# op:numeric-multiply
$functions{"op:numeric-multiply"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($query, $nodea) * $functions{$cast}->($query, $nodeb));
};

# op:numeric-divide
$functions{"op:numeric-divide"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($query, $nodea) / $functions{$cast}->($query, $nodeb));
};

# op:numeric-add
$functions{"op:numeric-add"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($query, $nodea) + $functions{$cast}->($query, $nodeb));
};

# op:numeric-subtract
$functions{"op:numeric-subtract"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:numeric';
	return ($functions{$cast}->($query, $nodea) - $functions{$cast}->($query, $nodeb));
};

# fn:compare
$functions{"http://www.w3.org/2005/04/xpath-functionscompare"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:str';
	return ($functions{$cast}->($query, $nodea) cmp $functions{$cast}->($query, $nodeb));
};

# fn:not
$functions{"http://www.w3.org/2005/04/xpath-functionsnot"}	= sub {
	my $query	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	my $cast	= 'sop:str';
	return (0 != ($functions{$cast}->($query, $nodea) cmp $functions{$cast}->($query, $nodeb)));
};

# fn:matches
$functions{"http://www.w3.org/2005/04/xpath-functionsmatches"}	= sub {
	my $query	= shift;
	my $cast	= 'sop:str';
	my $string	= $functions{$cast}->( $query, shift );
	my $pattern	= $functions{$cast}->( $query, shift );
	return undef if (index($pattern, '(?{') != -1);
	return undef if (index($pattern, '(??{') != -1);
	my $flags	= $functions{$cast}->( $query, shift );
	if ($flags) {
		$pattern	= "(?${flags}:${pattern})";
		return $string =~ /$pattern/;
	} else {
		return ($string =~ /$pattern/) ? 1 : 0;
	}
};

# sop:	http://www.w3.org/TR/rdf-sparql-query/
# xs:	http://www.w3.org/2001/XMLSchema
# fn:	http://www.w3.org/2005/04/xpath-functions
# xdt:	http://www.w3.org/2005/04/xpath-datatypes
# err:	http://www.w3.org/2004/07/xqt-errors



################################################################################
################################################################################
sub ________CUSTOM_FUNCTIONS________ {}#########################################
################################################################################

$functions{"java:com.hp.hpl.jena.query.function.library.sha1sum"}	= sub {
	my $query	= shift;
	my $node	= shift;
	require Digest::SHA1;
	my $cast	= 'sop:str';
	return Digest::SHA1::sha1_hex($functions{$cast}->($query, $node));
};

$functions{"java:com.hp.hpl.jena.query.function.library.now"}	= sub {
	my $query	= shift;
	my $dt		= DateTime->new();
	return $dt;
};

$functions{"java:com.hp.hpl.jena.query.function.library.langeq"}	= sub {
	my $query	= shift;
	my $cast	= 'sop:str';
	
	require I18N::LangTags;
	my $node	= shift;
	my $lang	= $functions{$cast}->( $query, shift );
	my $litlang	= $query->bridge->literal_value_language( $node );
	
	return I18N::LangTags::is_dialect_of( $litlang, $lang );
};

$functions{"java:com.hp.hpl.jena.query.function.library.listMember"}	= sub {
	my $query	= shift;
	my $bridge	= $query->bridge;
	
	my $list	= shift;
	my $value	= shift;
	if ($bridge->is_resource( $list ) and $bridge->uri_value( $list ) eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#nil') {
		return 0;
	} else {
		my $first	= $bridge->new_resource( 'http://www.w3.org/1999/02/22-rdf-syntax-ns#first' );
		my $rest	= $bridge->new_resource( 'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest' );
		my $stream	= $bridge->get_statements( $list, $first, undef );
		while (my $stmt = $stream->()) {
			my $member	= $bridge->object( $stmt );
			return 1 if ($bridge->equals( $value, $member ));
		}
		
		my $stmt	= $bridge->get_statements( $list, $rest, undef )->();
		my $tail	= $bridge->object( $stmt );
		if ($tail) {
			return $functions{"java:com.hp.hpl.jena.query.function.library.listMember"}->( $query, $tail, $value );
		} else {
			return 0;
		}
	}
};

$functions{"java:com.ldodds.sparql.Distance"}	= sub {
	my $query	= shift;
	my ($lat1, $lon1, $lat2, $lon2);
	
	require Geo::Distance;
	my $cast	= 'sop:str';
	if (2 == @_) {
		my $point1	= $functions{$cast}->( $query, shift );
		my $point2	= $functions{$cast}->( $query, shift );
		($lat1, $lon1)	= split(/ /, $point1);
		($lat2, $lon2)	= split(/ /, $point2);
	} else {
		$lat1	= $functions{$cast}->( $query, shift );
		$lon1	= $functions{$cast}->( $query, shift );
		$lat2	= $functions{$cast}->( $query, shift );
		$lon2	= $functions{$cast}->( $query, shift );
	}
	
	my $geo		= new Geo::Distance;
	my $dist	= $geo->distance(
					'kilometer',
					$lon1,
					$lat1,
					$lon2,
					$lat2,
				);
	return $dist;
};

$functions{"http://kasei.us/2007/09/functions/warn"}	= sub {
	my $query	= shift;
	my $cast	= 'sop:str';
	my $value	= $functions{$cast}->( $query, shift );
	no warnings 'uninitialized';
	warn "FILTER VALUE: $value\n";
	return $value;
};



1;

__END__

=back

=head1 Defined Hooks

=over 4

=item http://kasei.us/code/rdf-query/hooks/post-create-model

Called after loading all external files to a temporary model in queries that
use FROM and FROM NAMED.

Args: ( $query, $bridge )

C<$query> is the RDF::Query object.
C<$bridge> is the model bridge (RDF::Query::Model::*) object.

=back

=head1 Supported Built-in Operators and Functions

=over 4

=item * REGEX, BOUND, ISURI, ISBLANK, ISLITERAL

=item * Data-typed literals: DATATYPE(string)

=item * Language-typed literals: LANG(string), LANGMATCHES(string, lang)

=item * Casting functions: xsd:dateTime, xsd:string

=item * dateTime-equal, dateTime-greater-than

=back

=head1 TODO

=over 4

=item * Built-in Operators and Functions

L<http://www.w3.org/TR/rdf-sparql-query/#StandardOperations>

Casting functions: xsd:{boolean,double,float,decimal,integer}, rdf:{URIRef,Literal}, STR

XPath functions: numeric-equal, numeric-less-than, numeric-greater-than, numeric-multiply, numeric-divide, numeric-add, numeric-subtract, not, matches

SPARQL operators: sop:RDFterm-equal, sop:bound, sop:isURI, sop:isBlank, sop:isLiteral, sop:str, sop:lang, sop:datatype, sop:logical-or, sop:logical-and

=back

=head1 AUTHOR

 Gregory Todd Williams <greg@evilfunhouse.com>

=cut
