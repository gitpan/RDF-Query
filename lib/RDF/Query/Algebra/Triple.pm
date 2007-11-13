# RDF::Query::Algebra::Triple
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Triple - Algebra class for Triple patterns

=cut

package RDF::Query::Algebra::Triple;

use strict;
use warnings;
use base qw(RDF::Query::Algebra);

use Data::Dumper;
use List::MoreUtils qw(uniq);
use Carp qw(carp croak confess);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<new ( $s, $p, $o )>

Returns a new Triple structure.

=cut

sub new {
	my $class	= shift;
	my @nodes	= @_;
	return bless( [ 'TRIPLE', @nodes ] );
}

=item C<< nodes >>

Returns the subject, predicate and object of the triple pattern.

=cut

sub nodes {
	my $self	= shift;
	my $s		= $self->subject;
	my $p		= $self->predicate;
	my $o		= $self->object;
	return ($s, $p, $o);
}

=item C<< subject >>

Returns the subject node of the triple pattern.

=cut

sub subject {
	my $self	= shift;
	return $self->[1];
}

=item C<< predicate >>

Returns the predicate node of the triple pattern.

=cut

sub predicate {
	my $self	= shift;
	return $self->[2];
}

=item C<< object >>

Returns the object node of the triple pattern.

=cut

sub object {
	my $self	= shift;
	return $self->[3];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	
	return sprintf(
		'(triple %s %s %s)',
		$self->subject->sse,
		$self->predicate->sse,
		$self->object->sse,
	);
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'TRIPLE';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return uniq(map { $_->name } grep { $_->isa('RDF::Query::Node::Variable') } $self->nodes);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
