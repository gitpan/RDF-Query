#!/usr/bin/perl

package RDF::Query::Model::RDFCore;

use strict;
use warnings;
use base qw(RDF::Query::Model);

use Carp qw(carp croak);
use Scalar::Util qw(blessed);

use File::Spec;
use LWP::Simple;
use RDF::Core::Model;
use RDF::Core::Query;
use RDF::Core::Model::Parser;
use RDF::Core::Storage::Memory;
use RDF::Core::NodeFactory;
use RDF::Core::Model::Serializer;

use RDF::Query::Stream;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 142 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=item C<new ( $model )>

Returns a new bridge object for the specified C<$model>.

=cut

sub new {
	my $class	= shift;
	my $model	= shift;
	my %args	= @_;
	
	unless (blessed($model) and $model->isa('RDF::Core::Model')) {
		my $storage	= new RDF::Core::Storage::Memory;
		$model	= new RDF::Core::Model (Storage => $storage);
	}
	my $factory	= new RDF::Core::NodeFactory;
	my $self	= bless( {
					model	=> $model,
					parsed	=> $args{parsed},
					factory	=> $factory,
					sttime	=> time,
					counter	=> 0
				}, $class );
}

=item C<model ()>

Returns the underlying model object.

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
	return RDF::Core::Resource->new(@_);
}

=item C<new_literal ( $string, $language, $datatype )>

Returns a new literal object.

=cut

sub new_literal {
	my $self	= shift;
	return RDF::Core::Literal->new(@_);
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
	return $self->{'factory'}->newResource("_:${id}");
}

=item C<new_statement ( $s, $p, $o )>

Returns a new statement object.

=cut

sub new_statement {
	my $self	= shift;
	return RDF::Core::Statement->new(@_);
}

=item C<isa_node ( $node )>

Returns true if C<$node> is a node object for the current model.

=cut

sub isa_node {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Core::Node');
}

=item C<isa_resource ( $node )>

Returns true if C<$node> is a resource object for the current model.

=cut

sub isa_resource {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Core::Resource');
}

=item C<isa_literal ( $node )>

Returns true if C<$node> is a literal object for the current model.

=cut

sub isa_literal {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Core::Literal');
}

=item C<isa_blank ( $node )>

Returns true if C<$node> is a blank node object for the current model.

=cut

sub isa_blank {
	my $self	= shift;
	my $node	= shift;
	return (UNIVERSAL::isa($node,'RDF::Core::Resource') and $node->getURI =~ /^_:/);
}
*RDF::Query::Model::RDFCore::is_node		= \&isa_node;
*RDF::Query::Model::RDFCore::is_resource	= \&isa_resource;
*RDF::Query::Model::RDFCore::is_literal		= \&isa_literal;
*RDF::Query::Model::RDFCore::is_blank		= \&isa_blank;

=item C<as_string ( $node )>

Returns a string version of the node object.

=cut

sub as_string {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

=item C<literal_value ( $node )>

Returns the string value of the literal object.

=cut

sub literal_value {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

=item C<literal_datatype ( $node )>

Returns the datatype of the literal object.

=cut

sub literal_datatype {
	my $self	= shift;
	my $node	= shift;
	my $type	= $node->getDatatype;
	return $type;
}

=item C<literal_value_language ( $node )>

Returns the language of the literal object.

=cut

sub literal_value_language {
	my $self	= shift;
	my $node	= shift;
	my $lang	= $node->getLang;
	return $lang;
}

=item C<uri_value ( $node )>

Returns the URI string of the resource object.

=cut

sub uri_value {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

=item C<blank_identifier ( $node )>

Returns the identifier for the blank node object.

=cut

sub blank_identifier {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

=item C<add_uri ( $uri, $named )>

Addsd the contents of the specified C<$uri> to the model.
If C<$named> is true, the data is added to the model using C<$uri> as the
named context.

=cut

{ my $counter	= 0;
sub add_uri {
	my $self	= shift;
	my $url		= shift;
	my $named	= shift;
	
	die "This model does not support named graphs" if ($named);
	
	my $rdf		= LWP::Simple::get($url);
	my %options = (
				Model		=> $self->{'model'},
				Source		=> $rdf,
				SourceType	=> 'string',
				BaseURI		=> $url,
				BNodePrefix	=> "genid" . $counter++,
			);
	my $parser	= new RDF::Core::Model::Parser (%options);
	$parser->parse;
}
}

=item C<statement_method_map ()>

Returns an ordered list of method names that when called against a statement
object will return the subject, predicate, and object objects, respectively.

=cut

sub statement_method_map {
	return qw(getSubject getPredicate getObject);
}

=item C<get_statements ($subject, $predicate, $object)>

Returns a stream object of all statements matching the specified subject,
predicate and objects. Any of the arguments may be undef to match any value.

=cut

sub get_statements {
	my $self	= shift;
	my $enum	= $self->{'model'}->getStmts( @_ );
	my $stmt	= $enum->getNext;
	my $stream	= sub {
		return undef unless defined($stmt);
		my $ret	= $stmt;
		$stmt	= $enum->getNext;
		return $ret;
	};
	
	return RDF::Query::Stream->new( $stream, 'graph', undef, bridge => $self );
}

=item C<supports ($feature)>

Returns true if the underlying model supports the named C<$feature>.
Possible features include:

	* named_graph

=cut

sub supports {
	my $self	= shift;
	my $feature	= shift;
	return 0;
}

=item C<as_xml ($stream)>

Returns an RDF/XML serialization of the results graph.

=cut

sub as_xml {
	my $self	= shift;
	my $iter	= shift;
	return undef unless $iter->is_graph;
	my $storage	= new RDF::Core::Storage::Memory;
	my $model	= new RDF::Core::Model (Storage => $storage);
	while ($iter and not $iter->finished) {
		$model->addStmt( $iter->current );
	} continue { $iter->next }
	my $xml;
	my $serializer	= RDF::Core::Model::Serializer->new(
						Model	=> $model,
						Output	=> \$xml,
#						BaseURI => $self->base_ns,
					);
	$serializer->serialize;
	return $xml;
}

1;

__END__
