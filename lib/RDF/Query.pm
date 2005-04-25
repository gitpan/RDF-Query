# RDF::Query
# -------------
# $Revision: 1.12 $
# $Date: 2005/04/25 01:27:40 $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query - A SPARQL/RDQL implementation for RDF::Redland and RDF::Core

=cut

package RDF::Query;

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

 L<RDF::Redland|RDF::Redland>
  or
 L<RDF::Core|RDF::Core>

 L<Parse::RecDescent|Parse::RecDescent>
 L<LWP::Simple|LWP::Simple>
 L<Sort::Naturally>

=cut

use strict;
use warnings;
use Carp qw(carp croak confess);

use LWP::Simple ();
use Data::Dumper;
use Sort::Naturally;

use RDF::Query::Parser::RDQL;
use RDF::Query::Parser::SPARQL;

use RDF::Query::Model::Redland;
use RDF::Query::Model::RDFCore;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.12 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
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
	my $self 	= bless( {}, $class );
	no warnings 'uninitialized';
	my $parser	= ($lang eq 'rdql' or $languri eq 'http://jena.hpl.hp.com/2003/07/query/RDQL')
				? RDF::Query::Parser::RDQL->new()
				: RDF::Query::Parser::SPARQL->new();
	$self->{parser}	= $parser;
	$self->{parsed}	= $parser->parse( $query );
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
	if ($stream) {
		my $row		= $stream->();
		if (ref($row)) {
			return @{ $row };
		}
	}
	return undef;
}

=item C<execute ( $model )>

Executes the query using the specified model. If called in a list
context, returns an array of rows, otherwise returns an iterator.

=cut
sub execute {
	my $self	= shift;
	my $model	= shift;
	my $bridge	= (UNIVERSAL::isa($model, 'RDF::Redland::Model'))
				? RDF::Query::Model::Redland->new( $model )
				: RDF::Query::Model::RDFCore->new( $model );
	local($self->{model})	= $model;
	$self->{bridge}			= $bridge;
	
	my $parser	= $self->{parser};
	my $parsed	= $self->fixup( $self->{parsed} );
	my $stream	= $self->query_more( {}, @{ $parsed->{'triples'} } );
	warn "got stream: $stream" if ($debug);
	use B::Deparse; my $deparse = B::Deparse->new("-p", "-sC");
	warn 'stream: ' . $deparse->coderef2text($stream) if ($debug > 1);
	$stream		= $self->sort_rows( $stream, $parsed );
	if (wantarray) {
		my @results;
		while ($stream and my $r = $stream->()) {
			push(@results, $r);
		}
		return @results;
	} else {
		return RDF::Query::Stream->new( $stream );
	}
}

sub fixup {
	my $self		= shift;
	my $parsed		= shift;
	## CONVERT URIs to Resources, and strings to Literals
	foreach my $triple (@{ $parsed->{'triples'} }) {
		my ($sub,$pred,$obj)	= @{ $triple };
		if (UNIVERSAL::isa($pred, 'ARRAY') and $pred->[0] eq 'URI') {
			my $preduri	= (UNIVERSAL::isa($pred->[1], 'ARRAY'))
						? join('', $parsed->{'namespaces'}{$pred->[1][0]}, $pred->[1][1])
						: $pred->[1];
			$triple->[1]			= $self->bridge->new_resource($preduri);
		}
		
		if (UNIVERSAL::isa($sub, 'ARRAY') and $sub->[0] eq 'URI') {
			my $resource	= ref($sub->[1])
							? join('', $parsed->{'namespaces'}{$sub->[1][0]}, $sub->[1][1])
							: $sub->[1];
			$triple->[0]	= $self->bridge->new_resource($resource);
# 		} elsif ($sub->[0] eq 'LITERAL') {
# 			my $literal		= $self->bridge->new_literal($sub->[1]);
# 			$triple->[0]	= $literal;
		}
		
# XXX THIS CONDITIONAL SHOULD ALWAYS BE TRUE ... ? (IT IS IN ALL TEST CASES)
#		if (ref($obj)) {
			if (UNIVERSAL::isa($obj, 'ARRAY') and $obj->[0] eq 'LITERAL') {
				my $literal		= $self->bridge->new_literal($obj->[1]);
				$triple->[2]	= $literal;
			} elsif (UNIVERSAL::isa($obj, 'ARRAY') and $obj->[0] eq 'URI') {
				my $resource	= ref($obj->[1])
								? join('', $parsed->{'namespaces'}{$obj->[1][0]}, $obj->[1][1])
								: $obj->[1];
				$triple->[2]	= $self->bridge->new_resource($resource);
			}
#		} else {
#			warn "Object not a reference: " . Dumper($obj) . ' ';
#		}
	}
	
	## LOAD ANY EXTERNAL RDF FILES
	my $sources	= $parsed->{'sources'};
	if (UNIVERSAL::isa( $sources, 'ARRAY' )) { # and scalar(@{ $sources })) {
		$self->parse_urls( map { $_->[1] } @{ $sources } );
	}

	return $parsed;
}


=for private

=item C<query_more ( @triples )>

Internal recursive query function to bind pivot variables until only result
variables are left and found from the RDF store. Called from C<query>.

=end private

=cut
sub query_more {
	my $self	= shift;
	my $bound	= shift;
	
	my @triples	= @_;
#	warn 'query_more: ' . Dumper(\@triples);
	our $indent;

	my $parsed	= $self->parsed;
	my $bridge	= $self->bridge;
	my $triple	= shift(@triples);
	unless (ref($triple)) {
		carp "Something went wrong. No triple passed to query_more";
		return undef;
	}
	my @triple	= @{ $triple };
	
	no warnings 'uninitialized';
	warn "${indent}query_more: " . join(' ', map { $bridge->isa_node($_) ? '<' . $_->getLabel . '>' : $_->[1] } @triple) . "\n" if ($debug);
	warn "${indent}-> with " . scalar(@triples) . " triples to go\n" if ($debug);
	if ($debug) {
		warn "${indent}-> more: " . join(' ', map { $bridge->isa_node($_) ? '<' . $_->getLabel . '>' : $_->[1] } @{$_}) . "\n" for (@triples);
	}
	
	my $vars	= 0;
	my ($var, $method);
	my (@vars, @methods);
	
	my @methodmap	= $bridge->statement_method_map;
	for my $idx (0 .. 2) {
		my $data	= $triple[$idx];
		if (UNIVERSAL::isa($data, 'ARRAY')) {	# and $data->[0] eq 'VAR'
			if ($data->[0] eq 'VAR' or $data->[0] eq 'BLANK') {
				my $tmpvar	= ($data->[0] eq 'VAR') ? $data->[1] : '_' . $data->[1];
				my $val = $bound->{ $tmpvar };
				if ($bridge->isa_node($val)) {
					warn "${indent}-> already have value for $tmpvar: " . $val->getLabel . "\n" if ($debug);
					$triple[$idx]	= $val;
				} elsif (++$vars > 1) {
					warn "${indent}-> we've seen $vars variables in this triple... punt\n" if ($debug);
					if ($self->{punt} >= scalar(@{$self->{parsed}{triples}})) {
						warn "${indent}-> we've punted too many times. binding on ?$tmpvar" if ($debug);
						$triple[$idx]	= undef;
						$vars[$idx]		= $tmpvar;
						$methods[$idx]	= $methodmap[ $idx ];
	#					warn Dumper(\@triple) if ($debug > 1);
	#					warn Dumper(\@triples) if ($debug);
					} elsif (scalar(@triples)) {
						$self->{punt}++;
						push(@triples, $triple);
						return $self->query_more( { %{ $bound } }, @triples );
					} else {
						carp "Something went wrong. Not enough triples passed to query_more";
						return undef;
					}
				} else {
					warn "${indent}-> found variable $tmpvar (we've seen $vars variables already)\n" if ($debug);
					$triple[$idx]	= undef;
					$vars[$idx]		= $tmpvar;
					$methods[$idx]	= $methodmap[ $idx ];
				}
			}
		}
	}
	
	warn "${indent}getting: " . join(', ', grep defined, @vars) . "\n" if ($debug);
	
	warn Dumper([map { ($_) ? $_->getLabel : 'undef' } @triple]) if ($debug);
	my $statments	= $bridge->get_statements( @triple );
	my @streams;
	my $stream;
#	while (my $stmt = $statments->()) {
	push(@streams, sub {
		my $result;
		my $stmt	= $statments->();
		unless ($stmt) {
			warn 'no more statements' if ($debug);
			return undef;
		}
		if ($vars) {
			foreach (0 .. $#vars) {
				next unless defined($vars[$_]);
				my $var		= $vars[ $_ ];
				my $method	= $methods[ $_ ];
				warn "${indent}-> got variable $var = " . $stmt->$method()->getLabel . "\n" if ($debug);
				$bound->{ $var }	= $stmt->$method();
			}
		} else {
			warn "${indent}-> triple with no variable. ignoring.\n" if ($debug);
		}
		if (scalar(@triples)) {
			if ($debug) {
				warn "${indent}-> now for more triples...\n";
				warn "${indent}-> more: " . join(' ', map { $bridge->isa_node($_) ? '<' . $_->getLabel . '>' : $_->[1] } @{$_}) . "\n" for (@triples);
				warn Dumper(\@triples);
			}
			$indent	.= '  ';
			warn 'adding a new stream for more triples' if ($debug);
			unshift(@streams, $self->query_more( { %{ $bound } }, @triples ) );
		} else {
			my @values	= map { $bound->{$_} } map { $_->[1] } @{ $parsed->{'variables'} };
			warn "${indent}-> no triples left: result: " . join(', ', map {$_->getLabel} grep defined, @values) . "\n" if ($debug);
			if (check_constraints( $bound, $parsed->{'constraints'} )) {
				$result	= [@values];
			} else {
				warn "${indent}-> failed constraints check\n" if ($debug);
			}
		}
		foreach my $var (@vars) {
			if (defined($var)) {
				warn "deleting value for $var" if ($debug);
				delete $bound->{ $var };
			}
		}
		if ($result) {
			local($Data::Dumper::Indent)	= 0;
			warn 'found a result: ' . Dumper($result) if ($debug);
			return ($result);
		} else {
			warn 'no results yet...' if ($debug);
			return ();
		}
	} );

	substr($indent, -2, 2)	= '';
	$stream	= sub {
		while (@streams) {
			my @val = $streams[0]->();
			if (@val) {
				return $val[0] if defined($val[0]);
			} else {
				next;
			}
			shift(@streams);
		}
		return undef;
	};
	return $stream;
}

{
no warnings 'numeric';
my %dispatch	= (
					VAR		=> sub { my ($values, $data) = @_; return $values->{ $data->[0] }->getLabel },
					URI		=> sub { my ($values, $data) = @_; return $data->[0] },
					LITERAL	=> sub { my ($values, $data) = @_; return $data->[0] },
					'~~'	=> sub { my ($values, $data) = @_; my @operands = map { check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] =~ /$operands[1]/) },
					'=='	=> sub { my ($values, $data) = @_; my @operands = map { check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] eq $operands[1]) },
					'!='	=> sub { my ($values, $data) = @_; my @operands = map { check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] ne $operands[1]) },
					'<'		=> sub { my ($values, $data) = @_; my @operands = map { check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] < $operands[1]) },
					'>'		=> sub { my ($values, $data) = @_; my @operands = map { check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] > $operands[1]) },
					'<='	=> sub { my ($values, $data) = @_; my @operands = map { check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] <= $operands[1]) },
					'>='	=> sub { my ($values, $data) = @_; my @operands = map { check_constraints( $values, $_ ) } @{ $data }; return ($operands[0] >= $operands[1]) },
					'&&'	=> sub { my ($values, $data) = @_; foreach my $part (@{ $data }) { return 0 unless check_constraints( $values, $part ); } return 1 },
					'||'	=> sub { my ($values, $data) = @_; foreach my $part (@{ $data }) { return 1 if check_constraints( $values, $part ); } return 0 },
				);
sub check_constraints {
	my $values	= shift;
	my $data	= shift;
	warn 'check_constraints: ' . Dumper($data) if ($debug > 1);
	return 1 unless scalar(@$data);
	my $op		= $data->[0];
	my $code	= $dispatch{ $op };
	if ($code) {
		local($Data::Dumper::Indent)	= 0;
		my $result	= $code->( $values, [ @{$data}[1..$#{$data}] ] );
#		warn Dumper($op, $data);
#		warn "RESULT: " . $result . "\n\n";
		return $result;
	} else {
		confess "OPERATOR $op NOT IMPLEMENTED!";
	}
}
}

sub sort_rows {
	my $self	= shift;
	my $nodes	= shift;
	my $parsed	= shift;
	my $args	= $parsed->{options} || {};
	my $limit		= $args->{'limit'};
	my $unique		= $args->{'distinct'};
	my $offset		= $args->{'offset'} || 0;
	my @variables	= map { $_->[1] } (@{ $parsed->{variables} });
	my %colmap		= map { $variables[$_] => $_ } (0 .. $#variables);
	warn Dumper(\%colmap) if ($debug);
	
	if (exists $args->{'orderby'}) {
		my $cols	= $args->{'orderby'};
		my $col		= $cols->[0][1];
		warn "ordering by $col" if ($debug);
		my @nodes;
		while (my $node = $nodes->()) {
			push(@nodes, $node);
		}
		@nodes	= sort {
							($a->[1] =~ /^[-+]?\d/ and $b->[1] =~ /^[-+]?\d/)
								? ($a->[1] <=> $b->[1])
								: ($a->[1] =~ /^\w/ and $b->[1] =~ /^\w/)
									? ($a->[1] cmp $b->[1])
									: ncmp($a->[1], $b->[1])
						}
						map { [$_, $_->[$colmap{$col}]->getLabel] }
							@nodes;
		@nodes	= map { $_->[0] } @nodes;
		if ($limit) {
			$nodes	= sub {
				return undef unless ($limit);
				$limit--;
				return shift(@nodes);
			};
		} else {
			$nodes	= sub {
				my $row	= shift(@nodes);
				return $row;
			};
		}
	} elsif ($limit) {
		my $old	= $nodes;
		$nodes	= sub {
			return undef unless ($limit);
			$limit--;
			return $old->();
		};
	}
	
	if ($offset) {
		if ($unique) {
			my %seen;
			while (my $row = $nodes->()) {
				next if ($seen{ @$row }++);
				last unless --$offset;
			}
		} else {
			$nodes->() while ($offset--);
		}
	}
	
	if ($unique) {
		my %seen;
		my $old	= $nodes;
		$nodes	= sub {
			while (my $row = $old->()) {
				next if $seen{ join($;, map {$_->getLabel} @$row) }++;
				return $row;
			}
		};
	}
	
	return $nodes;
}

=for private

=item C<parse_files ( @files )>

Parse a local RDF file into the RDF store.

=end private

=cut
sub parse_files {
	my $self	= shift;
	my @files	= @_;
	my $bridge	= $self->bridge;
	
	foreach my $file (@files) {
		unless (-r $file) {
			warn "$file isn't readable!";
			next;
		}
		warn "parsing $file\n" if ($debug);
		$bridge->add_file( $file );
	}
}

=for private

=item C<parse_urls ( @urls )>

Retrieve a remote file by URL, and parse RDf into the RDF store.

=end private

=cut
sub parse_urls {
	my $self	= shift;
	my @urls	= @_;
	my $bridge	= $self->bridge;
	
	foreach my $url (@urls) {
		$bridge->add_uri( $url );
	}
}

sub AUTOLOAD {
	my $self	= $_[0];
	my $class	= ref($_[0]) || return undef;
	our $AUTOLOAD;
	return if ($AUTOLOAD =~ /DESTROY$/);
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

package RDF::Query::Stream;

use strict;
use warnings;

sub new {
	my $class		= shift;
	my $stream		= shift || sub { undef };
	my $open		= 0;
	my $finished	= 0;
	my $row;
	my $self;
	$self	= bless(sub {
		my $arg	= shift;
		if ($arg) {
			if ($arg eq 'next_result') {
				$open	= 1;
				$row	= $stream->();
				unless ($row) {
					$finished	= 1;
				}
			} elsif ($arg eq 'binding_value') {
				unless ($open) {
					$self->next_result;
				}
				my $val	= shift;
				return $row->[ $val ];
			} elsif ($arg eq 'finished') {
				return $finished;
			}
		} else {
			return $stream->();
		}
	}, $class);
	return $self;
}

sub AUTOLOAD {
	my $self	= shift;
	my $class	= ref($self) || return undef;
	our $AUTOLOAD;
	return if ($AUTOLOAD =~ /DESTROY$/);
	my $method		= $AUTOLOAD;
	$method			=~ s/^.*://;
	return $self->( $method, @_ );
}


1;

__END__

=back

=head1 REVISION HISTORY

 $Log: Query.pm,v $
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

 
=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
