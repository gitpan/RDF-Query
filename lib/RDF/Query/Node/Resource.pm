# RDF::Query::Node::Resource
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Node::Resource - RDF Node class for resources

=cut

package RDF::Query::Node::Resource;

use strict;
use warnings;
use base qw(RDF::Query::Node);

use Data::Dumper;
use Scalar::Util qw(reftype);
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

=item C<new ( $iri )>

Returns a new Resource structure.

=cut

sub new {
	my $class	= shift;
	my $iri		= shift;
	return bless( [ 'URI', $iri ], $class );
}

=item C<< uri_value >>

Returns the URI/IRI value of this resource.

=cut

sub uri_value {
	my $self	= shift;
	return $self->[1];
}

=item C<< sse >>

Returns the SSE string for this resource.

=cut

sub sse {
	my $self	= shift;
	my $uri		= $self->uri_value;
	if (ref($uri) and reftype($uri) eq 'ARRAY') {
		my ($ns, $local)	= @$uri;
		$ns	= '' if ($ns eq '__DEFAULT__');
		return join(':', $ns, $local);
	} else {
		return qq(<${uri}>);
	}
}

=item C<< as_sparql >>

Returns the SPARQL string for this node.

=cut

sub as_sparql {
	my $self	= shift;
	if ($self->uri_value eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type') {
		return 'a';
	} else {
		return $self->sse;
	}
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
