# RDF::Query::Node::Variable
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Node::Variable - RDF Node class for variables

=cut

package RDF::Query::Node::Variable;

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

Returns a new Variable structure.

=cut

sub new {
	my $class	= shift;
	my $name	= shift;
	return bless( [ 'VAR', $name ], $class );
}

=item C<< name >>

Returns the name of the variable.

=cut

sub name {
	my $self	= shift;
	return $self->[1];
}

=item C<< sse >>

Returns the SSE string for this variable.

=cut

sub sse {
	my $self	= shift;
	my $name	= $self->name;
	return qq(?${name});
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
