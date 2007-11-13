# RDF::Query::Optimizer::Peephole::Cost
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Optimizer::Peephole::Cost - Peephole optimizer for re-ordering triple patterns.

=cut

package RDF::Query::Optimizer::Peephole::Cost;

use strict;
use warnings;
use base qw(RDF::Query::Optimizer::Peephole);

use RDF::Query::Error qw(:try);

use Data::Dumper;
use List::Util qw(first reduce min max);
use Carp qw(carp croak confess);
use Scalar::Util qw(blessed reftype);

use RDF::Query::Error qw(:try);

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	__PACKAGE__->register( 2 );
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<< new ( $query, $model, %args ) >>

Returns a new optimizer object.

=cut

sub new {
	my $class	= shift;
	my $query	= shift;
	my $model	= shift;
	my %args	= @_;
	
	my $bridge;
	if (blessed($model) and $model->isa('RDF::Query::Model')) {
		$bridge	= $model;
	} else {
		$bridge	= $query->get_bridge( $model, %args );
	}

	return unless (blessed($bridge) and $bridge->supports( 'node_counts' ));
	my $self	= bless( { query => $query, model => $bridge, args => \%args }, $class );
	
	return $self;
}

=item C<< optimize_triplepattern ( $pattern ) >>

Recursively performs optimization on the supplied triple C<$pattern>. Re-orders
the triple patterns in C<$pattern> and returns the computed cost of the pattern.


=cut

sub optimize_triplepattern {
	my $self	= shift;
	my $pattern	= shift;
	
	Carp::confess( Dumper( $pattern ) ) unless ref($pattern->[0]);
	
	my(@cost, @non_orderable);
	foreach my $part (@{ $pattern }) {
		my $type	= $part->[0];
		if (reftype($type) or $type eq 'TRIPLE') {	# XXX if reftype(), then it's a node.
			my $cost	= $self->statement_cost( $part );
			push(@cost, [ $cost, $part ]);
		} else {					# XXX if not reftype(), then it's an aggregate (OPTIONAL, UNION, etc.)
			# recurse
			if ($type eq 'FILTER') {
				push(@non_orderable, $part);
			} elsif ($type eq 'GRAPH') {
				my $cost	= $self->optimize_triplepattern( $part->[2] );
				push(@cost, [ $cost, $part ]);
			} elsif ($type eq 'TIME') {
				my $cost	= $self->optimize_triplepattern( $part->[2] );
				push(@cost, [ $cost, $part ]);
			} elsif ($type eq 'OPTIONAL') {
				my $cost	= max( 1, $self->optimize_triplepattern( $part->[1] ) );
				push(@cost, [ $cost, $part ]);
			} elsif ($type eq 'MULTI') {
				Carp::cluck;
				my $cost	= reduce { $a + $b }
							map { $self->optimize_triplepattern( $_ ) }
								(@{ $part }[ 1 .. $#{ $part } ]);
				push(@cost, [ $cost, $part ]);
			} elsif ($type eq 'UNION') {
				my $cost	= reduce { $a + $b }
							map { $self->optimize_triplepattern( $_ ) }
								(@{ $part }[ 1 .. $#{ $part } ]);
				push(@cost, [ $cost, $part ]);
			} else {
				die "*** Unknown operator encountered during peephole optimization: " . Dumper($part);
			}
		}
	}
	
	@{ $pattern }	= ((map { $_->[1] } sort { $a->[0] <=> $b->[0] } @cost), @non_orderable);
	
	no warnings 'uninitialized';
	my $total	= 0 + reduce { $a * $b } grep { defined } map { $_->[0] } @cost;
	return $total;
}

=item C<< statement_cost ( $statement ) >>

Returns the computed cost of querying the triple store for the supplied C<$statement>.

=cut

sub statement_cost {
	my $self		= shift;
	my $statement	= shift;
	my @nodes		= @{ $statement };
	shift(@nodes) if ($nodes[0] eq 'TRIPLE');
	
	my $bridge		= $self->model;
	
	my @statement;
	foreach my $node (@nodes) {
		if (not blessed($node) and reftype($node) eq 'ARRAY') {
			my $type	= $node->[0];
			if ($type eq 'VAR') {
				push(@statement, undef);
			} elsif ($type eq 'URI') {
				my $uri	= (ref($node->[1]) and reftype($node->[1]) eq 'ARRAY')
						? $self->query->qualify_uri( $node )
						: $node->[1];
				push(@statement, $bridge->new_resource( $uri ));
			} elsif ($type eq 'LITERAL') {
				my (undef, $value, $lang, $dt)	= @$node;
				if ($dt and ref($dt) and reftype($dt) eq 'ARRAY') {
					$dt	= $self->query->qualify_uri( $dt );
				}
				push(@statement, $bridge->new_literal( $value, $lang, $dt ));
			} elsif ($type eq 'BLANK') {
				push(@statement, undef);
#				push(@statement, $bridge->new_blank( $node->[1] ));
			}
		}
	}
	
	my $cost		= $bridge->node_count( @statement );
	return $cost;
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
