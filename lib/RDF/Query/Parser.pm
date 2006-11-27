# RDF::Query::Parser
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Parser - Parser base class

=cut

package RDF::Query::Parser;

use strict;
use warnings;

use RDF::Query::Error qw(:try);

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

=item C<new_literal ( $literal, $language, $datatype )>

Returns a new literal structure.

=cut

sub new_literal {
	my $self	= shift;
	my $literal	= shift;
	my $lang	= shift;
	my $dt		= shift;
	if ($lang) {
		return [ 'LITERAL', $literal, $lang, undef ];
	} elsif ($dt) {
		return [ 'LITERAL', $literal, undef, $dt ];
	} else {
		return [ 'LITERAL', $literal ];
	}
}

=item C<new_variable ( $name )>

Returns a new variable structure.

=cut

sub new_variable {
	my $self	= shift;
	my $name	= shift;
	return [ 'VAR', $name ];
}

=item C<new_blank ( $name )>

Returns a new blank node structure.

=cut

sub new_blank {
	my $self	= shift;
	my $id		= shift;
	return ['BLANK', $id ];
}

=item C<new_uri ( $uri )>

Returns a new variable structure.

=cut

sub new_uri {
	my $self	= shift;
	my $uri		= shift;
	return [ 'URI', $uri ];
}

=item C<new_qname ( $prefix, $localPart )>

Returns a new QName URI structure.

=cut

sub new_qname {
	my $self	= shift;
	my $prefix	= shift;
	my $name	= shift;
	return [ 'URI', [ $prefix, $name ] ];
}

=item C<new_union ( @patterns )>

Returns a new UNION structure.

=cut

sub new_union {
	my $self		= shift;
	my @patterns	= @_;
	return [ 'UNION', @patterns ];
}

=item C<new_optional ( $patterns )>

Returns a new OPTIONAL structure.

=cut

sub new_optional {
	my $self		= shift;
	my $triples		= shift;
	return [ 'OPTIONAL', $triples ];
}

=item C<new_named_graph ( $graph, $triples )>

Returns a new NAMED GRAPH structure.

=cut

sub new_named_graph {
	my $self		= shift;
	my $graph		= shift;
	my $triples		= shift;
	return [ 'GRAPH', $graph, $triples ];
}

=item C<new_triple ( $s, $p, $o )>

Returns a new triple structure.

=cut

sub new_triple {
	my $self		= shift;
	my ($s,$p,$o)	= @_;
	return [ $s, $p, $o ];
}

=item C<new_unary_expression ( $operator, $operand )>

Returns a new unary expression structure.

=cut

sub new_unary_expression {
	my $self	= shift;
	my $op		= shift;
	my $operand	= shift;
	return [ $op, $operand ];
}

=item C<new_binary_expression ( $operator, @operands )>

Returns a new binary expression structure.

=cut

sub new_binary_expression {
	my $self		= shift;
	my $op			= shift;
	my @operands	= @_[0,1];
	return [ $op, @operands ];
}

=item C<new_logical_expression ( $operator, @operands )>

Returns a new logical expression structure.

=cut

sub new_logical_expression {
	my $self		= shift;
	my $op			= shift;
	my @operands	= @_;
	return [ $op, @operands ];
}

=item C<new_function_expression ( $function, @operands )>

Returns a new function expression structure.

=cut

sub new_function_expression {
	my $self		= shift;
	my $function	= shift;
	my @operands	= @_;
	return [ 'FUNCTION', $function, @operands ];
}

######################################################################

=item C<fail ( $error )>

Sets the current error to C<$error>.

If the parser is in commit mode (by calling C<set_commit>), throws a
RDF::Query::Error::ParseError object. Otherwise returns C<undef>.

=cut

sub fail {
	my $self	= shift;
	my $error	= shift;
	
	no warnings 'uninitialized';
	my $parsed	= substr($self->{input}, 0, $self->{position});
	my $line	= ($parsed =~ tr/\n//) + 1;
	my ($lline)	= $parsed =~ m/^(.*)\Z/mx;
	my $col		= length($lline);
	my $rest	= substr($self->{remaining}, 0, 10);
	
	$self->set_error( "$error at $line:$col (near '$rest')" );
	if ($self->{commit}) {
		Carp::cluck if ($RDF::Query::Parser::debug > 1);
		throw RDF::Query::Error::ParseError( -text => "$error at $line:$col (near '$rest')" );
	} else {
		return undef;
	}
}

######################################################################

=item C<error ()>

Returns the last error the parser experienced.

=cut

sub error {
	my $self	= shift;
	if (defined $self->{error}) {
		return $self->{error};
	} else {
		return '';
	}
}

=begin private

=item C<set_error ( $error )>

Sets the object's error variable.

=end private

=cut

sub set_error {
	my $self	= shift;
	my $error	= shift;
	$self->{error}	= $error;
}

=begin private

=item C<clear_error ()>

Clears the object's error variable.

=end private

=cut

sub clear_error {
	my $self	= shift;
	$self->{error}	= undef;
}

=begin private

=item C<set_commit ( [ $value ] )>

Sets the object's commit state.

=end private

=cut

sub set_commit {
	my $self	= shift;
	if (@_) {
		$self->{commit}	= shift;
	} else {
		$self->{commit}	= 1;
	}
}

=begin private

=item C<unset_commit ()>

Clears the object's commit state.

=end private

=cut

sub unset_commit {
	my $self	= shift;
	$self->{commit}	= 0;
}

=begin private

=item C<get_commit ()>

Returns the object's commit state.

=end private

=cut

sub get_commit {
	my $self	= shift;
	return $self->{commit};
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
