# RDF::Query::Algebra::Function
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Function - Algebra class for Function expressions

=cut

package RDF::Query::Algebra::Function;

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

=item C<new ( $uri, @arguments )>

Returns a new Function structure.

=cut

sub new {
	my $class	= shift;
	my $uri		= shift;
	my @args	= @_;
	return bless( [ 'FUNCTION', $uri, @args ] );
}

=item C<< uri >>

Returns the URI of the function.

=cut

sub uri {
	my $self	= shift;
	return $self->[1];
}

=item C<< arguments >>

Returns a list of the arguments to the function.

=cut

sub arguments {
	my $self	= shift;
	return @{ $self }[ 2 .. $#{ $self } ];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	
	return sprintf(
		'(function %s %s)',
		$self->uri,
		join(' ', map { $self->sse } $self->arguments),
	);
}

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $indent	= shift || '';
	my @args	= $self->arguments;
	my $string	= sprintf(
		"%s( %s )",
		$self->uri->as_sparql( $indent ),
		join(', ', map { $_->as_sparql( $indent ) } @args),
	);
	return $string;
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'FUNCTION';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return uniq(map { $_->name } grep { blessed($_) and $_->isa('RDF::Query::Node::Variable') } $self->arguments);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
