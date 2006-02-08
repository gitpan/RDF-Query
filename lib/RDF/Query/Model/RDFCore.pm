#!/usr/bin/perl

package RDF::Query::Model::RDFCore;

use strict;
use warnings;
use Carp qw(carp croak);

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
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

sub base_ns { 'http://kasei.us/e/ns/' }
sub new {
	my $class	= shift;
	my $model	= shift;
	unless (UNIVERSAL::isa($model, 'RDF::Core::Model')) {
		my $storage	= new RDF::Core::Storage::Memory;
		$model	= new RDF::Core::Model (Storage => $storage);
	}
	my $factory	= new RDF::Core::NodeFactory;
	my $self	= bless( {
					model	=> $model,
					factory	=> $factory,
					sttime	=> time,
					counter	=> 0
				}, $class );
}

sub model {
	my $self	= shift;
	return $self->{'model'};
}

sub new_resource {
	my $self	= shift;
	return RDF::Core::Resource->new(@_);
}

sub new_literal {
	my $self	= shift;
	return RDF::Core::Literal->new(@_);
}

sub new_blank {
	my $self	= shift;
	my $id		= shift;
	unless ($id) {
		$id	= 'r' . $self->{'sttime'} . 'r' . $self->{'counter'}++;
	}
	return $self->{'factory'}->newResource("_:${id}");
}

sub new_statement {
	my $self	= shift;
	return RDF::Core::Statement->new(@_);
}

sub isa_node {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Core::Node');
}

sub isa_resource {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Core::Resource');
}

sub isa_literal {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Core::Literal');
}

sub isa_blank {
	my $self	= shift;
	my $node	= shift;
	warn Data::Dumper::Dumper($node);
	return (UNIVERSAL::isa($node,'RDF::Core::Resource') and $node->getURI =~ /^_:/);
}
*RDF::Query::Model::RDFCore::is_node		= \&isa_node;
*RDF::Query::Model::RDFCore::is_resource	= \&isa_resource;
*RDF::Query::Model::RDFCore::is_literal		= \&isa_literal;
*RDF::Query::Model::RDFCore::is_blank		= \&isa_blank;

sub as_string {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

sub literal_value {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

sub literal_datatype {
	my $self	= shift;
	my $node	= shift;
	my $type	= $node->getDatatype;
	return $type;
}

sub literal_value_language {
	my $self	= shift;
	my $node	= shift;
	my $lang	= $node->getLang;
	return $lang;
}

sub uri_value {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

sub blank_identifier {
	my $self	= shift;
	my $node	= shift;
	return $node->getLabel;
}

sub add_uri {
	my $self	= shift;
	my $url		= shift;
	my $named	= shift;
	
	if ($named and not $self->supports('named_graph')) {
		die "This model does not support named graphs";
	}
	
	my $rdf		= LWP::Simple::get($url);
	my %options = (
				Model		=> $self->{'model'},
				Source		=> $rdf,
				SourceType	=> 'string',
				BaseURI		=> $self->base_ns,
				BNodePrefix	=> "genid"
			);
	my $parser	= new RDF::Core::Model::Parser (%options);
	$parser->parse;
}

sub statement_method_map {
	return qw(getSubject getPredicate getObject);
}

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

sub supports {
	my $self	= shift;
	my $feature	= shift;
	return 0;
}

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
						BaseURI => $self->base_ns,
					);
	$serializer->serialize;
	return $xml;
}

1;

__END__
