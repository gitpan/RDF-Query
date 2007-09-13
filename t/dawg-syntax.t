#!/usr/bin/perl

use strict;
use warnings;

use URI::file;
use RDF::Query;
use Test::More;
use Data::Dumper;
use Scalar::Util qw(blessed);

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
my $model	= new_model( glob( "t/dawg/data-r2/manifest-syntax.ttl" ) );

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
	
	warn "Manifest files: " . Dumper(\@manifests);
	add_to_model( $model, @manifests );
}

my $earl	= init_earl();
my $type	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" );
my $pos		= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest" );
my $neg		= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest" );
my $mfname	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#name" );

{
	print "# Positive Syntax Tests\n";
	my $st		= RDF::Redland::Statement->new( undef, $type, $pos );
	my $stream	= $model->find_statements( $st );
	while($stream and not $stream->end) {
		my $statement	= $stream->current;
		my $test		= $statement->subject;
		my $name		= get_first_literal( $model, $test, $mfname );
		my $ok			= positive_syntax_test( $model, $test );
		ok( $ok, $name );
		if ($ok) {
			earl_pass_test( $earl, $test );
		} else {
			earl_fail_test( $earl, $test );
			warn RDF::Query->error;
		}
	} continue {
		$stream->next;
	}
}

{
	print "# Negative Syntax Tests\n";
	my $st		= RDF::Redland::Statement->new( undef, $type, $neg );
	my $stream	= $model->find_statements( $st );
	while($stream and not $stream->end) {
		my $statement	= $stream->current;
		my $test		= $statement->subject;
		my $name		= get_first_literal( $model, $test, $mfname );
		my $ok			= negative_syntax_test( $model, $test );
		ok( $ok, $name );
		if ($ok) {
			earl_pass_test( $earl, $test );
		} else {
			earl_fail_test( $earl, $test );
		}
	} continue {
		$stream->next;
	}
}

open( my $fh, '>', 'earl-syntax.ttl' );
print {$fh} earl_output( $earl );
close($fh);


################################################################################


sub positive_syntax_test {
	my $model	= shift;
	my $test	= shift;
	my $action	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action" );
	my $file	= get_first_obj( $model, $test, $action );
	my $uri		= URI->new( $file->uri->as_string );
	my $filename	= $uri->file;
	my $sparql	= do { local($/) = undef; open(my $fh, '<', $filename); <$fh> };
	my $query	= eval { RDF::Query->new( $sparql, undef, undef, 'sparql' ) };
	return 0 if ($@);
	return blessed($query) ? 1 : 0;
}

sub negative_syntax_test {
	my $model	= shift;
	my $test	= shift;
	my $action	= RDF::Redland::Node->new_from_uri( "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action" );
	my $file	= get_first_obj( $model, $test, $action );
	my $uri		= URI->new( $file->uri->as_string );
	my $filename	= $uri->file;
	my $sparql	= do { local($/) = undef; open(my $fh, '<', $filename); <$fh> };
	my $query	= eval { RDF::Query->new( $sparql, undef, undef, 'sparql' ) };
	return 1 if ($@);
	return blessed($query) ? 0 : 1;
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
	my $parser		= RDF::Redland::Parser->new("turtle");
	foreach my $uri (@files) {
		my $source_uri	= RDF::Redland::URI->new( "$uri" );
		$parser->parse_into_model($source_uri, $source_uri, $model);
	}
	return 1;
}

sub file_uris {
	my @files	= @_;
	return map { URI::file->new_abs( $_ ) } @files;
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
