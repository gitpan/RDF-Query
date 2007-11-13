# RDF::Query::Optimizer::Peephole::Naive
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Optimizer::Peephole::Naive - Peephole optimizer for re-ordering triple patterns.

=cut

package RDF::Query::Optimizer::Peephole::Naive;

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
	__PACKAGE__->register( 1 );
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

	my(@cost, @non_orderable);
	foreach my $part (@{ $pattern }) {
		Carp::confess unless (reftype($part) eq 'ARRAY');
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
			} elsif ($type eq 'GGP') {
				my $cost	= $self->optimize_triplepattern( $part->[1] );
				push(@cost, [ $cost, $part ]);
			} elsif ($type eq 'BGP') {
				my $cost	= $self->optimize_triplepattern( [ @{ $part }[ 1 .. $#{ $part } ] ]);
				push(@cost, [ $cost, $part ]);
			} elsif ($type eq 'TIME') {
				my $cost	= $self->optimize_triplepattern( $part->[2] );
				push(@cost, [ $cost, $part ]);
			} elsif ($type eq 'OPTIONAL') {
				my $cost	= $self->optimize_triplepattern( [$part->[1]] );
				$cost		*= max( 1, $self->optimize_triplepattern( [$part->[2]] ) );
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
	
	my $cost		= 0;
	foreach my $node (@nodes) {
		if (not blessed($node) and ref($node) and reftype($node) eq 'ARRAY') {
			my $type	= $node->[0];
			if ($type eq 'VAR') {
				$cost	+= $self->variable_cost;
			} elsif ($type eq 'URI') {
				$cost	+= $self->resource_cost;
			} elsif ($type eq 'LITERAL') {
				$cost	+= $self->literal_cost;
			} elsif ($type eq 'BLANK') {
				$cost	+= $self->blank_cost;
			}
		}
	}
	return $cost;
}

=item C<< variable_cost >>

Returns the partial cost of querying the triple store for a statement containing
a variable.

=cut

sub variable_cost {
	my $self	= shift;
	return $self->{ 'variable_cost' } || 1;
}

=item C<< resource_cost >>

Returns the partial cost of querying the triple store for a statement containing
a resource.

=cut

sub resource_cost {
	my $self	= shift;
	return $self->{ 'resource_cost' } || 1/3;
}

=item C<< literal_cost >>

Returns the partial cost of querying the triple store for a statement containing
a literal.

=cut

sub literal_cost {
	my $self	= shift;
	return $self->{ 'literal_cost' } || 1/3;
}

=item C<< blank_cost >>

Returns the partial cost of querying the triple store for a statement containing
a blank node.

=cut

sub blank_cost {
	my $self	= shift;
	return $self->{ 'blank_cost' } || 1/3;
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
