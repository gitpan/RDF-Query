#!/usr/bin/perl

package RDF::Query::Model::Redland;

use strict;
use warnings;
use Carp qw(carp croak confess);

use File::Spec;
use RDF::Redland;
use Encode;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.5 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
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
	return RDF::Redland::Node->new_literal(@_);
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
	my $self	= shift;
	my $uri		= shift;
	my $parser	= RDF::Redland::Parser->new();
	my $redlanduri	= RDF::Redland::URI->new( $uri );
	my $redlandns	= RDF::Redland::URI->new( $self->base_ns );
	$parser->parse_into_model(
		$redlanduri,
		$redlandns,
		$self->{'model'}
	);
}

sub statement_method_map {
	return qw(subject predicate object);
}

sub get_statements {
	my $self	= shift;
	my @triple	= @_;
	my @defs	= grep defined, @triple;
	my $model	= $self->{'model'};
	my $stmt	= RDF::Redland::Statement->new( @triple );
	my $stream;
	
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
		$stream	= sub {
			return undef unless ($iter);
			if ($iter->end) {
				$iter	= undef;
				return undef;
			}
			my $ret	= $iter->current;
			$iter->next;
			my $s	= $stmt->clone;
			$s->$smethod( $ret );
			return $s;
		};
	} else {
		my $iter	= $model->find_statements( $stmt );
		$stream	= sub {
			return undef unless ($iter);
			if ($iter->end) {
				$iter	= undef;
				return undef;
			}
			my $ret	= $iter->current;
			$iter->next;
			return $ret;
		};
	}
	return RDF::Query::Stream->new( $stream );
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
