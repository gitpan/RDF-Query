# RDF::Query::Compiler::SQL
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Compiler::SQL - Compile a SPARQL query directly to SQL.

=cut

package RDF::Query::Compiler::SQL;

use strict;
use warnings;

use RDF::Query::Error qw(:try);

use Data::Dumper;
use Math::BigInt;
use LWP::Simple ();
use Digest::MD5 ('md5');
use Carp qw(carp croak confess);
use Scalar::Util qw(blessed reftype);

use RDF::Query::Error qw(:try);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 1;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<< new ( $parse_tree ) >>

Returns a new compiler object.

=cut

sub new {
	my $class	= shift;
	my $parsed	= shift;
	my $model	= shift;
	my $stable;
	if ($model) {
		my $mhash	= _mysql_hash( $model );
		$stable		= "Statements${mhash}";
	} else {
		$stable		= 'Statements';
	}
	
	my $self	= bless( {
					parsed	=> $parsed,
					stable	=> $stable,
					vars	=> {},
					from	=> [],
					where	=> [],
				}, $class );
				
	return $self;
}




=item C<< compile () >>

Returns a SQL query string for the specified parse tree.

=cut

sub compile {
	my $self	= shift;
	my $parsed	= $self->{parsed};
	
	my $sql;
	try {
		my $method	= uc $parsed->{'method'};
		if ($method eq 'SELECT') {
			$sql	= $self->emit_select();
		} else {
			throw RDF::Query::Error::CompilationError( -text => "SQL compilation of $method queries not yet implemented." );
		}
	} catch RDF::Query::Error::CompilationError with {
		my $err	= shift;
		throw $err;
	};
	
	return $sql;
}


sub emit_select {
	my $self	= shift;
	my $parsed	= $self->{parsed};
	
	my $level		= \do { my $a = 0 };
	my @vars		= map { $_->[1] } @{ $parsed->{variables} };
	my %select_vars	= map { $_ => 1 } @vars;
	
	$self->patterns2sql( $parsed->{'triples'}, $level );
	
	my $vars	= $self->{vars};
	my $from	= $self->{from};
	my $where	= $self->{where};
	
	my ($varcols, @cols)	= $self->add_variable_values_joins;
	my $options				= $parsed->{options} || {};
	my $unique				= $options->{'distinct'};
	
	my $sql	= "SELECT "
			. ($unique ? 'DISTINCT ' : '')
			. join(', ', @cols)
			. " FROM " . join(', ', @$from)
			. " WHERE " . join(' AND ', @$where)
			. $self->order_by_clause( $varcols, $level )
			. $self->limit_clause( $options )
			;
	return $sql;
}

sub limit_clause {
	my $self	= shift;
	my $options	= shift;
	if (my $limit = $options->{limit}) {
		return " LIMIT ${limit}";
	} else {
		return "";
	}
}

sub order_by_clause {
	my $self	= shift;
	my $varcols	= shift;
	my $level	= shift || \do{ my $a = 0 };
	
	my $vars	= $self->{vars};
	
	my $parsed				= $self->{parsed};
	my $options				= $parsed->{options} || {};
	my %variable_value_cols	= %$varcols;
	
	my $sql		= '';
	if ($options->{orderby}) {
		my $data	= $options->{orderby}[0];
		my $dir		= $data->[0];
		if ($data->[1][0] eq 'VAR') {
			my $var		= $data->[1][1];
			$sql	.= " ORDER BY ${var}_Value $dir, ${var}_URI $dir, ${var}_Name $dir";
		} elsif ($data->[1][0] eq 'FUNCTION') {
			my $uri		= $self->qualify_uri( $data->[1][1] );
			my $col	= $self->expr2sql( $data->[1], $level );
			foreach my $var (keys %$vars) {
				my ($l_sort_col, $r_sort_col, $b_sort_col)	= @{ $variable_value_cols{ $var } };
				my $varcol	= $vars->{ $var };
				if ($col =~ /${varcol}/) {
					my ($l, $r, $b)	= ($col) x 3;
					$l		=~ s/$varcol/${l_sort_col}/;
					$r		=~ s/$varcol/${r_sort_col}/;
					$b		=~ s/$varcol/${b_sort_col}/;
					$sql	.= " ORDER BY $l $dir, $r $dir, $b $dir";
					last;
				}
			}
		} else {
			throw RDF::Query::Error::CompilationError( -text => "Can't sort by $$data[1][0] yet." );
		}
	}
	
	return $sql;
}


sub add_variable_values_joins {
	my $self	= shift;
	my $parsed	= $self->{parsed};
	my @vars	= map { $_->[1] } @{ $parsed->{variables} };
	my %select_vars	= map { $_ => 1 } @vars;
	my %variable_value_cols;
	
	my $vars	= $self->{vars};
	my $from	= $self->{from};
	my $where	= $self->{where};
	
	my @cols;
	my $count	= 0;
	my %seen;
	foreach my $var (grep { not $seen{ $_ }++ } (@vars, keys %$vars)) {
		my $col	= $vars->{ $var };
		push(@cols, "${col} AS ${var}") if ($select_vars{ $var });
		my @value_table_data	= (['Resources', 'ljr', 'URI'], ['Literals', 'ljl', qw(Value Language Datatype)], ['Bnodes', 'ljb', qw(Name)]);
		foreach (@value_table_data) {
			my ($table, $alias, @join_cols)	= @$_;
			foreach my $jc (@join_cols) {
				my $column_real_name	= "${alias}${count}.${jc}";
				my $column_alias_name	= "${var}_${jc}";
				push(@cols, "${column_real_name} AS ${column_alias_name}");
				push( @{ $variable_value_cols{ $var } }, "${alias}${count}.${jc}");
				
				foreach my $i (0 .. $#{ $where }) {
					if ($where->[$i] =~ /\b$column_alias_name\b/) {
						$where->[$i]	=~ s/\b${column_alias_name}\b/${column_real_name}/g;
					}
				}
				
			}
		}
		
		my $col_table	= (split(/[.]/, $col))[0];
		foreach my $i (0 .. $#{ $from }) {
			my $f		= $from->[ $i ];
			my $alias	= (split(/ /, $f))[1];
			if ($alias eq $col_table) {
				foreach (@value_table_data) {
					my ($vtable, $vname)	= @$_;
					my $valias	= join('', $vname, $count);
					$f	.= " LEFT JOIN ${vtable} ${valias} ON ${col} = ${valias}.ID";
				}
				$from->[ $i ]	= $f;
				next;
			}
		}
		
		$count++;
	}
	
	return (\%variable_value_cols, @cols);
}

sub patterns2sql {
	my $self	= shift;
	my $triples	= shift;
	my $level	= shift || \do{ my $a = 0 };
	my %args	= @_;
	
#	my %vars	= scalar(@_) ? %{ $_[0] } : ();
	
	my $parsed		= $self->{parsed};
	my $parsed_vars	= $parsed->{variables};
	my %queryvars	= map { $_->[1] => 1 } @$parsed_vars;
	
#	my (@from, @where);
	
	my $from	= $self->{from};
	my $where	= $self->{where};
	my $vars	= $self->{vars};

	my $add_where	= sub {
		my $w	= shift;
		if (my $hook = $args{ where_hook }) {
			push(@$where, $hook->( $w ));
		} else {
			push(@$where, $w);
		}
		return $w;
	};
	
	my $add_from	= sub {
		my $f	= shift;
		if (my $hook = $args{ from_hook }) {
			push(@$from, $hook->( $f ));
		} else {
			push(@$from, $f);
		}
		return $f;
	};
	
	
	







	
# 	[
# 		[['VAR','person'],['URI',['foaf','name']],['VAR','name']],
# 		['OPTIONAL', [
# 			[['VAR','person'],['URI',['foaf','mbox']],['VAR','mbox']],
# 			[['VAR','person'],['URI',['foaf','nick']],['VAR','nick']]
# 		]]
# 	]	
	
	my $triple	= shift(@$triples);
	
	my @posmap	= qw(subject predicate object);
	if (ref($triple->[0])) {
		my ($s,$p,$o)	= @$triple;
		my $table	= "s${$level}";
		my $stable	= $self->{stable};
		$add_from->( "${stable} ${table}" );
		for my $idx (0 .. 2) {
			my $node	= $triple->[ $idx ];
			my $type	= $node->[0];
			my $pos		= $posmap[ $idx ];
			my $col		= "${table}.${pos}";
			if ($type eq 'VAR') {
				my $name	= $node->[1];
				if (exists $vars->{ $name }) {
					my $existing_col	= $vars->{ $name };
					$add_where->( "$col = ${existing_col}" );
				} else {
					$vars->{ $name }	= $col;
				}
			} elsif ($type eq 'URI') {
				my $uri	= $node->[1];
				my $id	= $self->_mysql_node_hash( $node );
				$add_where->( "${col} = $id" );
			} elsif ($type eq 'BLANK') {
				my $id	= $node->[1];
				my $b	= "b${$level}";
				$add_from->( "Bnodes $b" );
				
				$add_where->( "${col} = ${b}.ID" );
				$add_where->( "${b}.Name = '$id'" );
			} elsif ($type eq 'LITERAL') {
				my $literal	= $node->[1];
				my $id	= $self->_mysql_node_hash( $node );
				$add_where->( "${col} = $id" );
			} else {
				throw RDF::Query::Error::CompilationError( -text => "Unknown node type: $type" );
			}
		}
	} else {
		my $op	= $triple->[0];
		if ($op eq 'OPTIONAL') {
			my $pattern	= $triple->[1];
			throw RDF::Query::Error::CompilationError( -text => "SQL compilation of OPTIONAL queries not yet implemented." );
			++$$level;
			my @w;
			my $hook	= sub {
							my $w	= shift;
							push(@w, $w);
							return;
						};
			$self->patterns2sql( $pattern, $level, where_hook => $hook );
			
			$add_where->( 'OPTIONAL(' . join(' AND ', @w) . ')' );
		} elsif ($op eq 'GRAPH') {
			my $graph	= $triple->[1];
			my $pattern	= $triple->[2];
			
			if ($graph->[0] eq 'VAR') {
				my $name	= $graph->[1];
				my $context;
				my $hook	= sub {
								my $f	= shift;
								if ($f =~ /^Statements/i) {
									my $alias	= (split(/ /, $f))[1];
									if (defined($context)) {
										$add_where->( "${alias}.Context = ${context}" );
									} else {
										$context	= "${alias}.Context";
										$vars->{ $name }	= $context;
									}
								}
								return $f;
							};
				$self->patterns2sql( $pattern, $level, from_hook => $hook );
			} else {
				my $hash	= $self->_mysql_node_hash( $graph );
				my $hook	= sub {
								my $f	= shift;
								if ($f =~ /^Statements/i) {
									my $alias	= (split(/ /, $f))[1];
									$add_where->( "${alias}.Context = ${hash}" );
								}
								return $f;
							};
				$self->patterns2sql( $pattern, $level, from_hook => $hook );
			}
		} elsif ($op eq 'FILTER') {
			++$$level;
			my $expr		= $triple->[1];
			$self->expr2sql( $expr, $level, from_hook => $add_from, where_hook => $add_where );
		} else {
			throw RDF::Query::Error::CompilationError( -text => "Unknown op '$op' in SQL compilation." );
		}
	}
	
	
	if (scalar(@$triples)) {
		++$$level;
		$self->patterns2sql( $triples, $level );
	}
	return;
#	return (\%vars, \@from, \@where);
}

sub expr2sql {
	my $self	= shift;
	my $expr	= shift;
	my $level	= shift || \do{ my $a = 0 };
	my %args	= @_;
	
	my $from	= $self->{from};
	my $where	= $self->{where};
	my $vars	= $self->{vars};
	
	my $sql;
	my $add_where	= sub {
		my $w	= shift;
		$sql	||= $w;
		if (my $hook = $args{ where_hook }) {
			$hook->( $w );
		}
	};
	
	my $add_from	= sub {
		my $f	= shift;
		if (my $hook = $args{ from_hook }) {
			$hook->( $f );
		}
	};
	
	my $parsed		= $self->{parsed};
	my $parsed_vars	= $parsed->{variables};
	my %queryvars	= map { $_->[1] => 1 } @$parsed_vars;
	
	Carp::confess unless ref($expr);
	my ($op, @args)	= @{ $expr };
	
	if ($op eq '~~') {
		$op	= 'FUNCTION';
		unshift(@args, '~~');
	}
	
	if ($op eq 'LITERAL') {
		my $literal	= $args[0];
		my $dt		= $args[2];
		
		if (defined($dt)) {
			my $uri		= $dt;
			my $func	= $self->get_function( $self->qualify_uri( $uri ) );
			if ($func) {
				my ($v, $f, $w)	= $func->( $self, $parsed_vars, $level, [ 'LITERAL', $literal ] );
				$literal	= $w->[0];
			} else {
				$literal	= qq("${literal}");
			}
		} else {
			$literal	= qq("${literal}");
		}
		
		$add_where->( $literal );
	} elsif ($op eq 'VAR') {
		my $name	= $args[0];
		my $col		= $vars->{ $name };
		$add_where->( qq(${col}) );
	} elsif ($op =~ m#^[<>]=?$#) {
		++$$level; my $sql_a	= $self->expr2sql( $args[0], $level );
		++$$level; my $sql_b	= $self->expr2sql( $args[1], $level );
		$add_where->( "${sql_a} ${op} ${sql_b}" );
	} elsif ($op eq 'FUNCTION') {
		my $uri	= $self->qualify_uri( shift(@args) );
		my $func	= $self->get_function( $uri );
		if ($func) {
			my ($v, $f, $w)	= $func->( $self, $parsed_vars, $level, @args );
			foreach my $key (keys %$v) {
				my $val	= $v->{ $key };
				$vars->{ $key }	= $val unless (exists($vars->{ $key }));
			}
			
			foreach my $f (@$f) {
				$add_from->( @$f );
			}
			
			foreach my $w (@$w) {
				$add_where->( $w );
			}
		} else {
			throw RDF::Query::Error::CompilationError( -text => "Unknown custom function $uri in FILTER." );
		}
	} else {
		throw RDF::Query::Error::CompilationError( -text => "SQL compilation of FILTER($op) queries not yet implemented." );
	}
	
	return $sql;
	
	
	if (0) {
		my $data	= $expr->[1];
		my ($func, @args)	= @$data;
		if ($func eq '~~') {
			my ($var, $pattern)	= @args;
		} else {
			warn "unknown filter function: $func";
		}
	}
}

sub _mysql_hash {
	my $data	= shift;
	my @data	= unpack('C*', md5( $data ));
	my $sum		= Math::BigInt->new('0');
#	my $count	= 0;
	foreach my $count (0 .. 7) {
#	while (@data) {
		my $data	= Math::BigInt->new( $data[ $count ] ); #shift(@data);
		my $part	= $data << (8 * $count);
#		warn "+ $part\n";
		$sum		+= $part;
	} # continue { last if ++$count == 8 }	# limit to 64 bits
#	warn "= $sum\n";
	return $sum;
}

sub _mysql_node_hash {
	my $self	= shift;
	my $node	= shift;
	
	my @node	= @$node;
	my ($type, $value)	= splice(@node, 0, 2, ());
	
	my $data;
	if ($type eq 'URI') {
		if (ref($value)) {
			$value	= $self->qualify_uri( $value );
		}
		$data	= 'R' . $value;
	} elsif ($type eq 'B') {
		$data	= 'BLANK' . $value;
	} elsif ($type eq 'LITERAL') {
		my ($lang, $dt)	= splice(@node, 0, 2, ());
		no warnings 'uninitialized';
		$data	= sprintf("L%s<%s>%s", $value, $lang, $dt);
#		warn "($data)";
	} else {
		return undef;
	}
	
	my $hash	= _mysql_hash( $data );
	return $hash;
}

sub qualify_uri {
	my $self	= shift;
	my $uri		= shift;
	my $parsed	= $self->{parsed};
	if (ref($uri) and $uri->[0] eq 'URI') {
		$uri	= $uri->[1];
	}
	
	if (ref($uri)) {
		my ($abbr, $local)	= @$uri;
		if (exists $parsed->{namespaces}{$abbr}) {
			my $ns		= $parsed->{namespaces}{$abbr};
			$uri		= join('', $ns, $local);
		} else {
			throw RDF::Query::Error::ParseError ( -text => "Unknown namespace prefix: $abbr" );
		}
	}
	return $uri;
}

=item C<add_function ( $uri, $function )>

Associates the custom function C<$function> (a CODE reference) with the
specified URI, allowing the function to be called by query FILTERs.

=cut

sub add_function {
	my $self	= shift;
	my $uri		= shift;
	my $code	= shift;
	if (ref($self)) {
		$self->{'functions'}{$uri}	= $code;
	} else {
		our %functions;
		$functions{ $uri }	= $code;
	}
}

sub get_function {
	my $self	= shift;
	my $uri		= shift;
	
	our %functions;
	my $func	= $self->{'functions'}{$uri} || $functions{ $uri };
	return $func;
}




our %functions;

$functions{ '~~' }	= sub {
	my $self	= shift;
	my $parsed_vars	= shift;
	my $level	= shift || \do{ my $a = 0 };
	my @args	= @_;
	my (@from, @where);
	
	my (@regex, @literal, @pattern);
	if ($args[0][0] eq 'VAR') {
		my $name	= $args[0][1];
		push(@literal, "${name}_Value");
		push(@literal, "${name}_URI");
		push(@literal, "${name}_Name");
	} else {
		push(@literal, $self->expr2sql( $args[0], $level ));
	}
	
	if ($args[1][0] eq 'VAR') {
		my $name	= $args[0][1];
		push(@pattern, "${name}_Value");
		push(@pattern, "${name}_URI");
		push(@pattern, "${name}_Name");
	} else {
		push(@pattern, $self->expr2sql( $args[1], $level ));
	}
	
	foreach my $literal (@literal) {
		foreach my $pattern (@pattern) {
			push(@regex, sprintf(qq(%s REGEXP %s), $literal, $pattern));
		}
	}
	
	push(@where, '(' . join(' OR ', @regex) . ')');
	return ({}, \@from, \@where);
};

$functions{ 'http://www.w3.org/2001/XMLSchema#integer' }	= sub {
	my $self	= shift;
	my $parsed_vars	= shift;
	my $level	= shift || \do{ my $a = 0 };
	my @args	= @_;
	my (@from, @where);
	
	my $literal	= $self->expr2sql( $args[0], $level );
	push(@where, sprintf(qq((0 + %s)), $literal));
	return ({}, \@from, \@where);
};

$functions{ 'http://www.w3.org/2001/XMLSchema#decimal' }	= sub {
	my $self	= shift;
	my $parsed_vars	= shift;
	my $level	= shift || \do{ my $a = 0 };
	my @args	= @_;
	
	my (@from, @where);
	
	if ($args[0] eq 'FUNCTION') {
		Carp::confess;
	}
	
	my $literal	= $self->expr2sql( $args[0], $level );
	push(@where, sprintf(qq((0.0 + %s)), $literal));
	return ({}, \@from, \@where);
};
$functions{ 'http://www.w3.org/2001/XMLSchema#double' }	= $functions{ 'http://www.w3.org/2001/XMLSchema#decimal' };





1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
