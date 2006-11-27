# RDF::Query::Optimizer::Multiget
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Optimizer::Multiget - Multiget optimizer for grouping triple patterns.

=cut

package RDF::Query::Optimizer::Multiget;

use strict;
use warnings;

use RDF::Query::Error qw(:try);

use Data::Dumper;
use List::Util qw(first);
use Carp qw(carp croak confess);
use Scalar::Util qw(blessed reftype);

use RDF::Query::Error qw(:try);

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<< new ( $query, $model, %args ) >>

Returns a new optimizer object.

=cut

sub new {
	my $class	= shift;
	my $query	= shift;
	my $model	= shift;
	my %args	= @_;
	
	my $size	= exists($args{ size }) ? $args{ size } : 16;	# probably too large as a default, but it should be specified in %args
	my $self	= bless( { query => $query, model => $model, size => $size }, $class );
}

=item C<< optimize >>

Performs optimization on the query object.

=cut

sub optimize {
	my $self	= shift;
	my $query	= $self->query;
	my $triples	= $query->parsed->{'triples'};	# XXX triples should be a method call on a parsed object.
	$self->optimize_triplepattern( $triples );
}

=item C<< optimize_triplepattern >>

Performs optimization on a discrete triple pattern.

=cut

sub optimize_triplepattern {
	my $self	= shift;
	my $pattern	= shift;
	
	my $size	= $self->size;
	
	my @group;
	my @reordered;
	foreach my $part (@{ $pattern }) {
		
		if (reftype($part->[0])) {	# XXX if reftype(), then it's a node.
			
			push( @group, $part );
			
			if (@group == $size) {
				push(@reordered, [ 'MULTI', @group ]);
				@group	= ();
			}
		} else {			# XXX if not reftype(), then it's an aggregate (OPTIONAL, UNION, etc.)
			
			if (@group) {
				if (@group > 1) {
					push(@reordered, [ 'MULTI', @group ]);
				} else {
					push(@reordered, @group);
				}
				@group	= ();
			}
			
			# recurse
			my $type	= $part->[0];
			if ($type eq 'FILTER') {
				push(@reordered, $part);
			} elsif ($type eq 'GRAPH') {
				$self->optimize_triplepattern( $part->[2] );
				push(@reordered, $part);
			} elsif ($type eq 'OPTIONAL') {
				$self->optimize_triplepattern( $part->[1] );
				push(@reordered, $part);
			} elsif ($type eq 'UNION') {
				foreach my $i (1 .. $#{ $part }) {
					$self->optimize_triplepattern( $part->[ $i ] );
				}
				push(@reordered, $part);
			} else {
				die Dumper($part);
			}
		}
	}
	
	if (@group) {
		if (@group > 1) {
			push(@reordered, [ 'MULTI', @group ]);
		} else {
			push(@reordered, @group);
		}
		@group	= ();
	}
	
	@{ $pattern }	= @reordered;
	return 1;
}

=item C<< query >>

Returns the query object that the optimizer will modify.

=cut

sub query {
	my $self	= shift;
	my $query	= $self->{query};
	return $query;
}

=item C<< model >>

Returns the model object that the optimizer will rely on for triple information.

=cut

sub model {
	my $self	= shift;
	my $model	= $self->{model};
	return $model;
}

=item C<< size >>

Returns the desired size of the collection of triples in each multi-get.

=cut

sub size {
	my $self	= shift;
	my $size	= $self->{size};
	return $size;
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
