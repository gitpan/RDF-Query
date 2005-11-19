#!/usr/bin/perl

package RDF::Query::Model::DBI;

use strict;
use warnings;
use Carp qw(carp croak confess);

use File::Spec;
use Data::Dumper;
use Encode;
use DBI;
use URI;

use RDF::Query::Stream;
use RDF::Query::Model::DBI::Statement;

######################################################################

our ($VERSION, $debug);
BEGIN {
	*debug		= \$RDF::Query::debug;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.2 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
}

######################################################################

sub base_ns { 'http://kasei.us/e/ns/base#' }
sub new {
	my $class	= shift;
	my $data	= shift;
	my ($dbh, $model)	= @{ $data };
	my $self	= bless( {
					dbh				=> $dbh,
					model			=> $model,
					model_number	=> get_model_number( $dbh, $model ),
					sttime			=> time
				}, $class );
}

sub model {
	my $self	= shift;
	return [ @{ $self }{qw(dbh model)} ];
}

sub new_resource {
	my $self	= shift;
	my $uri		= shift;
	return bless({ uri => $uri }, 'RDF::Query::Model::DBI::Resource');
}

sub new_literal {
	my $self	= shift;
	my $value	= shift;
	my $lang	= shift;
	my $type	= shift;
	return bless({ value => $value, lang => $lang, type => $type }, 'RDF::Query::Model::DBI::Literal');
}

sub new_blank {
	my $self	= shift;
	my $id		= shift;
	unless ($id) {
		$id	= 'r' . $self->{'sttime'} . 'r' . $self->{'counter'}++;
	}
	return bless({ identifier => $id }, 'RDF::Query::Model::DBI::Blank');
}

sub new_statement {
	my $self	= shift;
	return RDF::Query::Model::DBI::Statement->new( @_ );
}

sub isa_node {
	my $self	= shift;
	my $node	= shift;
	return 1 if UNIVERSAL::isa($node,'RDF::Query::Model::DBI::Resource');
	return 1 if UNIVERSAL::isa($node,'RDF::Query::Model::DBI::Literal');
	return 1 if UNIVERSAL::isa($node,'RDF::Query::Model::DBI::Blank');
	return 0 ;
}

sub isa_resource {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Query::Model::DBI::Resource');
}

sub isa_literal {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Query::Model::DBI::Literal');
}

sub is_blank {
	my $self	= shift;
	my $node	= shift;
	return UNIVERSAL::isa($node,'RDF::Query::Model::DBI::Blank');
}
*RDF::Query::Model::DBI::is_node		= \&isa_node;
*RDF::Query::Model::DBI::is_resource	= \&isa_resource;
*RDF::Query::Model::DBI::is_literal		= \&isa_literal;

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

sub literal_value {
	my $self	= shift;
	my $node	= shift;
	return $node->{ value };
}

sub literal_datatype {
	my $self	= shift;
	my $node	= shift;
	return $node->{ type };
}

sub literal_value_language {
	my $self	= shift;
	my $node	= shift;
	return $node->{ lang };
}

sub uri_value {
	my $self	= shift;
	my $node	= shift;
	return $node->{ uri };
}

sub blank_identifier {
	my $self	= shift;
	my $node	= shift;
	return $node->{ identifier };
}

sub add_uri {
	my $self	= shift;
	my $uri		= shift;
	die "XXX unimplemented";
}

sub statement_method_map {
	return qw(subject predicate object);
}

sub get_statements {
	my $self	= shift;
	my @triple	= @_;
	
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

sub as_xml {
	my $self	= shift;
	my $iter	= shift;
	return undef unless $iter->is_graph;
	return '';
}

sub get_model_number {
	my $dbh		= shift;
	my $model	= shift;
	my $sth		= $dbh->prepare( 'SELECT ID FROM Models WHERE Name = ?' );
	$sth->execute( $model );
	my ($id)	= $sth->fetchrow_array;
	return $id;
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
