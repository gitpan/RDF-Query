#!/usr/bin/perl

package RDF::Query::Model::Redland;

use strict;
use warnings;
use Carp qw(carp croak confess);

use File::Spec;
use RDF::Redland;
use Data::Dumper;
use Encode;

use RDF::Query::Stream;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

sub base_ns { 'http://kasei.us/e/ns/base#' }
sub new {
	my $class	= shift;
	my $model	= shift;
	unless (UNIVERSAL::isa($model, 'RDF::Redland::Model')) {
		my $storage	= RDF::Redland::Storage->new( "hashes", "test", "new='yes',hash-type='memory'" );
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

sub new_resource {
	my $self	= shift;
	my $uri		= RDF::Redland::URI->new( shift );
	return RDF::Redland::Node->new_from_uri( $uri );
}

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

sub new_blank {
	my $self	= shift;
	return RDF::Redland::Node->new_from_blank_identifier(@_);
}

sub new_statement {
	my $self	= shift;
	return RDF::Redland::Statement->new(@_);
}

sub isa_node {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Redland::Node');
}

sub isa_resource {
	my $self	= shift;
	my $node	= shift;
	return (ref($node) and $node->is_resource);
}

sub isa_literal {
	my $self	= shift;
	my $node	= shift;
	return (ref($node) and $node->is_literal);
}

sub isa_blank {
	my $self	= shift;
	my $node	= shift;
	return (ref($node) and $node->is_blank);
}
*RDF::Query::Model::Redland::is_node		= \&isa_node;
*RDF::Query::Model::Redland::is_resource	= \&isa_resource;
*RDF::Query::Model::Redland::is_literal		= \&isa_literal;
*RDF::Query::Model::Redland::is_blank		= \&isa_blank;

sub as_string {
	my $self	= shift;
	my $node	= shift;
	return $node->as_string;
}

sub literal_value {
	my $self	= shift;
	my $node	= shift;
	return decode('utf8', $node->literal_value);
}

sub literal_datatype {
	my $self	= shift;
	my $node	= shift;
	my $type	= $node->literal_datatype;
	return $type->as_string;
}

sub literal_value_language {
	my $self	= shift;
	my $node	= shift;
	my $lang	= $node->literal_value_language;
	return $lang;
}

sub uri_value {
	my $self	= shift;
	my $node	= shift;
	return $node->uri->as_string;
}

sub blank_identifier {
	my $self	= shift;
	my $node	= shift;
	return $node->blank_identifier;
}

sub add_uri {
	my $self	= shift;
	my $uri		= shift;
	my $named	= shift;
	
	my $model	= $self->{model};
	my $parser	= RDF::Redland::Parser->new();
	my $redlanduri	= RDF::Redland::URI->new( $uri );
	my $redlandns	= RDF::Redland::URI->new( $self->base_ns );
	my $stream		= $parser->parse_as_stream(
		$redlanduri,
		$redlanduri,
	);
	$model->add_statements( $stream, ($named ? $redlanduri : ()) );
}

sub statement_method_map {
	return qw(subject predicate object);
}

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

sub supports {
	my $self	= shift;
	my $feature	= shift;
	return 1 if ($feature eq 'named_graph');
	return 0;
}

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
