# RDF::Query::Algebra::Optional
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Optional - Algebra class for Optional patterns

=cut

package RDF::Query::Algebra::Optional;

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

=item C<new ( $pattern, $opt_pattern )>

Returns a new Optional structure.

=cut

sub new {
	my $class	= shift;
	my $pattern	= shift;
	my $opt		= shift;
	return bless( [ 'OPTIONAL', $pattern, $opt ], $class );
}

=item C<< pattern >>

Returns the base pattern (LHS) onto which the optional pattern joins.

=cut

sub pattern {
	my $self	= shift;
	return $self->[1];
}

=item C<< optional >>

Returns the optional pattern (RHS).

=cut

sub optional {
	my $self	= shift;
	return $self->[2];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	
	return sprintf(
		'(leftjoin %s %s)',
		$self->pattern->sse,
		$self->optional->sse
	);
}

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $indent	= shift || '';
	my $string	= sprintf(
		"%s\n${indent}OPTIONAL %s",
		$self->pattern->as_sparql( $indent ),
		$self->optional->as_sparql( $indent ),
	);
	return $string;
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'OPTIONAL';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return uniq($self->pattern->referenced_variables, $self->optional->referenced_variables);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
