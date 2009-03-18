# RDF::Query::CostModel::Counted
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::CostModel::Counted - Execution cost estimator

=head1 METHODS

=over 4

=cut

package RDF::Query::CostModel::Counted;

our ($VERSION);
BEGIN {
	$VERSION	= '2.100';
}

use strict;
use warnings;
no warnings 'redefine';
use base qw(RDF::Query::CostModel::Naive);

use RDF::Query::Error qw(:try);

use Set::Scalar;
use Data::Dumper;
use Scalar::Util qw(blessed);
use List::MoreUtils qw(uniq);

sub _cost_triple {
	my $self	= shift;
	my $triple	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $triple->sse( {}, '' ) );
	return $self->_cardinality( $triple, $context );
}

sub _cardinality_triple {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	my $model	= $context->model;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	my $size	= $self->_size( $context );
	my $card	= $size * $model->node_count( $pattern->nodes );
	$l->debug( 'Cardinality of triple is : ' . $card );
	return $card;
}

sub _size {
	my $self	= shift;
	my $context	= shift;
	my $model	= $context->model;
	my $size	= $model->node_count();
	return $size;
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut