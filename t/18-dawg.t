#!/usr/bin/perl

use strict;
use warnings;
use File::Find ();
use Data::Dumper;
use RDF::Query;
use Test::More;
use URI::file;

if ($] < 5.007003) {
	plan skip_all => 'perl >= 5.7.3 required';
	exit;
}

if ($ENV{RDFQUERY_BIGTEST}) {
#	plan qw(no_plan);
} else {
	plan skip_all => 'Developer tests. Set RDFQUERY_BIGTEST to run these tests.';
	exit;
}

eval "use RDF::Query::Model::Redland;";
if ($@) {
	plan skip_all => "Failed to load RDF::Redland";
	exit;
} else {
#	plan 'no_plan';
}

plan qw(no_plan);
	
my @tests	= (
				['t/dawg/data/simple/', 'dawg-data-*.n3', 'data-*%02d.n3', 'dawg-tp-%02d.rq', 'result*%02d.n3', 4],
				['t/dawg/data/Expr1/', 'data-*.ttl', undef, 'expr-%d.rq', 'expr-%d-result.ttl', 3],
				['t/dawg/data/Expr2/', 'data-*.ttl', undef, 'query-bev-%d.rq', 'result-bev-%d.ttl', 6],
				['t/dawg/data/part1/', undef, 'dawg-data-*.n3', 'dawg-query-%03d.rq', 'dawg-result-%03d.n3', 4],
			);


foreach my $test_data (@tests) {
	my ($path, $data, $inc_data, $query, $results, $total)	= @$test_data;
	
	my $model	= new_model( ($data) ? glob( "${path}${data}" ) : () );
	TEST: foreach my $num (1..$total) {
		if ($inc_data) {
			my @files	= glob(sprintf("${path}${inc_data}", $num));
			next unless (@files);
			foreach my $file (@files) {
				next TEST unless (-r $file);
			}
			add_to_model( $model, @files );
		}
		
		my $filename	= sprintf("${path}${query}", $num);
		next unless (-r $filename);
		my $sparql	= do { local($/) = undef; open(my $fh, '<', $filename); <$fh> };
		my $expected	= get_expected_results( (glob(sprintf("${path}${results}", $num)))[0] );
		my $actual		= get_actual_results( $model, $sparql );
		compare_results( $expected, $actual );
	}
	print "\n\n\n";
}

exit;

######################################################################


sub new_model {
	my @files		= @_;
	my $storage		= RDF::Redland::Storage->new("hashes", "test", "new='yes',hash-type='memory'");
	my $model		= RDF::Redland::Model->new($storage, "");
	add_to_model( $model, @files );
	return $model;
}

sub add_to_model {
	my $model	= shift;
	my @files	= @_;
	my $parser		= RDF::Redland::Parser->new("turtle");
	my $base_uri	= RDF::Redland::URI->new( 'http://example.org/base#' );
	foreach my $file (@files) {
		my $uri			= URI::file->new_abs( $file );
		my $source_uri	= RDF::Redland::URI->new( "$uri" );
		$parser->parse_into_model($source_uri, $base_uri, $model);
	}
	return 1;
}

sub get_actual_results {
	my $model	= shift;
	my $sparql	= shift;
	
	my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
	return unless $query;
	
	my $results	= $query->execute( $model );
	my @keys	= $results->binding_names;
	
	my @results;
	while (!$results->finished) {
		my %data;
		my @values		= $results->binding_values;
#		warn "[ " . join(', ', map { (defined $_) ? $_->as_string : 'undef' } @values) . " ]\n";
		foreach my $i (0 .. $#keys) {
			my $value	= node_as_string( $values[ $i ] );
			if (defined $value) {
				$data{ $keys[ $i ] }	= $value;
			}
		}
		push(@results, \%data);
	} continue { $results->next }
	return \@results;
}

sub get_expected_results {
	my $file		= shift;
	my $model		= new_model( $file );
	my $p_type		= RDF::Redland::Node->new_from_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type');
	my $p_rv		= RDF::Redland::Node->new_from_uri('http://www.w3.org/2001/sw/DataAccess/tests/result-set#resultVariable');
	my $p_solution	= RDF::Redland::Node->new_from_uri('http://www.w3.org/2001/sw/DataAccess/tests/result-set#solution');
	my $p_binding	= RDF::Redland::Node->new_from_uri('http://www.w3.org/2001/sw/DataAccess/tests/result-set#binding');
	my $p_value		= RDF::Redland::Node->new_from_uri('http://www.w3.org/2001/sw/DataAccess/tests/result-set#value');
	my $p_variable	= RDF::Redland::Node->new_from_uri('http://www.w3.org/2001/sw/DataAccess/tests/result-set#variable');
	my $t_rs		= RDF::Redland::Node->new_from_uri('http://www.w3.org/2001/sw/DataAccess/tests/result-set#ResultSet');
	my ($rs)		= $model->sources( $p_type, $t_rs );
	my @vnodes		= $model->targets( $rs, $p_rv );
	my @vars		= map { $_->literal_value } @vnodes;
	my @rows		= $model->targets( $rs, $p_solution );
	
	my @results;
	foreach my $row (@rows) {
		my %data;
		my @bindings	= $model->targets( $row, $p_binding );
		foreach my $b (@bindings) {
			my $var		= get_first_as_string( $model, $b, $p_variable );
			my $value	= get_first_as_string( $model, $b, $p_value );
			$data{ $var }	= $value;
		}
		push(@results, \%data);
	}
	return \@results;
}


sub compare_results {
	my $expected	= shift;
	my $actual		= shift;
	
	my %actual_flat;
	foreach my $row (@$actual) {
		my @keys	= sort keys %$row;
		my $key		= join("\xFF", map { $row->{$_} } @keys);
		$actual_flat{ $key }++;
	}
	
	foreach my $row (@$expected) {
		my @keys	= keys %$row;
		my $key		= join("\xFF", map { $row->{$_} } sort @keys);
		if (exists($actual_flat{ $key })) {
			delete $actual_flat{ $key };
			pass( "expected result found: " . join(', ', @{$row}{ @keys }) );
		} else {
			fail( "expected but didn't find: " . join(', ', @{$row}{ @keys }) );
		}
	}
	
	my @remaining	= keys %actual_flat;
	warn Dumper(\@remaining) if (@remaining);
	is( scalar(@remaining), 0, 'no unchecked results' );
}


######################################################################


require Encode;

sub get_first_as_string  {
	my $node	= get_first_obj( @_ );
	return unless $node;
	return node_as_string( $node );
}

sub node_as_string {
	my $node	= shift;
	if ($node) {
		no warnings 'once';
		if ($node->type == $RDF::Redland::Node::Type_Resource) {
			return $node->uri->as_string;
		} elsif ($node->type == $RDF::Redland::Node::Type_Literal) {
			return Encode::decode('utf8', $node->literal_value);
		} else {
			return $node->blank_identifier;
		}
	} else {
		return;
	}
}


sub get_first_literal {
	my $node	= get_first_obj( @_ );
	return $node ? Encode::decode('utf8', $node->literal_value) : undef;
}

sub get_all_literal {
	my @nodes	= get_all_obj( @_ );
	return map { Encode::decode('utf8', $_->literal_value) } grep { $_->can('literal_value') } @nodes;
}

sub get_first_uri {
	my $node	= get_first_obj( @_ );
	return $node ? $node->uri->as_string : undef;
}

sub get_all_uri {
	my @nodes	= get_all_obj( @_ );
	return map { $_->uri->as_string } grep { defined($_) and $_->uri } @nodes;
}

sub get_first_obj {
	my $model	= shift;
	my $node	= shift;
	my $uri		= shift;
	my @uris	= UNIVERSAL::isa($uri, 'ARRAY') ? @{ $uri } : ($uri);
	my @preds	= map { ref($_) ? $_ : RDF::Redland::Node->new_from_uri( $_ ) } @uris;
	foreach my $pred (@preds) {
		my $targets	= $model->targets_iterator( $node, $pred );
		while ($targets and !$targets->end) {
			my $node	= $targets->current;
			return $node if ($node);
		} continue { $targets->next }
	}
}

sub get_all_obj {
	my $model	= shift;
	my $node	= shift;
	my $uri		= shift;
	my @uris	= UNIVERSAL::isa($uri, 'ARRAY') ? @{ $uri } : ($uri);
	my @preds	= map { ref($_) ? $_ : RDF::Redland::Node->new_from_uri( $_ ) } @uris;
	my @objs;
	return map { $model->targets( $node, $_ ) } @preds;
}

__END__
