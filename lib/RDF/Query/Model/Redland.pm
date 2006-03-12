package RDF::Query::Model::Redland;

use strict;
use warnings;
use Carp qw(carp croak confess);

use File::Spec;
use RDF::Redland 1.00;
use Data::Dumper;
use Scalar::Util qw(blessed);
use Encode;

use RDF::Query::Stream;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 137 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

sub new {
	my $class	= shift;
	my $model	= shift;
	unless (UNIVERSAL::isa($model, 'RDF::Redland::Model')) {
		my $storage	= RDF::Redland::Storage->new( "hashes", "test", "new='yes',hash-type='memory',contexts='yes'" );
		$model	= RDF::Redland::Model->new( $storage, '' );
	}
	my $self	= bless( {
					model	=> $model,
				}, $class );
}

sub model {
	my $self	= shift;
	return $self->{'model'};
}

=item C<new_resource ( $uri )>

Returns a new resource object.

=cut

sub new_resource {
	my $self	= shift;
	my $uri		= RDF::Redland::URI->new( shift );
	return RDF::Redland::Node->new_from_uri( $uri );
}

=item C<new_literal ( $string, $language, $datatype )>

Returns a new literal object.

=cut

sub new_literal {
	my $self	= shift;
	my $value	= shift;
	my $lang	= shift;
	my $type	= shift;
	my @args	= ($value);
	no warnings 'uninitialized';
	if ($type and $RDF::Redland::VERSION >= 1.00_02) {
		# $RDF::Redland::VERSION is introduced in 1.0.2, and that's also when datatypes are fixed.
		$type	= RDF::Redland::URI->new( $type );
		push(@args, $type);
	} elsif ($lang) {
		push(@args, undef);
	}
	
	if ($lang) {
		push(@args, $lang);
	}
	
	return RDF::Redland::Node->new_literal( @args );
}

=item C<new_blank ( $identifier )>

Returns a new blank node object.

=cut

sub new_blank {
	my $self	= shift;
	return RDF::Redland::Node->new_from_blank_identifier(@_);
}

=item C<new_statement ( $s, $p, $o )>

Returns a new statement object.

=cut

sub new_statement {
	my $self	= shift;
	return RDF::Redland::Statement->new(@_);
}

=item C<isa_node ( $node )>

Returns true if C<$node> is a node object for the current model.

=cut

sub isa_node {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Redland::Node');
}

=item C<isa_resource ( $node )>

Returns true if C<$node> is a resource object for the current model.

=cut

sub isa_resource {
	my $self	= shift;
	my $node	= shift;
	return (ref($node) and $node->is_resource);
}

=item C<isa_literal ( $node )>

Returns true if C<$node> is a literal object for the current model.

=cut

sub isa_literal {
	my $self	= shift;
	my $node	= shift;
	return (ref($node) and $node->is_literal);
}

=item C<isa_blank ( $node )>

Returns true if C<$node> is a blank node object for the current model.

=cut

sub isa_blank {
	my $self	= shift;
	my $node	= shift;
	return (ref($node) and $node->is_blank);
}
*RDF::Query::Model::Redland::is_node		= \&isa_node;
*RDF::Query::Model::Redland::is_resource	= \&isa_resource;
*RDF::Query::Model::Redland::is_literal		= \&isa_literal;
*RDF::Query::Model::Redland::is_blank		= \&isa_blank;

=item C<as_string ( $node )>

Returns a string version of the node object.

=cut

sub as_string {
	my $self	= shift;
	my $node	= shift;
	Carp:confess unless (blessed($node));
	return $node->as_string;
}

=item C<literal_value ( $node )>

Returns the string value of the literal object.

=cut

sub literal_value {
	my $self	= shift;
	my $node	= shift;
	return decode('utf8', $node->literal_value);
}

=item C<literal_datatype ( $node )>

Returns the datatype of the literal object.

=cut

sub literal_datatype {
	my $self	= shift;
	my $node	= shift;
	my $type	= $node->literal_datatype;
	return unless $type;
	return $type->as_string;
}

=item C<literal_value_language ( $node )>

Returns the language of the literal object.

=cut

sub literal_value_language {
	my $self	= shift;
	my $node	= shift;
	my $lang	= $node->literal_value_language;
	return $lang;
}

=item C<uri_value ( $node )>

Returns the URI string of the resource object.

=cut

sub uri_value {
	my $self	= shift;
	my $node	= shift;
	return $node->uri->as_string;
}

=item C<blank_identifier ( $node )>

Returns the identifier for the blank node object.

=cut

sub blank_identifier {
	my $self	= shift;
	my $node	= shift;
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
	my $named	= shift;
	
	my $model		= $self->{model};
	my $parser		= RDF::Redland::Parser->new('guess');
	my $redlanduri	= RDF::Redland::URI->new( $uri );
	
	if ($named) {
		my $stream		= $parser->parse_as_stream($redlanduri, $redlanduri);
		$model->add_statements( $stream, $redlanduri );
	} else {
		$parser->parse_into_model( $redlanduri, $redlanduri, $model );
	}
}

=item C<statement_method_map ()>

Returns an ordered list of method names that when called against a statement
object will return the subject, predicate, and object objects, respectively.

=cut

sub statement_method_map {
	return qw(subject predicate object);
}

=item C<get_statements ($subject, $predicate, $object)>

Returns a stream object of all statements matching the specified subject,
predicate and objects. Any of the arguments may be undef to match any value.

=cut

sub get_statements {
	my $self	= shift;
	my @triple	= splice(@_, 0, 3);
	my $context	= shift;
	
	my @defs	= grep defined, @triple;
	my $model	= $self->{'model'};
	my $stmt	= RDF::Redland::Statement->new( @triple );
	my $stream;
	
	my %args	= ( bridge => $self, named => 1 );
	
	if ($context) {
		my $iter	= $model->find_statements( $stmt, $context );
		$args{ context }	= $context;
		$stream	= sub {
			if (@_ and $_[0] eq 'context') {
				return $context;
			} elsif (not $iter) {
				return undef;
			} elsif ($iter->end) {
				$iter	= undef;
				return undef;
			} else {
				my $ret	= $iter->current;
				$iter->next;
				return $ret;
			}
		};
	} else {
		if (0) {
			my $stream	= $model->as_stream();
			warn "------------------------------\n";
			while (my $st = $stream->current) {
				warn $st->as_string;
			} continue { $stream->next }
			warn "------------------------------\n";
		}
		if (scalar(@defs) == 2) {
			my @imethods	= qw(sources_iterator arcs_iterator targets_iterator);
			my @smethods	= qw(subject predicate object);
			my ($imethod, $smethod);
			foreach my $i (0 .. 2) {
				if (not defined $triple[ $i ]) {
					$imethod	= $imethods[ $i ];
					$smethod	= $smethods[ $i ];
					last;
				}
			}
			my $iter	= $model->$imethod( @defs );
			my $context;
			$stream	= sub {
				if (@_ and $_[0] eq 'context') {
					return $context;
				} elsif (not $iter) {
					return undef;
				} elsif ($iter->end) {
					$iter	= undef;
					return undef;
				} else {
					my $ret	= $iter->current;
					$context	= $iter->context;
					$iter->next;
					my $s	= $stmt->clone;
					$s->$smethod( $ret );
					return $s;
				}
			};
		} else {
			my $iter	= $model->find_statements( $stmt );
			warn "iterator: $iter (" . $stmt->as_string . ')' if (0);
			my $context;
			$stream	= sub {
				no warnings 'uninitialized';
				if (@_ and $_[0] eq 'context') {
					return $context;
				} elsif (not $iter) {
					return undef;
				} elsif ($iter->end) {
					$context	= $iter->context;
					$iter	= undef;
					return undef;
				} else {
					my $ret	= $iter->current;
					$context	= $iter->context;
					$iter->next;
					return $ret;
				}
			};
		}
	}
	
	return RDF::Query::Stream->new( $stream, 'graph', undef, %args );
}

=item C<get_context ($stream)>

Returns the context node of the last statement retrieved from the specified
C<$stream>. The stream object, in turn, calls the closure (that was passed to
the stream constructor in C<get_statements>) with the argument 'context'.

=cut

sub get_context {
	my $self	= shift;
	my $stream	= shift;
	my %args	= @_;
	
	if (0) {
		Carp::cluck "get_context stream: ";
		local($RDF::Query::debug)	= 2;
		RDF::Query::_debug_closure( $stream );
	}
	
	my $context	= $stream->('context');
	return $context;
}

=item C<supports ($feature)>

Returns true if the underlying model supports the named C<$feature>.
Possible features include:

	* named_graph

=cut

sub supports {
	my $self	= shift;
	my $feature	= shift;
	return 1 if ($feature eq 'named_graph');
	return 0;
}

=item C<as_xml ($stream)>

Returns an RDF/XML serialization of the results graph.

=cut

sub as_xml {
	my $self	= shift;
	my $iter	= shift;
	return undef unless $iter->is_graph;
	my $storage	= RDF::Redland::Storage->new("hashes", "test", "new='yes',hash-type='memory'");
	my $model	= RDF::Redland::Model->new($storage, "");
	while (my $st = $iter->current) {
		$model->add_statement( $st );
		$iter->next;
	}
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
