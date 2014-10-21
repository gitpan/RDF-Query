# RDF::Query::Algebra::Quad
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Quad - Algebra class for Quad patterns

=cut

package RDF::Query::Algebra::Quad;

use strict;
use warnings;
no warnings 'redefine';
use base qw(RDF::Query::Algebra RDF::Trine::Statement::Quad);

use Data::Dumper;
use List::MoreUtils qw(uniq);
use Carp qw(carp croak confess);
use Scalar::Util qw(blessed reftype);
use RDF::Trine::Iterator qw(smap sgrep swatch);

######################################################################

our ($VERSION);
BEGIN {
	$VERSION	= '2.003_01';
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $context	= shift || {};
	my $indent	= shift;
	
	my $pred	= $self->predicate;
	if ($pred->isa('RDF::Trine::Node::Resource') and $pred->uri_value eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type') {
		$pred	= 'a';
	} else {
		$pred	= $pred->as_sparql( $context );
	}
	
	my $string	= sprintf(
		"%s %s %s .",
		$self->subject->as_sparql( $context ),
		$pred,
		$self->object->as_sparql( $context ),
	);
	return $string;
}

=item C<< referenced_blanks >>

Returns a list of the blank node names used in this algebra expression.

=cut

sub referenced_blanks {
	my $self	= shift;
	my @nodes	= $self->nodes;
	my @blanks	= grep { $_->isa('RDF::Trine::Node::Blank') } @nodes;
	return map { $_->blank_identifier } @blanks;
}

=item C<< qualify_uris ( \%namespaces, $base ) >>

Returns a new algebra pattern where all referenced Resource nodes representing
QNames (ns:local) are qualified using the supplied %namespaces.

=cut

sub qualify_uris {
	my $self	= shift;
	my $class	= ref($self);
	my $ns		= shift;
	my $base	= shift;
	my @nodes;
	foreach my $n ($self->nodes) {
		my $blessed	= blessed($n);
		if ($blessed and $n->isa('RDF::Query::Node::Resource')) {
			my $uri	= $n->uri;
			if (ref($uri)) {
				my ($n,$l)	= @$uri;
				unless (exists($ns->{ $n })) {
					throw RDF::Query::Error::QuerySyntaxError -text => "Namespace $n is not defined";
				}
				my $resolved	= RDF::Query::Node::Resource->new( join('', $ns->{ $n }, $l), $base );
				push(@nodes, $resolved);
			} else {
				push(@nodes, $n);
			}
		} elsif ($blessed and $n->isa('RDF::Query::Node::Literal')) {
			my $node	= $n;
			my $dt	= $node->literal_datatype;
			if (ref($dt)) {
				my ($n,$l)	= @$dt;
				unless (exists($ns->{ $n })) {
					throw RDF::Query::Error::QuerySyntaxError -text => "Namespace $n is not defined";
				}
				my $resolved	= RDF::Query::Node::Resource->new( join('', $ns->{ $n }, $l), $base );
				my $lit			= RDF::Query::Node::Literal->new( $node->literal_value, undef, $resolved->uri_value );
				push(@nodes, $lit);
			} else {
				push(@nodes, $node);
			}
		} else {
			push(@nodes, $n);
		}
	}
	return $class->new( @nodes );
}

=item C<< bf () >>

Returns a string representing the state of the nodes of the triple (bound or free).

=cut

sub bf {
	my $self	= shift;
	my $bf		= '';
	foreach my $n ($self->nodes) {
		$bf		.= ($n->isa('RDF::Query::Node::Variable'))
				? 'f'
				: 'b';
	}
	return $bf;
}

=item C<< fixup ( $query, $bridge, $base, \%namespaces ) >>

Returns a new pattern that is ready for execution using the given bridge.
This method replaces generic node objects with bridge-native objects.

=cut

sub fixup {
	my $self	= shift;
	my $class	= ref($self);
	my $query	= shift;
	my $bridge	= shift;
	my $base	= shift;
	my $ns		= shift;
	
	if (my $opt = $query->algebra_fixup( $self, $bridge, $base, $ns )) {
		return $opt;
	} else {
		my @nodes	= $self->nodes;
		@nodes	= map { $bridge->as_native( $_, $base, $ns ) } @nodes;
		my $fixed	= $class->new( @nodes );
		return $fixed;
	}
}


1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
