# RDF::Query::Algebra::BasicGraphPattern
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::BasicGraphPattern - Algebra class for BasicGraphPattern patterns

=cut

package RDF::Query::Algebra::BasicGraphPattern;

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

=item C<new ( @triples )>

Returns a new BasicGraphPattern structure.

=cut

sub new {
	my $class	= shift;
	my @triples	= @_;
	return bless( [ 'BGP', @triples ] );
}

=item C<< triples >>

Returns a list of triples belonging to this BGP.

=cut

sub triples {
	my $self	= shift;
	return @{ $self }[ 1 .. $#{ $self } ];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	
	return sprintf(
		'(bgp %s)',
		join(' ', map { $_->sse } $self->triples)
	);
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'BGP';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return uniq(map { $_->referenced_variables } $self->triples);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
