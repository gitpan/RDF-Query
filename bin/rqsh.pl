#!/usr/bin/perl
use strict;
use warnings;
no warnings 'redefine';
use lib qw(../lib lib);

use Scalar::Util qw(blessed);
use Data::Dumper;
use RDF::Query;
use RDF::Query::Error qw(:try);
use RDF::Query::Util;
use Term::ReadLine;

################################################################################
# Log::Log4perl::init( \q[
# 	log4perl.category.rdf.query.plan				= DEBUG, Screen
# 	log4perl.appender.Screen						= Log::Log4perl::Appender::Screen
# 	log4perl.appender.Screen.stderr					= 0
# 	log4perl.appender.Screen.layout					= Log::Log4perl::Layout::SimpleLayout
# ] );
################################################################################

$|			= 1;
my $model;
if ($ARGV[ $#ARGV ] =~ /.sqlite/) {
	my $file	= pop(@ARGV);
	my $dsn		= "DBI:SQLite:dbname=" . $file;
	my $store	= RDF::Trine::Store::DBI->new($model, $dsn, '', '');
	$model		= RDF::Trine::Model->new( $store );
} else {
	$model	= RDF::Trine::Model->temporary_model;
}
my %args	= &RDF::Query::Util::cli_parse_args();
my $class	= delete $args{ class } || 'RDF::Query';
my $term	= Term::ReadLine->new('rqsh');

while ( defined ($_ = $term->readline('rqsh> ')) ) {
	my $sparql	= $_;
	next unless (length($sparql));
	if ($sparql eq 'debug') {
		my $iter	= $model->get_statements( undef, undef, undef, undef );
		my @rows;
		my @names	= qw[subject predicate object context];
		while (my $row = $iter->next) {
			push(@rows, [map {$row->$_()->as_string} @names]);
		}
		my @rule			= qw(- +);
		my @headers			= (\q"| ");
		push(@headers, map { $_ => \q" | " } @names);
		pop	@headers;
		push @headers => (\q" |");
		my $table = Text::Table->new(@names);
		$table->rule(@rule);
		$table->body_rule(@rule);
		$table->load(@rows);
		print join('',
				$table->rule(@rule),
				$table->title,
				$table->rule(@rule),
				map({ $table->body($_) } 0 .. @rows),
				$table->rule(@rule)
			);
		my $size	= scalar(@rows);
		print "$size statements\n";
	} else {
		my $psparql	= join("\n", $RDF::Query::Util::PREFIXES, $sparql);
		my $query	= $class->new( $psparql, \%args );
		unless ($query) {
			print "Error: " . RDF::Query->error . "\n";
			next;
		}
		$term->addhistory($sparql);
		try {
			my ($plan, $ctx)	= $query->prepare($model);
			my $iter	= $query->execute_plan( $plan, $ctx );
			my $count	= -1;
			if (blessed($iter)) {
				print $iter->as_string( 0, \$count );
			}
			if ($plan->is_update) {
				my $size	= $model->size;
				print "$size statements\n";
			} elsif ($count >= 0) {
				print "$count results\n";
			}
		} catch RDF::Query::Error with {
			my $e	= shift;
			print "Error: $e\n";
		};
	}
}
