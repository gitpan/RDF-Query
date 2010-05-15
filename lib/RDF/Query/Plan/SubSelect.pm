# RDF::Query::Plan::SubSelect
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Plan::SubSelect - Executable query plan for sub-select queries.

=head1 VERSION

This document describes RDF::Query::Plan::SubSelect version 2.202_02, released 30 January 2010.

=head1 METHODS

=over 4

=cut

package RDF::Query::Plan::SubSelect;

use strict;
use warnings;
use base qw(RDF::Query::Plan);

use Data::Dumper;
use Scalar::Util qw(blessed);
use Storable qw(store_fd fd_retrieve);
use URI::Escape;

use RDF::Query::Error qw(:try);
use RDF::Query::ExecutionContext;
use RDF::Query::VariableBindings;

######################################################################

our ($VERSION);
BEGIN {
	$VERSION		= '2.202_02';
}

######################################################################

=item C<< new ( $query, [ \%logging_keys ] ) >>

Returns a new SubSelect query plan object. C<<$query>> is a RDF:Query object
representing a SELECT query.

=cut

sub new {
	my $class	= shift;
	my $query	= shift;
	my $keys	= shift || {};
	my $self	= $class->SUPER::new( $query );
	$self->[0]{referenced_variables}	= [ $query->variables ];
	$self->[0]{logging_keys}	= $keys;
	return $self;
}

=item C<< execute ( $execution_context ) >>

=cut

sub execute ($) {
	my $self	= shift;
	my $context	= shift;
	if ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "SUBSELECT plan can't be executed while already open";
	}
	my $l		= Log::Log4perl->get_logger("rdf.query.plan.subselect");
	my $query	= $self->query;
	my $iter	= $query->execute( $context->model->model );
	if ($iter) {
		$self->[0]{iter}	= $iter;
		$self->[0]{'open'}	= 1;
		$self->[0]{'count'}	= 0;
		$self->[0]{logger}	= $context->logger;
		$self->state( $self->OPEN );
	} else {
		warn "no iterator in execute()";
	}
	$self;
}

=item C<< next >>

=cut

sub next {
	my $self	= shift;
	unless ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "next() cannot be called on an un-open SERVICE";
	}
	return undef unless ($self->[0]{'open'});
	my $iter	= $self->[0]{iter};
	my $result	= $iter->next;
	
	return undef unless $result;
	$self->[0]{'count'}++;
	my $row	= RDF::Query::VariableBindings->new( $result );
	return $row;
};

=item C<< close >>

=cut

sub close {
	my $self	= shift;
	unless ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "close() cannot be called on an un-open SERVICE";
	}
	delete $self->[0]{iter};
	delete $self->[0]{args};
	delete $self->[0]{count};
	$self->SUPER::close();
}

=item C<< query >>

Returns the sub-select query object.

=cut

sub query {
	my $self	= shift;
	return $self->[1];
}

=item C<< distinct >>

Returns true if the pattern is guaranteed to return distinct results.

=cut

sub distinct {
	my $self	= shift;
	# XXX this could be set at construction time, if we want to trust the remote
	# XXX endpoint to return DISTINCT results (when appropriate).
	return 0;
}

=item C<< ordered >>

Returns true if the pattern is guaranteed to return ordered results.

=cut

sub ordered {
	my $self	= shift;
	# XXX this could be set at construction time, if we want to trust the remote
	# XXX endpoint to return ORDERED results (when appropriate).
	return 0;
}

=item C<< plan_node_name >>

Returns the string name of this plan node, suitable for use in serialization.

=cut

sub plan_node_name {
	return 'subselect';
}

=item C<< plan_prototype >>

Returns a list of scalar identifiers for the type of the content (children)
nodes of this plan node. See L<RDF::Query::Plan> for a list of the allowable
identifiers.

=cut

sub plan_prototype {
	my $self	= shift;
	return qw(Q);
}

=item C<< plan_node_data >>

Returns the data for this plan node that corresponds to the values described by
the signature returned by C<< plan_prototype >>.

=cut

sub plan_node_data {
	my $self	= shift;
	return ($self->query);
}

=item C<< graph ( $g ) >>

=cut

sub graph {
	my $self	= shift;
	my $g		= shift;
	die "graph is unimplemented for sub-selects";
}


1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
