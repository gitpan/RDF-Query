# RDF::Query::Model::SQL::Statement
# -------------
# $Revision: 151 $
# $Date: 2006-06-04 16:08:40 -0400 (Sun, 04 Jun 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Model::SQL::Statement - A class for representing RDF statements from a RDBMS store.

=cut

package RDF::Query::Model::SQL::Statement;

use strict;
use warnings;
use Carp qw(carp croak confess);

use File::Spec;
use Data::Dumper;
use Encode;
use DBI;
use URI;

use RDF::Query::Stream;

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

=item C<< new ( $subject, $predicate, $object ) >>

Returns a new statement object with the given C<$subject>, C<$predicate> and C<$object>.

=cut

sub new {
	my $class	= shift;
	return bless([@_], $class);
}

=item C<< subject >>

Returns the subject node of the statement.

=cut

sub subject {
	my $self	= shift;
	return $self->[0];
}

=item C<< predicate >>

Returns the predicate node of the statement.

=cut

sub predicate {
	my $self	= shift;
	return $self->[1];
}

=item C<< object >>

Returns the object node of the statement.

=cut

sub object {
	my $self	= shift;
	return $self->[2];
}



1;

__END__

=back

=cut
