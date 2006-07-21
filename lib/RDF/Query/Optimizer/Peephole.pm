# RDF::Query::Optimizer::Peephole
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Optimizer::Peephole - Peephole optimizer for re-ordering triple patterns.

=cut

package RDF::Query::Optimizer::Peephole;

use strict;
use warnings;

use RDF::Query::Error qw(:try);

use Data::Dumper;
use List::Util qw(first);
use Carp qw(carp croak confess);
use Scalar::Util qw(blessed reftype);

use RDF::Query::Error qw(:try);

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
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
	
	our %OPTIMIZERS;
	my @opts	= sort { $OPTIMIZERS{ $b } <=> $OPTIMIZERS{ $a } } (keys %OPTIMIZERS);
	foreach my $opt (@opts) {
		my $self	= $opt->new( @_ );
		next unless blessed($self);
		return $self;
	}
}

=item C<< optimize >>

Performs optimization on the query object.

=cut

sub optimize {
	my $self	= shift;
	my $query	= $self->query;
	my $triples	= $query->{'parsed'}{'triples'};
	my $cost	= $self->optimize_triplepattern( $triples );
	return $cost;
}

=begin private

=item C<< register ( $rank ) >>

Registers a Peephole optimizer sub-class with the specified C<$rank>. During
calls to C<new>, instantiation will be deferred to the sub-class with the
highest registered rank.

=end private

=cut

sub register {
	my $class	= shift;
	my $value	= shift;
	our %OPTIMIZERS;
	$OPTIMIZERS{ $class }	= $value;
}

=item C<< query >>

Returns the query object that the optimizer will modify.

=cut

sub query {
	my $self	= shift;
	my $query	= $self->{query};
	return $query;
}

=item C<< model >>

Returns the model object that the optimizer will rely on for triple information.

=cut

sub model {
	my $self	= shift;
	my $model	= $self->{model};
	return $model;
}


1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
