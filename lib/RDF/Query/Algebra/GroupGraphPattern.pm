# RDF::Query::Algebra::GroupGraphPattern
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::GroupGraphPattern - Algebra class for GroupGraphPattern patterns

=head1 VERSION

This document describes RDF::Query::Algebra::GroupGraphPattern version 2.901_01.

=cut

package RDF::Query::Algebra::GroupGraphPattern;

use strict;
use warnings;
no warnings 'redefine';
use base qw(RDF::Query::Algebra);

use Log::Log4perl;
use Scalar::Util qw(blessed);
use Data::Dumper;
use List::Util qw(first);
use Carp qw(carp croak confess);
use RDF::Query::Error qw(:try);
use Time::HiRes qw(gettimeofday tv_interval);
use RDF::Trine::Iterator qw(sgrep smap swatch);

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= '2.901_01';
	our %SERVICE_BLOOM_IGNORE	= ('http://dbpedia.org/sparql' => 1);	# by default, assume dbpedia doesn't implement k:bloom().
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<new ( @graph_patterns )>

Returns a new GroupGraphPattern structure.

=cut

sub new {
	my $class		= shift;
	my @patterns	= @_;
	my $self	= bless( \@patterns, $class );
	foreach my $p (@patterns) {
		unless (blessed($p)) {
			Carp::cluck;
			throw RDF::Query::Error::MethodInvocationError -text => "GroupGraphPattern constructor called with unblessed value";
		}
	}
	return $self;
}

=item C<< construct_args >>

Returns a list of arguments that, passed to this class' constructor,
will produce a clone of this algebra pattern.

=cut

sub construct_args {
	my $self	= shift;
	return ($self->patterns);
}

=item C<< patterns >>

Returns a list of the graph patterns in this GGP.

=cut

sub patterns {
	my $self	= shift;
	return @{ $self };
}

=item C<< add_pattern >>

Appends a new child pattern to the GGP.

=cut

sub add_pattern {
	my $self	= shift;
	my $pattern	= shift;
	push( @{ $self }, $pattern );
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	my $context	= shift;
	my $prefix	= shift || '';
	my $indent	= $context->{indent} || "\t";
	
	my @patterns	= $self->patterns;
	if (scalar(@patterns) == 1) {
		return $patterns[0]->sse( $context, $prefix );
	} else {
		return sprintf(
			"(join\n${prefix}${indent}%s)",
			join("\n${prefix}${indent}", map { $_->sse( $context, "${prefix}${indent}" ) } @patterns)
		);
	}
}

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $context	= shift;
	my $indent	= shift || '';
	
	my @patterns;
	foreach my $p ($self->patterns) {
		push(@patterns, $p->as_sparql( $context, "$indent\t" ));
	}
	return "{}" unless (@patterns);
	my $patterns	= join("\n${indent}\t", @patterns);
	my $string		= sprintf("{\n${indent}\t%s\n${indent}}", $patterns);
	return $string;
}

=item C<< as_hash >>

Returns the query as a nested set of plain data structures (no objects).

=cut

sub as_hash {
	my $self	= shift;
	my $context	= shift;
	return {
		type 		=> lc($self->type),
		patterns	=> [ map { $_->as_hash } $self->patterns ],
	};
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'GGP';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	return RDF::Query::_uniq(map { $_->referenced_variables } $self->patterns);
}

=item C<< binding_variables >>

Returns a list of the variable names used in this algebra expression that will
bind values during execution.

=cut

sub binding_variables {
	my $self	= shift;
	return RDF::Query::_uniq(map { $_->binding_variables } $self->patterns);
}

=item C<< definite_variables >>

Returns a list of the variable names that will be bound after evaluating this algebra expression.

=cut

sub definite_variables {
	my $self	= shift;
	return RDF::Query::_uniq(map { $_->definite_variables } $self->patterns);
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
