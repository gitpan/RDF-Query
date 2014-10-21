# RDF::Query::VariableBindings
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::VariableBindings - Variable bindings

=head1 VERSION

This document describes RDF::Query::VariableBindings version 2.903_01.

=head1 METHODS

=over 4

=cut

package RDF::Query::VariableBindings;

use strict;
use warnings;
use base qw(RDF::Trine::VariableBindings);
use overload	'""'	=> sub { $_[0]->as_string },
				'bool'	=> sub { return 1 };

use Scalar::Util qw(blessed refaddr);

######################################################################

our ($VERSION);
BEGIN {
	$VERSION	= '2.903_01';
}

######################################################################

=item C<< new ( \%bindings ) >>

=cut

sub new {
	my $class		= shift;
	my $bindings	= shift;
	my $data		= { %$bindings };
	foreach my $k (keys %$data) {
		my $node	= $data->{$k};
		if (ref($node) and not($node->isa('RDF::Query::Node'))) {
			$data->{$k}	= RDF::Query::Node->from_trine( $node );
		}
	}
	
	my $self	= $class->SUPER::new( $data );
	return $self;
}

=item C<< sse ( \%context, $indent ) >>

=cut

sub sse {
	my $self	= shift;
	my $context	= shift;
	my $indent	= shift;
	my $more	= '    ';
	my @keys	= sort keys %$self;
	return sprintf('(row %s)', CORE::join(' ', map { '[' . CORE::join(' ', '?' . $_, ($self->{$_}) ? $self->{$_}->as_string : ()) . ']' } (@keys)));
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
