# RDF::Query::Algebra::NamedGraph
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::NamedGraph - Algebra class for NamedGraph patterns

=cut

package RDF::Query::Algebra::NamedGraph;

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

=item C<new ( $graph, $pattern )>

Returns a new NamedGraph structure.

=cut

sub new {
	my $class	= shift;
	my $graph	= shift;
	my $pattern	= shift;
	return bless( [ 'GRAPH', $graph, $pattern ], $class );
}

=item C<< graph >>

Returns the graph node of the named graph expression.

=cut

sub graph {
	my $self	= shift;
	if (@_) {
		my $graph	= shift;
		$self->[1]	= $graph;
	}
	return $self->[1];
}

=item C<< pattern >>

Returns the graph pattern of the named graph expression.

=cut

sub pattern {
	my $self	= shift;
	return $self->[2];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	
	return sprintf(
		'(namedgraph %s %s)',
		$self->graph->sse,
		$self->pattern->sse
	);
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'GRAPH';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return uniq(
		map { $_->name } grep { $_->isa('RDF::Query::Node::Variable') } ($self->graph),
		$self->pattern->referenced_variables,
	);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
