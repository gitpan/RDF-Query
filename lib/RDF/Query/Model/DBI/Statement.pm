#!/usr/bin/perl

package RDF::Query::Model::DBI::Statement;

use strict;
use warnings;
use Carp qw(carp croak confess);

use File::Spec;
use Data::Dumper;
use Encode;
use DBI;
use URI;

use RDF::Query::Stream;

######################################################################

our ($VERSION, $debug);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.1 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
}

######################################################################

sub new {
	my $class	= shift;
	return bless([@_], $class);
}

sub subject {
	my $self	= shift;
	return $self->[0];
}

sub predicate {
	my $self	= shift;
	return $self->[1];
}

sub object {
	my $self	= shift;
	return $self->[2];
}



1;

__END__
