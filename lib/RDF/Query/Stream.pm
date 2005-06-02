# RDF::Query::Stream
# -------------
# $Revision: 1.3 $
# $Date: 2005/06/02 19:31:22 $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Stream - Stream (iterator) class for query results.

=cut

package RDF::Query::Stream;

use strict;
use warnings;
use Data::Dumper;
use Carp qw(carp);

our ($debug);
BEGIN {
	$debug		= $RDF::Query::debug;
}

sub new {
	my $class		= shift;
	my $stream		= shift || sub { undef };
	my $type		= shift || 'bindings';
	my $names		= shift || [];
	my %args		= @_;
	my $open		= 0;
	my $finished	= 0;
	my $row;
	my $self;
	$self	= bless(sub {
		my $arg	= shift;
		if ($arg) {
			if ($arg =~ /is_(\w+)$/) {
				return ($1 eq $type);
			} elsif ($arg =~ /^_(.*)$/ and exists $args{ $1 }) {
				return $args{ $1 };
			} elsif ($arg eq 'next_result' or $arg eq 'next') {
				$open	= 1;
				$row	= $stream->();
				unless ($row) {
					$finished	= 1;
				}
			} elsif ($arg eq 'current') {
				unless ($open) {
					$self->next_result;
				}
				return $row;
			} elsif ($arg eq 'binding_names') {
				return @{ $names };
			} elsif ($arg eq 'binding_name') {
				my $val	= shift;
				return $names->[ $val ]
			} elsif ($arg eq 'binding_value') {
				unless ($open) {
					$self->next_result;
				}
				my $val	= shift;
				return $row->[ $val ];
			} elsif ($arg eq 'binding_values') {
				unless ($open) {
					$self->next_result;
				}
				return @{ $row };
			} elsif ($arg eq 'bindings_count') {
				if (not $row or not scalar( @{ $row } )) {
					RDF::Query::_debug_closure( $stream );
				}
				
				unless ($open) {
					$self->next_result;
				}
				
				return scalar( @{ $names } )if (scalar(@$names));
				return 0 unless ref($row);
				return scalar( @{ $row } );
			} elsif ($arg eq 'finished' or $arg eq 'end') {
				unless ($open) {
					$self->next_result;
				}
				return $finished;
			}
		} else {
			RDF::Query::_debug_closure( $stream );
			return $stream->();
		}
	}, $class);
	return $self;
}

sub get_boolean {
	my $self	= shift;
	my $data	= $self->();
	return +$data;
}

sub get_all {
	my $self	= shift;
	my @data;
	while (my $data = $self->()) {
		push(@data, $data);
	}
	return @data;
}

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
			$xml	.= "\t\t\t" . format_node_raw($bridge, $value, $name) . "\n";
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

sub graph_as_xml {
	my $self	= shift;
	return $self->_bridge->as_xml( $self );
}

sub format_node_raw ($$) {
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


1;

__END__

=back

=head1 REVISION HISTORY

 $Log: Stream.pm,v $
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
