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

use Scalar::Util qw(blessed);
use File::Spec;
use Data::Dumper;
use Encode;
use DBI;
use URI;

use RDF::Query::Stream;
use RDF::Query::Model::SQL::Statement;

######################################################################

our ($VERSION, $debug);
BEGIN {
	*debug		= \$RDF::Query::debug;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=head1 METHODS

=over 4

=item C<new ( $dbh, $model )>

Returns a new bridge object for the database accessibly with the C<$dbh> handle,
using the specified C<$model> name.

=cut

sub new {
	my $class	= shift;
	my $dbh		= shift;
	my $model	= shift;
	my $self	= bless( {
					dbh				=> $dbh,
					model			=> $model,
					model_number	=> get_model_number( $dbh, $model ),
					sttime			=> time
				}, $class );
}

=item C<< model >>

Returns an ARRAY reference meant for use as an opaque structure representing the
underlying RDBMS triplestore.

=cut

sub model {
	my $self	= shift;
	return [ @{ $self }{qw(dbh model)} ];
}

=item C<new_resource ( $uri )>

Returns a new resource object.

=cut

sub new_resource {
	my $self	= shift;
	my $uri		= shift;
	return bless({ uri => $uri }, 'RDF::Query::Model::SQL::Resource');
}

=item C<new_literal ( $string, $language, $datatype )>

Returns a new literal object.

=cut

sub new_literal {
	my $self	= shift;
	my $value	= shift;
	my $lang	= shift;
	my $type	= shift;
	return RDF::Query::Model::SQL::Literal->new( $value, $lang, $type );
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
	return bless({ identifier => $id }, 'RDF::Query::Model::SQL::Blank');
}

=item C<new_statement ( $s, $p, $o )>

Returns a new statement object.

=cut

sub new_statement {
	my $self	= shift;
	return RDF::Query::Model::SQL::Statement->new( @_ );
}

=item C<is_node ( $node )>

=item C<isa_node ( $node )>

Returns true if C<$node> is a node object for the current model.

=cut

sub is_node {
	my $self	= shift;
	my $node	= shift;
	return unless ref($node);
	return 1 if $node->isa_resource;
	return 1 if $node->isa_literal;
	return 1 if $node->isa_blank;
	return 0 ;
}

=item C<is_resource ( $node )>

=item C<isa_resource ( $node )>

Returns true if C<$node> is a resource object for the current model.

=cut

sub is_resource {
	my $self	= shift;
	my $node	= shift;
	return unless ref($node);
	return $node->isa('RDF::Query::Model::SQL::Resource');
}

=item C<is_literal ( $node )>

=item C<isa_literal ( $node )>

Returns true if C<$node> is a literal object for the current model.

=cut

sub is_literal {
	my $self	= shift;
	my $node	= shift;
	return unless ref($node);
	return $node->isa('RDF::Query::Model::SQL::Literal');
}

=item C<is_blank ( $node )>

=item C<isa_blank ( $node )>

Returns true if C<$node> is a blank node object for the current model.

=cut

sub is_blank {
	my $self	= shift;
	my $node	= shift;
	return unless ref($node);
	return $node->isa('RDF::Query::Model::SQL::Blank');
}

*RDF::Query::Model::SQL::isa_node		= \&is_node;
*RDF::Query::Model::SQL::isa_resource	= \&is_resource;
*RDF::Query::Model::SQL::isa_literal	= \&is_literal;

=item C<< equals ( $node_a, $node_b ) >>

Returns true if C<$node_a> and C<$node_b> are equal

=cut

sub equals {
	my $self	= shift;
	my $nodea	= shift;
	my $nodeb	= shift;
	
	return 0 unless (blessed($nodea));
	return $nodea->equals( $nodeb );
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
	return $node->{ value };
}

=item C<literal_datatype ( $node )>

Returns the datatype of the literal object.

=cut

sub literal_datatype {
	my $self	= shift;
	my $node	= shift;
	return $node->{ type };
}

=item C<literal_value_language ( $node )>

Returns the language of the literal object.

=cut

sub literal_value_language {
	my $self	= shift;
	my $node	= shift;
	return $node->{ lang };
}

=item C<uri_value ( $node )>

Returns the URI string of the resource object.

=cut

sub uri_value {
	my $self	= shift;
	my $node	= shift;
	return $node->{ uri };
}

=item C<blank_identifier ( $node )>

Returns the identifier for the blank node object.

=cut

sub blank_identifier {
	my $self	= shift;
	my $node	= shift;
	return $node->{ identifier };
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
	Carp::confess "get_statements";
	
	my $dbh		= $self->{'dbh'};
	my $model	= $self->{'model'};
	my $mnum	= $self->{'model_number'};
	
	my @where;
	my @bind;
	my @map		= qw(Subject Predicate Object);
	foreach my $i (0 .. 2) {
		my $node	= $triple[$i];
		my $id;
		if ($self->is_node($node)) {
			if (ref($node) and $node->{ID}) {
				$id	= $node->{ID};
			} elsif ($self->is_resource($node)) {
				my $sth	= $dbh->prepare('SELECT ID FROM Resources WHERE URI = ?');
				$sth->execute( $self->uri_value($node) );
				($id)	= $sth->fetchrow_array;
				warn "Got uri $id = [" . $self->uri_value($node) . "]\n" if ($debug);
			} elsif ($self->is_blank($node)) {
				my $sth	= $dbh->prepare('SELECT ID FROM Bnodes WHERE Name = ?');
				$sth->execute( $self->blank_identifier($node) );
				($id)	= $sth->fetchrow_array;
				warn "Got blank $id = (" . $self->blank_identifier($node) . ")\n" if ($debug);
			} elsif ($self->is_literal($node)) {
				my $sth	= $dbh->prepare('SELECT ID FROM Literals WHERE Value = ?');
				$sth->execute( $self->literal_value($node) );
				($id)	= $sth->fetchrow_array;
				warn "Got literal $id = \"" . $self->literal_value($node) . "\"\n" if ($debug);
			}
			
			if ($id) {
				$node->{ID}	= $id;
				$self->{cache}{$id}	= $node;
				push(@where, join(' ', $map[$i], '=', $id));
			} else {
				return undef; # RDF::Query::Stream->new( sub { return undef } );
			}
		}
	}
	
	my $sql	= "SELECT Subject, Predicate, Object FROM Statements${mnum} WHERE " . join(' AND ', @where);
	my $sth	= $dbh->prepare( $sql );
	$sth->execute();
	
	my $finished	= 0;
	my $stream	= sub {
		return undef if ($finished);
		my @data	= $sth->fetchrow_array;
		unless (@data) {
			$finished	= 1;
			return undef;
		}
		
		my @const	= ([qw(new_resource URI)],  [qw(new_blank Name)], [qw(new_literal Value)]);
		my @sql	= (
					"SELECT * FROM Resources WHERE ID = ? LIMIT 1",
					"SELECT * FROM Bnodes WHERE ID = ? LIMIT 1",
					"SELECT * FROM Literals WHERE ID = ? LIMIT 1"
				);
		my @nodes;
		foreach my $id (@data) {
			my $added	= 0;
			if (exists $self->{cache}{$id}) {
				$added	= 1;
				push(@nodes, $self->{cache}{$id});
			} else {
				foreach my $i (0 .. 2) {
					my $method	= $const[ $i ][0];
					my $sql		= $sql[$i];
					$sql		=~ s/\?/$id/;
					my $sth		= $dbh->prepare( $sql );
					$sth->execute();
					warn "$sql\t\t($id)\n" if ($debug);
					my $data	= $sth->fetchrow_hashref;
					if (ref $data) {
						my $node		= $self->$method( @{ $data }{ @{ $const[$i] }[1 .. $#{ $const[$i] }] } );
						$node->{ ID }	= $id;
						$self->{cache}{$id}	= $node;
						warn '-> yes: ' . join(', ', @{ $data }{ @{ $const[$i] }[1 .. $#{ $const[$i] }] } ) if ($debug);
						push(@nodes, $node);
						$added++;
						last;
					} else {
						warn "-> no: " . $dbh->errstr . "\n" if ($debug);
					}
				}
				unless ($added) {
					warn "Uh oh.";
					return undef;
				}
			}
		}
		
		my $st		= $self->new_statement( @nodes );
	};
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

=begin private

=item C<< get_model_number ( $model ) >>

Returns the identifier for the named C<$model>.

=end private

=cut

sub get_model_number {
	my $dbh		= shift;
	my $model	= shift;
	my $sth		= $dbh->prepare( 'SELECT ID FROM Models WHERE Name = ?' );
	$sth->execute( $model );
	my ($id)	= $sth->fetchrow_array;
	return $id;
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
	
	my $code	= sub {
		my $data	= $sth->fetchrow_hashref;
		return unless ref($data);
		my @row;
		foreach my $var (@vars) {
			my ($l, $r, $b)	= @{ $data }{ map { "${var}_$_" } qw(Value URI Name) };
			if (defined $l) {
				push(@row, $self->new_literal( $l, @{ $data }{ map { "${var}_$_" } qw(Language Datatype) } ) );
			} elsif (defined $r) {
				push(@row, $self->new_resource( $r ));
			} elsif (defined $b) {
				push(@row, $self->new_blank( $b ));
			} else {
				push(@row, undef);
			}
		}
		return \@row;
	};
	return RDF::Query::Stream->new( $code, 'bindings', \@vars, bridge => $self );
}


package RDF::Query::Model::SQL::Node;
use base qw(RDF::Query::Model::SQL);

=begin private

=item C<< is_node >>

Returns true.

=end private

=cut

sub is_node {
	my $self	= shift;
	return 1;
	return RDF::Query::Model::SQL->is_node( $self );
}

=begin private

=item C<< is_resource >>

Returns true if the node is a resource object.

=end private

=cut

sub is_resource {
	my $self	= shift;
	return RDF::Query::Model::SQL->is_resource( $self );
}

=begin private

=item C<< is_literal >>

Returns true if the node is a literal object.

=end private

=cut

sub is_literal {
	my $self	= shift;
	return RDF::Query::Model::SQL->is_literal( $self );
}

=begin private

=item C<< is_blank >>

Returns true if the node is a blank object.

=end private

=cut

sub is_blank {
	my $self	= shift;
	return RDF::Query::Model::SQL->is_blank( $self );
}

package RDF::Query::Model::SQL::Resource;
use base qw(RDF::Query::Model::SQL::Node);
use URI;

=begin private

=item C<< uri >>

Returns a URI object for the resource node.

=end private

=cut

sub uri {
	my $self	= shift;
	return URI->new( $self->{uri} );
}

=begin private

=item C<< uri_value >>

Returns the URI value of the resource node.

=end private

=cut

sub uri_value {
	my $self	= shift;
	my $value	= RDF::Query::Model::SQL->uri_value( $self );
	return $value;
}

package RDF::Query::Model::SQL::Blank;
use base qw(RDF::Query::Model::SQL::Node);

=begin private

=item C<< blank_identifier >>

Returns the identifier of the blank node.

=end private

=cut

sub blank_identifier {
	my $self	= shift;
	my $value	= RDF::Query::Model::SQL->blank_identifier( $self );
	return $value;
}

package RDF::Query::Model::SQL::Literal;
use base qw(RDF::Query::Model::SQL::Node);

=begin private

=item C<< new ( $value, $language, $datatype ) >>

Returns a new literal node object with the specified C<$value>, C<$language>, and C<$datatype>.

=end private

=cut

sub new {
	my $class	= shift;
	my $value	= shift;
	my $lang	= shift;
	my $type	= shift;
	return bless({ value => $value, lang => $lang, type => $type }, 'RDF::Query::Model::SQL::Literal');
}

=begin private

=item C<< literal_value >>

Returns the string value of the literal node.

=end private

=cut

sub literal_value {
	my $self	= shift;
	my $value	= RDF::Query::Model::SQL->literal_value( $self );
	return $value;
}

=begin private

=item C<< literal_value_language >>

Returns the language of the literal node.

=end private

=cut

sub literal_value_language {
	my $self	= shift;
	my $lang	= RDF::Query::Model::SQL->literal_value_language( $self );
	return unless $lang;
	return $self->new( $lang, undef, undef );
}

=begin private

=item C<< literal_datatype >>

Returns the datatype value of the literal node.

=end private

=cut

sub literal_datatype {
	my $self	= shift;
	my $dt		= RDF::Query::Model::SQL->literal_datatype( $self );
	return unless $dt;
	return $self->new( $dt );
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
