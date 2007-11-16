# RDF::Query::Stream
# -------------
# $Revision: 293 $
# $Date: 2007-11-15 14:55:24 -0500 (Thu, 15 Nov 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Stream - Stream (iterator) class for query results.

=head1 VERSION

This document describes RDF::SPARQLResults version 1.000.


=head1 SYNOPSIS

    use RDF::SPARQLResults;
    my $query	= RDF::Query->new( '...query...' );
    my $stream	= $query->execute();
    while (my $row = $stream->next) {
    	my @vars	= @$row;
    	# do something with @vars
    }

=head1 METHODS

=over 4

=cut

package RDF::Query::Stream;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Carp qw(carp);
use Scalar::Util qw(blessed reftype);

our ($REVISION, $VERSION, $debug, @ISA, @EXPORT_OK);
use constant DEBUG	=> 0;
BEGIN {
	$debug		= DEBUG;
	$REVISION	= do { my $REV = (qw$Revision: 293 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$VERSION	= '1.000';
	
	require Exporter;
	@ISA		= qw(Exporter);
	@EXPORT_OK	= qw(sgrep smap swatch);
}


use overload 'bool' => sub { $_[0] };
use overload '&{}' => sub {
	my $self	= shift;
	return sub {
		return $self->next;
	};
};


=item C<new ( \@results, $type, \@names, %args )>

=item C<new ( \&results, $type, \@names, %args )>

Returns a new SPARQL Result interator object. Results must be either
an reference to an array containing results or a CODE reference that
acts as an iterator, returning successive items when called, and
returning undef when the iterator is exhausted.

$type should be one of: bindings, boolean, graph.

=cut

sub new {
	my $class		= shift;
	my $stream		= shift || sub { undef };
	my $type		= shift || 'bindings';
	my $names		= shift || [];
	my %args		= @_;
	
	if (ref($stream) and reftype($stream) eq 'ARRAY') {
		my $array	= $stream;
		$stream	= sub {
			return shift(@$array);
		}
	}
	
	my $open		= 0;
	my $finished	= 0;
	my $row;
	
	my $data	= {
		_open		=> 0,
		_finished	=> 0,
		_type		=> $type,
		_names		=> $names,
		_stream		=> $stream,
		_args		=> \%args,
		_row		=> undef,
	};
	
	my $self	= bless($data, $class);
	return $self;
}

=item C<type>

Returns the underlying result type (boolean, graph, bindings).

=cut

sub type {
	my $self			= shift;
	return $self->{_type};
}

=item C<is_boolean>

Returns true if the underlying result is a boolean value.

=cut

sub is_boolean {
	my $self			= shift;
	return ($self->{_type} eq 'boolean') ? 1 : 0;
}

=item C<is_bindings>

Returns true if the underlying result is a set of variable bindings.

=cut

sub is_bindings {
	my $self			= shift;
	return ($self->{_type} eq 'bindings') ? 1 : 0;
}

=item C<is_graph>

Returns true if the underlying result is an RDF graph.

=cut

sub is_graph {
	my $self			= shift;
	return ($self->{_type} eq 'graph') ? 1 : 0;
}

=item C<to_string ( $format )>

Returns a string representation of the stream data in the specified
C<$format>. If C<$format> is missing, defaults to XML serialization.
Other options are:

  http://www.w3.org/2001/sw/DataAccess/json-sparql/

=cut

sub to_string {
	my $self	= shift;
	my $format	= shift || 'http://www.w3.org/2001/sw/DataAccess/rf1/result2';
	if (ref($format) and $format->isa('RDF::Redland::URI')) {
		$format	= $format->as_string;
	}
	
	if ($format eq 'http://www.w3.org/2001/sw/DataAccess/json-sparql/') {
		return $self->as_json;
	} else {
		return $self->as_xml;
	}
}

=item C<< next >>

=item C<< next_result >>

Returns the next item in the stream.

=cut

sub next { $_[0]->next_result }
sub next_result {
	my $self	= shift;
	return if ($self->{_finished});
	
	my $stream	= $self->{_stream};
	my $value	= $stream->();
	unless (defined($value)) {
		$self->{_finished}	= 1;
	}

	my $args	= $self->_args;
	if ($args->{named}) {
		if ($self->_bridge->supports('named_graph')) {
			my $bridge	= $self->_bridge;
			$args->{context}	= $bridge->get_context( $self->{_stream}, %$args );
		}
	}
	
	$self->{_open}++;
	$self->{_row}	= $value;
	return $value;
}


=item C<< current >>

Returns the current item in the stream.

=cut

sub current {
	my $self	= shift;
	if ($self->open) {
		return $self->_row;
	} else {
		return $self->next;
	}
}

=item C<< binding_value_by_name ( $name ) >>

Returns the binding of the named variable in the current result.

=cut

sub binding_value_by_name {
	my $self	= shift;
	my $name	= shift;
	my $names	= $self->{_names};
	foreach my $i (0 .. $#{ $names }) {
		if ($names->[$i] eq $name) {
			return $self->binding_value( $i );
		}
	}
	warn "No variable named '$name' is present in query results.\n";
}

=item C<< binding_value ( $i ) >>

Returns the binding of the $i-th variable in the current result.

=cut

sub binding_value {
	my $self	= shift;
	my $val		= shift;
	my $row		= ($self->open) ? $self->current : $self->next;
	return $row->[ $val ];
}


=item C<binding_values>

Returns a list of the binding values from the current result.

=cut

sub binding_values {
	my $self	= shift;
	my $row		= ($self->open) ? $self->current : $self->next;
	return @$row;
}


=item C<binding_names>

Returns a list of the binding names.

=cut

sub binding_names {
	my $self	= shift;
	my $names	= $self->{_names};
	return @$names;
}

=item C<binding_name ( $i )>

Returns the name of the $i-th result column.

=cut

sub binding_name {
	my $self	= shift;
	my $names	= $self->{_names};
	my $val		= shift;
	return $names->[ $val ];
}


=item C<bindings_count>

Returns the number of variable bindings in the current result.

=cut

sub bindings_count {
	my $self	= shift;
	my $names	= $self->{_names};
	my $row		= ($self->open) ? $self->current : $self->next;
	return scalar( @$names )if (scalar(@$names));
	return 0 unless ref($row);
	return scalar( @$row );
}

=item C<< end >>

=item C<< finished >>

Returns true if the end of the stream has been reached, false otherwise.

=cut

sub end { $_[0]->finished }
sub finished {
	my $self	= shift;
	return $self->{_finished};
}

=item C<< open >>

Returns true if the first element of the stream has been retrieved, false otherwise.

=cut

sub open {
	my $self	= shift;
	return $self->{_open};
}

=item C<< close >>

Closes the stream. Future attempts to retrieve data from the stream will act as
if the stream had been exhausted.

=cut

sub close {
	my $self			= shift;
	$self->{_finished}	= 1;
	undef( $self->{ _stream } );
	return;
}

=item C<< context >>

Returns the context node of the current result (if applicable).

=cut

sub context {
	my $self	= shift;
	my $args	= $self->_args;
	my $bridge	= $args->{bridge};
	my $stream	= $self->{_stream};
	my $context	= $bridge->get_context( $stream, %$args );
	return $context;
}


=item C<< concat ( $stream ) >>

Returns a new stream resulting from the concatenation of the referant and the
argument streams. The new stream uses the stream type, and optional binding
names and C<<%args>> from the referant stream.

=cut

sub concat {
	my $self	= shift;
	my $stream	= shift;
	my $class	= ref($self);
	my @streams	= ($self, $stream);
	my $next	= sub {
		while (@streams) {
			my $data	= $streams[0]->next;
			unless (defined($data)) {
				shift(@streams);
				next;
			}
			return $data;
		}
		return;
	};
	my $type	= $self->type;
	my $names	= [$self->binding_names];
	my $args	= $self->_args;
	my $s	= $class->new( $next, $type, $names, %$args );
	return $s;
}


=item C<get_boolean>

Returns the boolean value of the first item in the stream.

=cut

sub get_boolean {
	my $self	= shift;
	my $data	= $self->next_result;
	return +$data;
}

=item C<get_all>

Returns an array containing all the items in the stream.

=cut

sub get_all {
	my $self	= shift;
	
	my @data;
	while (my $data = $self->next) {
		push(@data, $data);
	}
	return @data;
}

=item C<as_xml ( $max_size )>

Returns an XML serialization of the stream data.

=cut

sub as_xml {
	my $self			= shift;
	my $max_result_size	= shift || 0;
	if ($self->is_bindings) {
		return $self->bindings_as_xml( $max_result_size );
	} elsif ($self->is_graph) {
		return $self->graph_as_xml( $max_result_size );
	} elsif ($self->is_boolean) {
		return $self->boolean_as_xml();
	}
}

=item C<as_json ( $max_size )>

Returns a JSON serialization of the stream data.

=cut

sub as_json {
	my $self			= shift;
	my $max_result_size	= shift || 0;
	if ($self->is_bindings) {
		return $self->bindings_as_json( $max_result_size );
	} elsif ($self->is_graph) {
		throw RDF::Query::Error::SerializationError ( -text => 'There is no JSON serialization specified for graph query results' );
	} elsif ($self->is_boolean) {
		return $self->boolean_as_json();
	}
}

=item C<boolean_as_xml>

Returns an XML serialization of the first stream item, interpreted as a boolean value.

=cut

sub boolean_as_xml {
	my $self			= shift;
	my $value	= $self->get_boolean ? 'true' : 'false';
	my $xml	= <<"END";
<?xml version="1.0"?>
<sparql xmlns="http://www.w3.org/2001/sw/DataAccess/rf1/result2">
<head></head>
<results>
	<boolean>${value}</boolean>
</results>
</sparql>
END
	return $xml;
}

=item C<boolean_as_json>

Returns a JSON serialization of the first stream item, interpreted as a boolean value.

=cut

sub boolean_as_json {
	my $self	= shift;
	my $value	= $self->get_boolean ? JSON::True : JSON::False;
	my $data	= { head => { vars => [] }, boolean => $value };
	return objToJson( $data );
}

=item C<bindings_as_xml ( $max_size )>

Returns an XML serialization of the stream data, interpreted as query variable binding results.

=cut

sub bindings_as_xml {
	my $self			= shift;
	my $max_result_size	= shift;
	my $width			= $self->bindings_count;
	my $bridge			= $self->_bridge;
	
	my @variables;
	for (my $i=0; $i < $width; $i++) {
		my $name	= $self->binding_name($i);
		push(@variables, $name) if $name;
	}
	
	my $count	= 0;
	my $t	= join("\n\t", map { qq(<variable name="$_"/>) } @variables);
	my $xml	= <<"END";
<?xml version="1.0"?>
<sparql xmlns="http://www.w3.org/2001/sw/DataAccess/rf1/result2">
<head>
	${t}
</head>
<results>
END
	while (!$self->finished) {
		my @row;
		$xml	.= "\t\t<result>\n";
		for (my $i = 0; $i < $width; $i++) {
			my $name		= $self->binding_name($i);
			my $value		= $self->binding_value($i);
			$xml	.= "\t\t\t" . format_node_xml($bridge, $value, $name) . "\n";
		}
		$xml	.= "\t\t</result>\n";
		
		last if ($max_result_size and ++$count >= $max_result_size);
	} continue { $self->next_result }
	$xml	.= <<"EOT";
</results>
</sparql>
EOT
	return $xml;
}

=item C<bindings_as_json ( $max_size )>

Returns a JSON serialization of the stream data, interpreted as query variable binding results.

=cut

sub bindings_as_json {
	my $self			= shift;
	my $max_result_size	= shift;
	my $width			= $self->bindings_count;
	my $bridge			= $self->_bridge;
	
	my @variables;
	for (my $i=0; $i < $width; $i++) {
		my $name	= $self->binding_name($i);
		push(@variables, $name) if $name;
	}
	
	my $count	= 0;
	my $parsed	= $bridge->parsed;
	my $order	= ref($parsed->{options}{orderby}) ? JSON::True : JSON::False;
	my $dist	= $parsed->{options}{distinct} ? JSON::True : JSON::False;
	
	my $data	= {
					head	=> { vars => \@variables },
					results	=> { ordered => $order, distinct => $dist },
				};
	my @bindings;
	while (!$self->finished) {
		my %row;
		for (my $i = 0; $i < $width; $i++) {
			my $name		= $self->binding_name($i);
			my $value		= $self->binding_value($i);
			if (my ($k, $v) = format_node_json($bridge, $value, $name)) {
				$row{ $k }		= $v;
			}
		}
		
		push(@{ $data->{results}{bindings} }, \%row);
		last if ($max_result_size and ++$count >= $max_result_size);
	} continue { $self->next_result }
	
	return objToJson( $data );
}

=item C<graph_as_xml>

Returns an XML serialization of the stream data, interpreted as a results graph.

=cut

sub graph_as_xml {
	my $self	= shift;
	return $self->_bridge->as_xml( $self );
}

=begin private

=item C<format_node_xml ( $node, $name )>

Returns a string representation of C<$node> for use in an XML serialization.

=end private

=cut

sub format_node_xml ($$$) {
	my $bridge	= shift;
	return undef unless ($bridge);
	
	my $node	= shift;
	my $name	= shift;
	my $node_label;
	
	if(!defined $node) {
		$node_label	= "<unbound/>";
	} elsif ($bridge->is_resource($node)) {
		$node_label	= $bridge->uri_value( $node );
		$node_label	=~ s/&/&amp;/g;
		$node_label	=~ s/</&lt;/g;
		$node_label	=~ s/"/&quot;/g;
		$node_label	= qq(<uri>${node_label}</uri>);
	} elsif ($bridge->is_literal($node)) {
		$node_label	= $bridge->literal_value( $node );
		$node_label	=~ s/&/&amp;/g;
		$node_label	=~ s/</&lt;/g;
		$node_label	=~ s/"/&quot;/g;
		$node_label	= qq(<literal>${node_label}</literal>);
	} elsif ($bridge->is_blank($node)) {
		$node_label	= $bridge->blank_identifier( $node );
		$node_label	=~ s/&/&amp;/g;
		$node_label	=~ s/</&lt;/g;
		$node_label	=~ s/"/&quot;/g;
		$node_label	= qq(<bnode>${node_label}</bnode>);
	} else {
		$node_label	= "<unbound/>";
	}
	return qq(<binding name="${name}">${node_label}</binding>);
}

=begin private

=item C<format_node_json ( $node, $name )>

Returns a string representation of C<$node> for use in a JSON serialization.

=end private

=cut

sub format_node_json ($$$) {
	my $bridge	= shift;
	return undef unless ($bridge);
	
	my $node	= shift;
	my $name	= shift;
	my $node_label;
	
	if(!defined $node) {
		return;
	} elsif ($bridge->is_resource($node)) {
		$node_label	= $bridge->uri_value( $node );
		return $name => { type => 'uri', value => $node_label };
	} elsif ($bridge->is_literal($node)) {
		$node_label	= $bridge->literal_value( $node );
		return $name => { type => 'literal', value => $node_label };
	} elsif ($bridge->is_blank($node)) {
		$node_label	= $bridge->blank_identifier( $node );
		return $name => { type => 'bnode', value => $node_label };
	} else {
		return;
	}
}

=begin private

=item C<< debug >>

Prints debugging information about the stream.

=end private

=cut

sub debug {
	my $self	= shift;
	my $stream	= $self->{_stream};
	local($RDF::Query::debug)	= 2;
	RDF::Query::_debug_closure( $stream );
}

sub _args {
	my $self	= shift;
	return $self->{_args};
}

sub _row {
	my $self	= shift;
	return $self->{_row};
}

sub _bridge {
	my $self	= shift;
	return $self->_args->{bridge};
}

sub _names {
	my $self	= shift;
	return $self->{_names};
}

sub _stream {
	my $self	= shift;
	return $self->{_stream};
}






=back

=head1 FUNCTIONS

=over 4

=item C<sgrep { COND } $stream>

=cut

sub sgrep (&$) {
	my $block	= shift;
	my $stream	= shift;
	my $class	= ref($stream);
	
	my $open	= 1;
	my $next;
	
	$next	= sub {
		return undef unless ($open);
		my $data	= $stream->next;
		unless ($data) {
			$open	= 0;
			return undef;
		}
		
		local($_)	= $data;
		my $bool	= $block->( $data );
		if ($bool) {
#			warn "[SGREP] TRUE with: " . $data->as_string;
			if (@_ and $_[0]) {
				$stream->close;
				$open	= 0;
			}
			return $data;
		} else {
#			warn "[SGREP] FALSE with: " . $data->as_string;
			goto &$next;
		}
	};
	
	Carp::confess "not a stream: " . Dumper($stream) unless (blessed($stream));
	my $type	= $stream->type;
	my $names	= [$stream->binding_names];
	my $args	= $stream->_args;
	my $s	= $class->new( $next, $type, $names, %$args );
	return $s;
}

=item C<smap { EXPR } $stream>

=cut

sub smap (&$;$$$) {
	my $block	= shift;
	my $stream	= shift;
	my $type	= shift || $stream->type;
	my $names	= shift || [$stream->binding_names];
	my $args	= shift || $stream->_args;
	my $class	= ref($stream);
	
	my $open	= 1;
	my $next	= sub {
		return undef unless ($open);
		if (@_ and $_[0]) {
			$stream->close;
			$open	= 0;
		}
		my $data	= $stream->next;
		unless ($data) {
			$open	= 0;
			return undef;
		}
		
		local($_)	= $data;
		my ($item)	= $block->( $data );
		return $item;
	};
	
	my $s	= $class->new( $next, $type, $names, %$args );
	return $s;
}

=item C<swatch { EXPR } $stream>

=cut

sub swatch (&$) {
	my $block	= shift;
	my $stream	= shift;
	my $class	= ref($stream);
	
	my $open	= 1;
	my $next	= sub {
		return undef unless ($open);
		if (@_ and $_[0]) {
			$stream->close;
			$open	= 0;
		}
		my $data	= $stream->next;
		unless ($data) {
			$open	= 0;
			return undef;
		}
		
		local($_)	= $data;
		$block->( $data );
		return $data;
	};
	
	my $type	= $stream->type;
	my $names	= [$stream->binding_names];
	my $args	= $stream->_args;
	my $s	= $class->new( $next, $type, $names, %$args );
	return $s;
}

1;

__END__

=back

=head1 DEPENDENCIES

L<JSON|JSON>

L<Scalar::Util|Scalar::Util>


=head1 AUTHOR

Gregory Todd Williams  C<< <greg@evilfunhouse.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Gregory Todd Williams C<< <gwilliams@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


