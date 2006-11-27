# RDF::Query
# -------------
# $Revision: 181 $
# $Date: 2006-11-24 14:56:44 -0500 (Fri, 24 Nov 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query - An RDF query implementation of SPARQL/RDQL in Perl for use with RDF::Redland and RDF::Core.

=head1 VERSION

This document describes RDF::Query version 1.040.

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

use Data::Dumper;
use Storable qw(dclone);
use Scalar::Util qw(blessed reftype looks_like_number);
use DateTime::Format::W3CDTF;

use RDF::Query::Stream;
use RDF::Query::Parser::RDQL;
use RDF::Query::Parser::SPARQL;
use RDF::Query::Compiler::SQL;
use RDF::Query::Error qw(:try);

use RDF::Query::Optimizer::Multiget;
use RDF::Query::Optimizer::Peephole::Naive;
use RDF::Query::Optimizer::Peephole::Cost;

######################################################################

our ($REVISION, $VERSION, $debug);
use constant DEBUG	=> 0;
BEGIN {
	$debug		= 0;
	$REVISION	= do { my $REV = (qw$Revision: 181 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$VERSION	= '1.041';
}


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
	my ($query, $baseuri, $languri, $lang)	= @_;
	
	my $f	= DateTime::Format::W3CDTF->new;
	no warnings 'uninitialized';
	my $parser	= ($lang eq 'rdql' or $languri eq 'http://jena.hpl.hp.com/2003/07/query/RDQL')
				? RDF::Query::Parser::RDQL->new()
				: RDF::Query::Parser::SPARQL->new();
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
		return undef;
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
		
		unless ($self->{optimized}{'multi_get'}++) {
			if ($bridge->supports('multi_get')) {
				my $mopt	= RDF::Query::Optimizer::Multiget->new( $self, $bridge, size => 3 );
				$mopt->optimize;
			}
		}
		
		$parsed		= $self->fixup( $self->{parsed} );
		my @vars	= $self->variables( $parsed );
		$stream		= $self->query_more( bound => \%bound, triples => [@{ $parsed->{'triples'} }], variables => \@vars );
		
		_debug( "got stream: $stream" );
		$stream		= RDF::Query::Stream->new(
						$self->sort_rows( $stream, $parsed ),
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
		my @triples;
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
			push(@triples, $bridge->new_statement( @triple ));
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
	
	eval "use RDF::Query::Model::RDFBase;";
	if (RDF::Query::Model::RDFBase->can('new')) {
		return 'RDF::Query::Model::RDFBase';
	}
	
	eval "use RDF::Query::Model::Redland;";
	if (RDF::Query::Model::Redland->can('new')) {
		return 'RDF::Query::Model::Redland';
	}
	
	eval "use RDF::Query::Model::SQL;";
	if (RDF::Query::Model::SQL->can('new')) {
		return 'RDF::Query::Model::SQL';
	}
	
	eval "use RDF::Query::Model::RDFCore;";
	if (RDF::Query::Model::RDFCore->can('new')) {
		return 'RDF::Query::Model::RDFCore';
	}
	
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
	
	my $bridge;
	if (not $model) {
		$bridge	= $self->new_bridge();
	} elsif (blessed($model) and $model->isa('DBD')) {
		require RDF::Query::Model::SQL;
		my $storage	= RDF::Storage::DBI->new( $model, $args{'model'} );
		$bridge	= RDF::Query::Model::SQL->new( $storage, parsed => $parsed );
	} elsif (my $dbh = (ref($self) ? $self->{'dbh'} : undef) || $args{'dbh'}) {
		require RDF::Query::Model::SQL;
		no warnings 'uninitialized';
		if (not length($args{'model'})) {
			throw RDF::Query::Error::ExecutionError ( -text => 'No model specified for DBI-based triplestore' );
		}
		
		my $storage	= RDF::Storage::DBI->new( $dbh, $args{'model'} );
		$bridge	= RDF::Query::Model::SQL->new( $storage, parsed => $parsed );
	} elsif (blessed($model) and $model->isa('RDF::Base::Model')) {
		$bridge	= RDF::Query::Model::RDFBase->new( $model, parsed => $parsed );
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
				$self->set_named_graph_query();
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
	
	Carp::cluck unless ref($pred);
	
	if (reftype($pred) eq 'ARRAY' and $pred->[0] eq 'URI') {
		my $preduri		= $self->qualify_uri( $pred );
		$triple->[1]	= $self->bridge->new_resource($preduri);
	}
	
	if (reftype($sub) eq 'ARRAY' and $sub->[0] eq 'URI') {
		my $resource	= $self->qualify_uri( $sub );
		$triple->[0]	= $self->bridge->new_resource($resource);
# 	} elsif ($sub->[0] eq 'LITERAL') {
# 		my $literal		= $self->bridge->new_literal($sub->[1]);
# 		$triple->[0]	= $literal;
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
		if ($triples[0][0] eq 'OPTIONAL') {
			return $self->optional( bound => $bound, triples => \@triples, %args );
		} elsif ($triples[0][0] eq 'GRAPH') {
			if ($context) {
				throw RDF::Query::Error::QueryPatternError ( -text => "Can't use nested named graphs" );
			} else {
				return $self->named_graph( bound => $bound, triples => \@triples, variables => $variables );
			}
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
		} elsif ($triples[0][0] eq 'MULTI') {
			return $self->multi( bound => $bound, triples => \@triples, %args );
		}
	} else {
		# no more triples. return what we've got.
		my @values	= map { $bound->{$_} } @$variables;
		my @rows	= [@values];
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
		_debug( "${indent}query_more: " . join(' ', map { (($bridge->isa_node($_)) ? '<' . $bridge->as_string($_) . '>' : (reftype($_) eq 'ARRAY') ? $_->[1] : Dumper($_)) } @triple) . "\n" );
		_debug( "${indent}-> with " . scalar(@triples) . " triples to go\n" );
		_debug( "${indent}-> more: " . (($_->[0] =~ m/^(OPTIONAL|GRAPH|FILTER)$/) ? "$1 block" : join(' ', map { $bridge->isa_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
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
				if ($bridge->isa_node($val)) {
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
		_debug( 'query_more triple: ' . Dumper([map { blessed($_) ? $bridge->as_string($_) : ($_) ? Dumper($_) : 'undef' } (@triple, (($bridge->isa_node($context)) ? $context : ()))]) );
	}
	
	my @graph;
	if (ref($context) and reftype($context) eq 'ARRAY' and ($context->[0] eq 'VAR')) {
		my $context_var	= $context->[1];
		my $graph		= $bound->{ $context_var };
		if ($graph) {
			@graph	= $graph;
		}
	} elsif ($bridge->isa_node( $context )) {
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
					_debug( "${indent}-> more: " . (($_->[0] =~ m/^(OPTIONAL|GRAPH|FILTER)$/) ? "$1 block" : join(' ', map { $bridge->isa_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
					_debug( "${indent}-> " . Dumper(\@triples) );
				}
				
				$indent	.= '  ';
				_debug( 'adding a new stream for more triples' );
				unshift(@streams, $self->query_more( bound => { %{ $bound } }, triples => [@triples], variables => $variables, ($context ? (context => $context ) : ()) ) );
			} else {
				my @values	= map { $bound->{$_} } @$variables;
				_debug( "${indent}-> no triples left: result: " . join(', ', map {$bridge->as_string($_)} grep defined, @values) . "\n" );
				$result	= [@values];
			}
			
			foreach my $var (@vars) {
				if (defined($var)) {
					_debug( "deleting value for $var" );
					delete $bound->{ $var };
				}
			}
			
			if ($context_var) {
				_debug( "deleting value for $context_var" );
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

=begin private

=item C<multi ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle multi-get queries (where multiple triples
have been combined into one functional unit). Returns by calling C<query_more()>
with any remaining triples.

=end private

=cut

sub multi {
	my $self		= shift;
	my %args	= @_;
	
	my $bound	= delete($args{bound});
	my $triples	= delete($args{triples});
	my $context	= $args{context};
	
	my @triples	= @{$triples};
	my $multi	= shift(@triples);
	
	my $bridge	= $self->bridge;
	my $stream	= $bridge->multi_get( triples => [ @{ $multi }[ 1 .. $#{ $multi } ] ] );
	
	my $closed	= 0;
	my $more_stream;
	my $multi_bindings	= $stream->next;
	return sub {
		while (1) {
			if (not($more_stream)) {
				$multi_bindings	= $stream->next;
				if ($multi_bindings) {
					$more_stream	= $self->query_more( bound => { %{ $bound }, %{ $multi_bindings } }, triples => [@triples], %args );
				} else {
					$closed	= 1;
					undef $stream;
				}
			}
			
			return undef if ($closed);
			my $value	= $more_stream->();
			if ($value) {
				return $value;
			} else {
				undef $more_stream;
			}
		}
	};
}

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
					my $value	= $current->[ $i ];
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

=item C<named_graph ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle NAMED graph query patterns.
Matches graph context (binding the graph to a variable if applicable).
Returns by calling C<query_more()> with any remaining triples.

=end private

=cut

sub named_graph {
	my $self		= shift;
	my %args	= @_;
	
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
							my $value	= $data->[ $i ];
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
	my $parsed	= $self->{parsed};
	my $uri;
	if (ref($data->[1])) {
		my $prefix	= $data->[1][0];
		unless (exists($parsed->{'namespaces'}{$data->[1][0]})) {
			_debug( "No namespace defined for prefix '${prefix}'" );
		}
		my $ns	= $parsed->{'namespaces'}{$prefix};
		$uri	= join('', $ns, $data->[1][1]);
	} else {
		$uri	= $data->[1];
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
					'~~'	=> sub { my ($self, $values, $data) = @_; my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data }; return ($operands[0] =~ /$operands[1]/) },
					'=='	=> sub {
								my ($self, $values, $data) = @_;
								my @operands = map { $self->get_value( $self->check_constraints( $values, $_ ) ) } @{ $data };
								return ncmp($operands[0], $operands[1]) == 0;
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
						my $uri		= $data->[0][1];
						my $func	= $self->get_function( $uri );
						if ($func) {
							$self->{'values'}	= $values;
							my $value	= $func->(
											$self,
											map {
												($_->[0] eq 'VAR')
													? $values->{ $_->[1] }
													: $self->check_constraints( $values, $_ )
											} @{ $data }[1..$#{ $data }]
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
	} elsif ($bridge->isa_resource($value)) {
		return $bridge->uri_value( $value );
	} elsif ($bridge->isa_literal($value)) {
		my $literal	= $bridge->literal_value( $value );
		if (my $dt = $bridge->literal_datatype( $value )) {
			return [$literal, undef, $dt]
		} elsif (my $lang = $bridge->literal_value_language( $value )) {
			return [$literal, $lang, undef];
		} else {
			return $literal;
		}
	} elsif ($bridge->isa_blank($value)) {
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
	my $func	= $self->{'functions'}{$uri}
				|| $RDF::Query::functions{ $uri };
	return $func;
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
	for ($a, $b) {
		throw RDF::Query::Error::FilterEvaluationError unless defined($_);
	}
	
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
				next if $seen{ join($;, map {$bridge->as_string( $_ )} @$row) }++;
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
					my $result	= $self->check_constraints( {map { $_ => $node->[ $colmap{$_} ] } (keys %colmap)}, $data );
					my $value	= $self->get_value( $result );
					[ $node, $value ]
				} @nodes;
		@nodes	= sort { ncmp($a->[1], $b->[1]) }
						@nodes;
						
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
	$self->{error}	= undef;
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
	carp $body;
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
		if ($node->is_literal) {
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
		if ($type and $type->as_string eq 'http://www.w3.org/2001/XMLSchema#integer') {
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
	my $lang	= $bridge->literal_value_language( $node );
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
	if ($bridge->isa_resource( $list ) and $bridge->uri_value( $list ) eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#nil') {
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


REVISION HISTORY

 $Log$
 Revision 1.30  2006/01/13 23:55:48  greg
 - Updated requirements POD formatting.

 Revision 1.29  2006/01/11 06:16:19  greg
 - Added support for SELECT * in SPARQL queries.
 - Bugfix where one of two identical triple variables would be ignored ({ ?a ?a ?b })

 Revision 1.28  2005/11/19 00:58:07  greg
 - Fixed FILTER support in OPTIONAL queries.

 Revision 1.27  2005/07/27 00:30:04  greg
 - Added arithmetic operators to check_constraints().
 - Dependency cleanups.
 - Added debugging warnings when parsing fails.

 Revision 1.26  2005/06/06 00:49:00  greg
 - Added new DBI model bridge (accesses Redland's mysql storage directly).
 - Added built-in SPARQL functions and operators (not connected to grammar yet).
 - Added bridge methods for accessing typed literal information.

 Revision 1.25  2005/06/04 07:27:12  greg
 - Added support for typed literals.
   - (Redland support for datatypes is currently broken, however.)

 Revision 1.24  2005/06/02 19:28:49  greg
 - All debugging is now centrally located in the _debug method.
 - Internal code now uses the variables method.
 - Removed redundant code from ORDER BY/LIMIT/OFFSET handling.
 - Removed unused parse_files method.
 - Bridge object is now passed to the Stream constructor.

 Revision 1.23  2005/06/01 22:10:46  greg
 - Moved Stream class to lib/RDF/Query/Stream.pm.
 - Fixed tests that broke with previous fix to CONSTRUCT queries.
 - Fixed tests that broke with previous change to ASK query results.

 Revision 1.22  2005/06/01 21:21:09  greg
 - Fixed bug in CONSTRUCT queries that used blank nodes.
 - ASK queries now return a Stream object; Use the new get_boolean method.
 - Graph and Boolean streams now respond to is_graph and is_boolean methods.

 Revision 1.21  2005/06/01 05:06:33  greg
 - Added SPARQL UNION support.
 - Broke OPTIONAL handling code off into a seperate method.
 - Added new debugging code to trace errors in the twisty web of closures.

 Revision 1.20  2005/05/18 23:05:53  greg
 - Added support for SPARQL OPTIONAL graph patterns.
 - Added binding_values and binding_names methods to Streams.

 Revision 1.19  2005/05/18 04:19:45  greg
 - Added as_xml method to Stream class for XML Binding Results format.

 Revision 1.18  2005/05/16 17:37:06  greg
 - Added support for binding_name and is_bindings Stream methods.

 Revision 1.17  2005/05/09 01:03:20  greg
 - Added SPARQL test that was breaking when missing triples.
   - Added foaf:aimChatID to test foaf data.
 - Calling bindings_count on a stream now returns 0 with no data.

 Revision 1.16  2005/05/08 08:26:09  greg
 - Added initial support for SPARQL ASK, DESCRIBE and CONSTRUCT queries.
   - Added new test files for new query types.
 - Added methods to bridge classes for creating statements and blank nodes.
 - Added as_string method to bridge classes for getting string versions of nodes.
 - Broke out triple fixup code into fixup_triple_bridge_variables().
 - Updated FILTER test to use new Geo::Distance API.

 Revision 1.15  2005/05/03 05:51:25  greg
 - Added literal_value, uri_value, and blank_identifier methods to bridges.
 - Redland bridge now calls sources/arcs/targets when only one field is missing.
 - Fixes to stream code. Iterators are now destroyed in a timely manner.
   - Complex queries no longer max out mysql connections under Redland.
 - Cleaned up node sorting code.
   - Removed dependency on Sort::Naturally.
   - Added new node sorting function ncmp().
 - check_constraints now calls ncmp() for logical comparisons.
 - Added get_value method to make bridge calls and return a scalar value.
 - Fixed node creation in Redland bridge.
 - Moved DISTINCT handling code to occur before LIMITing.
 - Added variables method to retrieve bound variable names.
 - Added binding_count and get_all methods to streams.
 - get_statments bridge methods now return RDF::Query::Stream objects.

 Revision 1.14  2005/04/26 04:22:13  greg
 - added constraints tests
 - URIs in constraints are now part of the fixup
 - parser is removed from the Redland bridge in DESTROY
 - SPARQL FILTERs are now properly part of the triple patterns (within the braces)
 - added FILTER tests

 Revision 1.13  2005/04/26 02:54:40  greg
 - added core support for custom function constraints support
 - added initial SPARQL support for custom function constraints
 - SPARQL variables may now begin with the '$' sigil
 - broke out URL fixups into its own method
 - added direction support for ORDER BY (ascending/descending)
 - added 'next', 'current', and 'end' to Stream API

 Revision 1.12  2005/04/25 01:27:40  greg
 - stream objects now handle being constructed with an undef coderef

 Revision 1.11  2005/04/25 00:59:29  greg
 - streams are now objects usinig the Redland QueryResult API
 - RDF namespace is now always available in queries
 - row() now uses a stream when calling execute()
 - check_constraints() now copies args for recursive calls (instead of pass-by-ref)
 - added ORDER BY support to RDQL parser
 - SPARQL constraints now properly use the 'FILTER' keyword
 - SPARQL constraints can now use '&&' as an operator
 - SPARQL namespace declaration is now optional

 Revision 1.10  2005/04/21 08:12:07  greg
 - updated MANIFEST
 - updated POD

 Revision 1.9  2005/04/21 05:24:54  greg
 - execute now returns an iterator
 - added core support for DISTINCT, LIMIT, OFFSET
 - added initial core support for ORDER BY (only works on one column right now)
 - added SPARQL support for DISTINCT and ORDER BY
 - added stress test for large queries and sorting on local scutter model

 Revision 1.8  2005/04/21 02:21:44  greg
 - major changes (resurecting the project)
 - broke out the query parser into it's own RDQL class
 - added initial support for a SPARQL parser
   - added support for blank nodes
   - added lots of syntactic sugar (with blank nodes, multiple predicates and objects)
 - moved model-specific code into RDF::Query::Model::*
 - cleaned up the model-bridge code
 - moving over to redland's query API (pass in the model when query is executed)

 Revision 1.7  2005/02/10 09:57:24  greg
 - add code and grammar for initial constraints support
 - misc updates

 Revision 1.6  2004/07/12 11:24:09  greg
 - changed order of some Parse::RecDescent rules for common case

 Revision 1.5  2004/07/12 11:17:34  greg
 - updated namespace for relationship schema
 - fixed broken qURI regex in RDQL parser
 - query() now reverses result list (hack)
 - RDF::Query::Redland : getLabel now returns identifier for blank nodes

 Revision 1.4  2004/07/07 06:39:32  greg
 - added t/02-coverage.t and made code changes based on Devel::Cover results

 Revision 1.3  2004/07/07 04:45:57  greg
 - updated POD
 - commented out debugging code
 - moved backend model detection code to C<model>
 - changed block eval to string eval to only load one backend if both are present

 Revision 1.2  2004/07/07 03:43:14  greg
 - refactored code that deals with the RDF model
 - moved RDF::Core specific code to RDF::Query::RDFCore
 - added Redland support in RDF::Query::Redland
 - now uses Redland if available, falls back on RDF::Core
 - updated tests (removed RDF::Core specific code)

 Revision 1.1.1.1  2004/07/05 03:05:38  greg
 import

 
