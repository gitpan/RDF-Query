# RDF::Query::Plan::Filter
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Plan::Filter - Executable query plan for Filters.

=head1 VERSION

This document describes RDF::Query::Plan::Filter version 2.201_01, released 27 January 2010.

=head1 METHODS

=over 4

=cut

package RDF::Query::Plan::Filter;

use strict;
use warnings;
use base qw(RDF::Query::Plan);

######################################################################

our ($VERSION);
BEGIN {
	$VERSION	= '2.201_01';
}

######################################################################

=item C<< new ( $plan, $expr ) >>

=cut

sub new {
	my $class	= shift;
	my $expr	= shift;
	my $plan	= shift;
	my $self	= $class->SUPER::new( $expr, $plan );
	$self->[0]{referenced_variables}	= [ $plan->referenced_variables ];
	return $self;
}

=item C<< execute ( $execution_context ) >>

=cut

sub execute ($) {
	my $self	= shift;
	my $context	= shift;
	if ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "FILTER plan can't be executed while already open";
	}
	my $plan	= $self->[2];
	$plan->execute( $context );
	my $l		= Log::Log4perl->get_logger("rdf.query.plan.filter");
	
	if ($plan->state == $self->OPEN) {
		$self->state( $self->OPEN );
		my $expr	= $self->[1];
		my $bool	= RDF::Query::Node::Resource->new( "sparql:ebv" );
		my $filter	= RDF::Query::Expression::Function->new( $bool, $expr );
		if ($l->is_trace) {
			$l->trace("filter constructed for " . $expr->sse({}, ''));
		}
		my $query	= $context->query;
		my $bridge	= $context->model;
		$self->[0]{filter}	= sub {
			my $row		= shift;
			my $bool	= 0;
			eval {
				my $value	= $filter->evaluate( $query, $bridge, $row );
				$bool	= ($value->literal_value eq 'true') ? 1 : 0;
			};
			return $bool;
		};
	} else {
		warn "could not execute plan in filter";
	}
	$self;
}

=item C<< next >>

=cut

sub next {
	my $self	= shift;
	unless ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "next() cannot be called on an un-open FILTER";
	}
	my $plan	= $self->[2];
	my $filter	= $self->[0]{filter};
	my $l		= Log::Log4perl->get_logger("rdf.query.plan.filter");
	while (1) {
		my $row	= $plan->next;
		unless ($row) {
			$l->debug("no remaining rows in filter");
			return;
		}
		if ($l->is_trace) {
			$l->trace("filter processing bindings $row");
		}
		if ($filter->( $row )) {
			$l->trace( "- filter returned true on row" );
			return $row;
		} else {
			$l->trace( "- filter returned false on row" );
		}
	}
}

=item C<< close >>

=cut

sub close {
	my $self	= shift;
	unless ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "close() cannot be called on an un-open FILTER";
	}
	delete $self->[0]{filter};
	$self->[2]->close();
	$self->SUPER::close();
}

=item C<< pattern >>

Returns the query plan that will be used to produce the data to be filtered.

=cut

sub pattern {
	my $self	= shift;
	return $self->[2];
}

=item C<< distinct >>

Returns true if the pattern is guaranteed to return distinct results.

=cut

sub distinct {
	my $self	= shift;
	return $self->pattern->distinct;
}

=item C<< ordered >>

Returns true if the pattern is guaranteed to return ordered results.

=cut

sub ordered {
	my $self	= shift;
	return $self->pattern->ordered;
}

=item C<< plan_node_name >>

Returns the string name of this plan node, suitable for use in serialization.

=cut

sub plan_node_name {
	return 'filter';
}

=item C<< plan_prototype >>

Returns a list of scalar identifiers for the type of the content (children)
nodes of this plan node. See L<RDF::Query::Plan> for a list of the allowable
identifiers.

=cut

sub plan_prototype {
	my $self	= shift;
	return qw(E P);
}

=item C<< plan_node_data >>

Returns the data for this plan node that corresponds to the values described by
the signature returned by C<< plan_prototype >>.

=cut

sub plan_node_data {
	my $self	= shift;
	my $expr	= $self->[1];
	return ($expr, $self->pattern);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
