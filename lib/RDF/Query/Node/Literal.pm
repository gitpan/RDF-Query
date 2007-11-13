# RDF::Query::Node::Literal
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Node::Literal - RDF Node class for literals

=cut

package RDF::Query::Node::Literal;

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

=item C<new ( $string, $lang, $datatype )>

Returns a new Literal structure.

=cut

sub new {
	my $class	= shift;
	my $literal	= shift;
	my $lang	= shift;
	my $dt		= shift;
	my $self;
	if ($lang) {
		$self	= [ 'LITERAL', $literal, lc($lang), undef ];
	} elsif ($dt) {
		$self	= [ 'LITERAL', $literal, undef, $dt ];
	} else {
		$self	= [ 'LITERAL', $literal ];
	}
	bless($self, $class);
}

=item C<< literal_value >>

Returns the string value of the literal.

=cut

sub literal_value {
	my $self	= shift;
	return $self->[1];
}

=item C<< literal_value_language >>

Returns the language tag of the ltieral.

=cut

sub literal_value_language {
	my $self	= shift;
	return $self->[2];
}

=item C<< literal_datatype >>

Returns the datatype of the literal.

=cut

sub literal_datatype {
	my $self	= shift;
	return $self->[3];
}

=item C<< sse >>

Returns the SSE string for this literal.

=cut

sub sse {
	my $self	= shift;
	my $literal	= $self->[1];
	my $lang	= $self->[2];
	my $dt		= $self->[3];
	$literal	=~ s/"/\\"/g;
	if ($lang) {
		return qq("${literal}"@${lang});
	} elsif ($dt) {
		return qq("${literal}"^^<${dt}>);
	} else {
		return qq("${literal}");
	}
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
