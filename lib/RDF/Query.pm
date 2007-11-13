# RDF::Query
# -------------
# $Revision: 286 $
# $Date: 2007-11-12 23:26:54 -0500 (Mon, 12 Nov 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query - An RDF query implementation of SPARQL/RDQL in Perl for use with RDF::Redland and RDF::Core.

=head1 VERSION

This document describes RDF::Query version 1.500, released 13 November 2007.

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

L<LWP|LWP>

L<DateTime::Format::W3CDTF|DateTime::Format::W3CDTF>

L<Scalar::Util|Scalar::Util>

=cut

package RDF::Query;

use strict;
use warnings;
use Carp qw(carp croak confess);

use Data::Dumper;
use LWP::UserAgent;
use I18N::LangTags;
use Storable qw(dclone);
use List::Util qw(first);
use Scalar::Util qw(blessed reftype looks_like_number);
use DateTime::Format::W3CDTF;

use RDF::Query::Functions;	# all the built-in functions including:
							#     datatype casting, language ops, logical ops,
							#     numeric ops, datetime ops, and node type testing
							# also, custom functions including:
							#     jena:sha1sum, jena:now, jena:langeq, jena:listMember
							#     ldodds:Distance, kasei:warn
use RDF::Query::Algebra;
use RDF::Query::Node;
use RDF::Query::Stream qw(sgrep smap swatch);
use RDF::Query::Parser::RDQL;
use RDF::Query::Parser::SPARQL;
use RDF::Query::Parser::tSPARQL;	# XXX temporal extensions
use RDF::Query::Compiler::SQL;
use RDF::Query::Error qw(:try);

######################################################################

our ($REVISION, $VERSION, $debug, $js_debug, $DEFAULT_PARSER, $PROF);
use constant DEBUG	=> 0;
use constant PROF	=> 0;
BEGIN {
	$debug		= DEBUG;
	$js_debug	= 0;
	$REVISION	= do { my $REV = (qw$Revision: 286 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$VERSION	= '1.500';
	$ENV{RDFQUERY_NO_RDFBASE}	= 1;	# XXX Not ready for release
	$DEFAULT_PARSER		= 'sparql';
	
	# PROFILING
	if (PROF) {
		require Time::HiRes;
		Time::HiRes->import(qw(gettimeofday));
		open( $PROF, '>>', "rdfquery.profile.out" );
	}
}

######################################################################
if (PROF) {
	require Hook::LexWrap;
	Hook::LexWrap->import();
eval <<"END" for (qw(new get execute describe construct ask supports set_named_graph_query loadable_bridge_class new_bridge get_bridge fixup fixup_triple_bridge_variables query_more get_statements union optional query_more_ggp query_more_graph qualify_uri check_constraints _isa_known_node_type _one_isa _promote_to get_value add_function get_function net_filter_function _is_trusted new_javascript_engine add_hook get_hooks run_hook ncmp is_numeric_type sort_rows parse_url variables all_variables parsed error set_error clear_error));
wrap "RDF::Query::$_",
	pre		=> sub { _PROFILE(1,"$_") },
	post	=> sub { _PROFILE(0,"$_") };
END
}
######################################################################



our %PATTERN_TYPES	= map { $_ => 1 } (qw(
						BGP
						GGP
						GRAPH
						OPTIONAL
						UNION
						TRIPLE
					));
my $KEYWORD_RE	= qr/^(BGP|GGP|OPTIONAL|UNION|GRAPH|FILTER|TIME)$/;

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
					tsparql	=> 'RDF::Query::Parser::tSPARQL',
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
	my $parsed	= $parser->parse( $query );
	
	my $ua		= LWP::UserAgent->new( agent => "RDF::Query/${VERSION}" );
	my $self 	= bless( {
					base			=> $baseuri,
					dateparser		=> $f,
					parser			=> $parser,
					parsed			=> $parsed,
					parsed_orig		=> $parsed,
					named_models	=> {},
					useragent		=> $ua,
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
	my $row		= $stream->next;
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
	
	local($::NO_BRIDGE)	= 0;
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
		# JIT: Load external data, swap in model objects (Redland, RDF::Core, etc.) for abstract RDF Nodes
		$parsed		= $self->fixup( $self->{parsed} );
		my @vars	= $self->variables( $parsed );
		
		# RUN THE QUERY!
		$stream		= $self->query_more(
			bound		=> \%bound,
			triples		=> [@{ $parsed->{'triples'} }],
			variables	=> \@vars,
			bridge		=> $bridge,
			debug		=> 0,			# XXX DEBUG
		);
		
		_debug( "got stream: $stream" ) if (DEBUG);
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
			my (undef, @triple)	= @{ $triple };
			for my $i (0 .. 2) {
				if (blessed($triple[$i]) and $triple[$i]->isa('RDF::Query::Node')) {
					if ($triple[$i]->isa('RDF::Query::Node::Variable')) {
						my $name	= $triple[$i]->name;
						$triple[$i]	= $row->[ $variable_map{ $name } ];
					} elsif ($triple[$i]->isa('RDF::Query::Node::Blank')) {
						my $id	= $triple[$i]->blank_identifier;
						unless (exists($blank_map{ $id })) {
							$blank_map{ $id }	= $self->bridge->new_blank();
						}
						$triple[$i]	= $blank_map{ $id };
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
	_debug( "Replacing model bridge with a new (empty) one for a named graph query" ) if (DEBUG);
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
	} else { warn "RDF::Base supressed" if ($debug and not $ENV{RDFQUERY_SILENT}) }
	
	if (not $ENV{RDFQUERY_NO_REDLAND}) {
		eval "use RDF::Query::Model::Redland;";
		if (RDF::Query::Model::Redland->can('new')) {
			return 'RDF::Query::Model::Redland';
		} else {
			warn "RDF::Query::Model::Redland didn't load cleanly" if ($debug);
		}
	} else { warn "RDF::Redland supressed" if ($debug and not $ENV{RDFQUERY_SILENT}) }
	
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
	} else { warn "RDF::Core supressed" if ($debug and not $ENV{RDFQUERY_SILENT}) }
	
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
			}
			
			$self->parse_url( $self->qualify_uri( $source->[1] ), $named_source );
		}
		$self->run_hook( 'http://kasei.us/code/rdf-query/hooks/post-create-model', $bridge );
	}
	
	## CONVERT URIs to Resources, and strings to Literals
	my @triples	= @{ $parsed->{'triples'} || [] };
	while (my $triple = shift(@triples)) {
#		warn "fixup: " . Dumper($triple);
		my @new	= $self->fixup_pattern( $triple );
#		warn "====> adding " . Dumper(\@new);
		push( @triples, @new );
	}
	
	## SELECT * implies selecting all known variables
	no warnings 'uninitialized';
	$self->{known_variables}	= [ map { ['VAR', $_] } (keys %{ $self->{ known_variables_hash } }) ];
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
			my (undef, @nodes)	= @{ $triple };
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

=item C<fixup_pattern ( $pattern )>

Called by fixup() with individual graph patterns. Returns a list of sub-patterns
that may need fixing up.

=end private

=cut

sub fixup_pattern {
	my $self	= shift;
	my $triple	= shift;
	my $bridge		= $self->{bridge};

	Carp::confess "not an array: " . Dumper($triple) unless (reftype($triple) eq 'ARRAY');
	unless (blessed($triple) and $triple->isa('RDF::Query::Algebra')) {
		Carp::confess "not a graph pattern: " . Dumper($triple);
	}
	
	my $type	= $triple->type;
	if ($triple->isa('RDF::Query::Algebra::Triple')) {
		my @nodes	= $triple->nodes;
		my @vars	= map { $_->name } grep { blessed($_) and $_->isa('RDF::Query::Node::Variable') } @nodes;
		foreach my $var (@vars) {
			$self->{ known_variables_hash }{ $var }++
		}
		
		$self->fixup_triple_bridge_variables( $triple );
		return ();
	} elsif ($triple->isa('RDF::Query::Algebra::Optional')) {
		return ($triple->pattern, $triple->optional);
	} elsif ($triple->isa('RDF::Query::Algebra::GroupGraphPattern')) {
		return($triple->patterns);
	} elsif ($triple->isa('RDF::Query::Algebra::BasicGraphPattern')) {
		return($triple->triples);
	} elsif ($triple->isa('RDF::Query::Algebra::NamedGraph')) {
		my @triples;
		push(@triples, $triple->pattern);
		if ($triple->graph->isa('RDF::Query::Node::Resource')) {
			$triple->graph( $bridge->new_resource( $triple->graph->uri_value ) );
		} elsif ($triple->graph->isa('RDF::Query::Node::Variable')) {
			my $var	= $triple->graph->name;;
			$self->{ known_variables_hash }{ $var }++
		}
		return @triples;
	} elsif ($triple->isa('RDF::Query::Algebra::Union')) {
		return($triple->first, $triple->second);
	} elsif ($triple->isa('RDF::Query::Algebra::OldFilter')) {
		my @constraints	= ($triple->[1]);
		while (my $data = shift @constraints) {
			_debug( "FIXING CONSTRAINT DATA: " . Dumper($data), 2 ) if (DEBUG);
			if (reftype($data) eq 'ARRAY') {
				my ($op, @rest)	= @$data;
				if ($op eq 'URI') {
					$data->[1]	= $self->qualify_uri( $data );
					_debug( "FIXED: " . $data->[1], 2 ) if (DEBUG);
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
		return ();
### XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	} elsif ($type eq 'TIME') {
		if ($triple->[1][0] eq 'URI') {
			$triple->[1]	= $bridge->new_resource( $triple->[1][1] );
		}
		return(@{$triple->[2]});
	} else {
		die "unknown pattern in fixup: $type";
	}
}

=begin private

=item C<fixup_triple_bridge_variables ()>

Called by C<fixup()> to replace URIs and strings with model-specific objects.

=end private

=cut

sub fixup_triple_bridge_variables {
	my $self	= shift;
	my $triple	= shift;
	my ($type,$sub,$pred,$obj)	= @{ $triple };
	Carp::confess 'not a triple: ' . Dumper($triple) unless ($type eq 'TRIPLE');
	Carp::cluck "No predicate in triple passed to fixup_triple_bridge_variable: " . Dumper($triple) unless ref($pred);
	
	no warnings 'uninitialized';
	if (ref($sub) and reftype($sub) eq 'ARRAY' and $sub->[0] eq 'URI') {
		my $resource	= $self->qualify_uri( $sub );
		$triple->[1]	= $self->bridge->new_resource($resource);
#	} elsif (reftype($sub) eq 'ARRAY' and $sub->[0] eq 'BLANK') {
#		my $blank		= $self->bridge->new_blank($sub->[1]);
#		$triple->[1]	= $blank;
	}
	
	if (reftype($pred) eq 'ARRAY' and $pred->[0] eq 'URI') {
		my $preduri		= $self->qualify_uri( $pred );
		
		$triple->[2]	= $self->bridge->new_resource($preduri);
	}
	
# XXX THIS CONDITIONAL SHOULD ALWAYS BE TRUE ... ? (IT IS IN ALL TEST CASES)
#	if (ref($obj)) {
		if (ref($obj) and reftype($obj) eq 'ARRAY' and $obj->[0] eq 'LITERAL') {
			no warnings 'uninitialized';
			if (reftype($obj->[3]) eq 'ARRAY' and $obj->[3][0] eq 'URI') {
				$obj->[3]	= $self->qualify_uri( $obj->[3] );
			}
			my $literal		= $self->bridge->new_literal(@{$obj}[ 1 .. $#{$obj} ]);
			$triple->[3]	= $literal;
		} elsif (reftype($obj) eq 'ARRAY' and $obj->[0] eq 'URI') {
			my $resource	= $self->qualify_uri( $obj );
			$triple->[3]	= $self->bridge->new_resource($resource);
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
	local($::NO_BRIDGE)	= 1;

	my $bound		= delete($args{bound});
	my $triples		= delete($args{triples});
	my $context		= $args{context};
	my $variables	= $args{variables};
	my $bridge		= $args{bridge};
	Carp::confess unless (blessed($bridge));	# XXXassert

	my $debug		= delete($args{debug});	# XXX
	
	my @triples		= @{$triples};
	
	if (@triples) {
		my @streams;
		my @filters;
		foreach my $triple (@triples) {
#			warn "TRIPLE: " . Dumper($triple);
			Carp::confess "not an array: " . Dumper($triple) unless (reftype($triple) eq 'ARRAY');
			Carp::confess "not an algebra or rdf node: " . Dumper($triple) unless ($triple->isa('RDF::Query::Algebra') or $triple->isa('RDF::Query::Node'));
			
			my $type	= $triple->type;
			if ($PATTERN_TYPES{ $type }) {
				my $method	= 'query_more_' . lc($type);
				my $stream	= $self->$method( bound => {%$bound}, triples => [$triple], %args );
				push(@streams, $stream);
			} elsif ($type eq 'FILTER') {
				push(@filters, $triple);
			} elsif ($type eq 'TIME') {
				$triples[0][0]	= 'GRAPH';
				push(@streams, $self->query_more_graph( bound => {%$bound}, triples => [$triple], %args ));
			} else {
				push(@streams, $self->query_more_triple( bound => {%$bound}, triples => [ ['TRIPLE', @$triple] ], %args ));
			}
		}
		if (@streams) {
			while (@streams > 1) {
				my $a	= shift(@streams);
				my $b	= shift(@streams);
				unshift(@streams, $self->join_streams( $a, $b, %args, debug => $debug ));	# XXX remove debug
			}
		} else {
			push(@streams, RDF::Query::Stream->new([{}], 'bindings', []));
		}
		my $stream	= shift(@streams);
		
		foreach my $data (@filters) {
			$stream	= sgrep {
						my $bound			= $_;
						my $filter_value	= $self->call_function( $bridge, $bound, 'sop:boolean', $data->[1] );
						return ($filter_value);
					} $stream;
		}
		
		return $stream;
	} else {
		# no more triples. return what we've got.
		my @rows	= {%$bound};
		return RDF::Query::Stream->new(\@rows, 'bindings', [keys %$bound]);
	}
}

=begin private

=item C<query_more_triple ( bound => \%bound, triples => [$triple], variables => \@variables, bridge => $bridge )>

Called by C<query_more()> to handle individual triple patterns.
Calls C<get_statements()> with the triple pattern, returning an
RDF::Query::Stream of resulting bound variables.

=end private

=cut

sub query_more_triple {
	my $self		= shift;
	my %args	= @_;
	
	my $bound		= delete($args{bound});
	my $triples		= delete($args{triples});
	my $context		= $args{context};
	my $variables	= $args{variables};
	my $bridge		= $args{bridge};
	
	my ($triple)	= @{$triples};
#	my @triple		= @{ $triple };
	our $indent;
	
	Carp::confess unless (blessed($triple) and $triple->isa('RDF::Query::Algebra::Triple'));
	my @triple		= (
						$triple->subject,
						$triple->predicate,
						$triple->object,
					);
	
	my %bind;
	
	my $vars	= 0;
	my ($var, $method);
	my (@vars, @methods);
	my @methodmap	= $bridge->statement_method_map;
	
	my %map;
	my %seen;
	my $dup_var	= 0;
	my @dups;
	for my $idx (0 .. 2) {
		_debug( "looking at triple " . $methodmap[ $idx ] ) if (DEBUG);
		my $data	= $triple[$idx];
		if (ref($data) and reftype($data) eq 'ARRAY') {	# and $data->[0] eq 'VAR'
			if ($data->isa('RDF::Query::Node::Variable') or $data->isa('RDF::Query::Node::Blank')) {
				my $tmpvar	= ($data->isa('RDF::Query::Node::Variable'))
							? $data->name
							: '_' . $data->blank_identifier;
				$map{ $methodmap[ $idx ] }	= $tmpvar;
				if ($seen{ $tmpvar }++) {
					$dup_var	= 1;
				}
				my $val		= $bound->{ $tmpvar };
				if ($bridge->is_node($val)) {
					_debug( "${indent}-> already have value for $tmpvar: " . $bridge->as_string( $val ) . "\n" ) if (DEBUG);
					$triple[$idx]	= $val;
				} else {
					++$vars;
					_debug( "${indent}-> found variable $tmpvar (we've seen $vars variables already)\n" ) if (DEBUG);
					$triple[$idx]	= undef;
					$vars[$idx]		= $tmpvar;
					$methods[$idx]	= $methodmap[ $idx ];
				}
			}
		}
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
	
	my $statments	= $self->get_statements( triple => \@triple, graph => \@graph, require_context => 1, %args );
	if ($dup_var) {
		# there's a node in the triple pattern that is repeated (like (?a ?b ?b)), but since get_statements() can't
		# directly make that query, we're stuck filtering the triples after we get the stream back.
		my %counts;
		my $dup_key;
		for (keys %map) {
			my $val	= $map{ $_ };
			if ($counts{ $val }++) {
				$dup_key	= $val;
			}
		}
		my @dup_methods	= grep { $map{$_} eq $dup_key } @methodmap;
		$statments	= sgrep {
			my $stmt	= $_;
			if (2 == @dup_methods) {
				my ($a, $b)	= @dup_methods;
				return ($bridge->equals( $stmt->$a(), $stmt->$b() )) ? 1 : 0;
			} else {
				my ($a, $b, $c)	= @dup_methods;
				return (($bridge->equals( $stmt->$a(), $stmt->$b() )) and ($bridge->equals( $stmt->$a(), $stmt->$c() ))) ? 1 : 0;
			}
		} $statments;
	}
	
	return smap {
		my $stmt	= $_;
		
		my $result	= { %$bound };
		foreach (0 .. $#vars) {
			my $var		= $vars[ $_ ];
			my $method	= $methods[ $_ ];
			next unless (defined($var));
			
			_debug( "${indent}-> got variable $var = " . $bridge->as_string( $stmt->$method() ) . "\n" ) if (DEBUG);
			if (defined($bound->{$var})) {
				_debug( "${indent}-> uh oh. $var has been defined more than once.\n" ) if (DEBUG);
				if ($bridge->as_string( $stmt->$method() ) eq $bridge->as_string( $bound->{$var} )) {
					_debug( "${indent}-> the two values match. problem avoided.\n" ) if (DEBUG);
				} else {
					_debug( "${indent}-> the two values don't match. this triple won't work.\n" ) if (DEBUG);
					_debug( "${indent}-> the existing value is" . $bridge->as_string( $bound->{$var} ) . "\n" ) if (DEBUG);
					return ();
				}
			} else {
				$result->{ $var }	= $stmt->$method();
			}
		}
		$result;
	} $statments, 'bindings', [@vars], { bridge => $bridge };
}


# sub query_more_triple {
# 	my $self		= shift;
# 	my %args	= @_;
# 	
# 	my $bound		= delete($args{bound});
# 	my $triples		= delete($args{triples});
# 	my $context		= $args{context};
# 	my $variables	= $args{variables};
# 	my $bridge		= $args{bridge};
# 	
# 	my @triples		= @{$triples};
# 	my $triple		= shift(@triples);
# 	my @triple		= @{ $triple };
# 	
# 	my $type		= shift(@triple);	# 'TRIPLE'
# 	Carp::confess unless ($type eq 'TRIPLE');
# 	
# 	our $indent;
# 	if (DEBUG) {
# 		no warnings 'uninitialized';
# 		_debug( "${indent}query_more: " . join(' ', map { (($bridge->is_node($_)) ? '<' . $bridge->as_string($_) . '>' : (reftype($_) eq 'ARRAY') ? $_->[1] : Dumper($_)) } @triple) . "\n" );
# 		_debug( "${indent}-> with " . scalar(@triples) . " triples to go\n" );
# 		_debug( "${indent}-> more: " . (($_->[0] =~ $KEYWORD_RE) ? "$1 block" : join(' ', map { $bridge->is_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
# 	}
# 	
# 	my $vars	= 0;
# 	my ($var, $method);
# 	my (@vars, @methods);
# 	
# 	my @methodmap	= $bridge->statement_method_map;
# 	for my $idx (0 .. 2) {
# 		_debug( "looking at triple " . $methodmap[ $idx ] ) if (DEBUG);
# 		my $data	= $triple[$idx];
# 		if (ref($data) and reftype($data) eq 'ARRAY') {	# and $data->[0] eq 'VAR'
# 			if ($data->[0] eq 'VAR' or $data->[0] eq 'BLANK') {
# 				my $tmpvar	= ($data->[0] eq 'VAR') ? $data->[1] : '_' . $data->[1];
# 				my $val		= $bound->{ $tmpvar };
# 				if ($bridge->is_node($val)) {
# 					_debug( "${indent}-> already have value for $tmpvar: " . $bridge->as_string( $val ) . "\n" ) if (DEBUG);
# 					$triple[$idx]	= $val;
# 				} else {
# 					++$vars;
# 					_debug( "${indent}-> found variable $tmpvar (we've seen $vars variables already)\n" ) if (DEBUG);
# 					$triple[$idx]	= undef;
# 					$vars[$idx]		= $tmpvar;
# 					$methods[$idx]	= $methodmap[ $idx ];
# 				}
# 			}
# 		}
# 	}
# 	
# 	if (DEBUG) {
# 		_debug( "${indent}getting: " . join(', ', grep defined, @vars) . "\n" );
# 		_debug( 'query_more triple: ' . Dumper([map { blessed($_) ? $bridge->as_string($_) : (($_) ? Dumper($_) : 'undef') } (@triple, (($bridge->is_node($context)) ? $context : ()))]) );
# 	}
# 	
# 	my @graph;
# 	if (ref($context) and reftype($context) eq 'ARRAY' and ($context->[0] eq 'VAR')) {
# 		# if we're in a GRAPH ?var {} block...
# 		my $context_var	= $context->[1];
# 		my $graph		= $bound->{ $context_var };
# 		if ($graph) {
# 			# and ?var has already been bound, get the bound value and pass that on
# 			@graph	= $graph;
# 		}
# 	} elsif ($bridge->is_node( $context )) {
# 		# if we're in a GRAPH <uri> {} block, just pass it on
# 		@graph	= $context;
# 	}
# 	
# 	my $stream;
# 	my @streams;
# 	
# 	my $statments	= $self->get_statements( triple => \@triple, graph => \@graph, require_context => 1, %args );
# 	if ($statments) {
# 		my $sub	= sub {
# 			my $result;
# 			my ($stmt, $context_var);
# 			LOOP: while (not $statments->finished) {
# 				_debug_closure( $statments ) if (DEBUG);
# 				$stmt	= $statments->current();
# 				unless ($stmt) {
# 					_debug( 'no more statements' ) if (DEBUG);
# 					$statments	= undef;
# 					return undef;
# 				}
# 				
# 				if (ref($context) and reftype($context) eq 'ARRAY' and ($context->[0] eq 'VAR')) {
# 					# if we're in a GRAPH ?var {} block, bind the current context to ?var
# 					warn "Trying to get context of current statement..." if ($debug);
# 					my $graph	= $statments->context;
# 					if ($graph) {
# 						$context_var				= $context->[1];
# 						$bound->{ $context_var }	= $graph;
# 						_debug( "Got context ($context_var) from iterator: " . $bridge->as_string( $graph ) ) if (DEBUG);
# 					} else {
# 						$statments->next;
# 						next LOOP;
# 						_debug( "No context returned by iterator." ) if (DEBUG);
# 					}
# 				}
# 				last LOOP;
# 			}
# 			
# 			$statments->next;
# 			unless ($stmt) {
# 				warn "returning undef because there isn't a statement" if (DEBUG);
# 				return undef;
# 			}
# 			
# 			if ($vars) {
# 				my %private_bound;
# 				foreach (0 .. $#vars) {
# 					_debug( "looking at variable $_" ) if (DEBUG);
# 					next unless defined($vars[$_]);
# 					my $var		= $vars[ $_ ];
# 					my $method	= $methods[ $_ ];
# 					_debug( "${indent}-> got variable $var = " . $bridge->as_string( $stmt->$method() ) . "\n" ) if (DEBUG);
# 					if (defined($private_bound{$var})) {
# 						_debug( "${indent}-> uh oh. $var has been defined more than once.\n" ) if (DEBUG);
# 						if ($bridge->as_string( $stmt->$method() ) eq $bridge->as_string( $private_bound{$var} )) {
# 							_debug( "${indent}-> the two values match. problem avoided.\n" ) if (DEBUG);
# 						} else {
# 							_debug( "${indent}-> the two values don't match. this triple won't work.\n" ) if (DEBUG);
# 							_debug( "${indent}-> the existing value is" . $bridge->as_string( $private_bound{$var} ) . "\n" ) if (DEBUG);
# 							return ();
# 						}
# 					} else {
# 						$private_bound{ $var }	= $stmt->$method();
# 					}
# 				}
# 				@{ $bound }{ keys %private_bound }	= values %private_bound;
# 			} else {
# 				_debug( "${indent}-> triple with no variable. ignoring.\n" ) if (DEBUG);
# 			}
# 			
# 			if (scalar(@triples)) {
# 				if (DEBUG) {
# 					_debug( "${indent}-> now for more triples...\n" );
# 					_debug( "${indent}-> more: " . (($_->[0] =~ $KEYWORD_RE) ? "$1 block" : join(' ', map { $bridge->is_node($_) ? '<' . $bridge->as_string( $_ ) . '>' : $_->[1] } @{$_})) . "\n" ) for (@triples);
# 					_debug( "${indent}-> " . Dumper(\@triples) );
# 					_debug( 'adding a new stream for more triples' );
# 					$indent	.= '  ';
# 				}
# 				unshift(@streams, $self->query_more( bound => { %{ $bound } }, triples => [@triples], variables => $variables, ($context ? (context => $context ) : ()), %args ) );
# 			} else {
# 				my @values	= map { $bound->{$_} } @$variables;
# 				_debug( "${indent}-> no triples left: result: " . join(', ', map {$bridge->as_string($_)} grep defined, @values) . "\n" ) if (DEBUG);
# 				$result	= {%$bound};
# 			}
# 			
# 			foreach my $var (@vars) {
# 				if (defined($var)) {
# 					_debug( "deleting value for $var" ) if (DEBUG);
# 					delete $bound->{ $var };
# 				}
# 			}
# 			
# 			if ($context_var) {
# 				_debug( "deleting context value for $context_var" ) if (DEBUG);
# 				delete $bound->{ $context_var };
# 			}
# 			
# 			if ($result) {
# 				if (DEBUG) {
# 					local($Data::Dumper::Indent)	= 0;
# 					_debug( 'found a result: ' . Dumper($result) ) if (DEBUG);
# 				}
# 				
# #					warn "*** returning result ($result) to " . join(' ', caller());
# 				return ($result);
# 			} else {
# 				_debug( 'no results yet...' ) if (DEBUG);
# 				return ();
# 			}
# 		};
# 		push(@streams, $sub);
# 	}
# 	
# 	if (DEBUG) {
# 		substr($indent, -2, 2)	= '';
# 	}
# 	
# 	return RDF::Query::Stream->new( sub {
# 		_debug( 'query_more closure with ' . scalar(@streams) . ' streams' ) if (DEBUG);
# 		while (@streams) {
# 			_debug( '-> fetching from stream ' . $streams[0] ) if (DEBUG);
# 			_debug_closure( $streams[0] ) if (DEBUG);
# 			
# 			my @val	= $streams[0]->();
# 			_debug( '-> ' . (@val ? 'got' : 'no') . ' value' ) if (DEBUG);
# 			if (@val) {
# 				_debug( '-> "' . $val[0] . '"', 1, 1) if (DEBUG);
# 				if (defined $val[0]) {
# 					return $val[0];
# 				}
# 			} else {
# 				_debug( '-> no value returned from stream. using next stream.', 1) if (DEBUG);
# 				next;
# 			}
# 			shift(@streams);
# 		}
# 
# 		_debug( '-> no more streams.', 1) if (DEBUG);
# 		return undef;
# 	}, 'bindings', undef, bridge => $bridge );	
# }


=begin private

=item C<query_more_union ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle UNION queries.
Calls C<query_more()> with each UNION branch, and returns an aggregated data stream.

=end private

=cut

sub query_more_union {
	my $self		= shift;
	my %args	= @_;
	
	my $bound	= delete($args{bound});
	my $triples	= delete($args{triples});
	my $context	= $args{context};
	my $bridge	= $args{bridge};
	
	my ($triple)	= @{$triples};
	
	my @streams;
	foreach my $u_triples ($triple->first, $triple->second) {
		my $stream	= $self->query_more( bound => { %{ $bound } }, triples => [ $u_triples ], %args );
		push(@streams, $stream);
	}
	
	my $stream	= shift(@streams);
	while (@streams) {
		$stream	= $stream->concat( shift(@streams) );
	}
	
	$stream	= swatch {
		my $row	= $_;
#		warn "[UNION] " . join(', ', map { join('=',$_,$bridge->as_string($row->{$_})) } (keys %$row)) . "\n";
	} $stream;
	
	return $stream;
}

=begin private

=item C<query_more_optional ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle OPTIONAL query patterns.
Calls C<query_more()> with the OPTIONAL pattern, binding variables if the
pattern succeeds. Returns by calling C<query_more()> with any remaining triples.

=end private

=cut

sub query_more_optional {
	my $self		= shift;
	my %args		= @_;
	my $bound		= delete($args{bound});
	my $triples		= delete($args{triples});
	my $variables	= delete $args{variables};
	my $context		= $args{context};
	my $bridge		= $args{bridge};
	
	my @triples		= @{$triples};
	my $triple		= shift(@triples);
	
	my @triple			= @{ $triple };
	my $data_triples	= $triple[1];
	my $opt_triples		= $triple[2];
	
	my $dstream		= $self->query_more(
			bound		=> $bound,
			triples		=> [ $data_triples ],
			%args
		);
	
	my @names;
	my @results;
	while (my $rowa = $dstream->next) {
# 		warn "****************\n";
# 		warn "OUTER DATA:\n";
# 		foreach my $key (keys %$rowa) {
# 			warn "$key\t=> " . $bridge->as_string( $rowa->{ $key } ) . "\n";
# 		}
		
# 		warn "OPTIONAL TRIPLES: " . Dumper($opt_triples);
		my %obound	= (%$bound, %$rowa);
		my $ostream	= smap {
# 			warn "----------------\n";
# 			warn "OPTIONAL DATA:\n";
# 			foreach my $key (keys %$_) {
# 				warn "$key\t=> " . $bridge->as_string( $_->{ $key } ) . "\n";
# 			}
			$_
		} $self->query_more( bound => \%obound, triples => [$opt_triples], %args );
#		warn 'OPTIONAL ALREADY BOUND: ' . Dumper(\%obound, $opt_triples);
		
		my $count	= 0;
		while (my $rowb = $ostream->next) {
			$count++;
# 			warn "OPTIONAL JOINING: (" . join(', ', keys %$rowa) . ") JOIN (" . join(', ', keys %$rowb) . ")\n";
			my %keysa	= map {$_=>1} (keys %$rowa);
			my @shared	= grep { $keysa{ $_ } } (keys %$rowb);
			@names		= @shared unless (@names);
			my $ok		= 1;
			foreach my $key (@shared) {
				my $val_a	= $rowa->{ $key };
				my $val_b	= $rowb->{ $key };
				unless ($bridge->equals($val_a, $val_b)) {
					warn "can't join because mismatch of $key (" . join(' <==> ', map {$bridge->as_string($_)} ($val_a, $val_b)) . ")";
					$ok	= 0;
					last;
				}
			}
			
			if ($ok) {
				my $row	= { %$rowa, %$rowb };
# 				warn "JOINED:\n";
# 				foreach my $key (keys %$row) {
# 					warn "$key\t=> " . $bridge->as_string( $row->{ $key } ) . "\n";
# 				}
				push(@results, $row);
			} else {
				push(@results, $rowa);
			}
		}
		
		unless ($count) {
#################### XXXXXXXXXXXXXXXXXXXXXXXXX								
#			warn "[optional] didn't return any results. passing through outer result: " . Dumper($rowa);
			push(@results, $rowa);
		}
	}
	
	my $stream	= RDF::Query::Stream->new( \@results, 'bindings', \@names );
	$stream	= swatch {
		my $row	= $_;
#		warn "[OPTIONAL] " . join(', ', map { join('=',$_,$bridge->as_string($row->{$_})) } (keys %$row)) . "\n";
	} $stream;
	return $stream;
}


=begin private

=item C<query_more_bgp ( bound => \%bound, triples => \@triples, variables => \@variables, bridge => $bridge )>

Called by C<query_more()> to handle BasicGraphPattern query patterns (groups of triples).
Calls C<query_more()> with the BGP, which will in turn call C<query_more_triple> for each
of the BGP's triples.

=end private

=cut

sub query_more_bgp {
	my $self		= shift;
	my %args		= @_;
	
	my $bound		= { %{ delete($args{bound}) } };
	my $triples		= delete($args{triples});
	my $variables	= $args{variables};
	my $bridge		= $args{bridge};
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my (undef, @bgp_triples)	= @{ $triple };
	
	my $stream	= $self->query_more( bound => $bound, triples => \@bgp_triples, variables => $variables, %args );
	$stream	= swatch {
		my $row	= $_;
#		warn "[BGP] " . join(', ', map { join('=',$_,$bridge->as_string($row->{$_})) } (keys %$row)) . "\n";
	} $stream;
	return $stream;
}

=begin private

=item C<query_more_ggp ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle GroupGraphPattern query patterns (groups
of triples surrounded by '{ }'). Calls C<query_more()> with the GGP.
Returns by calling C<query_more()> with any remaining triples.

=end private

=cut

sub query_more_ggp {
	my $self		= shift;
	my %args		= @_;
	
	my $bound		= { %{ delete($args{bound}) } };
	my $triples		= delete($args{triples});
	my $variables	= $args{variables};
	my $bridge		= $args{bridge};
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my (undef, $ggp_triples)	= @{ $triple };
	my @ggp_triples	= @{ $ggp_triples };
	
	my $ggpstream	= $self->query_more( bound => $bound, triples => \@ggp_triples, variables => $variables, %args );
	if (@triples) {
		_debug( "with more triples to match." ) if (DEBUG);
		my $stream;
		my $ret	= sub {
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
								_debug( "Setting $name from named graph = $value\n" ) if (DEBUG);
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
		return RDF::Query::Stream->new( $ret, 'bindings', undef, bridge => $bridge );
	} else {
		_debug( "No more triples. Returning NAMED stream." ) if (DEBUG);
		return $ggpstream;
	}
}


=begin private

=item C<query_more_graph ( bound => \%bound, triples => \@triples )>

Called by C<query_more()> to handle NAMED graph query patterns.
Matches graph context (binding the graph to a variable if applicable).
Returns by calling C<query_more()> with any remaining triples.

=end private

=cut

sub query_more_graph {
	my $self		= shift;
	my %args		= @_;

	if ($args{context}) {
		throw RDF::Query::Error::QueryPatternError ( -text => "Can't use nested named graphs" );
	}
	
	my $bound		= { %{ delete($args{bound}) } };
	my $triples		= delete($args{triples});
	my $variables	= $args{variables};
	my $bridge		= delete $args{bridge};
	Carp::confess unless (blessed($bridge));	# XXXassert
	
	my @triples	= @{$triples};
	my $triple	= shift(@triples);
	
	my $context			= $triple->graph;
	my $named_triples	= $triple->pattern;
	
	_debug( 'named triples: ' . Dumper($named_triples), 1 ) if (DEBUG);
	
	
	my $nstream		= RDF::Query::Stream->new();
	foreach my $nmodel_data (values %{ $self->{named_models} }) {
		my ($nbridge, $name)	= @{ $nmodel_data };
		my $stream	= $self->query_more(
								bound => $bound,
								triples => [$named_triples],
								variables => $variables,
								context => $context,
								bridge => $nbridge,
								named_graph => 1
							);
		if (reftype($context) eq 'ARRAY' and $context->[0] eq 'VAR') {
			$stream	= smap {
				my $cvar	= $context->[1];
				my $row	= $_;
				return { %$row, $cvar => $name };
			} $stream;
		}
		$nstream	= $nstream->concat( $stream );
	}
	
	_debug( 'named stream: ' . $nstream, 1 ) if (DEBUG);
	_debug_closure( $nstream ) if (DEBUG);
	
	_debug( 'got named stream' ) if (DEBUG);
	if (@triples) {
		_debug( "with more triples to match." ) if (DEBUG);
		my $_stream;
		my $ret	= sub {
			while ($nstream or $_stream) {
				if (ref($_stream)) {
					my $data	= $_stream->();
					if ($data) {
						return $data;
					} else {
						undef $_stream;
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
								_debug( "Setting $name from named graph = $value\n" ) if (DEBUG);
							}
						}
						$_stream	= $self->query_more(
									bound		=> $bound,
									triples		=> \@triples,
									variables	=> $variables,
									bridge		=> $bridge,
								);
					} else {
						undef $nstream;
					}
				}
			}
			return undef;
		};
		
		my $stream	= RDF::Query::Stream->new( $ret, 'bindings', undef, bridge => $bridge );
		$stream	= swatch {
			my $row	= $_;
#			warn "[GRAPH] " . join(', ', map { join('=',$_,$bridge->as_string($row->{$_})) } (keys %$row)) . "\n";
		} $stream;
		return $stream;
	} else {
		_debug( "No more triples. Returning NAMED stream." ) if (DEBUG);
		return $nstream;
	}
}

=begin private

=item C<join_streams ( $stream1, $stream2, bridge => $bridge )>

Performs a natural, nested loop join of the two streams, returning a new stream
of joined results.

=end private

=cut

sub join_streams {
	my $self	= shift;
	my $a		= shift;
	my $b		= shift;
	my %args	= @_;
	my $bridge	= $args{bridge};
	my $debug	= $args{debug};
	
	my @results;
	my @data	= $b->get_all();
	my @names;
	while (my $rowa = $a->next) {
		LOOP: foreach my $rowb (@data) {
			warn "[--JOIN--] " . join(' ', map { my $row = $_; '{' . join(', ', map { join('=',$_,$bridge->as_string($row->{$_})) } (keys %$row)) . '}' } ($rowa, $rowb)) . "\n" if ($debug);
#			warn "JOINING: (" . join(', ', keys %$rowa) . ") JOIN (" . join(', ', keys %$rowb) . ")\n";
# 			warn "JOINING:\n";
# 			foreach my $row ($rowa, $rowb) {
# 				warn "------\n";
# 				foreach my $key (keys %$row) {
# 					warn "$key\t=> " . $bridge->as_string( $row->{ $key } ) . "\n";
# 				}
# 			}
# 			warn "------\n";
			my %keysa	= map {$_=>1} (keys %$rowa);
			my @shared	= grep { $keysa{ $_ } } (keys %$rowb);
			@names		= @shared unless (@names);
			foreach my $key (@shared) {
				my $val_a	= $rowa->{ $key };
				my $val_b	= $rowb->{ $key };
				unless ($bridge->equals($val_a, $val_b)) {
					warn "can't join because mismatch of $key (" . join(' <==> ', map {$bridge->as_string($_)} ($val_a, $val_b)) . ")" if ($debug);
					next LOOP;
				}
			}
			
			my $row	= { %$rowa, %$rowb };
			if ($debug) {
				warn "JOINED:\n";
				foreach my $key (keys %$row) {
					warn "$key\t=> " . $bridge->as_string( $row->{ $key } ) . "\n";
				}
			}
			push(@results, $row);
		}
	}
	return RDF::Query::Stream->new( \@results, 'bindings', \@names );
}

=begin private

=item C<get_statements ( $subject, $predicate, $object [, $graph] )>

Returns a RDF::Query::Stream iterator of statements matching the statement
pattern (including an optional context).

=end private

=cut

sub get_statements {
	my $self			= shift;
	my %args			= @_;
	my $class			= ref($self);
	
	my ($s,$p,$o)		= @{ delete $args{ triple } };
	my @c				= @{ (delete $args{ graph }) || [] };
	my $req_context		= $args{ require_context };
	my $named_graph		= $args{ named_graph };
	my $bridge			= $args{ bridge };
	
#	warn "get_statements:\n";
#	warn "-> " . (blessed($_) ? $bridge->as_string($_) : '') . "\n" for ($s,$p,$o);
	my $stream			= $bridge->get_statements( $s, $p, $o, @c );
#	$stream	= swatch { warn (blessed($_) ? $bridge->as_string($_) : '') } $stream;
	
	if (ref($p) and $bridge->is_resource($p) and $bridge->uri_value($p) =~ m<^http://www.w3.org/2006/09/time#(.*)>) {
 		my $pred	= $1;
# 		warn "owl-time predicate: $pred\n";
 		if ($pred eq 'inside') {
#			warn "-> " . (blessed($_) ? $bridge->as_string($_) : '') . "\n" for ($s,$p,$o);
#			warn Dumper([$s,$p,$o]);
 			my $interval	= $s;
 			my $instant		= $o;
 			if ($bridge->is_node( $instant )) {
 				if (not defined($interval)) {
#		 			warn "instant: " . $instant->as_string;
# 					warn Data::Dumper->Dump([$interval, $instant], [qw(interval instant)]);
 					my ($dt)	= $self->_promote_to( $bridge, 'DateTime', $bridge->literal_as_array( $instant ) );
 					my $sparql	= sprintf( <<"END", ($dt) x 4 );
 						PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
 						PREFIX t: <http://www.w3.org/2006/09/time#>
 						SELECT ?interval ?b ?e
 						WHERE {
							{
								?interval a t:Interval ;
											t:begins ?b ; t:ends ?e .
								FILTER( ?b <= "%s"^^xsd:dateTime && ?e > "%s"^^xsd:dateTime )
							} UNION {
								?interval a t:Interval ;
											t:begins ?b .
								OPTIONAL { ?interval t:ends ?e } .
								FILTER( !BOUND(?e) ) .
								FILTER( ?b <= "%s"^^xsd:dateTime )
							} UNION {
								?interval a t:Interval .
								OPTIONAL { ?interval t:begins ?b } .
								?interval t:ends ?e .
								FILTER( !BOUND(?b) ) .
								FILTER( ?e > "%s"^^xsd:dateTime )
							} UNION {
								?interval a t:Interval .
								OPTIONAL { ?interval t:begins ?b } .
								OPTIONAL { ?interval t:ends ?e } .
								FILTER( !BOUND(?b) && !BOUND(?e) ) .
							}
 						}
END
					my $query		= $class->new( $sparql, undef, undef, 'sparql' );
					my $time_stream	= $query->execute( $bridge->model );
					my $inside		= $bridge->new_resource('http://www.w3.org/2006/09/time#inside');
					my $time_stmts	= smap {
										return undef unless (reftype($_) eq 'ARRAY');
										warn sprintf("found an interval that contains $dt: [%s, %s]", map {blessed($_) ? $bridge->as_string($_) : '' } (@{$_}[1,2]));
										my $stmt	= $bridge->new_statement($_->[0],$inside,$instant);
										$stmt
									} $time_stream;
					$stream			= $stream->concat( $time_stmts );
 				} else {
 					warn "time:inside called with known interval";
 				}
 			} else {
 				warn "cannot inference time:inside without a time instant";
 			}
 		}
 	}
	
	
	return $stream;
	
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
	my $base	= $parsed->{base};
	if ($base) {
		$base	= $base->[1];
	} else {
		$base	= $self->{base};
	}
	
	if (ref($data) and reftype($data) eq 'ARRAY') {
		if ($data->[0] ne 'URI') {
			$data	= ['URI',$data];
		}
	}
	
	my $uri;
	if (ref($data)) {
		if (reftype($data) eq 'ARRAY' and ref($data->[1])) {
			my $prefix	= $data->[1][0];
			unless (exists($parsed->{'namespaces'}{$data->[1][0]})) {
				_debug( "No namespace defined for prefix '${prefix}'" ) if (DEBUG);
			}
			my $ns	= $parsed->{'namespaces'}{$prefix};
			$uri	= join('', $ns, $data->[1][1]);
		} else {
			$uri	= $data->[1];
		}
	} else {
		$uri	= $data;
	}
	
	if ($base) {
		
		### We have to work around the URI module not accepting IRIs. If there's
		### Unicode in the IRI, pull it out, leaving behind a breadcrumb. Turn
		### the URI into an absolute URI, and then replace the breadcrumbs with
		### the Unicode.
		my @uni;
		my $count	= 0;
		while ($uri =~ /([\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{02FF}\x{0370}-\x{037D}\x{037F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]+)/) {
			my $text	= $1;
			push(@uni, $text);
			$uri		=~ s/$1/',____' . $count . '____,'/e;
			$count++;
		}
		my $abs			= URI->new_abs( $uri, $base );
		my $uri			= $abs->as_string;
		while ($uri =~ /,____(\d+)____,/) {
			my $num	= $1;
			my $i	= index($uri, ",____${num}____,");
			my $len	= 10 + length($num);
			substr($uri, $i, $len)	= shift(@uni);
		}
		return $uri;
	} else {
		return $uri;
	}
}

=begin private

=item C<_check_constraints ( \%bound, \@data )>

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
								my $name	= $data->[0];
								my $value	= $values->{ $name };
								return $value;
							},
					URI		=> sub { my ($self, $values, $data) = @_; return $data->[0] },
					LITERAL	=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								
								if (defined($data->[2])) {
									my $literal	= $data->[0];
									my $lang	= $data->[1];
									my $uri		= $self->qualify_uri( $data->[2] );
									return $bridge->new_literal( $literal, $lang, $uri );
								}
								return $data->[0];
							},
					'~~'	=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								
								my $text	= $self->_check_constraints( $values, $data->[0], %args );
								my $pattern	= $self->_check_constraints( $values, $data->[1], %args );
								if (scalar(@$data) == 3) {
									my $flags	= $self->get_value( $self->_check_constraints( $values, $data->[2], %args ), %args );
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
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands = map {
									my $value	= $self->_check_constraints( $values, $_, %args );
									my $v		= $self->get_value( $value, %args );
									$v;
								} @{ $data };
								
								my $eq;
								if ($self->_one_isa( $bridge, 'DateTime', @operands )) {
									@operands	= $self->_promote_to( $bridge, 'DateTime', @operands );
									$eq			= (0 == DateTime->compare( $operands[0], $operands[1] ));
								} else {
									$eq		= eval { (0 == ncmp(@operands, $bridge)) };
#									warn $@;
								}
# 								warn "EQ [$eq]: " . Dumper(\@operands);
								return $eq;
							},
					'!='	=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands = map { $self->get_value( $self->_check_constraints( $values, $_, %args ), %args ) } @{ $data };
								if ($self->_one_isa( $bridge, 'DateTime', @operands )) {
									@operands	= $self->_promote_to( $bridge, 'DateTime', @operands );
								}
								foreach my $node (@operands) {
									next unless (ref($node));
									unless ($self->_isa_known_node_type( $bridge, $node )) {
										warn "not a known type in neq: " . Dumper($node) if ($debug);
										return 0;
									}
								}
								my $eq	= ncmp($operands[0], $operands[1], $bridge) != 0;
								return $eq;
							},
					'<'		=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands = map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								my $cmp		= ncmp($operands[0], $operands[1], $bridge);
#								warn '-----------------------------';
#								warn "LESS-THAN OP[0]: " . eval { $operands[0]->as_string };
#								warn "LESS-THAN OP[1]: " . eval { $operands[1]->as_string };
#								warn "LESS-THAN: $cmp\n";
								return $cmp == -1;
							},
					'>'		=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands = map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								return ncmp($operands[0], $operands[1], $bridge) == 1;
							},
					'<='	=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands = map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								return ncmp($operands[0], $operands[1], $bridge) != 1
							},
					'>='	=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands = map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								return ncmp($operands[0], $operands[1], $bridge) != -1
							},
					'&&'	=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @results;
								foreach my $part (@{ $data }) {
									my $error;
									my $value;
									try {
										my $data	= $self->_check_constraints( $values, $part, %args );
										$value		= $self->get_function('sop:boolean')->( $self, $bridge, $data );
										push(@results, $value);
									} catch RDF::Query::Error::FilterEvaluationError with {
										$error	= shift;
										push(@results, $error);
									};
									if (not $error and not $value) {
										return 0;
									}
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
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my $error;
								my $bool	= 0;
								foreach my $part (@{ $data }) {
									undef $error;
									my $value;
									try {
										my $data	= $self->_check_constraints( $values, $part, %args );
										$value		= $self->get_function('sop:boolean')->( $self, $bridge, $data );
									} catch RDF::Query::Error::FilterEvaluationError with {
										$error	= shift;
										$value	= 0;
									};
									
# 									warn "OR [1]: " . Dumper($part);
									if ($value) {
										$bool	= 1;
										last;
									}
								}
								
								if ($error) {
									throw $error;
								} else {
									return $bool;
								}
							},
					'*'		=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands	= map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								my @types		= map { $bridge->literal_datatype( $_ ) } @operands;
								my @values		= map { $self->get_function('sop:numeric')->( $self, $bridge, $_ ) } @operands;
								my $value		= $values[0] * $values[1];
								my $type		= $self->_result_type( '*', @types );
								return $bridge->new_literal($value, undef, $type);
							},
					'/'		=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands	= map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								my @types		= map { $bridge->literal_datatype( $_ ) } @operands;
								my @values		= map { $self->get_function('sop:numeric')->( $self, $bridge, $_ ) } @operands;
								my $value		= $values[0] / $values[1];
								my $type		= $self->_result_type( '/', @types );
								return $bridge->new_literal($value, undef, $type);
							},
					'+'		=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands	= map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								my @types		= map { $bridge->literal_datatype( $_ ) } @operands;
								my @values		= map { $self->get_function('sop:numeric')->( $self, $bridge, $_ ) } @operands;
								my $value		= $values[0] + $values[1];
								my $type		= $self->_result_type( '+', @types );
								return $bridge->new_literal($value, undef, $type);
							},
					'-'		=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my @operands	= map { $self->_check_constraints( $values, $_, %args ) } @{ $data };
								my @types		= map { $bridge->literal_datatype( $_ ) } @operands;
								my @values		= map { $self->get_function('sop:numeric')->( $self, $bridge, $_ ) } @operands;
								my $value		= (1 == @operands) ? (-1 * $values[0]) : ($values[0] - $values[1]);
								my $type		= $self->_result_type( '-', @types );
								return $bridge->new_literal($value, undef, $type);
							},
					'!'		=> sub {
								my $self	= shift;
								my $values	= shift;
								my $data	= shift;
								my %args	= @_;
								my $bridge	= $args{bridge};
								my $value	= $self->_check_constraints( $values, $data->[0], %args );
								if (defined $value) {
									my $bool	= $self->get_function('sop:boolean')->( $self, $bridge, $value );
									return (not $bool) ? $self->_true( $bridge ) : $self->_false( $bridge );
								} else {
									throw RDF::Query::Error::TypeError ( -text => 'Cannot negate an undefined value' );
								}
							},
					'FUNCTION'	=> sub {
						our %functions;
						my $self	= shift;
						my $values	= shift;
						my $data	= shift;
						my %args	= @_;
						my $bridge	= $args{bridge};
						my $uri		= $self->qualify_uri( $data->[0][1] );
						my $func	= $self->get_function( $uri, %args );
						if (ref($func) and reftype($func) eq 'CODE') {
							my $value;
							$self->{'values'}	= $values;
							my @args	= map {
												($_->[0] eq 'VAR')
													? $values->{ $_->[1] }
													: $self->_check_constraints( $values, $_, %args )
											} @{ $data }[1..$#{ $data }];
							$value	= $func->(
										$self,
										$bridge,
										@args
									);
							{ no warnings 'uninitialized';
								_debug( "function <$uri> -> $value" ) if (DEBUG);
							}
							return $value;
						} else {
							warn "No function defined for <${uri}>\n";
							Carp::cluck if ($::counter++ > 5);
							return undef;
						}
					},
				);
sub _check_constraints {
	my $self	= shift;
	my $values	= shift;
	my $data	= shift;
	my %args	= @_;
	Carp::confess unless ($args{bridge});	# XXXassert
	
	_debug( '_check_constraints: ' . Dumper($data), 2 ) if (DEBUG);
	return 1 unless scalar(@$data);
	my $op		= $data->[0];
	my $code	= $dispatch{ $op };
	
	if ($code) {
#		local($Data::Dumper::Indent)	= 0;
		my $result	= $code->( $self, $values, [ @{$data}[1..$#{$data}] ], %args );
		_debug( "OP: $op -> " . Dumper($data), 2 ) if (DEBUG);
		return $result;
	} else {
		confess "OPERATOR $op NOT IMPLEMENTED!";
	}
}
}

=begin private

=item C<check_constraints ( \%bound, \@data )>

Returns the value returned by evaluating the expression structures in C<@data>
with the bound variables in C<%bound>. Catches any evaluation exceptions,
returning undef if an error is raised.

=end private

=cut

sub check_constraints {
	my $self	= shift;
	my $values	= shift;
	my $data	= shift;
	my %args	= @_;
	
	my $result;
	try {
		$result	= $self->_check_constraints( $values, $data, %args );
	} catch RDF::Query::Error::FilterEvaluationError with {
		my $error	= shift;
		warn "FilterEvaluationError: $error\n" if ($debug);
		$result	= undef;
	} catch RDF::Query::Error::TypeError with {
		my $error	= shift;
		warn "TypeError: $error\n" if ($debug);
		$result	= undef;
	} except {
		my $error	= shift;
		warn "Error: $error\n" if ($debug);
	};
	return $result;
}


{
my $xsd				= 'http://www.w3.org/2001/XMLSchema#';
my $integerTypes	= qr<^http://www.w3.org/2001/XMLSchema#(integer|non(Positive|Negative)Integer|(positive|negative)Integer|long|int|short|byte|unsigned(Long|Int|Short|Byte))>;
my @typeOrder		= qw(double float decimal integer);
sub _result_type {
	my $self	= shift;
	my $op		= shift;
	my @data	= @_;
	no warnings 'uninitialized';
	return "${xsd}integer" if ($data[0] =~ $integerTypes and $data[1] =~ $integerTypes);
	foreach my $t (@typeOrder) {
		no warnings 'uninitialized';
		return "${xsd}${t}" if ($data[0] =~ /$t/i or $data[1] =~ /$t/i);
	}
}
}

sub _true {
	my $self	= shift;
	my $bridge	= shift || $self->bridge;
	return $bridge->new_literal('true', undef, 'http://www.w3.org/2001/XMLSchema#boolean');
}

sub _false {
	my $self	= shift;
	my $bridge	= shift || $self->bridge;
	return $bridge->new_literal('false', undef, 'http://www.w3.org/2001/XMLSchema#boolean');
}

sub _isa_known_datatype {
	my $self	= shift;
	my $type	= shift;
	no warnings 'uninitialized';
	return 1 if ($type =~ m<^http://www.w3.org/2001/XMLSchema#(boolean|double|float|decimal|integer|dateTime|string)$>);
	return 0;
}

sub _isa_known_node_type {
	my $self	= shift;
	my $bridge	= shift;
	my $data	= shift;
	
	return 0 unless (ref($data));
	return 1 if (blessed($_) and $_->isa( 'DateTime' ));
	return 1 if (blessed($_) and $bridge->is_resource($_));
	if (blessed($data) and $bridge->is_literal($data)) {
		my $type	= $bridge->literal_datatype( $data );
		if ($type) {
			return $self->_isa_known_datatype( $type );
		} else {
			return 1;
		}
	}
	
	if (reftype($data) eq 'ARRAY') {
		if ($data->[0] eq 'LITERAL') {
			if ($data->[3]) {
				my $type	= $data->[3];
				return $self->_isa_known_datatype( $type );
			} else {
				return 1;
			}
		} else {
			if ($data->[2]) {
				my $type	= $data->[2];
				return 1 if ($type =~ m<^http://www.w3.org/2001/XMLSchema#(boolean|double|float|decimal|integer|dateTime|string)$>);
				return 0;
			} else {
				return 1;
			}
		}
	} else {
		return 0;
	}
}

sub _one_isa {
	my $self	= shift;
	my $bridge	= shift;
	my $type	= shift;
	my $a		= shift;
	my $b		= shift;
#	warn Data::Dumper->Dump([$a,$b], [qw(a b)]);
	for ($a, $b) {
		return 1 if (blessed($_) and $_->isa( $type ));
		return 1 if (blessed($_) and reftype($_) eq 'ARRAY' and $_->[0] eq $type);
		if ($type eq 'DateTime') {
			return 1 if (blessed($_) and $bridge->is_literal($_) and $bridge->literal_datatype($_) eq 'http://www.w3.org/2001/XMLSchema#dateTime');
			no warnings 'uninitialized';
			if (reftype($_) eq 'ARRAY') {
				return 1 if ($_->[2] eq 'http://www.w3.org/2001/XMLSchema#dateTime');
			}
		}
	}
	return 0;
}

sub _promote_to {
	my $self	= shift;
	my $bridge	= shift;
	Carp::confess unless (blessed($bridge));	# XXXassert
	
	my $type	= shift;
	my @objects	= @_;
	if ($type eq 'DateTime') {
		@objects	= map {
						(blessed($_) and $_->isa($type))
							? $_
							: (reftype($_) eq 'ARRAY' and $_->[0] eq 'LITERAL')
								? $self->call_function( $bridge, {}, 'http://www.w3.org/2001/XMLSchema#dateTime', $_ )
								: $self->call_function( $bridge, {}, 'http://www.w3.org/2001/XMLSchema#dateTime', [ 'LITERAL', @$_ ] );
					} @objects;
	}
	return @objects;
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
	my %args	= @_;
	my $bridge	= $args{bridge};
	Carp::confess unless ($bridge);	# XXXassert
	
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

=item C<get_function ( $uri, %args )>

If C<$uri> is associated with a query function, returns a CODE reference
to the function. Otherwise returns C<undef>.

=end private

=cut

sub get_function {
	my $self	= shift;
	my $uri		= shift;
	my %args	= @_;
	warn "trying to get function from $uri" if ($debug);
	
	my $func	= $self->{'functions'}{$uri}
				|| $RDF::Query::functions{ $uri };
	if ($func) {
		return $func;
	} elsif ($self->{options}{net_filters}) {
		return $self->net_filter_function( $uri, %args );
	}
	return;
}


=begin private

=item C<< call_function ( $bridge, $bound, $uri, @args ) >>

If C<$uri> is associated with a query function, calls the function with the supplied arguments.

=end private

=cut

sub call_function {
	my $self	= shift;
	my $bridge	= shift;
	my $bound	= shift;
	my $uri		= shift;
	warn "trying to get function from $uri" if (DEBUG);
	
	my $filter			= [ 'FUNCTION', ['URI', $uri], @_ ];
	return $self->check_constraints( $bound, $filter, bridge => $bridge );
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
	my %args	= @_;
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
	
	my $resp	= $self->{useragent}->get( $impl );
	unless ($resp->is_success) {
		warn "No content available from $uri: " . $resp->status_line;
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
		
		my $sigresp	= $self->{useragent}->get( "${impl}.asc" );
#		if (not $sigresp) {
#			throw RDF::Query::Error::ExecutionError -text => "Required signature not found: ${impl}.asc\n";
		if ($sigresp->is_success) {
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

	my ($rt, $cx)	= $self->new_javascript_engine(%args);
	my $r		= $cx->eval( $content );
	
#	die "Requested function URL does not match the function's URI" unless ($meta->{uri} eq $url);
	return sub {
		my $query	= shift;
		my $bridge	= shift;
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
	my %args	= @_;
	my $bridge	= $args{bridge};
	
	my $rt		= JavaScript::Runtime->new();
	my $cx		= $rt->create_context();
	my $meta	= $bridge->meta;
	$cx->bind_function( 'warn' => sub { warn @_ if ($debug || $js_debug) } );
	$cx->bind_function( '_warn' => sub { warn @_ } );
	$cx->bind_function( 'makeTerm' => sub {
		my $term	= shift;
		my $lang	= shift;
		my $dt		= shift;
#		warn 'makeTerm: ' . Dumper($term);
		if (not blessed($term)) {
			my $node	= $bridge->new_literal( $term, $lang, $dt );
			return $node;
		} else {
			return $term;
		}
	} );
	
	my $toString	= sub {
		my $string	= $bridge->literal_value( @_ ) . '';
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

sub ncmp ($$;$) {
	my ($a, $b, $bridge)	= @_;
	for ($a, $b) {
		throw RDF::Query::Error::FilterEvaluationError ( -text => 'Cannot sort undefined values' ) unless defined($_);
	}
	my @node_type	= map {
		my $node	= $_;
		my $type;
		if (blessed($node) and not $node->isa('DateTime')) {
			if ($bridge->is_blank( $node )) {
				$type	= 'BLANK' ;
			} elsif ($bridge->is_resource( $node )) {
				$type	= 'URI';
			} elsif ($bridge->is_literal( $node )) {
				$type	= 'LITERAL';
			} else {
				$type	= undef;
			}
		} elsif (ref($node) and reftype($node) eq 'ARRAY' and $node->[0] =~ /^[A-Z]+$/) {
			$type	= 'LITERAL';
		} else {
			$type	= 'LITERAL';
		}
		$type;
	} ($a, $b);
	
	if ($node_type[0] ne $node_type[1]) {
		throw RDF::Query::Error::FilterEvaluationError ( -text => 'Cannot compare values of different types' );
	}
	
	my $get_value	= sub {
		my $node	= shift;
		if (blessed($node) and not $node->isa('DateTime')) {
			return $bridge->literal_value( $node );
		} elsif (ref($node) and reftype($node) eq 'ARRAY') {
			return $node->[0];
		} else {
			return $node;
		}
	};
	
	my $get_type	= sub {
		my $node	= shift;
		if (blessed($node) and not $node->isa('DateTime')) {
			return $bridge->literal_datatype( $node );
		} elsif (ref($node) and reftype($node) eq 'ARRAY') {
			return $node->[2];
		} else {
			return undef;
		}
	};
	
	my $get_lang	= sub {
		my $node	= shift;
		if (blessed($node) and not $node->isa('DateTime')) {
			return $bridge->literal_value_language( $node );
		} elsif (ref($node) and reftype($node) eq 'ARRAY') {
			return $node->[1];
		} else {
			return undef;
		}
	};
	
	my @values	= map { $get_value->( $_ ) } ($a, $b);
	my @types	= map { $get_type->( $_ ) } ($a, $b);
	my @langs	= map { $get_lang->( $_ ) } ($a, $b);
	my @numeric	= map { is_numeric_type($_) } @types;
#	warn Dumper(\@values, \@types, \@langs, \@numeric);	# XXX
	
	no warnings 'numeric';
	no warnings 'uninitialized';
	my $num_cmp		= ($numeric[0] and $numeric[1]);
	my $lang_cmp	= ($langs[0] or $langs[1]);
	
	if ($num_cmp) {
#		warn "num cmp";
		for (@values) {
			unless (looks_like_number($_)) {
				throw RDF::Query::Error::FilterEvaluationError ( -text => "Not a numeric literal: '$_'" );
			}
		}
		return ($values[0] <=> $values[1]);
	} elsif ($lang_cmp) {
#		warn "lang cmp";
		return (lc($langs[0]) cmp lc($langs[1])) if (lc($langs[0]) ne lc($langs[1]));
		my $av	= $values[0];
		my $bv	= $values[1];
		return ($values[0] cmp $values[1]);
	} else {
		if (RDF::Query->_isa_known_datatype($types[0]) xor RDF::Query->_isa_known_datatype($types[1])) {
			if ($types[0] eq $types[1] and $values[0] eq $values[1]) {
				return 0;
			} else {
				throw RDF::Query::Error::FilterEvaluationError ( -text => 'Cannot compare values of unknown types' );
			}
		}
		if (defined($types[0]) or defined($types[1])) {
			no warnings 'uninitialized';
			if ($types[0] ne $types[1]) {
				throw RDF::Query::Error::FilterEvaluationError ( -text => 'Cannot compare values of unknown types' );
			}
		}
#		warn "plain cmp";
		return ($values[0] cmp $values[1]);
	}
}

=begin private

=item C<is_numeric_type ( $type )>

Returns true if the specified C<$type> URI represents a numeric type.
This includes XSD numeric, double and integer types.
	
=end private

=cut

sub is_numeric_type {
	my $type	= shift || '';
	return ($type =~ m<^http://www.w3.org/2001/XMLSchema#(integer|decimal|float|double|numeric|non(Positive|Negative)Integer|(positive|negative)Integer|long|int|short|byte|unsigned(Long|Int|Short|Byte))>) ? 1 : 0;
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
	
	Carp::confess unless ($nodes);	# XXXassert
	
	if ($unique) {
		my %seen;
		my $old	= $nodes;
		$nodes	= sgrep {
			my $row	= $_;
			no warnings 'uninitialized';
			my $key	= join($;, map {$bridge->as_string( $_ )} map { $row->{$_} } @variables);
			return (not $seen{ $key }++);
		} $nodes;
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
		_debug( "ordering by $col" ) if (DEBUG);
		
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
					my $result	= $self->check_constraints( \%data, $data, bridge => $bridge );
					my $value	= $self->get_value( $result, bridge => $bridge );
					[ $node, $value ]
				} @nodes;
		
		@nodes	= sort {
					my $val	= eval { ncmp($a->[1],$b->[1]) } || 0;
				} @nodes;
		@nodes	= reverse @nodes if ($dir eq 'DESC');
		
		@nodes	= map { $_->[0] } @nodes;


		my $type	= $nodes->type;
		my $names	= [$nodes->binding_names];
		my $args	= $nodes->_args;
		$nodes		= RDF::Query::Stream->new( sub { shift(@nodes) }, $type, $names, %$args );
	}
	
	if ($offset) {
		$nodes->() while ($offset--);
	}
	
	if (defined($limit)) {
		$nodes	= sgrep { if ($limit > 0) { $limit--; 1 } else { 0 } } $nodes;
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
	
	if ($named) {
		my $class	= ref($self->bridge) || $self->loadable_bridge_class;
		my $bridge	= $class->new();
		$bridge->add_uri( $url, $named );
		$self->{ named_models }{ $url }	= [$bridge, $bridge->new_resource($url)];
	} else {
		$bridge->add_uri( $url );
	}
}

=begin private

=item C<parse_string ( $string, $name )>

Parse the RDF in $string into the RDF store.
If $name is TRUE, associate all parsed triples with a named graph.

=end private

=cut
sub parse_string {
	my $self	= shift;
	my $string	= shift;
	my $name	= shift;
	my $bridge	= $self->bridge;
	
	if ($name) {
		my $class	= ref($self->bridge) || $self->loadable_bridge_class;
		my $bridge	= $class->new();
		$bridge->add_string( $string, $name, $name );
		$self->{ named_models }{ $name }	= [$bridge, $bridge->new_resource($name)];
	} else {
		$bridge->add_string( $string );
	}
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

=item C<bridge ()>

Returns the model bridge of the default graph.

=cut

sub bridge {
	Carp::confess if ($::NO_BRIDGE);
	my $self	= shift;
	if (@_) {
		$self->{bridge}	= shift;
	}
	return $self->{bridge};
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
		
		### PROFILING ###
		if (PROF) {
			wrap $AUTOLOAD,
				pre		=> sub { _PROFILE(1,$AUTOLOAD) },
				post	=> sub { _PROFILE(0,$AUTOLOAD) };
		}
		goto &$method;
	} else {
		croak qq[Can't locate object method "$method" via package $class];
	}
}


sub _PROFILE {
	my $enter	= shift;
	my $name	= shift;
	my $time	= gettimeofday();
#	my ($package, $filename, $line, $sub)	= caller(2);
	my $char	= ($enter) ? '>' : '<';
	print {$PROF} "${char} $name $time\n";
}



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
