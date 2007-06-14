# RDF::Query::Model::SQL
# -------------
# $Revision: 151 $
# $Date: 2006-06-04 16:08:40 -0400 (Sun, 04 Jun 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Model::SQL - A bridge class for interacting with a RDBMS triplestore using the Redland schema.

=cut

package RDF::Query::Model::SQL;

use strict;
use warnings;
use base qw(RDF::Query::Model);
use Carp qw(carp croak confess);

use RDF::Base;
use RDF::Base::Storage::DBI;
use RDF::Query::Stream;
use Scalar::Util qw(blessed);

######################################################################

our ($VERSION, $debug);
BEGIN {
	*debug		= \$RDF::Query::debug;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=head1 METHODS

=over 4

=item C<new ( $model )>

Returns a new bridge object for the database accessibly with the C<$dbh> handle,
using the specified C<$model> name.

=cut

sub new {
	my $class	= shift;
	my $model	= shift;
	my %args	= @_;
	
	if (not defined $model) {
		$model	= RDF::Base::Storage::DBI->new();
	}

	unless (blessed($model) and ($model->isa('RDF::Base::Storage') or $model->isa('RDF::Base::Model'))) {
		throw RDF::Query::Error::MethodInvocationError ( -text => 'Not a RDF::Base::Storage::DBI passed to bridge constructor' );
	}
	
	my $self	= bless( {
					model			=> $model,
					parsed			=> $args{parsed},
					sttime			=> time
				}, $class );
}

=item C<< model >>

Returns an ARRAY reference meant for use as an opaque structure representing the
underlying RDBMS triplestore.

=cut

sub model {
	my $self	= shift;
	return $self->{'model'};
}

=item C<new_resource ( $uri )>

Returns a new resource object.

=cut

sub new_resource {
	my $self	= shift;
	my $uri		= shift;
	return RDF::Base::Node::Resource->new( uri => $uri );
}

=item C<new_literal ( $string, $language, $datatype )>

Returns a new literal object.

=cut

sub new_literal {
	my $self	= shift;
	my $value	= shift;
	my $lang	= shift;
	my $type	= shift;
	
	my %args	= ( value => $value );
	if ($lang) {
		$args{ language }	= $lang;
	} elsif ($type) {
		$args{ datatype }	= $type;
	}
	
	return RDF::Base::Node::Literal->new( %args );
}

=item C<new_blank ( $identifier )>

Returns a new blank node object.

=cut

sub new_blank {
	my $self	= shift;
	my $id		= shift;
	unless ($id) {
		$id	= 'r' . $self->{'sttime'} . 'r' . $self->{'counter'}++;
	}
	return RDF::Base::Node::Blank->new( name => $id );
}

=item C<new_statement ( $s, $p, $o )>

Returns a new statement object.

=cut

sub new_statement {
	my $self		= shift;
	my ($s,$p,$o)	= @_;
	return RDF::Base::Statement->new( subject => $s, predicate => $p, object => $o );
}

=item C<is_node ( $node )>

=item C<isa_node ( $node )>

Returns true if C<$node> is a node object for the current model.

=cut

sub is_node {
	my $self	= shift;
	my $node	= shift;
	return unless blessed($node);
	return $node->isa('RDF::Base::Node');
}

=item C<is_resource ( $node )>

=item C<isa_resource ( $node )>

Returns true if C<$node> is a resource object for the current model.

=cut

sub is_resource {
	my $self	= shift;
	my $node	= shift;
	return unless blessed($node);
	return $node->isa('RDF::Base::Node::Resource');
}

=item C<is_literal ( $node )>

=item C<isa_literal ( $node )>

Returns true if C<$node> is a literal object for the current model.

=cut

sub is_literal {
	my $self	= shift;
	my $node	= shift;
	return unless blessed($node);
	return $node->isa('RDF::Base::Node::Literal');
}

=item C<is_blank ( $node )>

=item C<isa_blank ( $node )>

Returns true if C<$node> is a blank node object for the current model.

=cut

sub is_blank {
	my $self	= shift;
	my $node	= shift;
	return unless blessed($node);
	return $node->isa('RDF::Base::Node::Blank');
}

*RDF::Query::Model::SQL::isa_node		= \&is_node;
*RDF::Query::Model::SQL::isa_resource	= \&is_resource;
*RDF::Query::Model::SQL::isa_literal	= \&is_literal;
*RDF::Query::Model::SQL::isa_blank		= \&is_blank;



=item C<< equals ( $node_a, $node_b ) >>

Returns true if C<$node_a> and C<$node_b> are equal

=cut

sub equals {
	my $self	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	if ($self->is_resource( $nodea ) and $self->is_resource( $nodeb )) {
		return ($nodea->uri_value eq $nodeb->uri_value);
	} elsif ($self->is_literal( $nodea ) and $self->is_literal( $nodeb )) {
		my @values	= map { $self->literal_value( $_ ) } ($nodea, $nodeb);
		my @langs	= map { $self->literal_value_language( $_ ) } ($nodea, $nodeb);
		my @types	= map { $self->literal_datatype( $_ ) } ($nodea, $nodeb);
		
		if ($values[0] eq $values[1]) {
			no warnings 'uninitialized';
			if (@langs) {
				return ($langs[0] eq $langs[1]);
			} elsif (@types) {
				return ($types[0] eq $types[1]);
			} else {
				return 1;
			}
		} else {
			return 0;
		}
	} elsif ($self->is_blank( $nodea ) and $self->is_blank( $nodeb )) {
		return ($nodea->blank_identifier eq $nodeb->blank_identifier);
	} else {
		return 0;
	}
}

=item C<as_string ( $node )>

Returns a string version of the node object.

=cut

sub as_string {
	my $self	= shift;
	my $node	= shift;
	if ($self->is_literal($node)) {
		return $self->literal_value($node);
	} elsif ($self->is_resource($node)) {
		return $self->uri_value($node);
	} else {
		return $self->blank_identifier($node);
	}
}

=item C<literal_value ( $node )>

Returns the string value of the literal object.

=cut

sub literal_value {
	my $self	= shift;
	my $node	= shift;
	return unless (blessed($node));
	return $node->literal_value;
}

=item C<literal_datatype ( $node )>

Returns the datatype of the literal object.

=cut

sub literal_datatype {
	my $self	= shift;
	my $node	= shift;
	return unless (blessed($node));
	return $node->datatype;
}

=item C<literal_value_language ( $node )>

Returns the language of the literal object.

=cut

sub literal_value_language {
	my $self	= shift;
	my $node	= shift;
	return unless (blessed($node));
	return $node->language;
}

=item C<uri_value ( $node )>

Returns the URI string of the resource object.

=cut

sub uri_value {
	my $self	= shift;
	my $node	= shift;
	return unless (blessed($node));
	return $node->uri_value;
}

=item C<blank_identifier ( $node )>

Returns the identifier for the blank node object.

=cut

sub blank_identifier {
	my $self	= shift;
	my $node	= shift;
	return unless (blessed($node));
	return $node->blank_identifier;
}

=item C<add_uri ( $uri, $named )>

Addsd the contents of the specified C<$uri> to the model.
If C<$named> is true, the data is added to the model using C<$uri> as the
named context.

=cut

sub add_uri {
	my $self	= shift;
	my $uri		= shift;
	die "XXX unimplemented";
}

=item C<statement_method_map ()>

Returns an ordered list of method names that when called against a statement
object will return the subject, predicate, and object objects, respectively.

=cut

sub statement_method_map {
	return qw(subject predicate object);
}

=item C<< subject ( $statement ) >>

Returns the subject node of the specified C<$statement>.

=cut

sub subject {
	my $self	= shift;
	my $stmt	= shift;
	return $stmt->subject;
}

=item C<< predicate ( $statement ) >>

Returns the predicate node of the specified C<$statement>.

=cut

sub predicate {
	my $self	= shift;
	my $stmt	= shift;
	return $stmt->predicate;
}

=item C<< object ( $statement ) >>

Returns the object node of the specified C<$statement>.

=cut

sub object {
	my $self	= shift;
	my $stmt	= shift;
	return $stmt->object;
}

=item C<get_statements ($subject, $predicate, $object)>

Returns a stream object of all statements matching the specified subject,
predicate and objects. Any of the arguments may be undef to match any value.

=cut

sub get_statements {
	my $self	= shift;
	my @triple	= @_;
	
	my $stream	= $self->model->get_statements( @triple );
	return RDF::Query::Stream->new( $stream, 'graph', undef, bridge => $self );
}


=item C<as_xml ($stream)>

Returns an RDF/XML serialization of the results graph.

=cut

sub as_xml {
	my $self	= shift;
	my $iter	= shift;
	return undef unless $iter->is_graph;
	die;
	return '';
}

=item C<supports ($feature)>

Returns true if the underlying model supports the named C<$feature>.
Possible features include:

	* named_graph
	* node_counts
	* temp_model
	* xml

=cut

sub supports {
	my $self	= shift;
	my $feature	= shift;
	
	return 1 if ($feature eq 'temp_model');
	return 0;
}


=begin private

=item C<< stream ( $parsed, $sth ) >>

Returns a RDF::Query::Stream for the result rows from the C<$sth> statement
handle. C<$sth> must already have been executed.

=end private

=cut

sub stream {
	my $self	= shift;
	my $parsed	= shift;
	my $sth		= shift;
	my $vars	= $parsed->{variables};
	my @vars	= map { $_->[1] } @$vars;
	
	use Data::Dumper;
	warn "Variables: " . Dumper(\@vars) if ($debug);
	
	my $code	= sub {
		my $data	= $sth->fetchrow_hashref;
		return unless ref($data);
		warn "row from sth: " . Dumper($data) if ($debug);
		
		my @row;
		foreach my $var (@vars) {
			my ($l, $r, $b)	= @{ $data }{ map { "${var}_$_" } qw(value uri name) };
			if (defined $l) {
				warn "Literal: " . $l if ($debug);
				push(@row, $self->new_literal( $l, @{ $data }{ map { "${var}_$_" } qw(language datatype) } ) );
			} elsif (defined $r) {
				warn "Resource: " . $r if ($debug);
				push(@row, $self->new_resource( $r ));
			} elsif (defined $b) {
				warn "Blank: " . $b if ($debug);
				push(@row, $self->new_blank( $b ));
			} else {
				push(@row, undef);
			}
		}
		return \@row;
	};
	return RDF::Query::Stream->new( $code, 'bindings', \@vars, bridge => $self );
}



__END__

sub as_xml {
	my $self	= shift;
	my $iter	= shift;
	return undef unless $iter->is_graph;
	my $storage	= RDF::Redland::Storage->new("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= RDF::Redland::Model->new($storage, "");
	while ($iter and not $iter->finished) {
		$model->add_statement( $iter->current );
	} continue { $iter->next }
	return $model->to_string;
}

sub RDF::Redland::Node::getLabel {
	my $node	= shift;
	if ($node->type == $RDF::Redland::Node::Type_Resource) {
		return $node->uri->as_string;
	} elsif ($node->type == $RDF::Redland::Node::Type_Literal) {
		return $node->literal_value;
	} elsif ($node->type == $RDF::Redland::Node::Type_Blank) {
		return $node->blank_identifier;
	}
}

1;

__END__
