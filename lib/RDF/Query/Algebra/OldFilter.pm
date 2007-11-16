# RDF::Query::Algebra::OldFilter
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::OldFilter - Algebra class for Filter expressions

=cut

package RDF::Query::Algebra::OldFilter;

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

=item C<new ( $filter_expression, $pattern )>

Returns a new Filter structure.

=cut

sub new {
	my $class	= shift;
	my $expr	= shift;
	return bless( [ 'FILTER', $expr ] );
}

=item C<< expr >>

Returns the filter expression.

=cut

sub expr {
	my $self	= shift;
	return $self->[1];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	
	return sprintf(
		'(oldfilter %s)',
		$self->expr->sse,
	);
}

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $indent	= shift || '';
	warn Dumper($self->expr);
	my $string	= sprintf(
		"FILTER %s",
		$self->expr->as_sparql( $indent ),
	);
	return $string;
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'FILTER';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return uniq($self->expr->referenced_variables);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
