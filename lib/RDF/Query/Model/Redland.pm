#!/usr/bin/perl

package RDF::Query::Model::Redland;

use strict;
use warnings;
use Carp qw(carp croak confess);

use File::Spec;
use RDF::Redland;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.2 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
}

######################################################################

sub base_ns { 'http://kasei.us/about/foaf.xrdf' }
# sub base_ns { 'http://kasei.us/e/ns/base' }
sub new {
	my $class	= shift;
	my $model	= shift;
	unless (UNIVERSAL::isa($model, 'RDF::Redland::Model')) {
		my $storage	= RDF::Redland::Storage->new( "hashes", "test", "new='yes',hash-type='memory'" );
		$model	= RDF::Redland::Model->new( $storage, '' );
	}
	my $parser	= RDF::Redland::Parser->new();
	my $self	= bless( {
					model	=> $model,
					parser	=> $parser
				}, $class );
}

sub model {
	my $self	= shift;
	return $self->{'model'};
}

sub new_resource {
	my $self	= shift;
	my $uri		= RDF::Redland::URI->new( shift );
	return RDF::Redland::Node->new( $uri );
}

sub new_literal {
	my $self	= shift;
	return RDF::Redland::Node->new(@_);
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

sub count {
	my $self	= shift;
	return $self->{'model'}->size;
}

sub add_file {
#	warn 'Z';
	my $self	= shift;
	my $file	= File::Spec->rel2abs( shift );
	warn $file if ($debug);
	$self->add_uri( "file://${file}" );
#	warn 'Y';
}

sub add_uri {
#	warn 'X';
	my $self	= shift;
	my $uri		= shift;
#	warn $uri;
	my $parser	= $self->{'parser'};
	my $redlanduri	= RDF::Redland::URI->new( $uri );
	my $redlandns	= RDF::Redland::URI->new( $self->base_ns );
#	warn 'URI: ' . $redlanduri->as_string;
#	warn 'NS: ' . $redlandns->as_string;
	$parser->parse_into_model(
		$redlanduri,
		$redlandns,
		$self->{'model'}
	);
#	warn 'W';
}

sub statement_method_map {
	return qw(subject predicate object);
}

sub get_statements {
	my $self	= shift;
	my $match	= RDF::Redland::Statement->new( @_ );
	my $stream	= $self->{'model'}->find_statements( $match );
	return sub {
		return undef if ($stream->end);
		my $ret	= $stream->current;
		$stream->next;
		return $ret;
	};
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

sub RDF::Redland::Statement::getLabel {
	my $st	= shift;
	return $st->as_string;
}

1;

__END__
