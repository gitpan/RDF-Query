# RDF::Query::Stream
# -------------
# $Revision: 199 $
# $Date: 2007-04-18 22:45:33 -0400 (Wed, 18 Apr 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Stream - Stream (iterator) class for query results.

=head1 METHODS

=over 4

=cut

package RDF::Query::Stream;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Carp qw(carp);
use Scalar::Util qw(weaken);

our ($debug);
BEGIN {
	$debug		= $RDF::Query::debug;
}

=item C<new ( $closure, $type, $names, %args )>

Returns a new stream (interator) object. C<$closure> must be a CODE
reference that acts as an iterator, returning successive items when
called, and returning undef when the iterator is exhausted.

=cut

sub new {
	my $class		= shift;
	my $stream		= shift || sub { undef };
	my $type		= shift || 'bindings';
	my $names		= shift || [];
#	Carp::cluck(Dumper($names));
	my %args		= @_;
	my $open		= 0;
	my $finished	= 0;
	my $row;
	my $self;
	
	my $selfref;
	$self	= bless(sub {
		my $arg	= shift;
		if ($arg) {
			if ($arg =~ /is_(\w+)$/) {
				return ($1 eq $type);
			} elsif ($arg =~ /^_(.*)$/ and exists $args{ $1 }) {
				return $args{ $1 };
			} elsif ($arg eq 'next_result' or $arg eq 'next') {
				$open	= 1;
				$row	= $selfref->();
				if ($args{named}) {
					if ($args{bridge}->supports('named_graph') and my $bridge = $args{bridge}) {
						$args{context}	= $bridge->get_context( $stream, %args );
					}
				}
				unless (defined $row) {
					$finished	= 1;
				}
			} elsif ($arg eq 'current') {
				unless ($open) {
					$selfref->next_result;
				}
				return $row;
			} elsif ($arg eq 'binding_names') {
				return @{ $names };
			} elsif ($arg eq 'binding_name') {
				my $val	= shift;
				return $names->[ $val ]
			} elsif ($arg eq 'binding_value_by_name') {
				my $name	= shift;
				foreach my $i (0 .. $#{ $names }) {
					if ($names->[$i] eq $name) {
						return $selfref->binding_value( $i );
					}
				}
				warn "No variable named '$name' is present in query results.\n";
			} elsif ($arg eq 'binding_value') {
				unless ($open) {
					$selfref->next_result;
				}
				my $val	= shift;
				return $row->[ $val ];
			} elsif ($arg eq 'binding_values') {
				unless ($open) {
					$selfref->next_result;
				}
				return @{ $row };
			} elsif ($arg eq 'bindings_count') {
				unless ($open) {
					$selfref->next_result;
				}
				
				return scalar( @{ $names } )if (scalar(@$names));
				return 0 unless ref($row);
				return scalar( @{ $row } );
			} elsif ($arg eq 'open') {
				return $open;
			} elsif ($arg eq 'finished' or $arg eq 'end') {
				unless ($open) {
					$selfref->next_result;
				}
				return $finished;
			} elsif ($arg eq 'context') {
				my $bridge	= $args{bridge};
				my $context	= $bridge->get_context( $stream, %args );
				return $context;
			} elsif ($arg eq 'close') {
				$open	= 0;
				undef $stream;
				return undef;
			} elsif ($arg eq 'debug') {
				local($RDF::Query::debug)	= 2;
				RDF::Query::_debug_closure( $stream );
			}
		} else {
			RDF::Query::_debug_closure( $stream );
			my $data	= $stream->();
			return $data;
		}
	}, $class);
	
	$selfref	= $self;
	weaken($selfref);
	return $self;
}

=item C<get_boolean>

Returns the boolean value of the first item in the stream.

=cut

sub get_boolean {
	my $self	= shift;
	my $data	= $self->();
	return +$data;
}

=item C<get_all>

Returns an array containing all the items in the stream.

=cut

sub get_all {
	my $self	= shift;
	my @data;
	while (my $data = $self->()) {
		push(@data, $data);
	}
	return @data;
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

sub AUTOLOAD {
	my $self	= shift;
	my $class	= ref($self) || return undef;
	our $AUTOLOAD;
	return if ($AUTOLOAD =~ /:DESTROY$/);
	my $method		= $AUTOLOAD;
	$method			=~ s/^.*://;
	if (UNIVERSAL::isa( $self, 'CODE' )) {
		return $self->( $method, @_ );
	} else {
		carp "Not a CODE reference";
		return undef;
	}
}

sub DESTROY {
	my $self	= shift;
	$self->close;
}

1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.4  2005/07/27 00:30:29  greg
 - Added binding_value_by_name() method.

 Revision 1.3  2005/06/02 19:31:22  greg
 - Bridge object is now passed to the Stream constructor.
 - bindings_count() now returns the right number even if there is no data.
 - XML Result format now works with RDF::Core models.
 - Added XML Results support for graph queries (DESCRIBE, CONSTRUCT).

 Revision 1.2  2005/06/01 22:34:18  greg
 - Added Boolean XML Results format.

 Revision 1.1  2005/06/01 22:10:46  greg
 - Moved Stream class to lib/RDF/Query/Stream.pm.
 - Fixed tests that broke with previous fix to CONSTRUCT queries.
 - Fixed tests that broke with previous change to ASK query results.


=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
