# RDF::Query::Node::Blank
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Node::Blank - RDF Node class for blank nodes

=cut

package RDF::Query::Node::Blank;

use strict;
use warnings;
use base qw(RDF::Query::Node);

use Data::Dumper;
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

=item C<new ( $name )>

Returns a new Blank structure.

=cut

sub new {
	my $class	= shift;
	my $name	= shift;
	return bless( [ 'BLANK', $name ], $class );
}

=item C<< blank_identifier >>

Returns the identifier of the blank node.

=cut

sub blank_identifier {
	my $self	= shift;
	return $self->[1];
}

=item C<< sse >>

Returns the SSE string for this blank node.

=cut

sub sse {
	my $self	= shift;
	my $id		= $self->blank_identifier;
	return qq(_:${id});
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
