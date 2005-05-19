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

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.4 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
}

######################################################################

sub base_ns { 'http://kasei.us/e/ns/' }
sub new {
	my $class	= shift;
	my $storage	= new RDF::Core::Storage::Memory;
	my $model	= new RDF::Core::Model (Storage => $storage);
	my $factory	= new RDF::Core::NodeFactory;
	my $self	= bless( {
					model	=> $model,
					factory	=> $factory
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
	return RDF::Core::Resource->new(@_);
}

sub new_blank {
	my $self	= shift;
	my $id		= shift;
	return $self->factory->newResoruce("_:${id}");
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

sub count {
	my $self	= shift;
	return $self->{'model'}->countStmts;
}

sub add_file {
	my $self	= shift;
	my $file	= File::Spec->rel2abs( shift );
	my %options = (
				Model		=> $self->{'model'},
				Source		=> $file,
				SourceType	=> 'file',
				BaseURI		=> $self->base_ns,
				BNodePrefix	=> "genid"
			);
	my $parser	= new RDF::Core::Model::Parser (%options);
	$parser->parse;
}

sub add_uri {
	my $self	= shift;
	my $url		= shift;
	my $rdf		= LWP::Simple::get($url);
	my %options = (
				Model		=> $self->{'model'},
				Source		=> $rdf,
				SourceType	=> 'string',
				BaseURI		=> "http://kasei.us/e/ns/querybase",
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
	my $stmt	= $enum->getFirst;
	return RDF::Query::Stream->new( sub {
		return undef unless defined($stmt);
		my $ret	= $stmt;
		$stmt	= $enum->getNext;
		return $ret;
	} );
}


sub AUTOLOAD {
	my $self	= shift;
	my $class	= ref($self);
	return undef unless ($class);
	
	our $AUTOLOAD;
	return if ($AUTOLOAD =~ /DESTROY/);
	my $method		= $AUTOLOAD;
	$method			=~ s/^.*://;
	my $model		= $self->{'model'};
	
	if ($model->can($method)) {
		$model->$method( @_ );
	} else {
		croak qq[Can't locate object method "$method" via package $class];
	}
}


1;

__END__
