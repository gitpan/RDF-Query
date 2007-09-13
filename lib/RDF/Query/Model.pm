# RDF::Query::Model
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Model - Model base class

=cut

package RDF::Query::Model;

use strict;
use warnings;

use RDF::Query::Error qw(:try);

use Data::Dumper;
use Carp qw(carp croak confess);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 1;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=head1 METHODS

=over 4

=item C<parsed>

Returns the query parse tree.

=cut

sub parsed {
	my $self	= shift;
	return $self->{parsed};
}





# sub new;
# sub model;
# sub new_resource;
# sub new_literal;
# sub new_blank;
# sub new_statement;
# sub new_variable;
# sub isa_node;
# sub isa_resource;
# sub isa_literal;
# sub isa_blank;
# sub equals;
# sub as_string;
# sub literal_value;
# sub literal_datatype;
# sub literal_value_language;
# sub uri_value;
# sub blank_identifier;
# sub add_uri;
# sub add_string;
# sub statement_method_map;
# sub subject;
# sub predicate;
# sub object;
# sub get_statements;
# sub multi_get;
# sub add_statement;
# sub remove_statement;
# sub get_context;
# sub supports;
# sub node_count;
# sub model_as_stream;

=item C<< debug >>

Prints debugging information about the model (including all statements in the
model) to STDERR.

=cut

sub debug {
	my $self	= shift;
	my $stream	= $self->model_as_stream();
	warn "------------------------------\n";
	while (my $st = $stream->current) {
		warn $self->as_string( $st );
	} continue { $stream->next }
	warn "------------------------------\n";
}



1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
