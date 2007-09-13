#!/usr/bin/perl

use strict;
use warnings;

use URI::file;
use RDF::Query;
use Test::More;
use Data::Dumper;
use Storable qw(dclone);
use Scalar::Util qw(blessed reftype);

our $debug	= 0;
if ($] < 5.007003) {
	plan skip_all => 'perl >= 5.7.3 required';
	exit;
}

if ($ENV{RDFQUERY_DAWGTEST}) {
#	plan qw(no_plan);
} else {
	plan skip_all => 'Developer tests. Set RDFQUERY_DAWGTEST to run these tests.';
	exit;
}

require XML::Simple;
eval "use RDF::Query::Model::Redland;";
if ($@) {
	plan skip_all => "Failed to load RDF::Redland";
	exit;
} else {
#	plan 'no_plan';
}

plan qw(no_plan);
require "t/dawg/earl.pl";
	



my @manifests;
my $model	= new_model( glob( "t/dawg/data-r2/manifest-evaluation.ttl" ) );

{
	my $ns		= 'http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#';
	my $inc		= RDF::Redland::URI->new( "${ns}include" );
	my $st		= RDF::Redland::Statement->new( undef, $inc, undef );
	my ($statement)	= $model->find_statements( $st );
	if ($statement) {
		my $list		= $statement->object;
		my $first	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/1999/02/22-rdf-syntax-ns#first" );
		my $rest	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest" );
		while ($list and $list->as_string ne '[http://www.w3.org/1999/02/22-rdf-syntax-ns#nil]') {
			my $value			= get_first_obj( $model, $list, $first );
			$list				= get_first_obj( $model, $list, $rest );
			my $manifest		= $value->uri->as_string;
			push(@manifests, $manifest);
		}
	}
	
	add_to_model( $model, @manifests );
}

my $earl	= init_earl();
my $type	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" );
my $evalt	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest" );
my $mfname	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#name" );

{
	print "# Evaluation Tests\n";
	my $st		= RDF::Redland::Statement->new( undef, $type, $evalt );
	my $stream	= $model->find_statements( $st );
	while($stream and not $stream->end) {
		my $statement	= $stream->current;
		my $test		= $statement->subject;
		my $name		= get_first_literal( $model, $test, $mfname );
		warn "### eval test: " . $name . "\n";
		eval_test( $model, $test, $earl );
	} continue {
		$stream->next;
	}
}

open( my $fh, '>', 'earl-eval.ttl' ) or die $!;
print {$fh} earl_output( $earl );
close($fh);


################################################################################


sub eval_test {
	my $model	= shift;
	my $test	= shift;
	my $earl	= shift;
	my $mfact	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action" );
	my $mfres	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#result" );
	my $qtquery	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-query#query" );
	my $qtdata	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-query#data" );
	
	my $action	= get_first_obj( $model, $test, $mfact );
	my $result	= get_first_obj( $model, $test, $mfres );
	my $queryd	= get_first_obj( $model, $action, $qtquery );
	my $data	= get_first_obj( $model, $action, $qtdata );
		
	my $uri			= URI->new( $queryd->uri->as_string );
	my $filename	= $uri->file;
	my $sparql		= do { local($/) = undef; open(my $fh, '<', $filename); <$fh> };
	
	my $q			= $sparql;
	$q				=~ s/\s+/ /g;
	warn "### test  : " . $test->as_string . "\n";
	warn "# sparql  : $q\n";
	warn "# data    : " . $data->as_string if (blessed($data));
	warn "# result  : " . $result->as_string;
	
	print STDERR "constructing model... " if ($debug);
	my $test_model	= new_model();
	if (blessed($data)) {
		add_to_model( $test_model, $data->uri->as_string );
	}
	print STDERR "ok\n" if ($debug);
	
	my $resuri		= URI->new( $result->uri->as_string );
	my $resfilename	= $resuri->file;
	
	my $ok	= eval {
		print STDERR "getting actual results... " if ($debug);
		my $actual		= get_actual_results( $test_model, $sparql );
		print STDERR "ok\n" if ($debug);
		
		print STDERR "getting expected results... " if ($debug);
		my $type		= (blessed($actual) and $actual->isa('RDF::Redland::Model')) ? 'graph' : '';
		my $expected	= get_expected_results( $resfilename, $type );
		print STDERR "ok\n" if ($debug);
		
	#	warn "comparing results...";
		my $ok			= compare_results( $expected, $actual, $earl );
	};
	if ($ok) {
		earl_pass_test( $earl, $test );
	} else {
		earl_fail_test( $earl, $test );
	}
}


exit;

######################################################################


sub new_model {
	my @files		= @_;
	my $storage		= RDF::Redland::Storage->new("hashes", "test", "new='yes',hash-type='memory'");
	my $model		= RDF::Redland::Model->new($storage, "");
	add_to_model( $model, file_uris( @files ) );
	return $model;
}

sub add_to_model {
	my $model	= shift;
	my @files	= @_;
	foreach my $uri (@files) {
		my $format		= ($uri =~ /[.]rdf$/) ? 'rdfxml'
						: ($uri =~ /[.]ttl$/) ? 'turtle'
						: 'guess';
		my $parser		= RDF::Redland::Parser->new($format);
		my $source_uri	= RDF::Redland::URI->new( "$uri" );
		$parser->parse_into_model($source_uri, $source_uri, $model);
	}
	return 1;
}

sub add_source_to_model {
	my $model	= shift;
	my @sources	= @_;
	foreach my $source (@sources) {
		my $format		= 'guess';
		my $parser		= RDF::Redland::Parser->new($format);
		my $source_uri	= RDF::Redland::URI->new( "http://kasei.us/e/base#" );
		$parser->parse_string_into_model($source, $source_uri, $model);
	}
	return 1;
}

sub file_uris {
	my @files	= @_;
	return map { URI::file->new_abs( $_ ) } @files;
}

######################################################################

sub get_actual_results {
	my $model	= shift;
	my $sparql	= shift;
	
	my $query	= RDF::Query->new( $sparql, undef, undef, 'sparql' );
	return unless $query;
	
	my $results	= $query->execute( $model );
	my @keys	= $results->binding_names;
	
	if ($results->is_bindings) {
		my @results;
		while (!$results->finished) {
			my %data;
			my @values		= $results->binding_values;
	#		warn "[ " . join(', ', map { (defined $_) ? $_->as_string : 'undef' } @values) . " ]\n";
			foreach my $i (0 .. $#keys) {
				my $value	= node_as_string( $values[ $i ] );
				if (defined $value) {
					my $string	= $values[$i]->as_string;
					$data{ $keys[ $i ] }	= $value;
				}
			}
			push(@results, \%data);
		} continue { $results->next }
		return \@results;
	} elsif ($results->is_boolean) {
		return ($results->get_boolean) ? 'true' : 'false';
	} elsif ($results->is_graph) {
		my $xml		= $results->graph_as_xml;
		my $model	= new_model();
		add_source_to_model( $model, $xml );
		return $model;
	}
}

sub get_expected_results {
	my $file		= shift;
	my $type		= shift;
	
	if ($type eq 'graph') {
		my $model	= new_model( $file );
		return $model;
	} elsif ($file =~ /[.]srx/) {
		my $data		= do { local($/) = undef; open(my $fh, '<', $file); <$fh> };
		my $xml			= XMLin( $file );
		
		
		if (exists $xml->{results}) {
			my $results	= $xml->{results}{result};
#			die Dumper($results) unless (reftype($results) eq 'ARRAY');
			my @xml_results	= (reftype($results) eq 'ARRAY')
							? @{ $results }
							: (defined($results))
								? ($results)
								: ();
			
			my @results;
			my %bnode_map;
			my $bnode_next	= 0;
			foreach my $r (@xml_results) {
				my $binding	= $r->{binding};
				my @bindings;
				if (exists $binding->{name}) {
					my $name	= $binding->{name};
					push(@bindings, [$name, $binding]);
				} else {
					foreach my $key (keys %$binding) {
						push(@bindings, [$key, $binding->{$key}]);
					}
				}
				
				my $result	= {};
				foreach my $data (@bindings) {
					my $name	= $data->[0];
					my $binding	= $data->[1];
					
					my $type	= reftype($binding);
					if ($type eq 'HASH') {
						if (exists($binding->{literal})) {
							if (ref($binding->{literal})) {
								my $value	= $binding->{literal}{content} || '';
								my $lang	= $binding->{literal}{'xml:lang'};
								my $dt		= $binding->{literal}{'datatype'};
								my $string	= literal_as_string( $value, $lang, $dt );
	#							push(@results, { $name => $string });
								$result->{ $name }	= $string;
							} else {
								my $string	= literal_as_string( $binding->{literal}, undef, undef );
	#							push(@results, { $name => $string });
								$result->{ $name }	= $string;
							}
						} elsif (exists($binding->{bnode})) {
							my $bnode	= $binding->{bnode};
							my $id;
							if (exists $bnode_map{ $bnode }) {
								$id	= $bnode_map{ $bnode };
							} else {
								$id	= join('', 'r', $bnode_next++);
								$bnode_map{ $bnode }	= $id;
							}
	#						push(@results, { $name => $id });
							$result->{ $name }	= $id;
						} elsif (exists($binding->{uri})) {
							$result->{ $name }	= $binding->{uri};
	#						push(@results, { $name => $binding->{uri} });
						} else {
	#						push(@results, {});
	#						die "Uh oh. Unrecognized binding node type: " . Dumper($binding);
						}
					} elsif ($type eq 'ARRAY') {
						die "Uh oh. ARRAY binding type: " . Dumper($binding);
					} else {
						die "Uh oh. Unknown result reftype: " . Dumper($r);
					}
				}
				push(@results, $result);
			}
			return \@results;
		} elsif (exists $xml->{boolean}) {
			return $xml->{boolean};
		}
	} else {
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
}

sub model_to_arrayref {
	my $model	= shift;
	my @data;
	my $stream	= $model->as_stream;
	{
		my %bnode_map;
		while($stream && !$stream->end) {
			my $statement	= $stream->current;
			my $s			= $statement->subject;
			my $p			= $statement->predicate;
			my $o			= $statement->object;
			my @triple;
			foreach my $node ($s, $p, $o) {
				if ($node->is_blank) {
					my $id		= $node->blank_identifier;
					unless (exists( $bnode_map{ $id } )) {
						my $blank			= [];
						$bnode_map{ $id }	= $blank;
					}
					push( @triple, $bnode_map{ $id } );
				} elsif ($node->is_resource) {
					push( @triple, $node->uri->as_string );
				} else {
					push( @triple, node_as_string( $node ) );
				}
			}
			push(@data, \@triple);
		} continue {
			$stream->next;
		}
	}
	return \@data;
}

sub compare_results {
	my $expected	= shift;
	my $actual		= shift;
	my $earl		= shift;
	warn 'compare_results: ' . Data::Dumper->Dump([$expected, $actual], [qw(expected actual)]);# if ($debug);
	
	if (not(ref($actual))) {
		my $ok	= is( $actual, $expected );
		die unless ($ok);	# XXX
	} elsif (blessed($actual) and $actual->isa('RDF::Redland::Model')) {
		die unless (blessed($expected) and $expected->isa('RDF::Redland::Model'));
		
		my $act_array	= model_to_arrayref( $actual );
		my $exp_array	= model_to_arrayref( $expected );
		return is_deeply( $act_array, $exp_array );
	} else {
		my %actual_flat;
		foreach my $i (0 .. $#{ $actual }) {
			my $row	= $actual->[ $i ];
			my @keys	= sort keys %$row;
			my $key		= join("\xFF", map { $row->{$_} } @keys);
			push( @{ $actual_flat{ $key } }, [ $i, $row ] );;
		}
		
		my %bnode_map;
		my $bnode	= 1;
	#	local($debug)	= 1;
		EXPECTED: foreach my $row (@$expected) {
			my @keys	= keys %$row;
			my @skeys	= sort @keys;
			my @values	= map { $row->{$_} } @skeys;
			my $key		= join("\xFF", @values);
			if (exists($actual_flat{ $key })) {
				my $i	= $actual_flat{ $key }[0][0];
				shift(@{ $actual_flat{ $key } });
				unless (scalar(@{ $actual_flat{ $key } })) {
					$actual->[ $i ]	= undef;
					delete $actual_flat{ $key };
				}
				pass( "expected result found: " . join(', ', @{$row}{ @keys }) );
				return 1;
			} else {
				warn "looking for an actual result matching the expected: " . Dumper($row) if ($debug);
				warn "remaining actual results: " . Dumper($actual) if ($debug);
				my $passed	= 0;
				my $skipped	= 0;
				my %seen;
	#			ACTUAL: while (keys %actual_flat) {
				ACTUAL: foreach my $actual_key (keys %actual_flat) {
					# while there are remaining actual results,
					# keep trying to match them with expected results
					
					if ($seen{ $actual_key }++) {
						$skipped++;
						next ACTUAL;
					}
					
					my $actual_row		= $actual_flat{ $actual_key }[0][ 1 ];
					warn "\t actual result: " . Dumper($actual_row) if ($debug);
					my @actual_keys		= keys %{ $actual_row };
					my @actual_values	= map { $actual_row->{$_} } sort @actual_keys;
					
					my $ok	= 1;
					PROP: foreach my $i (0 .. $#values) {
						# try to match each property of this actual result
						# with the values from the expected result.
						
						my $actualv		= $actual_values[ $i ];
						my $expectedv	= $values[ $i ];
						if ($expectedv eq $actualv) {
							warn "\tvalues of $skeys[$i] match. going to next property\n" if ($debug);
							next PROP;
						}
						if ($values[ $i ] =~ /^(r\d+[r0-9]*)$/ and $actual_values[ $i ] =~ /^(r\d+[r0-9]*)$/) {
							my $id;
							if (exists $bnode_map{ actual }{ $actual_values[ $i ] }) {
								my $id	= $bnode_map{ actual }{ $actual_values[ $i ] };
								if ($id == $bnode_map{ expected }{ $values[ $i ] }) {
									warn "\tvalues of $skeys[$i] are merged bnodes. going to next property\n" if ($debug);
									next PROP;
								} else {
									warn Dumper(\%bnode_map);
								}
							} elsif (exists $bnode_map{ expected }{ $values[ $i ] }) {
								my $id	= $bnode_map{ expected }{ $values[ $i ] };
								if ($id == $bnode_map{ actual }{ $actual_values[ $i ] }) {
									warn "\tvalues of $skeys[$i] are merged bnodes. going to next property\n" if ($debug);
									next PROP;
								}
							} else {
								my $id	= $bnode++;
								warn "\tvalues of $skeys[$i] are both bnodes ($actual_values[ $i ] and $values[ $i ]). merging them and going to next property\n" if ($debug);
								$bnode_map{ actual }{ $actual_values[ $i ] }	= $id;
								$bnode_map{ expected }{ $values[ $i ] }			= $id;
								next PROP;
							}
						}
						
						# we didn't match this property, so this actual result doesn't
						# match the expected result. break out and try another actual result.
						$ok	= 0;
						warn "did not match: $actualv <=> $expectedv\n" if ($debug);
						next ACTUAL;
					}
					if ($ok) {
						$passed	= 1;
#						pass( "expected result found: " . join(', ', @{$row}{ @keys }) );
						my $i	= $actual_flat{ $actual_key }[0][0];
						shift(@{ $actual_flat{ $actual_key } });
						unless (scalar(@{ $actual_flat{ $actual_key } })) {
							$actual->[ $i ]	= undef;
							delete $actual_flat{ $actual_key };
						}
					}
				}
				
				unless ($passed) {
	#				warn 'did not pass test. actual data: ' . Dumper($actual);
					fail( "expected but didn't find: " . join(', ', @{$row}{ @keys }) );
					return 0;
				}
			}
		}
		
		my @remaining	= keys %actual_flat;
		warn "remaining: " . Dumper(\@remaining) if (@remaining);
		return is( scalar(@remaining), 0, 'no unchecked results' );
	}
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
			my $value	= Encode::decode('utf8', $node->literal_value) || '';
			my $lang	= $node->literal_value_language;
			my $dt		= ($node->literal_datatype) ? $node->literal_datatype->as_string : '';
			return literal_as_string( $value, $lang, $dt );
		} else {
			return $node->blank_identifier;
		}
	} else {
		return;
	}
}

sub literal_as_string {
	my $value	= shift;
	my $lang	= shift;
	my $dt		= shift;
	if (defined $value) {
		my $string	= qq["$value"];
		if ($lang) {
			$string	.= '@' . $lang;
		} elsif ($dt) {
			$string	.= '^^<' . $dt . '>';
		}
		return $string;
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
