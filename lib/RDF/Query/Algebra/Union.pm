# RDF::Query::Algebra::Union
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Union - Algebra class for Union patterns

=cut

package RDF::Query::Algebra::Union;

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

=item C<new ( $left, $right )>

Returns a new Union structure.

=cut

sub new {
	my $class	= shift;
	my $left	= shift;
	my $right	= shift;
	return bless( [ 'UNION', $left, $right ], $class );
}

=item C<< first >>

Returns the first pattern (LHS) of the union.

=cut

sub first {
	my $self	= shift;
	return $self->[1];
}

=item C<< second >>

Returns the second pattern (RHS) of the union.

=cut

sub second {
	my $self	= shift;
	return $self->[2];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	
	return sprintf(
		'(union %s %s)',
		$self->first->sse,
		$self->second->sse
	);
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'UNION';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return uniq($self->first->referenced_variables, $self->second->referenced_variables);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
