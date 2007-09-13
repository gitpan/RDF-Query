###################################################################################
#
#    This file was generated using Parse::Eyapp version 1.074.
#
# (c) Parse::Yapp Copyright 1998-2001 Francois Desarmenien.
# (c) Parse::Eyapp Copyright 2006 Casiano Rodriguez-Leon. Universidad de La Laguna.
#        Don't edit this file, use source file "SPARQL.yp" instead.
#
#             ANY CHANGE MADE HERE WILL BE LOST !
#
###################################################################################
package RDF::Query::Parser::SPARQL;
use strict;

push @RDF::Query::Parser::SPARQL::ISA, 'Parse::Eyapp::Driver';

#Included Parse/Eyapp/Driver.pm file----------------------------------------
{
#
# Module Parse::Eyapp::Driver
#
# This module is part of the Parse::Eyapp package available on your
# nearest CPAN
#
# This module is based on Francois Desarmenien Parse::Yapp module
# (c) Parse::Yapp Copyright 1998-2001 Francois Desarmenien, all rights reserved.
# (c) Parse::Eyapp Copyright 2006 Casiano Rodriguez-Leon, all rights reserved.

package Parse::Eyapp::Driver;

require 5.004;

use strict;

our ( $VERSION, $COMPATIBLE, $FILENAME );

$VERSION = '1.074';
$COMPATIBLE = '0.07';
$FILENAME=__FILE__;

use Carp;

#Known parameters, all starting with YY (leading YY will be discarded)
my(%params)=(YYLEX => 'CODE', 'YYERROR' => 'CODE', YYVERSION => '',
	     YYRULES => 'ARRAY', YYSTATES => 'ARRAY', YYDEBUG => '', 
	     # added by Casiano
	     #YYPREFIX  => '',  # Not allowed at YYParse time but in new
	     YYFILENAME => '', 
       YYBYPASS   => '',
	     YYGRAMMAR  => 'ARRAY', 
	     YYTERMS    => 'HASH',
	     ); 
my (%newparams) = (%params, YYPREFIX => '',);

#Mandatory parameters
my(@params)=('LEX','RULES','STATES');

sub new {
    my($class)=shift;
	my($errst,$nberr,$token,$value,$check,$dotpos);
    my($self)={ ERROR => \&_Error,
				ERRST => \$errst,
				NBERR => \$nberr,
				TOKEN => \$token,
				VALUE => \$value,
				DOTPOS => \$dotpos,
				STACK => [],
				DEBUG => 0,
				PREFIX => "",
				CHECK => \$check };

	_CheckParams( [], \%newparams, \@_, $self );

		exists($$self{VERSION})
	and	$$self{VERSION} < $COMPATIBLE
	and	croak "Eyapp driver version $VERSION ".
			  "incompatible with version $$self{VERSION}:\n".
			  "Please recompile parser module.";

        ref($class)
    and $class=ref($class);

    bless($self,$class);
}

sub YYParse {
    my($self)=shift;
    my($retval);

	_CheckParams( \@params, \%params, \@_, $self );

	if($$self{DEBUG}) {
		_DBLoad();
		$retval = eval '$self->_DBParse()';#Do not create stab entry on compile
        $@ and die $@;
	}
	else {
		$retval = $self->_Parse();
	}
    return $retval;
}

sub YYData {
	my($self)=shift;

		exists($$self{USER})
	or	$$self{USER}={};

	$$self{USER};
	
}

sub YYErrok {
	my($self)=shift;

	${$$self{ERRST}}=0;
    undef;
}

sub YYNberr {
	my($self)=shift;

	${$$self{NBERR}};
}

sub YYRecovering {
	my($self)=shift;

	${$$self{ERRST}} != 0;
}

sub YYAbort {
	my($self)=shift;

	${$$self{CHECK}}='ABORT';
    undef;
}

sub YYAccept {
	my($self)=shift;

	${$$self{CHECK}}='ACCEPT';
    undef;
}

sub YYError {
	my($self)=shift;

	${$$self{CHECK}}='ERROR';
    undef;
}

sub YYSemval {
	my($self)=shift;
	my($index)= $_[0] - ${$$self{DOTPOS}} - 1;

		$index < 0
	and	-$index <= @{$$self{STACK}}
	and	return $$self{STACK}[$index][1];

	undef;	#Invalid index
}

### Casiano methods

sub YYLhs { 
  # returns the syntax variable on
  # the left hand side of the current production
  my $self = shift;

  return $self->{CURRENT_LHS}
}

sub YYRuleindex { 
  # returns the index of the rule
  # counting the super rule as rule 0
  my $self = shift;

  return $self->{CURRENT_RULE}
}

sub YYRightside { 
  # returns the rule
  # counting the super rule as rule 0
  my $self = shift;

  return @{$self->{GRAMMAR}->[$self->{CURRENT_RULE}]->[2]};
}

sub YYIsterm {
  my $self = shift;
  my $symbol = shift;

  return exists ($self->{TERMS}->{$symbol});
}

sub YYIssemantic {
  my $self = shift;
  my $symbol = shift;

  return ($self->{TERMS}->{$symbol});
}


sub YYName {
  my $self = shift;

  return $self->{GRAMMAR}->[$self->{CURRENT_RULE}]->[0];
}

sub YYPrefix {
  my $self = shift;

  $self->{PREFIX} = $_[0] if @_;
  #$self->{PREFIX} .= '::' unless  $self->{PREFIX} =~ /::$/;
  $self->{PREFIX};
}

sub YYFilename {
  my $self = shift;

  $self->{FILENAME} = $_[0] if @_;
  $self->{FILENAME};
}

sub YYBypass {
  my $self = shift;

  $self->{BYPASS} = $_[0] if @_;
  $self->{BYPASS};
}

sub YYBypassrule {
  my $self = shift;

  return $self->{GRAMMAR}->[$self->{CURRENT_RULE}][3];
}

sub YYFirstline {
  my $self = shift;

  $self->{FIRSTLINE} = $_[0] if @_;
  $self->{FIRSTLINE};
}

sub BeANode {
  my $class = shift;

    no strict 'refs';
    push @{$class."::ISA"}, "Parse::Eyapp::Node" unless $class->isa("Parse::Eyapp::Node");
}

#sub BeATranslationScheme {
#  my $class = shift;
#
#    no strict 'refs';
#    push @{$class."::ISA"}, "Parse::Eyapp::TranslationScheme" unless $class->isa("Parse::Eyapp::TranslationScheme");
#}

{
  my $attr =  sub { 
      $_[0]{attr} = $_[1] if @_ > 1;
      $_[0]{attr}
    };

  sub make_node_classes {
    my $self = shift;
    my $prefix = $self->YYPrefix() || '';

    { no strict 'refs';
      *{$prefix."TERMINAL::attr"} = $attr;
    }

    for (@_) {
       BeANode("$prefix$_"); 
    }
  }
}

####################################################################
# Usage      : ????
# Purpose    : Responsible for the %tree directive 
#              On each production the default action becomes:
#              sub { goto &Parse::Eyapp::Driver::YYBuildAST }
#
# Returns    : ????
# Parameters : ????
# Throws     : no exceptions
# Comments   : none
# See Also   : n/a
# To Do      : many things: Optimize this!!!!
sub YYBuildAST { 
  my $self = shift;
  my $PREFIX = $self->YYPrefix();
  my @right = $self->YYRightside(); # Symbols on the right hand side of the production
  my $lhs = $self->YYLhs;
  my $name = $self->YYName();
  my $bypass = $self->YYBypassrule; # Boolean: shall we do bypassing of lonely nodes?
  my $class = "$PREFIX$name";
  my @children;

  my $node = bless {}, $class;

  for(my $i = 0; $i < @right; $i++) {
    $_ = $right[$i]; # The symbol
    my $ch = $_[$i]; # The attribute/reference
    if ($self->YYIssemantic($_)) {
      my $class = $PREFIX.'TERMINAL';
      my $node = bless { token => $_, attr => $ch, children => [] }, $class;
      push @children, $node;
      next;
    }

    if ($self->YYIsterm($_)) {
      next unless UNIVERSAL::can($PREFIX."TERMINAL", "save_attributes");
      TERMINAL::save_attributes($ch, $node);
      next;
    }

    if (UNIVERSAL::isa($ch, $PREFIX."_PAREN")) { # Warning: weak code!!!
      push @children, @{$ch->{children}};
      next;
    }

    # If it is an intermediate semantic action skip it
    next if $_ =~ qr{@}; # intermediate rule
    next unless ref($ch);
    push @children, $ch;
  }

  
  if ($bypass and @children == 1) {
    $node = $children[0]; 
    # Re-bless unless is "an automatically named node", but the characterization of this is 
    bless $node, $class unless $name =~ /${lhs}_\d+$/; # lazy, weak (and wicked).
    return $node;
  }
  $node->{children} = \@children; 
  return $node;
}

sub YYBuildTS { 
  my $self = shift;
  my $PREFIX = $self->YYPrefix();
  my @right = $self->YYRightside(); # Symbols on the right hand side of the production
  my $lhs = $self->YYLhs;
  my $name = $self->YYName();
  my $class;
  my @children;

  for(my $i = 0; $i < @right; $i++) {
    $_ = $right[$i]; # The symbol
    my $ch = $_[$i]; # The attribute/reference

    if ($self->YYIsterm($_)) { 
      $class = $PREFIX.'TERMINAL';
      push @children, bless { token => $_, attr => $ch, children => [] }, $class;
      next;
    }

    if (UNIVERSAL::isa($ch, $PREFIX."_PAREN")) { # Warning: weak code!!!
      push @children, @{$ch->{children}};
      next;
    }

    # Substitute intermediate code node _CODE(CODE()) by CODE()
    if (UNIVERSAL::isa($ch, $PREFIX."_CODE")) { # Warning: weak code!!!
      push @children, $ch->child(0);
      next;
    }

    next unless ref($ch);
    push @children, $ch;
  }

  if (unpack('A1',$lhs) eq '@') { # class has to be _CODE check
          $lhs =~ /^\@[0-9]+\-([0-9]+)$/
      or  croak "In line rule name '$lhs' ill formed: report it as a BUG.\n";
      my $dotpos = $1;
 
      croak "Fatal error building metatree when processing  $lhs -> @right" 
      unless exists($_[$dotpos]) and UNIVERSAL::isa($_[$dotpos], 'CODE') ; 
      push @children, $_[$dotpos];
  }
  else {
    my $code = $_[@right];
    if (UNIVERSAL::isa($code, 'CODE')) {
      push @children, $code; 
    }
    else {
      croak "Fatal error building translation scheme. Code or undef expected" if (defined($code));
    }
  }

  $class = "$PREFIX$name";
  my $node = bless { children => \@children }, $class; 
  $node;
}

# for lists
sub YYActionforT_TX1X2 {
  my $self = shift;
  my $head = shift;
  my $PREFIX = $self->YYPrefix();
  my @right = $self->YYRightside();
  my $class;

  for(my $i = 1; $i < @right; $i++) {
    $_ = $right[$i];
    my $ch = $_[$i-1];
    if ($self->YYIssemantic($_)) {
      $class = $PREFIX.'TERMINAL';
      push @{$head->{children}}, bless { token => $_, attr => $ch, children => [] }, $class;
      
      next;
    }
    next if $self->YYIsterm($_);
    if (ref($ch) eq  $PREFIX."_PAREN") { # Warning: weak code!!!
      push @{$head->{children}}, @{$ch->{children}};
      next;
    }
    next unless ref($ch);
    push @{$head->{children}}, $ch;
  }
  return $head;
}

sub YYActionforT_empty {
  my $self = shift;
  my $PREFIX = $self->YYPrefix();
  my $name = $self->YYName();

  # Allow use of %name
  my $class = $PREFIX.$name;
  my $node = bless { children => [] }, $class;
  #BeANode($class);
  $node;
}

sub YYActionforT_single {
  my $self = shift;
  my $PREFIX = $self->YYPrefix();
  my $name = $self->YYName();
  my @right = $self->YYRightside();
  my $class;

  # Allow use of %name
  my @t;
  for(my $i = 0; $i < @right; $i++) {
    $_ = $right[$i];
    my $ch = $_[$i];
    if ($self->YYIssemantic($_)) {
      $class = $PREFIX.'TERMINAL';
      push @t, bless { token => $_, attr => $ch, children => [] }, $class;
      #BeANode($class);
      next;
    }
    next if $self->YYIsterm($_);
    if (ref($ch) eq  $PREFIX."_PAREN") { # Warning: weak code!!!
      push @t, @{$ch->{children}};
      next;
    }
    next unless ref($ch);
    push @t, $ch;
  }
  $class = $PREFIX.$name;
  my $node = bless { children => \@t }, $class;
  #BeANode($class);
  $node;
}

### end Casiano methods

sub YYCurtok {
	my($self)=shift;

        @_
    and ${$$self{TOKEN}}=$_[0];
    ${$$self{TOKEN}};
}

sub YYCurval {
	my($self)=shift;

        @_
    and ${$$self{VALUE}}=$_[0];
    ${$$self{VALUE}};
}

sub YYExpect {
    my($self)=shift;

    keys %{$self->{STATES}[$self->{STACK}[-1][0]]{ACTIONS}}
}

sub YYLexer {
    my($self)=shift;

	$$self{LEX};
}


#################
# Private stuff #
#################


sub _CheckParams {
	my($mandatory,$checklist,$inarray,$outhash)=@_;
	my($prm,$value);
	my($prmlst)={};

	while(($prm,$value)=splice(@$inarray,0,2)) {
        $prm=uc($prm);
			exists($$checklist{$prm})
		or	croak("Unknow parameter '$prm'");
			ref($value) eq $$checklist{$prm}
		or	croak("Invalid value for parameter '$prm'");
        $prm=unpack('@2A*',$prm);
		$$outhash{$prm}=$value;
	}
	for (@$mandatory) {
			exists($$outhash{$_})
		or	croak("Missing mandatory parameter '".lc($_)."'");
	}
}

sub _Error {
	print "Parse error.\n";
}

sub _DBLoad {
	{
		no strict 'refs';

			exists(${__PACKAGE__.'::'}{_DBParse})#Already loaded ?
		and	return;
	}
	my($fname)=__FILE__;
	my(@drv);
	local $/ = "\n";
	open(DRV,"<$fname") or die "Report this as a BUG: Cannot open $fname";
  local $_;
	while(<DRV>) {
                	/^\s*sub\s+_Parse\s*{\s*$/ .. /^\s*}\s*#\s*_Parse\s*$/
        	and     do {
                	s/^#DBG>//;
                	push(@drv,$_);
        	}
	}
	close(DRV);

	$drv[0]=~s/_P/_DBP/;
	eval join('',@drv);
}

#Note that for loading debugging version of the driver,
#this file will be parsed from 'sub _Parse' up to '}#_Parse' inclusive.
#So, DO NOT remove comment at end of sub !!!
sub _Parse {
    my($self)=shift;

	my($rules,$states,$lex,$error)
     = @$self{ 'RULES', 'STATES', 'LEX', 'ERROR' };
	my($errstatus,$nberror,$token,$value,$stack,$check,$dotpos)
     = @$self{ 'ERRST', 'NBERR', 'TOKEN', 'VALUE', 'STACK', 'CHECK', 'DOTPOS' };

#DBG>	my($debug)=$$self{DEBUG};
#DBG>	my($dbgerror)=0;

#DBG>	my($ShowCurToken) = sub {
#DBG>		my($tok)='>';
#DBG>		for (split('',$$token)) {
#DBG>			$tok.=		(ord($_) < 32 or ord($_) > 126)
#DBG>					?	sprintf('<%02X>',ord($_))
#DBG>					:	$_;
#DBG>		}
#DBG>		$tok.='<';
#DBG>	};

	$$errstatus=0;
	$$nberror=0;
	($$token,$$value)=(undef,undef);
	@$stack=( [ 0, undef ] );
	$$check='';

    while(1) {
        my($actions,$act,$stateno);

        $stateno=$$stack[-1][0];
        $actions=$$states[$stateno];

#DBG>	print STDERR ('-' x 40),"\n";
#DBG>		$debug & 0x2
#DBG>	and	print STDERR "In state $stateno:\n";
#DBG>		$debug & 0x08
#DBG>	and	print STDERR "Stack:[".
#DBG>					 join(',',map { $$_[0] } @$stack).
#DBG>					 "]\n";


        if  (exists($$actions{ACTIONS})) {

				defined($$token)
            or	do {
				($$token,$$value)=&$lex($self);
#DBG>				$debug & 0x01
#DBG>			and	do { 
#DBG>       print STDERR "Need token. Got ".&$ShowCurToken."\n";
#DBG>     };
			};

            $act=   exists($$actions{ACTIONS}{$$token})
                    ?   $$actions{ACTIONS}{$$token}
                    :   exists($$actions{DEFAULT})
                        ?   $$actions{DEFAULT}
                        :   undef;
        }
        else {
            $act=$$actions{DEFAULT};
#DBG>			$debug & 0x01
#DBG>		and	print STDERR "Don't need token.\n";
        }

            defined($act)
        and do {

                $act > 0
            and do {        #shift

#DBG>				$debug & 0x04
#DBG>			and	print STDERR "Shift and go to state $act.\n";

					$$errstatus
				and	do {
					--$$errstatus;

#DBG>					$debug & 0x10
#DBG>				and	$dbgerror
#DBG>				and	$$errstatus == 0
#DBG>				and	do {
#DBG>					print STDERR "**End of Error recovery.\n";
#DBG>					$dbgerror=0;
#DBG>				};
				};


                push(@$stack,[ $act, $$value ]);

					$$token ne ''	#Don't eat the eof
				and	$$token=$$value=undef;
                next;
            };

            #reduce
            my($lhs,$len,$code,@sempar,$semval);
            ($lhs,$len,$code)=@{$$rules[-$act]};

#DBG>			$debug & 0x04
#DBG>		and	$act
#DBG>		and	print STDERR "Reduce using rule ".-$act." ($lhs,$len): ";

                $act
            or  $self->YYAccept();

            $$dotpos=$len;

                unpack('A1',$lhs) eq '@'    #In line rule
            and do {
                    $lhs =~ /^\@[0-9]+\-([0-9]+)$/
                or  die "In line rule name '$lhs' ill formed: ".
                        "report it as a BUG.\n";
                $$dotpos = $1;
            };

            @sempar =       $$dotpos
                        ?   map { $$_[1] } @$stack[ -$$dotpos .. -1 ]
                        :   ();

            $self->{CURRENT_LHS} = $lhs;
            $self->{CURRENT_RULE} = -$act; # count the super-rule?
            $semval = $code ? &$code( $self, @sempar )
                            : @sempar ? $sempar[0] : undef;

            splice(@$stack,-$len,$len);

                $$check eq 'ACCEPT'
            and do {

#DBG>			$debug & 0x04
#DBG>		and	print STDERR "Accept.\n";

				return($semval);
			};

                $$check eq 'ABORT'
            and	do {

#DBG>			$debug & 0x04
#DBG>		and	print STDERR "Abort.\n";

				return(undef);

			};

#DBG>			$debug & 0x04
#DBG>		and	print STDERR "Back to state $$stack[-1][0], then ";

                $$check eq 'ERROR'
            or  do {
#DBG>				$debug & 0x04
#DBG>			and	print STDERR 
#DBG>				    "go to state $$states[$$stack[-1][0]]{GOTOS}{$lhs}.\n";

#DBG>				$debug & 0x10
#DBG>			and	$dbgerror
#DBG>			and	$$errstatus == 0
#DBG>			and	do {
#DBG>				print STDERR "**End of Error recovery.\n";
#DBG>				$dbgerror=0;
#DBG>			};

			    push(@$stack,
                     [ $$states[$$stack[-1][0]]{GOTOS}{$lhs}, $semval ]);
                $$check='';
                next;
            };

#DBG>			$debug & 0x04
#DBG>		and	print STDERR "Forced Error recovery.\n";

            $$check='';

        };

        #Error
            $$errstatus
        or   do {

            $$errstatus = 1;
            &$error($self);
                $$errstatus # if 0, then YYErrok has been called
            or  next;       # so continue parsing

#DBG>			$debug & 0x10
#DBG>		and	do {
#DBG>			print STDERR "**Entering Error recovery.\n";
#DBG>			{ 
#DBG>       local $" = ", "; 
#DBG>       my @expect = map { ">$_<" } $self->YYExpect();
#DBG>       print STDERR "Expecting one of: @expect\n";
#DBG>     };
#DBG>			++$dbgerror;
#DBG>		};

            ++$$nberror;

        };

			$$errstatus == 3	#The next token is not valid: discard it
		and	do {
				$$token eq ''	# End of input: no hope
			and	do {
#DBG>				$debug & 0x10
#DBG>			and	print STDERR "**At eof: aborting.\n";
				return(undef);
			};

#DBG>			$debug & 0x10
#DBG>		and	print STDERR "**Discard invalid token ".&$ShowCurToken.".\n";

			$$token=$$value=undef;
		};

        $$errstatus=3;

		while(	  @$stack
			  and (		not exists($$states[$$stack[-1][0]]{ACTIONS})
			        or  not exists($$states[$$stack[-1][0]]{ACTIONS}{error})
					or	$$states[$$stack[-1][0]]{ACTIONS}{error} <= 0)) {

#DBG>			$debug & 0x10
#DBG>		and	print STDERR "**Pop state $$stack[-1][0].\n";

			pop(@$stack);
		}

			@$stack
		or	do {

#DBG>			$debug & 0x10
#DBG>		and	print STDERR "**No state left on stack: aborting.\n";

			return(undef);
		};

		#shift the error token

#DBG>			$debug & 0x10
#DBG>		and	print STDERR "**Shift \$error token and go to state ".
#DBG>						 $$states[$$stack[-1][0]]{ACTIONS}{error}.
#DBG>						 ".\n";

		push(@$stack, [ $$states[$$stack[-1][0]]{ACTIONS}{error}, undef ]);

    }

    #never reached
	croak("Error in driver logic. Please, report it as a BUG");

}#_Parse
#DO NOT remove comment

1;

=head1 NAME 

Parse::Eyapp::Driver - LR Parser and methods to support parsing
 
=head1 SEE ALSO
  
No documentation here. To learn about Parse::Eyapp::Driver see:

=over

=item * L<Parse::Eyapp>,

=item * L<eyapptut>

=item * The pdf files in L<http://nereida.deioc.ull.es/~pl/perlexamples/Eyapp.pdf> and  
L<http://nereida.deioc.ull.es/~pl/perlexamples/eyapptut.pdf>.

=item * L<http://nereida.deioc.ull.es/~pl/perlexamples/section_eyappts.html> (Spanish),

=item * L<eyapp>,

=item * L<treereg>,

=item * L<Parse::yapp>,

=item * yacc(1),

=item * bison(1),

=item * the classic book "Compilers: Principles, Techniques, and Tools" by Alfred V. Aho, Ravi Sethi and

=item * Jeffrey D. Ullman (Addison-Wesley 1986)

=item * L<Parse::RecDescent>.

=back

=head1 AUTHOR
 
Casiano Rodriguez-Leon (casiano@ull.es)
 
=head1 ACKNOWLEDGMENTS

This work has been supported by CEE (FEDER) and the Spanish Ministry of
Educaci�n y Ciencia through Plan Nacional I+D+I number TIN2005-08818-C04-04
(ULL::OPLINK project). Support from Gobierno de Canarias was through GC02210601
(Grupos Consolidados).
The University of La Laguna has also supported my work in many ways
and for many years.
I wish to thank Francois Desarmenien for his C<Parse::Yapp> module,
to my students at La Laguna and to the Perl Community. Special thanks to
my family and Larry Wall.

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006 Casiano Rodriguez-Leon (casiano@ull.es). All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut


}
#End of include--------------------------------------------------



#line 888 SPARQL.pm

my $warnmessage =<< "EOFWARN";
Warning!: Did you changed the \@RDF::Query::Parser::SPARQL::ISA variable inside the header section of the eyapp program?
EOFWARN

sub new {
        my($class)=shift;
        ref($class)
    and $class=ref($class);

    warn $warnmessage unless __PACKAGE__->isa('Parse::Eyapp::Driver'); 
    my($self)=$class->SUPER::new( yyversion => '1.074',
                                  yyGRAMMAR  =>
[
  [ _SUPERSTART => '$start', [ 'Query', '$end' ], 0 ],
  [ Query_1 => 'Query', [ 'Prologue', 'SelectQuery' ], 0 ],
  [ Query_2 => 'Query', [ 'Prologue', 'ConstructQuery' ], 0 ],
  [ Query_3 => 'Query', [ 'Prologue', 'DescribeQuery' ], 0 ],
  [ Query_4 => 'Query', [ 'Prologue', 'AskQuery' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-1', [ 'BaseDecl' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-1', [  ], 0 ],
  [ _STAR_LIST_2 => 'STAR-2', [ 'STAR-2', 'PrefixDecl' ], 0 ],
  [ _STAR_LIST_2 => 'STAR-2', [  ], 0 ],
  [ Prologue_9 => 'Prologue', [ 'OPTIONAL-1', 'STAR-2' ], 0 ],
  [ BaseDecl_10 => 'BaseDecl', [ 'BASE', 'IRI_REF' ], 0 ],
  [ PrefixDecl_11 => 'PrefixDecl', [ 'PREFIX', 'PNAME_NS', 'IRI_REF' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-3', [ 'SelectModifier' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-3', [  ], 0 ],
  [ _STAR_LIST_4 => 'STAR-4', [ 'STAR-4', 'DatasetClause' ], 0 ],
  [ _STAR_LIST_4 => 'STAR-4', [  ], 0 ],
  [ SelectQuery_16 => 'SelectQuery', [ 'SELECT', 'OPTIONAL-3', 'SelectVars', 'STAR-4', 'WhereClause', 'SolutionModifier' ], 0 ],
  [ SelectModifier_17 => 'SelectModifier', [ 'DISTINCT' ], 0 ],
  [ SelectModifier_18 => 'SelectModifier', [ 'REDUCED' ], 0 ],
  [ _PLUS_LIST => 'PLUS-5', [ 'PLUS-5', 'Var' ], 0 ],
  [ _PLUS_LIST => 'PLUS-5', [ 'Var' ], 0 ],
  [ SelectVars_21 => 'SelectVars', [ 'PLUS-5' ], 0 ],
  [ SelectVars_22 => 'SelectVars', [ '*' ], 0 ],
  [ _STAR_LIST_6 => 'STAR-6', [ 'STAR-6', 'DatasetClause' ], 0 ],
  [ _STAR_LIST_6 => 'STAR-6', [  ], 0 ],
  [ ConstructQuery_25 => 'ConstructQuery', [ 'CONSTRUCT', 'ConstructTemplate', 'STAR-6', 'WhereClause', 'SolutionModifier' ], 0 ],
  [ _STAR_LIST_7 => 'STAR-7', [ 'STAR-7', 'DatasetClause' ], 0 ],
  [ _STAR_LIST_7 => 'STAR-7', [  ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-8', [ 'WhereClause' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-8', [  ], 0 ],
  [ DescribeQuery_30 => 'DescribeQuery', [ 'DESCRIBE', 'DescribeVars', 'STAR-7', 'OPTIONAL-8', 'SolutionModifier' ], 0 ],
  [ _PLUS_LIST => 'PLUS-9', [ 'PLUS-9', 'VarOrIRIref' ], 0 ],
  [ _PLUS_LIST => 'PLUS-9', [ 'VarOrIRIref' ], 0 ],
  [ DescribeVars_33 => 'DescribeVars', [ 'PLUS-9' ], 0 ],
  [ DescribeVars_34 => 'DescribeVars', [ '*' ], 0 ],
  [ _STAR_LIST_10 => 'STAR-10', [ 'STAR-10', 'DatasetClause' ], 0 ],
  [ _STAR_LIST_10 => 'STAR-10', [  ], 0 ],
  [ AskQuery_37 => 'AskQuery', [ 'ASK', 'STAR-10', 'WhereClause' ], 0 ],
  [ DatasetClause_38 => 'DatasetClause', [ 'FROM', 'DefaultGraphClause' ], 0 ],
  [ DatasetClause_39 => 'DatasetClause', [ 'FROM NAMED', 'NamedGraphClause' ], 0 ],
  [ DefaultGraphClause_40 => 'DefaultGraphClause', [ 'SourceSelector' ], 0 ],
  [ NamedGraphClause_41 => 'NamedGraphClause', [ 'SourceSelector' ], 0 ],
  [ SourceSelector_42 => 'SourceSelector', [ 'IRIref' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-11', [ 'WHERE' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-11', [  ], 0 ],
  [ WhereClause_45 => 'WhereClause', [ 'OPTIONAL-11', 'GroupGraphPattern' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-12', [ 'OrderClause' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-12', [  ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-13', [ 'LimitOffsetClauses' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-13', [  ], 0 ],
  [ SolutionModifier_50 => 'SolutionModifier', [ 'OPTIONAL-12', 'OPTIONAL-13' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-14', [ 'OffsetClause' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-14', [  ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-15', [ 'LimitClause' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-15', [  ], 0 ],
  [ LimitOffsetClauses_55 => 'LimitOffsetClauses', [ 'LimitClause', 'OPTIONAL-14' ], 0 ],
  [ LimitOffsetClauses_56 => 'LimitOffsetClauses', [ 'OffsetClause', 'OPTIONAL-15' ], 0 ],
  [ _PLUS_LIST => 'PLUS-16', [ 'PLUS-16', 'OrderCondition' ], 0 ],
  [ _PLUS_LIST => 'PLUS-16', [ 'OrderCondition' ], 0 ],
  [ OrderClause_59 => 'OrderClause', [ 'ORDER BY', 'PLUS-16' ], 0 ],
  [ OrderCondition_60 => 'OrderCondition', [ 'OrderDirection', 'BrackettedExpression' ], 0 ],
  [ OrderCondition_61 => 'OrderCondition', [ 'Constraint' ], 0 ],
  [ OrderCondition_62 => 'OrderCondition', [ 'Var' ], 0 ],
  [ OrderDirection_63 => 'OrderDirection', [ 'ASC' ], 0 ],
  [ OrderDirection_64 => 'OrderDirection', [ 'DESC' ], 0 ],
  [ LimitClause_65 => 'LimitClause', [ 'LIMIT', 'INTEGER' ], 0 ],
  [ OffsetClause_66 => 'OffsetClause', [ 'OFFSET', 'INTEGER' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-17', [ 'TriplesBlock' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-17', [  ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-18', [ '.' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-18', [  ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-19', [ 'TriplesBlock' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-19', [  ], 0 ],
  [ _PAREN => 'PAREN-20', [ 'GGPAtom', 'OPTIONAL-18', 'OPTIONAL-19' ], 0 ],
  [ _STAR_LIST_21 => 'STAR-21', [ 'STAR-21', 'PAREN-20' ], 0 ],
  [ _STAR_LIST_21 => 'STAR-21', [  ], 0 ],
  [ GroupGraphPattern_76 => 'GroupGraphPattern', [ '{', 'OPTIONAL-17', 'STAR-21', '}' ], 0 ],
  [ GGPAtom_77 => 'GGPAtom', [ 'GraphPatternNotTriples' ], 0 ],
  [ GGPAtom_78 => 'GGPAtom', [ 'Filter' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-22', [ 'TriplesBlock' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-22', [  ], 0 ],
  [ _PAREN => 'PAREN-23', [ '.', 'OPTIONAL-22' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-24', [ 'PAREN-23' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-24', [  ], 0 ],
  [ TriplesBlock_84 => 'TriplesBlock', [ 'TriplesSameSubject', 'OPTIONAL-24' ], 0 ],
  [ GraphPatternNotTriples_85 => 'GraphPatternNotTriples', [ 'OptionalGraphPattern' ], 0 ],
  [ GraphPatternNotTriples_86 => 'GraphPatternNotTriples', [ 'GroupOrUnionGraphPattern' ], 0 ],
  [ GraphPatternNotTriples_87 => 'GraphPatternNotTriples', [ 'GraphGraphPattern' ], 0 ],
  [ OptionalGraphPattern_88 => 'OptionalGraphPattern', [ 'OPTIONAL', 'GroupGraphPattern' ], 0 ],
  [ GraphGraphPattern_89 => 'GraphGraphPattern', [ 'GRAPH', 'VarOrIRIref', 'GroupGraphPattern' ], 0 ],
  [ _PAREN => 'PAREN-25', [ 'UNION', 'GroupGraphPattern' ], 0 ],
  [ _STAR_LIST_26 => 'STAR-26', [ 'STAR-26', 'PAREN-25' ], 0 ],
  [ _STAR_LIST_26 => 'STAR-26', [  ], 0 ],
  [ GroupOrUnionGraphPattern_93 => 'GroupOrUnionGraphPattern', [ 'GroupGraphPattern', 'STAR-26' ], 0 ],
  [ Filter_94 => 'Filter', [ 'FILTER', 'Constraint' ], 0 ],
  [ Constraint_95 => 'Constraint', [ 'BrackettedExpression' ], 0 ],
  [ Constraint_96 => 'Constraint', [ 'BuiltInCall' ], 0 ],
  [ Constraint_97 => 'Constraint', [ 'FunctionCall' ], 0 ],
  [ FunctionCall_98 => 'FunctionCall', [ 'IRIref', 'ArgList' ], 0 ],
  [ _PAREN => 'PAREN-27', [ ',', 'Expression' ], 0 ],
  [ _STAR_LIST_28 => 'STAR-28', [ 'STAR-28', 'PAREN-27' ], 0 ],
  [ _STAR_LIST_28 => 'STAR-28', [  ], 0 ],
  [ ArgList_102 => 'ArgList', [ '(', 'Expression', 'STAR-28', ')' ], 0 ],
  [ ArgList_103 => 'ArgList', [ 'NIL' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-29', [ 'ConstructTriples' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-29', [  ], 0 ],
  [ ConstructTemplate_106 => 'ConstructTemplate', [ '{', 'OPTIONAL-29', '}' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-30', [ 'ConstructTriples' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-30', [  ], 0 ],
  [ _PAREN => 'PAREN-31', [ '.', 'OPTIONAL-30' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-32', [ 'PAREN-31' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-32', [  ], 0 ],
  [ ConstructTriples_112 => 'ConstructTriples', [ 'TriplesSameSubject', 'OPTIONAL-32' ], 0 ],
  [ TriplesSameSubject_113 => 'TriplesSameSubject', [ 'VarOrTerm', 'PropertyListNotEmpty' ], 0 ],
  [ TriplesSameSubject_114 => 'TriplesSameSubject', [ 'TriplesNode', 'PropertyList' ], 0 ],
  [ _PAREN => 'PAREN-33', [ 'Verb', 'ObjectList' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-34', [ 'PAREN-33' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-34', [  ], 0 ],
  [ _PAREN => 'PAREN-35', [ ';', 'OPTIONAL-34' ], 0 ],
  [ _STAR_LIST_36 => 'STAR-36', [ 'STAR-36', 'PAREN-35' ], 0 ],
  [ _STAR_LIST_36 => 'STAR-36', [  ], 0 ],
  [ PropertyListNotEmpty_121 => 'PropertyListNotEmpty', [ 'Verb', 'ObjectList', 'STAR-36' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-37', [ 'PropertyListNotEmpty' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-37', [  ], 0 ],
  [ PropertyList_124 => 'PropertyList', [ 'OPTIONAL-37' ], 0 ],
  [ _PAREN => 'PAREN-38', [ ',', 'Object' ], 0 ],
  [ _STAR_LIST_39 => 'STAR-39', [ 'STAR-39', 'PAREN-38' ], 0 ],
  [ _STAR_LIST_39 => 'STAR-39', [  ], 0 ],
  [ ObjectList_128 => 'ObjectList', [ 'Object', 'STAR-39' ], 0 ],
  [ Object_129 => 'Object', [ 'GraphNode' ], 0 ],
  [ Verb_130 => 'Verb', [ 'VarOrIRIref' ], 0 ],
  [ Verb_131 => 'Verb', [ 'a' ], 0 ],
  [ TriplesNode_132 => 'TriplesNode', [ 'Collection' ], 0 ],
  [ TriplesNode_133 => 'TriplesNode', [ 'BlankNodePropertyList' ], 0 ],
  [ BlankNodePropertyList_134 => 'BlankNodePropertyList', [ '[', 'PropertyListNotEmpty', ']' ], 0 ],
  [ _PLUS_LIST => 'PLUS-40', [ 'PLUS-40', 'GraphNode' ], 0 ],
  [ _PLUS_LIST => 'PLUS-40', [ 'GraphNode' ], 0 ],
  [ Collection_137 => 'Collection', [ '(', 'PLUS-40', ')' ], 0 ],
  [ GraphNode_138 => 'GraphNode', [ 'VarOrTerm' ], 0 ],
  [ GraphNode_139 => 'GraphNode', [ 'TriplesNode' ], 0 ],
  [ VarOrTerm_140 => 'VarOrTerm', [ 'Var' ], 0 ],
  [ VarOrTerm_141 => 'VarOrTerm', [ 'GraphTerm' ], 0 ],
  [ VarOrIRIref_142 => 'VarOrIRIref', [ 'Var' ], 0 ],
  [ VarOrIRIref_143 => 'VarOrIRIref', [ 'IRIref' ], 0 ],
  [ Var_144 => 'Var', [ 'VAR1' ], 0 ],
  [ Var_145 => 'Var', [ 'VAR2' ], 0 ],
  [ GraphTerm_146 => 'GraphTerm', [ 'IRIref' ], 0 ],
  [ GraphTerm_147 => 'GraphTerm', [ 'RDFLiteral' ], 0 ],
  [ GraphTerm_148 => 'GraphTerm', [ 'NumericLiteral' ], 0 ],
  [ GraphTerm_149 => 'GraphTerm', [ 'BooleanLiteral' ], 0 ],
  [ GraphTerm_150 => 'GraphTerm', [ 'BlankNode' ], 0 ],
  [ GraphTerm_151 => 'GraphTerm', [ 'NIL' ], 0 ],
  [ Expression_152 => 'Expression', [ 'ConditionalOrExpression' ], 0 ],
  [ _PAREN => 'PAREN-41', [ '||', 'ConditionalAndExpression' ], 0 ],
  [ _STAR_LIST_42 => 'STAR-42', [ 'STAR-42', 'PAREN-41' ], 0 ],
  [ _STAR_LIST_42 => 'STAR-42', [  ], 0 ],
  [ ConditionalOrExpression_156 => 'ConditionalOrExpression', [ 'ConditionalAndExpression', 'STAR-42' ], 0 ],
  [ _PAREN => 'PAREN-43', [ '&&', 'ValueLogical' ], 0 ],
  [ _STAR_LIST_44 => 'STAR-44', [ 'STAR-44', 'PAREN-43' ], 0 ],
  [ _STAR_LIST_44 => 'STAR-44', [  ], 0 ],
  [ ConditionalAndExpression_160 => 'ConditionalAndExpression', [ 'ValueLogical', 'STAR-44' ], 0 ],
  [ ValueLogical_161 => 'ValueLogical', [ 'RelationalExpression' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-45', [ 'RelationalExpressionExtra' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-45', [  ], 0 ],
  [ RelationalExpression_164 => 'RelationalExpression', [ 'NumericExpression', 'OPTIONAL-45' ], 0 ],
  [ RelationalExpressionExtra_165 => 'RelationalExpressionExtra', [ '=', 'NumericExpression' ], 0 ],
  [ RelationalExpressionExtra_166 => 'RelationalExpressionExtra', [ '!=', 'NumericExpression' ], 0 ],
  [ RelationalExpressionExtra_167 => 'RelationalExpressionExtra', [ '<', 'NumericExpression' ], 0 ],
  [ RelationalExpressionExtra_168 => 'RelationalExpressionExtra', [ '>', 'NumericExpression' ], 0 ],
  [ RelationalExpressionExtra_169 => 'RelationalExpressionExtra', [ '<=', 'NumericExpression' ], 0 ],
  [ RelationalExpressionExtra_170 => 'RelationalExpressionExtra', [ '>=', 'NumericExpression' ], 0 ],
  [ NumericExpression_171 => 'NumericExpression', [ 'AdditiveExpression' ], 0 ],
  [ _STAR_LIST_46 => 'STAR-46', [ 'STAR-46', 'AdditiveExpressionExtra' ], 0 ],
  [ _STAR_LIST_46 => 'STAR-46', [  ], 0 ],
  [ AdditiveExpression_174 => 'AdditiveExpression', [ 'MultiplicativeExpression', 'STAR-46' ], 0 ],
  [ AdditiveExpressionExtra_175 => 'AdditiveExpressionExtra', [ '+', 'MultiplicativeExpression' ], 0 ],
  [ AdditiveExpressionExtra_176 => 'AdditiveExpressionExtra', [ '-', 'MultiplicativeExpression' ], 0 ],
  [ AdditiveExpressionExtra_177 => 'AdditiveExpressionExtra', [ 'NumericLiteralPositive' ], 0 ],
  [ AdditiveExpressionExtra_178 => 'AdditiveExpressionExtra', [ 'NumericLiteralNegative' ], 0 ],
  [ _STAR_LIST_47 => 'STAR-47', [ 'STAR-47', 'MultiplicativeExpressionExtra' ], 0 ],
  [ _STAR_LIST_47 => 'STAR-47', [  ], 0 ],
  [ MultiplicativeExpression_181 => 'MultiplicativeExpression', [ 'UnaryExpression', 'STAR-47' ], 0 ],
  [ MultiplicativeExpressionExtra_182 => 'MultiplicativeExpressionExtra', [ '*', 'UnaryExpression' ], 0 ],
  [ MultiplicativeExpressionExtra_183 => 'MultiplicativeExpressionExtra', [ '/', 'UnaryExpression' ], 0 ],
  [ UnaryExpression_184 => 'UnaryExpression', [ '!', 'PrimaryExpression' ], 0 ],
  [ UnaryExpression_185 => 'UnaryExpression', [ '+', 'PrimaryExpression' ], 0 ],
  [ UnaryExpression_186 => 'UnaryExpression', [ '-', 'PrimaryExpression' ], 0 ],
  [ UnaryExpression_187 => 'UnaryExpression', [ 'PrimaryExpression' ], 0 ],
  [ PrimaryExpression_188 => 'PrimaryExpression', [ 'BrackettedExpression' ], 0 ],
  [ PrimaryExpression_189 => 'PrimaryExpression', [ 'BuiltInCall' ], 0 ],
  [ PrimaryExpression_190 => 'PrimaryExpression', [ 'IRIrefOrFunction' ], 0 ],
  [ PrimaryExpression_191 => 'PrimaryExpression', [ 'RDFLiteral' ], 0 ],
  [ PrimaryExpression_192 => 'PrimaryExpression', [ 'NumericLiteral' ], 0 ],
  [ PrimaryExpression_193 => 'PrimaryExpression', [ 'BooleanLiteral' ], 0 ],
  [ PrimaryExpression_194 => 'PrimaryExpression', [ 'Var' ], 0 ],
  [ BrackettedExpression_195 => 'BrackettedExpression', [ '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_196 => 'BuiltInCall', [ 'STR', '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_197 => 'BuiltInCall', [ 'LANG', '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_198 => 'BuiltInCall', [ 'LANGMATCHES', '(', 'Expression', ',', 'Expression', ')' ], 0 ],
  [ BuiltInCall_199 => 'BuiltInCall', [ 'DATATYPE', '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_200 => 'BuiltInCall', [ 'BOUND', '(', 'Var', ')' ], 0 ],
  [ BuiltInCall_201 => 'BuiltInCall', [ 'SAMETERM', '(', 'Expression', ',', 'Expression', ')' ], 0 ],
  [ BuiltInCall_202 => 'BuiltInCall', [ 'ISIRI', '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_203 => 'BuiltInCall', [ 'ISURI', '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_204 => 'BuiltInCall', [ 'ISBLANK', '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_205 => 'BuiltInCall', [ 'ISLITERAL', '(', 'Expression', ')' ], 0 ],
  [ BuiltInCall_206 => 'BuiltInCall', [ 'RegexExpression' ], 0 ],
  [ _PAREN => 'PAREN-48', [ ',', 'Expression' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-49', [ 'PAREN-48' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-49', [  ], 0 ],
  [ RegexExpression_210 => 'RegexExpression', [ 'REGEX', '(', 'Expression', ',', 'Expression', 'OPTIONAL-49', ')' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-50', [ 'ArgList' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-50', [  ], 0 ],
  [ IRIrefOrFunction_213 => 'IRIrefOrFunction', [ 'IRIref', 'OPTIONAL-50' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-51', [ 'LiteralExtra' ], 0 ],
  [ _OPTIONAL => 'OPTIONAL-51', [  ], 0 ],
  [ RDFLiteral_216 => 'RDFLiteral', [ 'STRING', 'OPTIONAL-51' ], 0 ],
  [ LiteralExtra_217 => 'LiteralExtra', [ 'LANGTAG' ], 0 ],
  [ LiteralExtra_218 => 'LiteralExtra', [ '^^', 'IRIref' ], 0 ],
  [ NumericLiteral_219 => 'NumericLiteral', [ 'NumericLiteralUnsigned' ], 0 ],
  [ NumericLiteral_220 => 'NumericLiteral', [ 'NumericLiteralPositive' ], 0 ],
  [ NumericLiteral_221 => 'NumericLiteral', [ 'NumericLiteralNegative' ], 0 ],
  [ NumericLiteralUnsigned_222 => 'NumericLiteralUnsigned', [ 'INTEGER' ], 0 ],
  [ NumericLiteralUnsigned_223 => 'NumericLiteralUnsigned', [ 'DECIMAL' ], 0 ],
  [ NumericLiteralUnsigned_224 => 'NumericLiteralUnsigned', [ 'DOUBLE' ], 0 ],
  [ NumericLiteralPositive_225 => 'NumericLiteralPositive', [ 'INTEGER_POSITIVE' ], 0 ],
  [ NumericLiteralPositive_226 => 'NumericLiteralPositive', [ 'DECIMAL_POSITIVE' ], 0 ],
  [ NumericLiteralPositive_227 => 'NumericLiteralPositive', [ 'DOUBLE_POSITIVE' ], 0 ],
  [ NumericLiteralNegative_228 => 'NumericLiteralNegative', [ 'INTEGER_NEGATIVE' ], 0 ],
  [ NumericLiteralNegative_229 => 'NumericLiteralNegative', [ 'DECIMAL_NEGATIVE' ], 0 ],
  [ NumericLiteralNegative_230 => 'NumericLiteralNegative', [ 'DOUBLE_NEGATIVE' ], 0 ],
  [ BooleanLiteral_231 => 'BooleanLiteral', [ 'TRUE' ], 0 ],
  [ BooleanLiteral_232 => 'BooleanLiteral', [ 'FALSE' ], 0 ],
  [ IRIref_233 => 'IRIref', [ 'IRI_REF' ], 0 ],
  [ IRIref_234 => 'IRIref', [ 'PrefixedName' ], 0 ],
  [ PrefixedName_235 => 'PrefixedName', [ 'PNAME_LN' ], 0 ],
  [ PrefixedName_236 => 'PrefixedName', [ 'PNAME_NS' ], 0 ],
  [ BlankNode_237 => 'BlankNode', [ 'BLANK_NODE_LABEL' ], 0 ],
  [ BlankNode_238 => 'BlankNode', [ 'ANON' ], 0 ],
  [ IRI_REF_239 => 'IRI_REF', [ 'URI' ], 0 ],
  [ PNAME_NS_240 => 'PNAME_NS', [ 'NAME', ':' ], 0 ],
  [ PNAME_NS_241 => 'PNAME_NS', [ ':' ], 0 ],
  [ PNAME_LN_242 => 'PNAME_LN', [ 'PNAME_NS', 'PN_LOCAL' ], 0 ],
  [ BLANK_NODE_LABEL_243 => 'BLANK_NODE_LABEL', [ '_:', 'PN_LOCAL' ], 0 ],
  [ PN_LOCAL_244 => 'PN_LOCAL', [ 'VARNAME', 'PN_LOCAL_EXTRA' ], 0 ],
  [ PN_LOCAL_245 => 'PN_LOCAL', [ 'INTEGER', 'VARNAME', 'PN_LOCAL_EXTRA' ], 0 ],
  [ PN_LOCAL_246 => 'PN_LOCAL', [ 'INTEGER', 'VARNAME' ], 0 ],
  [ PN_LOCAL_247 => 'PN_LOCAL', [ 'VARNAME' ], 0 ],
  [ PN_LOCAL_EXTRA_248 => 'PN_LOCAL_EXTRA', [ 'INTEGER_NO_WS' ], 0 ],
  [ PN_LOCAL_EXTRA_249 => 'PN_LOCAL_EXTRA', [ '-', 'NAME' ], 0 ],
  [ PN_LOCAL_EXTRA_250 => 'PN_LOCAL_EXTRA', [ '_', 'NAME' ], 0 ],
  [ VAR1_251 => 'VAR1', [ '?', 'VARNAME' ], 0 ],
  [ VAR2_252 => 'VAR2', [ '$', 'VARNAME' ], 0 ],
  [ _PLUS_LIST => 'PLUS-52', [ 'PLUS-52', 'NAME' ], 0 ],
  [ _PLUS_LIST => 'PLUS-52', [ 'NAME' ], 0 ],
  [ _PAREN => 'PAREN-53', [ '-', 'PLUS-52' ], 0 ],
  [ _STAR_LIST_54 => 'STAR-54', [ 'STAR-54', 'PAREN-53' ], 0 ],
  [ _STAR_LIST_54 => 'STAR-54', [  ], 0 ],
  [ LANGTAG_258 => 'LANGTAG', [ '@', 'NAME', 'STAR-54' ], 0 ],
  [ INTEGER_POSITIVE_259 => 'INTEGER_POSITIVE', [ '+', 'INTEGER' ], 0 ],
  [ DOUBLE_POSITIVE_260 => 'DOUBLE_POSITIVE', [ '+', 'DOUBLE' ], 0 ],
  [ DECIMAL_POSITIVE_261 => 'DECIMAL_POSITIVE', [ '+', 'DECIMAL' ], 0 ],
  [ VARNAME_262 => 'VARNAME', [ 'NAME' ], 0 ],
  [ VARNAME_263 => 'VARNAME', [ 'a' ], 0 ],
  [ VARNAME_264 => 'VARNAME', [ 'ASC' ], 0 ],
  [ VARNAME_265 => 'VARNAME', [ 'ASK' ], 0 ],
  [ VARNAME_266 => 'VARNAME', [ 'BASE' ], 0 ],
  [ VARNAME_267 => 'VARNAME', [ 'BOUND' ], 0 ],
  [ VARNAME_268 => 'VARNAME', [ 'CONSTRUCT' ], 0 ],
  [ VARNAME_269 => 'VARNAME', [ 'DATATYPE' ], 0 ],
  [ VARNAME_270 => 'VARNAME', [ 'DESCRIBE' ], 0 ],
  [ VARNAME_271 => 'VARNAME', [ 'DESC' ], 0 ],
  [ VARNAME_272 => 'VARNAME', [ 'DISTINCT' ], 0 ],
  [ VARNAME_273 => 'VARNAME', [ 'FILTER' ], 0 ],
  [ VARNAME_274 => 'VARNAME', [ 'FROM' ], 0 ],
  [ VARNAME_275 => 'VARNAME', [ 'GRAPH' ], 0 ],
  [ VARNAME_276 => 'VARNAME', [ 'LANGMATCHES' ], 0 ],
  [ VARNAME_277 => 'VARNAME', [ 'LANG' ], 0 ],
  [ VARNAME_278 => 'VARNAME', [ 'LIMIT' ], 0 ],
  [ VARNAME_279 => 'VARNAME', [ 'NAMED' ], 0 ],
  [ VARNAME_280 => 'VARNAME', [ 'OFFSET' ], 0 ],
  [ VARNAME_281 => 'VARNAME', [ 'OPTIONAL' ], 0 ],
  [ VARNAME_282 => 'VARNAME', [ 'PREFIX' ], 0 ],
  [ VARNAME_283 => 'VARNAME', [ 'REDUCED' ], 0 ],
  [ VARNAME_284 => 'VARNAME', [ 'REGEX' ], 0 ],
  [ VARNAME_285 => 'VARNAME', [ 'SELECT' ], 0 ],
  [ VARNAME_286 => 'VARNAME', [ 'STR' ], 0 ],
  [ VARNAME_287 => 'VARNAME', [ 'UNION' ], 0 ],
  [ VARNAME_288 => 'VARNAME', [ 'WHERE' ], 0 ],
  [ VARNAME_289 => 'VARNAME', [ 'ISBLANK' ], 0 ],
  [ VARNAME_290 => 'VARNAME', [ 'ISIRI' ], 0 ],
  [ VARNAME_291 => 'VARNAME', [ 'ISLITERAL' ], 0 ],
  [ VARNAME_292 => 'VARNAME', [ 'ISURI' ], 0 ],
  [ VARNAME_293 => 'VARNAME', [ 'SAMETERM' ], 0 ],
  [ VARNAME_294 => 'VARNAME', [ 'TRUE' ], 0 ],
  [ VARNAME_295 => 'VARNAME', [ 'FALSE' ], 0 ],
  [ _STAR_LIST_55 => 'STAR-55', [ 'STAR-55', 'WS' ], 0 ],
  [ _STAR_LIST_55 => 'STAR-55', [  ], 0 ],
  [ NIL_298 => 'NIL', [ '(', 'STAR-55', ')' ], 0 ],
  [ _STAR_LIST_56 => 'STAR-56', [ 'STAR-56', 'WS' ], 0 ],
  [ _STAR_LIST_56 => 'STAR-56', [  ], 0 ],
  [ ANON_301 => 'ANON', [ '[', 'STAR-56', ']' ], 0 ],
  [ INTEGER_302 => 'INTEGER', [ 'INTEGER_WS' ], 0 ],
  [ INTEGER_303 => 'INTEGER', [ 'INTEGER_NO_WS' ], 0 ],
],
                                  yyTERMS  =>
{ '$end' => 0, '!' => 0, '!=' => 0, '$' => 0, '&&' => 0, '(' => 0, ')' => 0, '*' => 0, '+' => 0, ',' => 0, '-' => 0, '.' => 0, '/' => 0, ':' => 0, ';' => 0, '<' => 0, '<=' => 0, '=' => 0, '>' => 0, '>=' => 0, '?' => 0, '@' => 0, 'ASC' => 0, 'ASK' => 0, 'BASE' => 0, 'CONSTRUCT' => 0, 'DESC' => 0, 'DESCRIBE' => 0, 'DISTINCT' => 0, 'FALSE' => 0, 'FILTER' => 0, 'FROM NAMED' => 0, 'FROM' => 0, 'GRAPH' => 0, 'LIMIT' => 0, 'OFFSET' => 0, 'OPTIONAL' => 0, 'ORDER BY' => 0, 'PREFIX' => 0, 'REDUCED' => 0, 'REGEX' => 0, 'SELECT' => 0, 'TRUE' => 0, 'UNION' => 0, 'WHERE' => 0, '[' => 0, ']' => 0, '^^' => 0, '_' => 0, '_:' => 0, 'a' => 0, '{' => 0, '||' => 0, '}' => 0, ASC => 1, ASK => 1, BASE => 1, BOUND => 1, CONSTRUCT => 1, DATATYPE => 1, DECIMAL => 1, DECIMAL_NEGATIVE => 1, DESC => 1, DESCRIBE => 1, DISTINCT => 1, DOUBLE => 1, DOUBLE_NEGATIVE => 1, FALSE => 1, FILTER => 1, FROM => 1, GRAPH => 1, INTEGER_NEGATIVE => 1, INTEGER_NO_WS => 1, INTEGER_WS => 1, ISBLANK => 1, ISIRI => 1, ISLITERAL => 1, ISURI => 1, LANG => 1, LANGMATCHES => 1, LIMIT => 1, NAME => 1, NAMED => 1, OFFSET => 1, OPTIONAL => 1, PREFIX => 1, REDUCED => 1, REGEX => 1, SAMETERM => 1, SELECT => 1, STR => 1, STRING => 1, TRUE => 1, UNION => 1, URI => 1, WHERE => 1, WS => 1, a => 1 },
                                  yyFILENAME  => "SPARQL.yp",
                                  yystates =>
[
	{#State 0
		ACTIONS => {
			"BASE" => 1
		},
		DEFAULT => -6,
		GOTOS => {
			'Query' => 3,
			'Prologue' => 2,
			'BaseDecl' => 4,
			'OPTIONAL-1' => 5
		}
	},
	{#State 1
		ACTIONS => {
			'URI' => 6
		},
		GOTOS => {
			'IRI_REF' => 7
		}
	},
	{#State 2
		ACTIONS => {
			"SELECT" => 8,
			"DESCRIBE" => 12,
			"CONSTRUCT" => 15,
			"ASK" => 10
		},
		GOTOS => {
			'DescribeQuery' => 11,
			'AskQuery' => 9,
			'SelectQuery' => 13,
			'ConstructQuery' => 14
		}
	},
	{#State 3
		ACTIONS => {
			'' => 16
		}
	},
	{#State 4
		DEFAULT => -5
	},
	{#State 5
		DEFAULT => -8,
		GOTOS => {
			'STAR-2' => 17
		}
	},
	{#State 6
		DEFAULT => -239
	},
	{#State 7
		DEFAULT => -10
	},
	{#State 8
		ACTIONS => {
			"REDUCED" => 18,
			"DISTINCT" => 19
		},
		DEFAULT => -13,
		GOTOS => {
			'SelectModifier' => 20,
			'OPTIONAL-3' => 21
		}
	},
	{#State 9
		DEFAULT => -4
	},
	{#State 10
		DEFAULT => -36,
		GOTOS => {
			'STAR-10' => 22
		}
	},
	{#State 11
		DEFAULT => -3
	},
	{#State 12
		ACTIONS => {
			":" => 23,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"*" => 26,
			"\$" => 27
		},
		GOTOS => {
			'DescribeVars' => 24,
			'PLUS-9' => 33,
			'PrefixedName' => 34,
			'VAR1' => 25,
			'PNAME_LN' => 35,
			'IRI_REF' => 28,
			'PNAME_NS' => 36,
			'IRIref' => 38,
			'VarOrIRIref' => 37,
			'VAR2' => 29,
			'Var' => 30
		}
	},
	{#State 13
		DEFAULT => -1
	},
	{#State 14
		DEFAULT => -2
	},
	{#State 15
		ACTIONS => {
			"{" => 39
		},
		GOTOS => {
			'ConstructTemplate' => 40
		}
	},
	{#State 16
		DEFAULT => 0
	},
	{#State 17
		ACTIONS => {
			"PREFIX" => 42
		},
		DEFAULT => -9,
		GOTOS => {
			'PrefixDecl' => 41
		}
	},
	{#State 18
		DEFAULT => -18
	},
	{#State 19
		DEFAULT => -17
	},
	{#State 20
		DEFAULT => -12
	},
	{#State 21
		ACTIONS => {
			"?" => 32,
			"*" => 44,
			"\$" => 27
		},
		GOTOS => {
			'PLUS-5' => 46,
			'VAR1' => 25,
			'SelectVars' => 43,
			'Var' => 45,
			'VAR2' => 29
		}
	},
	{#State 22
		ACTIONS => {
			"FROM" => 49,
			"WHERE" => 47,
			"FROM NAMED" => 48
		},
		DEFAULT => -44,
		GOTOS => {
			'OPTIONAL-11' => 50,
			'WhereClause' => 52,
			'DatasetClause' => 51
		}
	},
	{#State 23
		DEFAULT => -241
	},
	{#State 24
		DEFAULT => -27,
		GOTOS => {
			'STAR-7' => 53
		}
	},
	{#State 25
		DEFAULT => -144
	},
	{#State 26
		DEFAULT => -34
	},
	{#State 27
		ACTIONS => {
			'BASE' => 72,
			'TRUE' => 71,
			'LANGMATCHES' => 54,
			'OFFSET' => 73,
			'a' => 56,
			'NAMED' => 55,
			'DATATYPE' => 57,
			'ISIRI' => 74,
			'ISLITERAL' => 58,
			'UNION' => 76,
			'ASC' => 75,
			'ISBLANK' => 78,
			'FILTER' => 77,
			'FALSE' => 60,
			'SAMETERM' => 61,
			'LANG' => 62,
			'DISTINCT' => 79,
			'CONSTRUCT' => 64,
			'LIMIT' => 63,
			'STR' => 80,
			'DESC' => 82,
			'NAME' => 81,
			'REDUCED' => 83,
			'REGEX' => 65,
			'ASK' => 66,
			'PREFIX' => 67,
			'BOUND' => 84,
			'FROM' => 68,
			'WHERE' => 85,
			'GRAPH' => 86,
			'DESCRIBE' => 87,
			'SELECT' => 69,
			'ISURI' => 88,
			'OPTIONAL' => 70
		},
		GOTOS => {
			'VARNAME' => 59
		}
	},
	{#State 28
		DEFAULT => -233
	},
	{#State 29
		DEFAULT => -145
	},
	{#State 30
		DEFAULT => -142
	},
	{#State 31
		ACTIONS => {
			":" => 89
		}
	},
	{#State 32
		ACTIONS => {
			'BASE' => 72,
			'TRUE' => 71,
			'LANGMATCHES' => 54,
			'OFFSET' => 73,
			'a' => 56,
			'NAMED' => 55,
			'DATATYPE' => 57,
			'ISIRI' => 74,
			'ISLITERAL' => 58,
			'ASC' => 75,
			'UNION' => 76,
			'FILTER' => 77,
			'ISBLANK' => 78,
			'FALSE' => 60,
			'SAMETERM' => 61,
			'LANG' => 62,
			'DISTINCT' => 79,
			'CONSTRUCT' => 64,
			'LIMIT' => 63,
			'STR' => 80,
			'NAME' => 81,
			'DESC' => 82,
			'REDUCED' => 83,
			'REGEX' => 65,
			'ASK' => 66,
			'PREFIX' => 67,
			'BOUND' => 84,
			'FROM' => 68,
			'WHERE' => 85,
			'GRAPH' => 86,
			'DESCRIBE' => 87,
			'SELECT' => 69,
			'ISURI' => 88,
			'OPTIONAL' => 70
		},
		GOTOS => {
			'VARNAME' => 90
		}
	},
	{#State 33
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31,
			"?" => 32,
			"\$" => 27
		},
		DEFAULT => -33,
		GOTOS => {
			'PrefixedName' => 34,
			'VAR1' => 25,
			'PNAME_LN' => 35,
			'IRI_REF' => 28,
			'PNAME_NS' => 36,
			'IRIref' => 38,
			'VarOrIRIref' => 91,
			'VAR2' => 29,
			'Var' => 30
		}
	},
	{#State 34
		DEFAULT => -234
	},
	{#State 35
		DEFAULT => -235
	},
	{#State 36
		ACTIONS => {
			'NAMED' => 55,
			'DATATYPE' => 57,
			'ISLITERAL' => 58,
			'INTEGER_NO_WS' => 94,
			'REGEX' => 65,
			'ASK' => 66,
			'FROM' => 68,
			'OPTIONAL' => 70,
			'TRUE' => 71,
			'BASE' => 72,
			'OFFSET' => 73,
			'UNION' => 76,
			'ISBLANK' => 78,
			'FILTER' => 77,
			'STR' => 80,
			'DESC' => 82,
			'NAME' => 81,
			'WHERE' => 85,
			'DESCRIBE' => 87,
			'ISURI' => 88,
			'LANGMATCHES' => 54,
			'a' => 56,
			'SAMETERM' => 61,
			'FALSE' => 60,
			'LANG' => 62,
			'LIMIT' => 63,
			'CONSTRUCT' => 64,
			'PREFIX' => 67,
			'SELECT' => 69,
			'ISIRI' => 74,
			'INTEGER_WS' => 95,
			'ASC' => 75,
			'DISTINCT' => 79,
			'REDUCED' => 83,
			'BOUND' => 84,
			'GRAPH' => 86
		},
		DEFAULT => -236,
		GOTOS => {
			'INTEGER' => 93,
			'VARNAME' => 92,
			'PN_LOCAL' => 96
		}
	},
	{#State 37
		DEFAULT => -32
	},
	{#State 38
		DEFAULT => -143
	},
	{#State 39
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE' => 124,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		DEFAULT => -105,
		GOTOS => {
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'TriplesSameSubject' => 121,
			'IRI_REF' => 28,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 123,
			'INTEGER' => 103,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 129,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'OPTIONAL-29' => 107,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'ConstructTriples' => 110,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 40
		DEFAULT => -24,
		GOTOS => {
			'STAR-6' => 133
		}
	},
	{#State 41
		DEFAULT => -7
	},
	{#State 42
		ACTIONS => {
			":" => 23,
			'NAME' => 31
		},
		GOTOS => {
			'PNAME_NS' => 134
		}
	},
	{#State 43
		DEFAULT => -15,
		GOTOS => {
			'STAR-4' => 135
		}
	},
	{#State 44
		DEFAULT => -22
	},
	{#State 45
		DEFAULT => -20
	},
	{#State 46
		ACTIONS => {
			"?" => 32,
			"\$" => 27
		},
		DEFAULT => -21,
		GOTOS => {
			'VAR1' => 25,
			'Var' => 136,
			'VAR2' => 29
		}
	},
	{#State 47
		DEFAULT => -43
	},
	{#State 48
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31
		},
		GOTOS => {
			'NamedGraphClause' => 139,
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'IRIref' => 138,
			'SourceSelector' => 137,
			'PrefixedName' => 34
		}
	},
	{#State 49
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31
		},
		GOTOS => {
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'DefaultGraphClause' => 141,
			'IRIref' => 138,
			'SourceSelector' => 140,
			'PrefixedName' => 34
		}
	},
	{#State 50
		ACTIONS => {
			"{" => 143
		},
		GOTOS => {
			'GroupGraphPattern' => 142
		}
	},
	{#State 51
		DEFAULT => -35
	},
	{#State 52
		DEFAULT => -37
	},
	{#State 53
		ACTIONS => {
			"{" => -44,
			"WHERE" => 47,
			"FROM NAMED" => 48,
			"FROM" => 49
		},
		DEFAULT => -29,
		GOTOS => {
			'OPTIONAL-8' => 146,
			'OPTIONAL-11' => 50,
			'DatasetClause' => 145,
			'WhereClause' => 144
		}
	},
	{#State 54
		DEFAULT => -276
	},
	{#State 55
		DEFAULT => -279
	},
	{#State 56
		DEFAULT => -263
	},
	{#State 57
		DEFAULT => -269
	},
	{#State 58
		DEFAULT => -291
	},
	{#State 59
		DEFAULT => -252
	},
	{#State 60
		DEFAULT => -295
	},
	{#State 61
		DEFAULT => -293
	},
	{#State 62
		DEFAULT => -277
	},
	{#State 63
		DEFAULT => -278
	},
	{#State 64
		DEFAULT => -268
	},
	{#State 65
		DEFAULT => -284
	},
	{#State 66
		DEFAULT => -265
	},
	{#State 67
		DEFAULT => -282
	},
	{#State 68
		DEFAULT => -274
	},
	{#State 69
		DEFAULT => -285
	},
	{#State 70
		DEFAULT => -281
	},
	{#State 71
		DEFAULT => -294
	},
	{#State 72
		DEFAULT => -266
	},
	{#State 73
		DEFAULT => -280
	},
	{#State 74
		DEFAULT => -290
	},
	{#State 75
		DEFAULT => -264
	},
	{#State 76
		DEFAULT => -287
	},
	{#State 77
		DEFAULT => -273
	},
	{#State 78
		DEFAULT => -289
	},
	{#State 79
		DEFAULT => -272
	},
	{#State 80
		DEFAULT => -286
	},
	{#State 81
		DEFAULT => -262
	},
	{#State 82
		DEFAULT => -271
	},
	{#State 83
		DEFAULT => -283
	},
	{#State 84
		DEFAULT => -267
	},
	{#State 85
		DEFAULT => -288
	},
	{#State 86
		DEFAULT => -275
	},
	{#State 87
		DEFAULT => -270
	},
	{#State 88
		DEFAULT => -292
	},
	{#State 89
		DEFAULT => -240
	},
	{#State 90
		DEFAULT => -251
	},
	{#State 91
		DEFAULT => -31
	},
	{#State 92
		ACTIONS => {
			"-" => 147,
			'INTEGER_NO_WS' => 148,
			"_" => 150
		},
		DEFAULT => -247,
		GOTOS => {
			'PN_LOCAL_EXTRA' => 149
		}
	},
	{#State 93
		ACTIONS => {
			'BASE' => 72,
			'TRUE' => 71,
			'LANGMATCHES' => 54,
			'OFFSET' => 73,
			'a' => 56,
			'NAMED' => 55,
			'DATATYPE' => 57,
			'ISIRI' => 74,
			'ISLITERAL' => 58,
			'ASC' => 75,
			'UNION' => 76,
			'FILTER' => 77,
			'ISBLANK' => 78,
			'FALSE' => 60,
			'SAMETERM' => 61,
			'LANG' => 62,
			'DISTINCT' => 79,
			'CONSTRUCT' => 64,
			'LIMIT' => 63,
			'STR' => 80,
			'NAME' => 81,
			'DESC' => 82,
			'REDUCED' => 83,
			'REGEX' => 65,
			'ASK' => 66,
			'PREFIX' => 67,
			'BOUND' => 84,
			'FROM' => 68,
			'WHERE' => 85,
			'GRAPH' => 86,
			'DESCRIBE' => 87,
			'SELECT' => 69,
			'ISURI' => 88,
			'OPTIONAL' => 70
		},
		GOTOS => {
			'VARNAME' => 151
		}
	},
	{#State 94
		DEFAULT => -303
	},
	{#State 95
		DEFAULT => -302
	},
	{#State 96
		DEFAULT => -242
	},
	{#State 97
		DEFAULT => -149
	},
	{#State 98
		DEFAULT => -228
	},
	{#State 99
		DEFAULT => -223
	},
	{#State 100
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31,
			"?" => 32,
			"a" => 153,
			"\$" => 27
		},
		DEFAULT => -300,
		GOTOS => {
			'STAR-56' => 156,
			'Verb' => 154,
			'PrefixedName' => 34,
			'VAR1' => 25,
			'PropertyListNotEmpty' => 152,
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'IRIref' => 38,
			'VarOrIRIref' => 155,
			'VAR2' => 29,
			'Var' => 30
		}
	},
	{#State 101
		DEFAULT => -148
	},
	{#State 102
		DEFAULT => -140
	},
	{#State 103
		DEFAULT => -222
	},
	{#State 104
		DEFAULT => -231
	},
	{#State 105
		DEFAULT => -238
	},
	{#State 106
		DEFAULT => -226
	},
	{#State 107
		ACTIONS => {
			"}" => 157
		}
	},
	{#State 108
		DEFAULT => -230
	},
	{#State 109
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE' => 124,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		DEFAULT => -297,
		GOTOS => {
			'GraphNode' => 158,
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'STAR-55' => 160,
			'VarOrTerm' => 159,
			'INTEGER' => 103,
			'PLUS-40' => 161,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 162,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 110
		DEFAULT => -104
	},
	{#State 111
		DEFAULT => -146
	},
	{#State 112
		DEFAULT => -133
	},
	{#State 113
		DEFAULT => -132
	},
	{#State 114
		DEFAULT => -220
	},
	{#State 115
		DEFAULT => -227
	},
	{#State 116
		ACTIONS => {
			'DOUBLE' => 165,
			'INTEGER_NO_WS' => 94,
			'DECIMAL' => 163,
			'INTEGER_WS' => 95
		},
		GOTOS => {
			'INTEGER' => 164
		}
	},
	{#State 117
		DEFAULT => -221
	},
	{#State 118
		ACTIONS => {
			"\@" => 167,
			"^^" => 170
		},
		DEFAULT => -215,
		GOTOS => {
			'OPTIONAL-51' => 169,
			'LiteralExtra' => 166,
			'LANGTAG' => 168
		}
	},
	{#State 119
		DEFAULT => -219
	},
	{#State 120
		DEFAULT => -151
	},
	{#State 121
		ACTIONS => {
			"." => 173
		},
		DEFAULT => -111,
		GOTOS => {
			'OPTIONAL-32' => 171,
			'PAREN-31' => 172
		}
	},
	{#State 122
		DEFAULT => -229
	},
	{#State 123
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31,
			"?" => 32,
			"a" => 153,
			"\$" => 27
		},
		GOTOS => {
			'Verb' => 154,
			'PrefixedName' => 34,
			'VAR1' => 25,
			'PropertyListNotEmpty' => 174,
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'IRIref' => 38,
			'VarOrIRIref' => 155,
			'VAR2' => 29,
			'Var' => 30
		}
	},
	{#State 124
		DEFAULT => -224
	},
	{#State 125
		DEFAULT => -232
	},
	{#State 126
		DEFAULT => -225
	},
	{#State 127
		DEFAULT => -237
	},
	{#State 128
		DEFAULT => -141
	},
	{#State 129
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31,
			"?" => 32,
			"a" => 153,
			"\$" => 27
		},
		DEFAULT => -123,
		GOTOS => {
			'Verb' => 154,
			'PrefixedName' => 34,
			'VAR1' => 25,
			'PropertyListNotEmpty' => 175,
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'PropertyList' => 176,
			'OPTIONAL-37' => 177,
			'IRIref' => 38,
			'VarOrIRIref' => 155,
			'VAR2' => 29,
			'Var' => 30
		}
	},
	{#State 130
		DEFAULT => -150
	},
	{#State 131
		DEFAULT => -147
	},
	{#State 132
		ACTIONS => {
			'BASE' => 72,
			'TRUE' => 71,
			'LANGMATCHES' => 54,
			'OFFSET' => 73,
			'a' => 56,
			'NAMED' => 55,
			'DATATYPE' => 57,
			'ISIRI' => 74,
			'ISLITERAL' => 58,
			'INTEGER_WS' => 95,
			'ASC' => 75,
			'UNION' => 76,
			'FILTER' => 77,
			'ISBLANK' => 78,
			'FALSE' => 60,
			'SAMETERM' => 61,
			'LANG' => 62,
			'DISTINCT' => 79,
			'CONSTRUCT' => 64,
			'LIMIT' => 63,
			'STR' => 80,
			'NAME' => 81,
			'DESC' => 82,
			'INTEGER_NO_WS' => 94,
			'REDUCED' => 83,
			'REGEX' => 65,
			'ASK' => 66,
			'PREFIX' => 67,
			'BOUND' => 84,
			'FROM' => 68,
			'WHERE' => 85,
			'GRAPH' => 86,
			'DESCRIBE' => 87,
			'SELECT' => 69,
			'ISURI' => 88,
			'OPTIONAL' => 70
		},
		GOTOS => {
			'INTEGER' => 93,
			'VARNAME' => 92,
			'PN_LOCAL' => 178
		}
	},
	{#State 133
		ACTIONS => {
			"FROM" => 49,
			"WHERE" => 47,
			"FROM NAMED" => 48
		},
		DEFAULT => -44,
		GOTOS => {
			'OPTIONAL-11' => 50,
			'WhereClause' => 180,
			'DatasetClause' => 179
		}
	},
	{#State 134
		ACTIONS => {
			'URI' => 6
		},
		GOTOS => {
			'IRI_REF' => 181
		}
	},
	{#State 135
		ACTIONS => {
			"FROM" => 49,
			"WHERE" => 47,
			"FROM NAMED" => 48
		},
		DEFAULT => -44,
		GOTOS => {
			'OPTIONAL-11' => 50,
			'WhereClause' => 183,
			'DatasetClause' => 182
		}
	},
	{#State 136
		DEFAULT => -19
	},
	{#State 137
		DEFAULT => -41
	},
	{#State 138
		DEFAULT => -42
	},
	{#State 139
		DEFAULT => -39
	},
	{#State 140
		DEFAULT => -40
	},
	{#State 141
		DEFAULT => -38
	},
	{#State 142
		DEFAULT => -45
	},
	{#State 143
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE' => 124,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		DEFAULT => -68,
		GOTOS => {
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'TriplesSameSubject' => 186,
			'IRI_REF' => 28,
			'TriplesBlock' => 184,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 123,
			'INTEGER' => 103,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 129,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'OPTIONAL-17' => 185,
			'RDFLiteral' => 131
		}
	},
	{#State 144
		DEFAULT => -28
	},
	{#State 145
		DEFAULT => -26
	},
	{#State 146
		ACTIONS => {
			"ORDER BY" => 187
		},
		DEFAULT => -47,
		GOTOS => {
			'SolutionModifier' => 189,
			'OrderClause' => 190,
			'OPTIONAL-12' => 188
		}
	},
	{#State 147
		ACTIONS => {
			'NAME' => 191
		}
	},
	{#State 148
		DEFAULT => -248
	},
	{#State 149
		DEFAULT => -244
	},
	{#State 150
		ACTIONS => {
			'NAME' => 192
		}
	},
	{#State 151
		ACTIONS => {
			"-" => 147,
			'INTEGER_NO_WS' => 148,
			"_" => 150
		},
		DEFAULT => -246,
		GOTOS => {
			'PN_LOCAL_EXTRA' => 193
		}
	},
	{#State 152
		ACTIONS => {
			"]" => 194
		}
	},
	{#State 153
		DEFAULT => -131
	},
	{#State 154
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			'DOUBLE' => 124,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		GOTOS => {
			'GraphNode' => 196,
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'Object' => 197,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 159,
			'INTEGER' => 103,
			'ObjectList' => 195,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 162,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 155
		DEFAULT => -130
	},
	{#State 156
		ACTIONS => {
			'WS' => 199,
			"]" => 198
		}
	},
	{#State 157
		DEFAULT => -106
	},
	{#State 158
		DEFAULT => -136
	},
	{#State 159
		DEFAULT => -138
	},
	{#State 160
		ACTIONS => {
			'WS' => 200,
			")" => 201
		}
	},
	{#State 161
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			")" => 203,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE' => 124,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		GOTOS => {
			'GraphNode' => 202,
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 159,
			'INTEGER' => 103,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 162,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 162
		DEFAULT => -139
	},
	{#State 163
		DEFAULT => -261
	},
	{#State 164
		DEFAULT => -259
	},
	{#State 165
		DEFAULT => -260
	},
	{#State 166
		DEFAULT => -214
	},
	{#State 167
		ACTIONS => {
			'NAME' => 204
		}
	},
	{#State 168
		DEFAULT => -217
	},
	{#State 169
		DEFAULT => -216
	},
	{#State 170
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31
		},
		GOTOS => {
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'IRIref' => 205,
			'PrefixedName' => 34
		}
	},
	{#State 171
		DEFAULT => -112
	},
	{#State 172
		DEFAULT => -110
	},
	{#State 173
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE' => 124,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		DEFAULT => -108,
		GOTOS => {
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'TriplesSameSubject' => 121,
			'IRI_REF' => 28,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'OPTIONAL-30' => 207,
			'VarOrTerm' => 123,
			'INTEGER' => 103,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 129,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'ConstructTriples' => 206,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 174
		DEFAULT => -113
	},
	{#State 175
		DEFAULT => -122
	},
	{#State 176
		DEFAULT => -114
	},
	{#State 177
		DEFAULT => -124
	},
	{#State 178
		DEFAULT => -243
	},
	{#State 179
		DEFAULT => -23
	},
	{#State 180
		ACTIONS => {
			"ORDER BY" => 187
		},
		DEFAULT => -47,
		GOTOS => {
			'SolutionModifier' => 208,
			'OrderClause' => 190,
			'OPTIONAL-12' => 188
		}
	},
	{#State 181
		DEFAULT => -11
	},
	{#State 182
		DEFAULT => -14
	},
	{#State 183
		ACTIONS => {
			"ORDER BY" => 187
		},
		DEFAULT => -47,
		GOTOS => {
			'SolutionModifier' => 209,
			'OrderClause' => 190,
			'OPTIONAL-12' => 188
		}
	},
	{#State 184
		DEFAULT => -67
	},
	{#State 185
		DEFAULT => -75,
		GOTOS => {
			'STAR-21' => 210
		}
	},
	{#State 186
		ACTIONS => {
			"." => 212
		},
		DEFAULT => -83,
		GOTOS => {
			'OPTIONAL-24' => 211,
			'PAREN-23' => 213
		}
	},
	{#State 187
		ACTIONS => {
			":" => 23,
			'LANGMATCHES' => 214,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			"ASC" => 229,
			'ISBLANK' => 231,
			"\$" => 27,
			'SAMETERM' => 219,
			'LANG' => 220,
			'STR' => 232,
			"DESC" => 233,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			'BOUND' => 234,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'RegexExpression' => 226,
			'OrderDirection' => 216,
			'PLUS-16' => 218,
			'VAR1' => 25,
			'Constraint' => 230,
			'FunctionCall' => 228,
			'IRI_REF' => 28,
			'VAR2' => 29,
			'Var' => 221,
			'BrackettedExpression' => 222,
			'PrefixedName' => 34,
			'BuiltInCall' => 224,
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'OrderCondition' => 235,
			'IRIref' => 225
		}
	},
	{#State 188
		ACTIONS => {
			"LIMIT" => 238,
			"OFFSET" => 239
		},
		DEFAULT => -49,
		GOTOS => {
			'LimitOffsetClauses' => 242,
			'LimitClause' => 243,
			'OPTIONAL-13' => 240,
			'OffsetClause' => 241
		}
	},
	{#State 189
		DEFAULT => -30
	},
	{#State 190
		DEFAULT => -46
	},
	{#State 191
		DEFAULT => -249
	},
	{#State 192
		DEFAULT => -250
	},
	{#State 193
		DEFAULT => -245
	},
	{#State 194
		DEFAULT => -134
	},
	{#State 195
		DEFAULT => -120,
		GOTOS => {
			'STAR-36' => 244
		}
	},
	{#State 196
		DEFAULT => -129
	},
	{#State 197
		DEFAULT => -127,
		GOTOS => {
			'STAR-39' => 245
		}
	},
	{#State 198
		DEFAULT => -301
	},
	{#State 199
		DEFAULT => -299
	},
	{#State 200
		DEFAULT => -296
	},
	{#State 201
		DEFAULT => -298
	},
	{#State 202
		DEFAULT => -135
	},
	{#State 203
		DEFAULT => -137
	},
	{#State 204
		DEFAULT => -257,
		GOTOS => {
			'STAR-54' => 246
		}
	},
	{#State 205
		DEFAULT => -218
	},
	{#State 206
		DEFAULT => -107
	},
	{#State 207
		DEFAULT => -109
	},
	{#State 208
		DEFAULT => -25
	},
	{#State 209
		DEFAULT => -16
	},
	{#State 210
		ACTIONS => {
			"GRAPH" => 251,
			"}" => 247,
			"{" => 143,
			"OPTIONAL" => 258,
			"FILTER" => 254
		},
		GOTOS => {
			'Filter' => 256,
			'PAREN-20' => 253,
			'GroupGraphPattern' => 250,
			'OptionalGraphPattern' => 248,
			'GGPAtom' => 252,
			'GroupOrUnionGraphPattern' => 257,
			'GraphPatternNotTriples' => 249,
			'GraphGraphPattern' => 255
		}
	},
	{#State 211
		DEFAULT => -84
	},
	{#State 212
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE' => 124,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		DEFAULT => -80,
		GOTOS => {
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'OPTIONAL-22' => 259,
			'TriplesSameSubject' => 186,
			'IRI_REF' => 28,
			'TriplesBlock' => 260,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 123,
			'INTEGER' => 103,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 129,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 213
		DEFAULT => -82
	},
	{#State 214
		ACTIONS => {
			"(" => 261
		}
	},
	{#State 215
		ACTIONS => {
			"(" => 262
		}
	},
	{#State 216
		ACTIONS => {
			"(" => 223
		},
		GOTOS => {
			'BrackettedExpression' => 263
		}
	},
	{#State 217
		ACTIONS => {
			"(" => 264
		}
	},
	{#State 218
		ACTIONS => {
			":" => 23,
			'LANGMATCHES' => 214,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			"ASC" => 229,
			'ISBLANK' => 231,
			"\$" => 27,
			'SAMETERM' => 219,
			'LANG' => 220,
			'STR' => 232,
			"DESC" => 233,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			'BOUND' => 234,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		DEFAULT => -59,
		GOTOS => {
			'RegexExpression' => 226,
			'OrderDirection' => 216,
			'BrackettedExpression' => 222,
			'PrefixedName' => 34,
			'VAR1' => 25,
			'Constraint' => 230,
			'FunctionCall' => 228,
			'PNAME_LN' => 35,
			'BuiltInCall' => 224,
			'OrderCondition' => 265,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'IRIref' => 225,
			'VAR2' => 29,
			'Var' => 221
		}
	},
	{#State 219
		ACTIONS => {
			"(" => 266
		}
	},
	{#State 220
		ACTIONS => {
			"(" => 267
		}
	},
	{#State 221
		DEFAULT => -62
	},
	{#State 222
		DEFAULT => -95
	},
	{#State 223
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 285,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 224
		DEFAULT => -96
	},
	{#State 225
		ACTIONS => {
			"(" => 290
		},
		GOTOS => {
			'NIL' => 291,
			'ArgList' => 289
		}
	},
	{#State 226
		DEFAULT => -206
	},
	{#State 227
		ACTIONS => {
			"(" => 292
		}
	},
	{#State 228
		DEFAULT => -97
	},
	{#State 229
		DEFAULT => -63
	},
	{#State 230
		DEFAULT => -61
	},
	{#State 231
		ACTIONS => {
			"(" => 293
		}
	},
	{#State 232
		ACTIONS => {
			"(" => 294
		}
	},
	{#State 233
		DEFAULT => -64
	},
	{#State 234
		ACTIONS => {
			"(" => 295
		}
	},
	{#State 235
		DEFAULT => -58
	},
	{#State 236
		ACTIONS => {
			"(" => 296
		}
	},
	{#State 237
		ACTIONS => {
			"(" => 297
		}
	},
	{#State 238
		ACTIONS => {
			'INTEGER_NO_WS' => 94,
			'INTEGER_WS' => 95
		},
		GOTOS => {
			'INTEGER' => 298
		}
	},
	{#State 239
		ACTIONS => {
			'INTEGER_NO_WS' => 94,
			'INTEGER_WS' => 95
		},
		GOTOS => {
			'INTEGER' => 299
		}
	},
	{#State 240
		DEFAULT => -50
	},
	{#State 241
		ACTIONS => {
			"LIMIT" => 238
		},
		DEFAULT => -54,
		GOTOS => {
			'LimitClause' => 301,
			'OPTIONAL-15' => 300
		}
	},
	{#State 242
		DEFAULT => -48
	},
	{#State 243
		ACTIONS => {
			"OFFSET" => 239
		},
		DEFAULT => -52,
		GOTOS => {
			'OPTIONAL-14' => 303,
			'OffsetClause' => 302
		}
	},
	{#State 244
		ACTIONS => {
			";" => 305
		},
		DEFAULT => -121,
		GOTOS => {
			'PAREN-35' => 304
		}
	},
	{#State 245
		ACTIONS => {
			"," => 306
		},
		DEFAULT => -128,
		GOTOS => {
			'PAREN-38' => 307
		}
	},
	{#State 246
		ACTIONS => {
			"-" => 308
		},
		DEFAULT => -258,
		GOTOS => {
			'PAREN-53' => 309
		}
	},
	{#State 247
		DEFAULT => -76
	},
	{#State 248
		DEFAULT => -85
	},
	{#State 249
		DEFAULT => -77
	},
	{#State 250
		DEFAULT => -92,
		GOTOS => {
			'STAR-26' => 310
		}
	},
	{#State 251
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31,
			"?" => 32,
			"\$" => 27
		},
		GOTOS => {
			'PrefixedName' => 34,
			'VAR1' => 25,
			'PNAME_LN' => 35,
			'IRI_REF' => 28,
			'PNAME_NS' => 36,
			'IRIref' => 38,
			'VarOrIRIref' => 311,
			'VAR2' => 29,
			'Var' => 30
		}
	},
	{#State 252
		ACTIONS => {
			"." => 312
		},
		DEFAULT => -70,
		GOTOS => {
			'OPTIONAL-18' => 313
		}
	},
	{#State 253
		DEFAULT => -74
	},
	{#State 254
		ACTIONS => {
			'STR' => 232,
			":" => 23,
			'URI' => 6,
			'NAME' => 31,
			'LANGMATCHES' => 214,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'BOUND' => 234,
			"(" => 223,
			'SAMETERM' => 219,
			'ISBLANK' => 231,
			'ISURI' => 236,
			'LANG' => 220,
			"REGEX" => 237
		},
		GOTOS => {
			'RegexExpression' => 226,
			'BrackettedExpression' => 222,
			'PrefixedName' => 34,
			'PNAME_LN' => 35,
			'BuiltInCall' => 224,
			'FunctionCall' => 228,
			'Constraint' => 314,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'IRIref' => 225
		}
	},
	{#State 255
		DEFAULT => -87
	},
	{#State 256
		DEFAULT => -78
	},
	{#State 257
		DEFAULT => -86
	},
	{#State 258
		ACTIONS => {
			"{" => 143
		},
		GOTOS => {
			'GroupGraphPattern' => 315
		}
	},
	{#State 259
		DEFAULT => -81
	},
	{#State 260
		DEFAULT => -79
	},
	{#State 261
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 316,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 262
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 317,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 263
		DEFAULT => -60
	},
	{#State 264
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 318,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 265
		DEFAULT => -57
	},
	{#State 266
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 319,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 267
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 320,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 268
		DEFAULT => -193
	},
	{#State 269
		ACTIONS => {
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 116,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			'ISBLANK' => 231,
			"\$" => 27,
			'SAMETERM' => 219,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 321,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 270
		DEFAULT => -161
	},
	{#State 271
		DEFAULT => -159,
		GOTOS => {
			'STAR-44' => 322
		}
	},
	{#State 272
		DEFAULT => -173,
		GOTOS => {
			'STAR-46' => 323
		}
	},
	{#State 273
		ACTIONS => {
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 116,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			'ISBLANK' => 231,
			"\$" => 27,
			'SAMETERM' => 219,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 324,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 274
		DEFAULT => -192
	},
	{#State 275
		DEFAULT => -190
	},
	{#State 276
		ACTIONS => {
			"!=" => 331,
			"<" => 325,
			"=" => 332,
			">=" => 327,
			"<=" => 328,
			">" => 329
		},
		DEFAULT => -163,
		GOTOS => {
			'OPTIONAL-45' => 330,
			'RelationalExpressionExtra' => 326
		}
	},
	{#State 277
		DEFAULT => -194
	},
	{#State 278
		DEFAULT => -188
	},
	{#State 279
		DEFAULT => -187
	},
	{#State 280
		DEFAULT => -189
	},
	{#State 281
		DEFAULT => -180,
		GOTOS => {
			'STAR-47' => 333
		}
	},
	{#State 282
		ACTIONS => {
			"(" => 290
		},
		DEFAULT => -212,
		GOTOS => {
			'NIL' => 291,
			'ArgList' => 334,
			'OPTIONAL-50' => 335
		}
	},
	{#State 283
		ACTIONS => {
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 116,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			'ISBLANK' => 231,
			"\$" => 27,
			'SAMETERM' => 219,
			'DECIMAL' => 336,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 339,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 337,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 338,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 284
		DEFAULT => -152
	},
	{#State 285
		ACTIONS => {
			")" => 340
		}
	},
	{#State 286
		DEFAULT => -155,
		GOTOS => {
			'STAR-42' => 341
		}
	},
	{#State 287
		DEFAULT => -171
	},
	{#State 288
		DEFAULT => -191
	},
	{#State 289
		DEFAULT => -98
	},
	{#State 290
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			'DATATYPE' => 215,
			'ISLITERAL' => 217,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			"+" => 283,
			'ISIRI' => 227,
			'INTEGER_WS' => 95,
			'STRING' => 118,
			'ISBLANK' => 231,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'NAME' => 31,
			'URI' => 6,
			'DOUBLE' => 124,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'ISURI' => 236,
			"REGEX" => 237
		},
		DEFAULT => -297,
		GOTOS => {
			'BooleanLiteral' => 268,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'VAR1' => 25,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'UnaryExpression' => 281,
			'IRIref' => 282,
			'NumericLiteralPositive' => 114,
			'RegexExpression' => 226,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'IRI_REF' => 28,
			'ConditionalOrExpression' => 284,
			'STAR-55' => 160,
			'Expression' => 342,
			'INTEGER_POSITIVE' => 126,
			'ConditionalAndExpression' => 286,
			'PNAME_NS' => 36,
			'AdditiveExpression' => 287,
			'RDFLiteral' => 288
		}
	},
	{#State 291
		DEFAULT => -103
	},
	{#State 292
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 343,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 293
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 344,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 294
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 345,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 295
		ACTIONS => {
			"?" => 32,
			"\$" => 27
		},
		GOTOS => {
			'VAR1' => 25,
			'Var' => 346,
			'VAR2' => 29
		}
	},
	{#State 296
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 347,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 297
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 348,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 298
		DEFAULT => -65
	},
	{#State 299
		DEFAULT => -66
	},
	{#State 300
		DEFAULT => -56
	},
	{#State 301
		DEFAULT => -53
	},
	{#State 302
		DEFAULT => -51
	},
	{#State 303
		DEFAULT => -55
	},
	{#State 304
		DEFAULT => -119
	},
	{#State 305
		ACTIONS => {
			":" => 23,
			'URI' => 6,
			'NAME' => 31,
			"?" => 32,
			"a" => 153,
			"\$" => 27
		},
		DEFAULT => -117,
		GOTOS => {
			'OPTIONAL-34' => 351,
			'Verb' => 350,
			'PrefixedName' => 34,
			'PAREN-33' => 349,
			'VAR1' => 25,
			'PNAME_LN' => 35,
			'PNAME_NS' => 36,
			'IRI_REF' => 28,
			'IRIref' => 38,
			'VarOrIRIref' => 155,
			'VAR2' => 29,
			'Var' => 30
		}
	},
	{#State 306
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			'DOUBLE' => 124,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		GOTOS => {
			'GraphNode' => 196,
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'Object' => 352,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 159,
			'INTEGER' => 103,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 162,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 307
		DEFAULT => -126
	},
	{#State 308
		ACTIONS => {
			'NAME' => 354
		},
		GOTOS => {
			'PLUS-52' => 353
		}
	},
	{#State 309
		DEFAULT => -256
	},
	{#State 310
		ACTIONS => {
			"UNION" => 355
		},
		DEFAULT => -93,
		GOTOS => {
			'PAREN-25' => 356
		}
	},
	{#State 311
		ACTIONS => {
			"{" => 143
		},
		GOTOS => {
			'GroupGraphPattern' => 357
		}
	},
	{#State 312
		DEFAULT => -69
	},
	{#State 313
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE' => 124,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		DEFAULT => -72,
		GOTOS => {
			'BooleanLiteral' => 97,
			'OPTIONAL-19' => 359,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'TriplesSameSubject' => 186,
			'IRI_REF' => 28,
			'TriplesBlock' => 358,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 123,
			'INTEGER' => 103,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 129,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 314
		DEFAULT => -94
	},
	{#State 315
		DEFAULT => -88
	},
	{#State 316
		ACTIONS => {
			"," => 360
		}
	},
	{#State 317
		ACTIONS => {
			")" => 361
		}
	},
	{#State 318
		ACTIONS => {
			")" => 362
		}
	},
	{#State 319
		ACTIONS => {
			"," => 363
		}
	},
	{#State 320
		ACTIONS => {
			")" => 364
		}
	},
	{#State 321
		DEFAULT => -186
	},
	{#State 322
		ACTIONS => {
			"&&" => 365
		},
		DEFAULT => -160,
		GOTOS => {
			'PAREN-43' => 366
		}
	},
	{#State 323
		ACTIONS => {
			"-" => 367,
			"+" => 370,
			'INTEGER_NEGATIVE' => 98,
			'DECIMAL_NEGATIVE' => 122,
			'DOUBLE_NEGATIVE' => 108
		},
		DEFAULT => -174,
		GOTOS => {
			'NumericLiteralPositive' => 369,
			'DOUBLE_POSITIVE' => 115,
			'AdditiveExpressionExtra' => 368,
			'INTEGER_POSITIVE' => 126,
			'NumericLiteralNegative' => 371,
			'DECIMAL_POSITIVE' => 106
		}
	},
	{#State 324
		DEFAULT => -184
	},
	{#State 325
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 372,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 326
		DEFAULT => -162
	},
	{#State 327
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 373,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 328
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 374,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 329
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 375,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 330
		DEFAULT => -164
	},
	{#State 331
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 376,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 332
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 377,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 333
		ACTIONS => {
			"*" => 378,
			"/" => 380
		},
		DEFAULT => -181,
		GOTOS => {
			'MultiplicativeExpressionExtra' => 379
		}
	},
	{#State 334
		DEFAULT => -211
	},
	{#State 335
		DEFAULT => -213
	},
	{#State 336
		DEFAULT => -223
	},
	{#State 337
		DEFAULT => -222
	},
	{#State 338
		DEFAULT => -185
	},
	{#State 339
		DEFAULT => -224
	},
	{#State 340
		DEFAULT => -195
	},
	{#State 341
		ACTIONS => {
			"||" => 382
		},
		DEFAULT => -156,
		GOTOS => {
			'PAREN-41' => 381
		}
	},
	{#State 342
		DEFAULT => -101,
		GOTOS => {
			'STAR-28' => 383
		}
	},
	{#State 343
		ACTIONS => {
			")" => 384
		}
	},
	{#State 344
		ACTIONS => {
			")" => 385
		}
	},
	{#State 345
		ACTIONS => {
			")" => 386
		}
	},
	{#State 346
		ACTIONS => {
			")" => 387
		}
	},
	{#State 347
		ACTIONS => {
			")" => 388
		}
	},
	{#State 348
		ACTIONS => {
			"," => 389
		}
	},
	{#State 349
		DEFAULT => -116
	},
	{#State 350
		ACTIONS => {
			":" => 23,
			"+" => 116,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"\$" => 27,
			'DECIMAL' => 99,
			"[" => 100,
			'DECIMAL_NEGATIVE' => 122,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			'NAME' => 31,
			'URI' => 6,
			'DOUBLE' => 124,
			"?" => 32,
			"FALSE" => 125,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 109,
			"_:" => 132
		},
		GOTOS => {
			'GraphNode' => 196,
			'BooleanLiteral' => 97,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'NIL' => 120,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'Object' => 197,
			'NumericLiteral' => 101,
			'VAR2' => 29,
			'Var' => 102,
			'VarOrTerm' => 159,
			'INTEGER' => 103,
			'ObjectList' => 390,
			'INTEGER_POSITIVE' => 126,
			'ANON' => 105,
			'TriplesNode' => 162,
			'GraphTerm' => 128,
			'BLANK_NODE_LABEL' => 127,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PNAME_LN' => 35,
			'BlankNode' => 130,
			'PNAME_NS' => 36,
			'IRIref' => 111,
			'BlankNodePropertyList' => 112,
			'Collection' => 113,
			'RDFLiteral' => 131
		}
	},
	{#State 351
		DEFAULT => -118
	},
	{#State 352
		DEFAULT => -125
	},
	{#State 353
		ACTIONS => {
			'NAME' => 391
		},
		DEFAULT => -255
	},
	{#State 354
		DEFAULT => -254
	},
	{#State 355
		ACTIONS => {
			"{" => 143
		},
		GOTOS => {
			'GroupGraphPattern' => 392
		}
	},
	{#State 356
		DEFAULT => -91
	},
	{#State 357
		DEFAULT => -89
	},
	{#State 358
		DEFAULT => -71
	},
	{#State 359
		DEFAULT => -73
	},
	{#State 360
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 393,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 361
		DEFAULT => -199
	},
	{#State 362
		DEFAULT => -205
	},
	{#State 363
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 394,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 364
		DEFAULT => -197
	},
	{#State 365
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 395,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 366
		DEFAULT => -158
	},
	{#State 367
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 396,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 368
		DEFAULT => -172
	},
	{#State 369
		DEFAULT => -177
	},
	{#State 370
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 336,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 339,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'MultiplicativeExpression' => 397,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 337,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 371
		DEFAULT => -178
	},
	{#State 372
		DEFAULT => -167
	},
	{#State 373
		DEFAULT => -170
	},
	{#State 374
		DEFAULT => -169
	},
	{#State 375
		DEFAULT => -168
	},
	{#State 376
		DEFAULT => -166
	},
	{#State 377
		DEFAULT => -165
	},
	{#State 378
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 398,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 379
		DEFAULT => -179
	},
	{#State 380
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'Var' => 277,
			'VAR2' => 29,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 399,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 381
		DEFAULT => -154
	},
	{#State 382
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 400,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 383
		ACTIONS => {
			"," => 402,
			")" => 403
		},
		GOTOS => {
			'PAREN-27' => 401
		}
	},
	{#State 384
		DEFAULT => -202
	},
	{#State 385
		DEFAULT => -204
	},
	{#State 386
		DEFAULT => -196
	},
	{#State 387
		DEFAULT => -200
	},
	{#State 388
		DEFAULT => -203
	},
	{#State 389
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 404,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 390
		DEFAULT => -115
	},
	{#State 391
		DEFAULT => -253
	},
	{#State 392
		DEFAULT => -90
	},
	{#State 393
		ACTIONS => {
			")" => 405
		}
	},
	{#State 394
		ACTIONS => {
			")" => 406
		}
	},
	{#State 395
		DEFAULT => -157
	},
	{#State 396
		DEFAULT => -176
	},
	{#State 397
		DEFAULT => -175
	},
	{#State 398
		DEFAULT => -182
	},
	{#State 399
		DEFAULT => -183
	},
	{#State 400
		DEFAULT => -153
	},
	{#State 401
		DEFAULT => -100
	},
	{#State 402
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 407,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 403
		DEFAULT => -102
	},
	{#State 404
		ACTIONS => {
			"," => 408
		},
		DEFAULT => -209,
		GOTOS => {
			'OPTIONAL-49' => 409,
			'PAREN-48' => 410
		}
	},
	{#State 405
		DEFAULT => -198
	},
	{#State 406
		DEFAULT => -201
	},
	{#State 407
		DEFAULT => -99
	},
	{#State 408
		ACTIONS => {
			"-" => 269,
			":" => 23,
			'LANGMATCHES' => 214,
			"+" => 283,
			'DATATYPE' => 215,
			'ISIRI' => 227,
			'ISLITERAL' => 217,
			'STRING' => 118,
			'INTEGER_WS' => 95,
			'INTEGER_NEGATIVE' => 98,
			"!" => 273,
			'ISBLANK' => 231,
			'SAMETERM' => 219,
			"\$" => 27,
			'DECIMAL' => 99,
			'LANG' => 220,
			'DECIMAL_NEGATIVE' => 122,
			'STR' => 232,
			'DOUBLE' => 124,
			'URI' => 6,
			'NAME' => 31,
			'INTEGER_NO_WS' => 94,
			"TRUE" => 104,
			"?" => 32,
			"FALSE" => 125,
			'BOUND' => 234,
			'DOUBLE_NEGATIVE' => 108,
			"(" => 223,
			'ISURI' => 236,
			"REGEX" => 237
		},
		GOTOS => {
			'BooleanLiteral' => 268,
			'RegexExpression' => 226,
			'NumericLiteralPositive' => 114,
			'DOUBLE_POSITIVE' => 115,
			'RelationalExpression' => 270,
			'ValueLogical' => 271,
			'MultiplicativeExpression' => 272,
			'NumericLiteralNegative' => 117,
			'NumericLiteralUnsigned' => 119,
			'VAR1' => 25,
			'IRI_REF' => 28,
			'NumericLiteral' => 274,
			'IRIrefOrFunction' => 275,
			'NumericExpression' => 276,
			'ConditionalOrExpression' => 284,
			'VAR2' => 29,
			'Var' => 277,
			'INTEGER' => 103,
			'Expression' => 411,
			'BrackettedExpression' => 278,
			'INTEGER_POSITIVE' => 126,
			'PrefixedName' => 34,
			'DECIMAL_POSITIVE' => 106,
			'ConditionalAndExpression' => 286,
			'PrimaryExpression' => 279,
			'PNAME_LN' => 35,
			'BuiltInCall' => 280,
			'PNAME_NS' => 36,
			'UnaryExpression' => 281,
			'AdditiveExpression' => 287,
			'IRIref' => 282,
			'RDFLiteral' => 288
		}
	},
	{#State 409
		ACTIONS => {
			")" => 412
		}
	},
	{#State 410
		DEFAULT => -208
	},
	{#State 411
		DEFAULT => -207
	},
	{#State 412
		DEFAULT => -210
	}
],
                                  yyrules  =>
[
	[#Rule _SUPERSTART
		 '$start', 2, undef
#line 5948 SPARQL.pm
	],
	[#Rule Query_1
		 'Query', 2,
sub {
#line 4 "SPARQL.yp"
 { method => 'SELECT', %{ $_[1] }, %{ $_[2] } } }
#line 5955 SPARQL.pm
	],
	[#Rule Query_2
		 'Query', 2,
sub {
#line 5 "SPARQL.yp"
 { method => 'CONSTRUCT', %{ $_[1] }, %{ $_[2] } } }
#line 5962 SPARQL.pm
	],
	[#Rule Query_3
		 'Query', 2,
sub {
#line 6 "SPARQL.yp"
 { method => 'DESCRIBE', %{ $_[1] }, %{ $_[2] } } }
#line 5969 SPARQL.pm
	],
	[#Rule Query_4
		 'Query', 2,
sub {
#line 7 "SPARQL.yp"
 { method => 'ASK', %{ $_[1] }, %{ $_[2] } } }
#line 5976 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-1', 1,
sub {
#line 10 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 5983 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-1', 0,
sub {
#line 10 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 5990 SPARQL.pm
	],
	[#Rule _STAR_LIST_2
		 'STAR-2', 2,
sub {
#line 10 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 5997 SPARQL.pm
	],
	[#Rule _STAR_LIST_2
		 'STAR-2', 0,
sub {
#line 10 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6004 SPARQL.pm
	],
	[#Rule Prologue_9
		 'Prologue', 2,
sub {
#line 10 "SPARQL.yp"

										my $ret	= +{
													namespaces	=> { map {%$_} @{$_[2]{children}} },
													map { %$_ } (@{$_[1]{children}})
												};
										$ret;
									}
#line 6017 SPARQL.pm
	],
	[#Rule BaseDecl_10
		 'BaseDecl', 2,
sub {
#line 18 "SPARQL.yp"
 +{ 'base' => $_[2] } }
#line 6024 SPARQL.pm
	],
	[#Rule PrefixDecl_11
		 'PrefixDecl', 3,
sub {
#line 20 "SPARQL.yp"
 +{ $_[2] => $_[3][1] } }
#line 6031 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-3', 1,
sub {
#line 22 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6038 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-3', 0,
sub {
#line 22 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6045 SPARQL.pm
	],
	[#Rule _STAR_LIST_4
		 'STAR-4', 2,
sub {
#line 22 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6052 SPARQL.pm
	],
	[#Rule _STAR_LIST_4
		 'STAR-4', 0,
sub {
#line 22 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6059 SPARQL.pm
	],
	[#Rule SelectQuery_16
		 'SelectQuery', 6,
sub {
#line 23 "SPARQL.yp"

					my $sel_modifier	= $_[2]{children}[0];
					my $sol_modifier	= $_[6];
					my $ret	= +{
						variables	=> $_[3],
						sources		=> $_[4]{children},
						triples		=> $_[5],
					};
					
					if (my $o = $sol_modifier->{orderby}){
						$ret->{options}{orderby}	= $o;
					}
					if (my $l = $sol_modifier->{limitoffset}) {
						my %data	= @$l;
						while (my($k,$v) = each(%data)) {
							$ret->{options}{$k}	= $v;
						}
					}
					
					if (ref($sel_modifier) and Scalar::Util::reftype($sel_modifier) eq 'ARRAY') {
						my %data	= @$sel_modifier;
						while (my($k,$v) = each(%data)) {
							$ret->{options}{$k}	= $v;
						}
					}
					
					return $ret;
				}
#line 6093 SPARQL.pm
	],
	[#Rule SelectModifier_17
		 'SelectModifier', 1,
sub {
#line 52 "SPARQL.yp"
 [ distinct => 1 ] }
#line 6100 SPARQL.pm
	],
	[#Rule SelectModifier_18
		 'SelectModifier', 1,
sub {
#line 53 "SPARQL.yp"
 [ reduced => 1 ] }
#line 6107 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-5', 2,
sub {
#line 55 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6114 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-5', 1,
sub {
#line 55 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6121 SPARQL.pm
	],
	[#Rule SelectVars_21
		 'SelectVars', 1,
sub {
#line 55 "SPARQL.yp"
 $_[1]{children} }
#line 6128 SPARQL.pm
	],
	[#Rule SelectVars_22
		 'SelectVars', 1,
sub {
#line 56 "SPARQL.yp"
 ['*'] }
#line 6135 SPARQL.pm
	],
	[#Rule _STAR_LIST_6
		 'STAR-6', 2,
sub {
#line 58 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6142 SPARQL.pm
	],
	[#Rule _STAR_LIST_6
		 'STAR-6', 0,
sub {
#line 58 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6149 SPARQL.pm
	],
	[#Rule ConstructQuery_25
		 'ConstructQuery', 5,
sub {
#line 59 "SPARQL.yp"

					my $template	= $_[2];
					my $ret	= +{
						construct_triples	=> $template,
						sources				=> $_[3]{children},
						triples				=> $_[4],
					};
					
					return $ret;
				}
#line 6165 SPARQL.pm
	],
	[#Rule _STAR_LIST_7
		 'STAR-7', 2,
sub {
#line 70 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6172 SPARQL.pm
	],
	[#Rule _STAR_LIST_7
		 'STAR-7', 0,
sub {
#line 70 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6179 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-8', 1,
sub {
#line 70 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6186 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-8', 0,
sub {
#line 70 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6193 SPARQL.pm
	],
	[#Rule DescribeQuery_30
		 'DescribeQuery', 5,
sub {
#line 71 "SPARQL.yp"

					my $modifier	= $_[5];
					my $ret	= +{
						variables	=> $_[2],
						sources		=> $_[3]{children},
						triples		=> ${ $_[4]{children} || [] }[0],
					};
					$ret->{triples}	= [] if (not defined($ret->{triples}));
					if (my $o = $modifier->{orderby}){
						$ret->{orderby}	= $o;
					}
					$ret;
				}
#line 6212 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-9', 2,
sub {
#line 84 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6219 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-9', 1,
sub {
#line 84 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6226 SPARQL.pm
	],
	[#Rule DescribeVars_33
		 'DescribeVars', 1,
sub {
#line 84 "SPARQL.yp"
 $_[1]{children} }
#line 6233 SPARQL.pm
	],
	[#Rule DescribeVars_34
		 'DescribeVars', 1,
sub {
#line 85 "SPARQL.yp"
 '*' }
#line 6240 SPARQL.pm
	],
	[#Rule _STAR_LIST_10
		 'STAR-10', 2,
sub {
#line 87 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6247 SPARQL.pm
	],
	[#Rule _STAR_LIST_10
		 'STAR-10', 0,
sub {
#line 87 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6254 SPARQL.pm
	],
	[#Rule AskQuery_37
		 'AskQuery', 3,
sub {
#line 88 "SPARQL.yp"

		my $ret	= +{
			sources		=> $_[2]{children},
			triples		=> $_[3],
			variables	=> [],
		};
		return $ret;
	}
#line 6268 SPARQL.pm
	],
	[#Rule DatasetClause_38
		 'DatasetClause', 2,
sub {
#line 97 "SPARQL.yp"
 $_[2] }
#line 6275 SPARQL.pm
	],
	[#Rule DatasetClause_39
		 'DatasetClause', 2,
sub {
#line 98 "SPARQL.yp"
 $_[2] }
#line 6282 SPARQL.pm
	],
	[#Rule DefaultGraphClause_40
		 'DefaultGraphClause', 1,
sub {
#line 101 "SPARQL.yp"
 $_[1] }
#line 6289 SPARQL.pm
	],
	[#Rule NamedGraphClause_41
		 'NamedGraphClause', 1,
sub {
#line 103 "SPARQL.yp"
 [ @{ $_[1] }, 'NAMED' ] }
#line 6296 SPARQL.pm
	],
	[#Rule SourceSelector_42
		 'SourceSelector', 1,
sub {
#line 105 "SPARQL.yp"
 $_[1] }
#line 6303 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-11', 1,
sub {
#line 107 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6310 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-11', 0,
sub {
#line 107 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6317 SPARQL.pm
	],
	[#Rule WhereClause_45
		 'WhereClause', 2,
sub {
#line 107 "SPARQL.yp"

																my $ggp	= $_[2];
																shift(@$ggp);
																$ggp;
															}
#line 6328 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-12', 1,
sub {
#line 113 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6335 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-12', 0,
sub {
#line 113 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6342 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-13', 1,
sub {
#line 113 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6349 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-13', 0,
sub {
#line 113 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6356 SPARQL.pm
	],
	[#Rule SolutionModifier_50
		 'SolutionModifier', 2,
sub {
#line 114 "SPARQL.yp"

		return +{ orderby => $_[1]{children}[0], limitoffset => $_[2]{children}[0] };
	}
#line 6365 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-14', 1,
sub {
#line 118 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6372 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-14', 0,
sub {
#line 118 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6379 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-15', 1,
sub {
#line 119 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6386 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-15', 0,
sub {
#line 119 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6393 SPARQL.pm
	],
	[#Rule LimitOffsetClauses_55
		 'LimitOffsetClauses', 2,
sub {
#line 118 "SPARQL.yp"
 [ @{$_[1]}, @{ $_[2]{children}[0] || [] } ] }
#line 6400 SPARQL.pm
	],
	[#Rule LimitOffsetClauses_56
		 'LimitOffsetClauses', 2,
sub {
#line 119 "SPARQL.yp"
 [ @{$_[1]}, @{ $_[2]{children}[0] || [] } ] }
#line 6407 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-16', 2,
sub {
#line 122 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6414 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-16', 1,
sub {
#line 122 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6421 SPARQL.pm
	],
	[#Rule OrderClause_59
		 'OrderClause', 2,
sub {
#line 123 "SPARQL.yp"

		my $order	= $_[2]{children};
		return $order;
	}
#line 6431 SPARQL.pm
	],
	[#Rule OrderCondition_60
		 'OrderCondition', 2,
sub {
#line 128 "SPARQL.yp"
 [ $_[1], $_[2] ] }
#line 6438 SPARQL.pm
	],
	[#Rule OrderCondition_61
		 'OrderCondition', 1,
sub {
#line 129 "SPARQL.yp"
 [ 'ASC', $_[1] ] }
#line 6445 SPARQL.pm
	],
	[#Rule OrderCondition_62
		 'OrderCondition', 1,
sub {
#line 130 "SPARQL.yp"
 [ 'ASC', $_[1] ] }
#line 6452 SPARQL.pm
	],
	[#Rule OrderDirection_63
		 'OrderDirection', 1,
sub {
#line 132 "SPARQL.yp"
 'ASC' }
#line 6459 SPARQL.pm
	],
	[#Rule OrderDirection_64
		 'OrderDirection', 1,
sub {
#line 133 "SPARQL.yp"
 'DESC' }
#line 6466 SPARQL.pm
	],
	[#Rule LimitClause_65
		 'LimitClause', 2,
sub {
#line 136 "SPARQL.yp"
 [ limit => $_[2] ] }
#line 6473 SPARQL.pm
	],
	[#Rule OffsetClause_66
		 'OffsetClause', 2,
sub {
#line 138 "SPARQL.yp"
 [ offset => $_[2] ] }
#line 6480 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-17', 1,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6487 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-17', 0,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6494 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-18', 1,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6501 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-18', 0,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6508 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-19', 1,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6515 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-19', 0,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6522 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-20', 3,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 6529 SPARQL.pm
	],
	[#Rule _STAR_LIST_21
		 'STAR-21', 2,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6536 SPARQL.pm
	],
	[#Rule _STAR_LIST_21
		 'STAR-21', 0,
sub {
#line 140 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6543 SPARQL.pm
	],
	[#Rule GroupGraphPattern_76
		 'GroupGraphPattern', 4,
sub {
#line 141 "SPARQL.yp"

						my @ggp	= ( @{ $_[2]{children}[0] || [] } );
						if (@{ $_[3]{children} }) {
							my $opt				= $_[3]{children};
							
							my $index	= 0;
							for ($index = 0; $index < $#{$opt}; $index += 3) {
								my $ggpatom			= $opt->[ $index ];
								my $triplesblock	= $opt->[ $index + 2 ]{children}[0];
								my @data			= ($ggpatom);
								if (@{ $triplesblock || [] }) {
									push(@data, @{ $triplesblock || [] });
								}
								push(@ggp, @data);
							}
						}
						
						if (scalar(@ggp) > 1) {
							for (my $i = $#ggp; $i > 0; $i--) {
								if ($ggp[$i][0] eq 'FILTER' and $ggp[$i-1][0] eq 'FILTER') {
									my ($filter)	= splice(@ggp, $i, 1, ());
									my $expr2		= $filter->[1];
									my $expr1		= $ggp[$i-1][1];
									$ggp[$i-1][1]	= [ '&&', $expr1, $expr2 ];
								}
							}
						}
						
						return [ 'GGP', @ggp ];
					}
#line 6579 SPARQL.pm
	],
	[#Rule GGPAtom_77
		 'GGPAtom', 1,
sub {
#line 172 "SPARQL.yp"
 $_[1] }
#line 6586 SPARQL.pm
	],
	[#Rule GGPAtom_78
		 'GGPAtom', 1,
sub {
#line 173 "SPARQL.yp"
 [ 'FILTER', $_[1] ] }
#line 6593 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-22', 1,
sub {
#line 176 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6600 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-22', 0,
sub {
#line 176 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6607 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-23', 2,
sub {
#line 176 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 6614 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-24', 1,
sub {
#line 176 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6621 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-24', 0,
sub {
#line 176 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6628 SPARQL.pm
	],
	[#Rule TriplesBlock_84
		 'TriplesBlock', 2,
sub {
#line 177 "SPARQL.yp"

		my @triples	= @{ $_[1] };
		if (@{ $_[2]{children} }) {
			foreach my $child (@{ $_[2]{children} }) {
				foreach my $data (@{ $child->{children} }) {
					push(@triples, @$data);
				}
			}
		}
		
		
		\@triples;
	}
#line 6647 SPARQL.pm
	],
	[#Rule GraphPatternNotTriples_85
		 'GraphPatternNotTriples', 1,
sub {
#line 193 "SPARQL.yp"
 $_[1] }
#line 6654 SPARQL.pm
	],
	[#Rule GraphPatternNotTriples_86
		 'GraphPatternNotTriples', 1,
sub {
#line 194 "SPARQL.yp"
 $_[1] }
#line 6661 SPARQL.pm
	],
	[#Rule GraphPatternNotTriples_87
		 'GraphPatternNotTriples', 1,
sub {
#line 195 "SPARQL.yp"
 $_[1] }
#line 6668 SPARQL.pm
	],
	[#Rule OptionalGraphPattern_88
		 'OptionalGraphPattern', 2,
sub {
#line 198 "SPARQL.yp"

																	my $ggp	= $_[2];
																	shift(@$ggp);
																	return ['OPTIONAL', $ggp]
																}
#line 6679 SPARQL.pm
	],
	[#Rule GraphGraphPattern_89
		 'GraphGraphPattern', 3,
sub {
#line 204 "SPARQL.yp"

																	my $ggp	= $_[3];
																	shift(@$ggp);
																	['GRAPH', $_[2], $ggp]
																}
#line 6690 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-25', 2,
sub {
#line 210 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 6697 SPARQL.pm
	],
	[#Rule _STAR_LIST_26
		 'STAR-26', 2,
sub {
#line 210 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6704 SPARQL.pm
	],
	[#Rule _STAR_LIST_26
		 'STAR-26', 0,
sub {
#line 210 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6711 SPARQL.pm
	],
	[#Rule GroupOrUnionGraphPattern_93
		 'GroupOrUnionGraphPattern', 2,
sub {
#line 211 "SPARQL.yp"

		if (@{ $_[2]{children} }) {
			my $total	= $#{ $_[2]{children} };
			my @ggp		= map { [ @{ $_ }[ 1 .. $#{ $_ } ] ] }
						map { $_[2]{children}[$_] } grep { $_ % 2 == 1 } (0 .. $total);
			my $ggp	= $_[1];
			shift(@$ggp);
			my $data	= [
				'UNION',
				$ggp,
				@ggp
			];
			return $data;
		} else {
			return $_[1];
		}
	}
#line 6734 SPARQL.pm
	],
	[#Rule Filter_94
		 'Filter', 2,
sub {
#line 229 "SPARQL.yp"

#									warn 'FILTER CONSTRAINT: ' . Dumper($_[2]);
								$_[2]
							}
#line 6744 SPARQL.pm
	],
	[#Rule Constraint_95
		 'Constraint', 1,
sub {
#line 234 "SPARQL.yp"
 $_[1] }
#line 6751 SPARQL.pm
	],
	[#Rule Constraint_96
		 'Constraint', 1,
sub {
#line 235 "SPARQL.yp"
 $_[1] }
#line 6758 SPARQL.pm
	],
	[#Rule Constraint_97
		 'Constraint', 1,
sub {
#line 236 "SPARQL.yp"
 $_[1] }
#line 6765 SPARQL.pm
	],
	[#Rule FunctionCall_98
		 'FunctionCall', 2,
sub {
#line 240 "SPARQL.yp"

		$_[0]->new_function_expression( $_[1], @{ $_[2] } )
	}
#line 6774 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-27', 2,
sub {
#line 244 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 6781 SPARQL.pm
	],
	[#Rule _STAR_LIST_28
		 'STAR-28', 2,
sub {
#line 244 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6788 SPARQL.pm
	],
	[#Rule _STAR_LIST_28
		 'STAR-28', 0,
sub {
#line 244 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6795 SPARQL.pm
	],
	[#Rule ArgList_102
		 'ArgList', 4,
sub {
#line 245 "SPARQL.yp"

			my $args	= [
				$_[2],
				map { $_ } @{ $_[3]{children} }
			];
			
			$args;
		}
#line 6809 SPARQL.pm
	],
	[#Rule ArgList_103
		 'ArgList', 1,
sub {
#line 253 "SPARQL.yp"
 [] }
#line 6816 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-29', 1,
sub {
#line 255 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6823 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-29', 0,
sub {
#line 255 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6830 SPARQL.pm
	],
	[#Rule ConstructTemplate_106
		 'ConstructTemplate', 3,
sub {
#line 256 "SPARQL.yp"

	if (@{ $_[2]{children} }) {
		return $_[2]{children}[0];
	} else {
		return {};
	}
}
#line 6843 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-30', 1,
sub {
#line 264 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6850 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-30', 0,
sub {
#line 264 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6857 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-31', 2,
sub {
#line 264 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 6864 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-32', 1,
sub {
#line 264 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6871 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-32', 0,
sub {
#line 264 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6878 SPARQL.pm
	],
	[#Rule ConstructTriples_112
		 'ConstructTriples', 2,
sub {
#line 265 "SPARQL.yp"

		my @triples	= @{ $_[1] };
		if (@{ $_[2]{children} }) {
			my $triples	= $_[2]{children}[0]{children}[0];
			push(@triples, @{ $triples || [] });
		}
		return \@triples;
	}
#line 6892 SPARQL.pm
	],
	[#Rule TriplesSameSubject_113
		 'TriplesSameSubject', 2,
sub {
#line 274 "SPARQL.yp"

															my ($props, $triples)	= @{ $_[2] };
															my $subj	= $_[1];
															
															my @triples;
															push(@triples, map { [ $subj, @{$_} ] } @$props);
															push(@triples, @{ $triples });
															return \@triples;
														}
#line 6907 SPARQL.pm
	],
	[#Rule TriplesSameSubject_114
		 'TriplesSameSubject', 2,
sub {
#line 283 "SPARQL.yp"

															my ($node, $triples)	= @{ $_[1] };
															my @triples				= @$triples;
															
															my ($props, $prop_triples)	= @{ $_[2] };
															if (@$props) {
																push(@triples, @{ $prop_triples });
																foreach my $child (@$props) {
																	push(@triples, [ $node, @$child ]);
																	
																}
															}
															
															return \@triples;
														}
#line 6928 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-33', 2,
sub {
#line 300 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 6935 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-34', 1,
sub {
#line 300 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 6942 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-34', 0,
sub {
#line 300 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6949 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-35', 2,
sub {
#line 300 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 6956 SPARQL.pm
	],
	[#Rule _STAR_LIST_36
		 'STAR-36', 2,
sub {
#line 300 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 6963 SPARQL.pm
	],
	[#Rule _STAR_LIST_36
		 'STAR-36', 0,
sub {
#line 300 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 6970 SPARQL.pm
	],
	[#Rule PropertyListNotEmpty_121
		 'PropertyListNotEmpty', 3,
sub {
#line 301 "SPARQL.yp"

															my $objectlist	= $_[2];
															my @objects		= @{ $objectlist->[0] };
															my @triples		= @{ $objectlist->[1] };
															
															my $prop = [
																(map { [ $_[1], $_ ] } @objects),
																(map {
																	my $o = $_;
																	my @objects	= (ref($_->{children}[1][0]) and reftype($_->{children}[1][0]) eq 'ARRAY')
																				? @{ $_->{children}[1][0] }
																				: ();
																	push(@triples, @{ $_->{children}[1][1] || [] });
																	map {
																		[
																			$o->{children}[0], $_
																		]
																	} @objects;
																} @{$_[3]{children}})
															];
															return [ $prop, \@triples ];
														}
#line 6998 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-37', 1,
sub {
#line 324 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 7005 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-37', 0,
sub {
#line 324 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7012 SPARQL.pm
	],
	[#Rule PropertyList_124
		 'PropertyList', 1,
sub {
#line 325 "SPARQL.yp"

		if (@{ $_[1]{children} }) {
			return $_[1]{children}[0];
		} else {
			return [ [], [] ];
		}
	}
#line 7025 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-38', 2,
sub {
#line 333 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 7032 SPARQL.pm
	],
	[#Rule _STAR_LIST_39
		 'STAR-39', 2,
sub {
#line 333 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 7039 SPARQL.pm
	],
	[#Rule _STAR_LIST_39
		 'STAR-39', 0,
sub {
#line 333 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7046 SPARQL.pm
	],
	[#Rule ObjectList_128
		 'ObjectList', 2,
sub {
#line 334 "SPARQL.yp"

		my @objects	= ($_[1][0], map { $_->[0] } @{ $_[2]{children} });
		my @triples	= (@{ $_[1][1] }, map { @{ $_->[1] } } @{ $_[2]{children} });
		my $data	= [ \@objects, \@triples ];
		return $data;
	}
#line 7058 SPARQL.pm
	],
	[#Rule Object_129
		 'Object', 1,
sub {
#line 341 "SPARQL.yp"
 $_[1] }
#line 7065 SPARQL.pm
	],
	[#Rule Verb_130
		 'Verb', 1,
sub {
#line 343 "SPARQL.yp"
 $_[1] }
#line 7072 SPARQL.pm
	],
	[#Rule Verb_131
		 'Verb', 1,
sub {
#line 344 "SPARQL.yp"
 $_[0]->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type') }
#line 7079 SPARQL.pm
	],
	[#Rule TriplesNode_132
		 'TriplesNode', 1,
sub {
#line 347 "SPARQL.yp"
 return $_[1] }
#line 7086 SPARQL.pm
	],
	[#Rule TriplesNode_133
		 'TriplesNode', 1,
sub {
#line 348 "SPARQL.yp"
 return $_[1] }
#line 7093 SPARQL.pm
	],
	[#Rule BlankNodePropertyList_134
		 'BlankNodePropertyList', 3,
sub {
#line 352 "SPARQL.yp"

		my $node	= $_[0]->new_blank();
		my ($props, $triples)	= @{ $_[2] };
		my @triples	= @$triples;
		
		push(@triples, map { [$node, @$_] } @$props);
		return [ $node, \@triples ];
	}
#line 7107 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-40', 2,
sub {
#line 361 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 7114 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-40', 1,
sub {
#line 361 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 7121 SPARQL.pm
	],
	[#Rule Collection_137
		 'Collection', 3,
sub {
#line 362 "SPARQL.yp"

		my $self		= $_[0];
		my @children	= @{ $_[2]{children}};
		my @triples;
		
		my $node;
		my $last_node;
		while (my $child = shift(@children)) {
			my $p_first		= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#first');
			my $p_rest		= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#rest');
			my $cur_node	= $self->new_blank();
			if (defined($last_node)) {
				push(@triples, [ $last_node, $p_rest, $cur_node ]);
			}
			
			my ($child_node, $triples)	= @$child;
			push(@triples, [ $cur_node, $p_first, $child_node ]);
			unless (defined($node)) {
				$node	= $cur_node;
			}
			$last_node	= $cur_node;
			push(@triples, @$triples);
		}
		
		my $p_rest		= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#rest');
		my $nil			= $self->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil');
		push(@triples, [ $last_node, $p_rest, $nil ]);
		return [ $node, \@triples ];
	}
#line 7156 SPARQL.pm
	],
	[#Rule GraphNode_138
		 'GraphNode', 1,
sub {
#line 392 "SPARQL.yp"
 [$_[1], []] }
#line 7163 SPARQL.pm
	],
	[#Rule GraphNode_139
		 'GraphNode', 1,
sub {
#line 393 "SPARQL.yp"
 $_[1] }
#line 7170 SPARQL.pm
	],
	[#Rule VarOrTerm_140
		 'VarOrTerm', 1,
sub {
#line 396 "SPARQL.yp"
 $_[1] }
#line 7177 SPARQL.pm
	],
	[#Rule VarOrTerm_141
		 'VarOrTerm', 1,
sub {
#line 397 "SPARQL.yp"
 $_[1] }
#line 7184 SPARQL.pm
	],
	[#Rule VarOrIRIref_142
		 'VarOrIRIref', 1,
sub {
#line 400 "SPARQL.yp"
 $_[1] }
#line 7191 SPARQL.pm
	],
	[#Rule VarOrIRIref_143
		 'VarOrIRIref', 1,
sub {
#line 401 "SPARQL.yp"
 $_[1] }
#line 7198 SPARQL.pm
	],
	[#Rule Var_144
		 'Var', 1,
sub {
#line 404 "SPARQL.yp"
 $_[1] }
#line 7205 SPARQL.pm
	],
	[#Rule Var_145
		 'Var', 1,
sub {
#line 405 "SPARQL.yp"
 $_[1] }
#line 7212 SPARQL.pm
	],
	[#Rule GraphTerm_146
		 'GraphTerm', 1,
sub {
#line 408 "SPARQL.yp"
 $_[1] }
#line 7219 SPARQL.pm
	],
	[#Rule GraphTerm_147
		 'GraphTerm', 1,
sub {
#line 409 "SPARQL.yp"
 $_[1] }
#line 7226 SPARQL.pm
	],
	[#Rule GraphTerm_148
		 'GraphTerm', 1,
sub {
#line 410 "SPARQL.yp"
 $_[1] }
#line 7233 SPARQL.pm
	],
	[#Rule GraphTerm_149
		 'GraphTerm', 1,
sub {
#line 411 "SPARQL.yp"
 $_[1] }
#line 7240 SPARQL.pm
	],
	[#Rule GraphTerm_150
		 'GraphTerm', 1,
sub {
#line 412 "SPARQL.yp"
 $_[1] }
#line 7247 SPARQL.pm
	],
	[#Rule GraphTerm_151
		 'GraphTerm', 1,
sub {
#line 413 "SPARQL.yp"
 $_[1] }
#line 7254 SPARQL.pm
	],
	[#Rule Expression_152
		 'Expression', 1,
sub {
#line 416 "SPARQL.yp"
 $_[1] }
#line 7261 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-41', 2,
sub {
#line 418 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 7268 SPARQL.pm
	],
	[#Rule _STAR_LIST_42
		 'STAR-42', 2,
sub {
#line 418 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 7275 SPARQL.pm
	],
	[#Rule _STAR_LIST_42
		 'STAR-42', 0,
sub {
#line 418 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7282 SPARQL.pm
	],
	[#Rule ConditionalOrExpression_156
		 'ConditionalOrExpression', 2,
sub {
#line 419 "SPARQL.yp"

		my $expr	= $_[1];
		if (@{ $_[2]{children} }) {
			$expr	= [ '||', $expr, @{ $_[2]{children} } ];
		}
		$expr;
	}
#line 7295 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-43', 2,
sub {
#line 427 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 7302 SPARQL.pm
	],
	[#Rule _STAR_LIST_44
		 'STAR-44', 2,
sub {
#line 427 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 7309 SPARQL.pm
	],
	[#Rule _STAR_LIST_44
		 'STAR-44', 0,
sub {
#line 427 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7316 SPARQL.pm
	],
	[#Rule ConditionalAndExpression_160
		 'ConditionalAndExpression', 2,
sub {
#line 428 "SPARQL.yp"

		my $expr	= $_[1];
		if (@{ $_[2]{children} }) {
			$expr	= [ '&&', $expr, @{ $_[2]{children} } ];
		}
		$expr;
	}
#line 7329 SPARQL.pm
	],
	[#Rule ValueLogical_161
		 'ValueLogical', 1,
sub {
#line 436 "SPARQL.yp"
 $_[1] }
#line 7336 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-45', 1,
sub {
#line 438 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 7343 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-45', 0,
sub {
#line 438 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7350 SPARQL.pm
	],
	[#Rule RelationalExpression_164
		 'RelationalExpression', 2,
sub {
#line 439 "SPARQL.yp"

		my $expr	= $_[1];
		if (@{ $_[2]{children} }) {
			my $more	= $_[2]{children}[0];
			$expr	= [ $more->[0], $expr, $more->[1] ];
		}
		$expr;
	}
#line 7364 SPARQL.pm
	],
	[#Rule RelationalExpressionExtra_165
		 'RelationalExpressionExtra', 2,
sub {
#line 448 "SPARQL.yp"
 [ '==', $_[2] ] }
#line 7371 SPARQL.pm
	],
	[#Rule RelationalExpressionExtra_166
		 'RelationalExpressionExtra', 2,
sub {
#line 449 "SPARQL.yp"
 [ '!=', $_[2] ] }
#line 7378 SPARQL.pm
	],
	[#Rule RelationalExpressionExtra_167
		 'RelationalExpressionExtra', 2,
sub {
#line 450 "SPARQL.yp"
 [ '<', $_[2] ] }
#line 7385 SPARQL.pm
	],
	[#Rule RelationalExpressionExtra_168
		 'RelationalExpressionExtra', 2,
sub {
#line 451 "SPARQL.yp"
 [ '>', $_[2] ] }
#line 7392 SPARQL.pm
	],
	[#Rule RelationalExpressionExtra_169
		 'RelationalExpressionExtra', 2,
sub {
#line 452 "SPARQL.yp"
 [ '<=', $_[2] ] }
#line 7399 SPARQL.pm
	],
	[#Rule RelationalExpressionExtra_170
		 'RelationalExpressionExtra', 2,
sub {
#line 453 "SPARQL.yp"
 [ '>=', $_[2] ] }
#line 7406 SPARQL.pm
	],
	[#Rule NumericExpression_171
		 'NumericExpression', 1,
sub {
#line 456 "SPARQL.yp"
 $_[1] }
#line 7413 SPARQL.pm
	],
	[#Rule _STAR_LIST_46
		 'STAR-46', 2,
sub {
#line 458 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 7420 SPARQL.pm
	],
	[#Rule _STAR_LIST_46
		 'STAR-46', 0,
sub {
#line 458 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7427 SPARQL.pm
	],
	[#Rule AdditiveExpression_174
		 'AdditiveExpression', 2,
sub {
#line 459 "SPARQL.yp"

		my $expr	= $_[1];
		foreach my $extra (@{ $_[2]{children} }) {
			$expr	= [ $extra->[0], $expr, $extra->[1] ];
		}
		return $expr
	}
#line 7440 SPARQL.pm
	],
	[#Rule AdditiveExpressionExtra_175
		 'AdditiveExpressionExtra', 2,
sub {
#line 466 "SPARQL.yp"
 ['+',$_[2]] }
#line 7447 SPARQL.pm
	],
	[#Rule AdditiveExpressionExtra_176
		 'AdditiveExpressionExtra', 2,
sub {
#line 467 "SPARQL.yp"
 ['-',$_[2]] }
#line 7454 SPARQL.pm
	],
	[#Rule AdditiveExpressionExtra_177
		 'AdditiveExpressionExtra', 1,
sub {
#line 468 "SPARQL.yp"
 $_[1] }
#line 7461 SPARQL.pm
	],
	[#Rule AdditiveExpressionExtra_178
		 'AdditiveExpressionExtra', 1,
sub {
#line 469 "SPARQL.yp"
 $_[1] }
#line 7468 SPARQL.pm
	],
	[#Rule _STAR_LIST_47
		 'STAR-47', 2,
sub {
#line 472 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 7475 SPARQL.pm
	],
	[#Rule _STAR_LIST_47
		 'STAR-47', 0,
sub {
#line 472 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7482 SPARQL.pm
	],
	[#Rule MultiplicativeExpression_181
		 'MultiplicativeExpression', 2,
sub {
#line 473 "SPARQL.yp"

		my $expr	= $_[1];
		foreach my $extra (@{ $_[2]{children} }) {
			 $expr	= [ $extra->[0], $expr, $extra->[1] ];
		}
		$expr
}
#line 7495 SPARQL.pm
	],
	[#Rule MultiplicativeExpressionExtra_182
		 'MultiplicativeExpressionExtra', 2,
sub {
#line 480 "SPARQL.yp"
 [ '*', $_[2] ] }
#line 7502 SPARQL.pm
	],
	[#Rule MultiplicativeExpressionExtra_183
		 'MultiplicativeExpressionExtra', 2,
sub {
#line 481 "SPARQL.yp"
 [ '/', $_[2] ] }
#line 7509 SPARQL.pm
	],
	[#Rule UnaryExpression_184
		 'UnaryExpression', 2,
sub {
#line 483 "SPARQL.yp"
 ['!', $_[2]] }
#line 7516 SPARQL.pm
	],
	[#Rule UnaryExpression_185
		 'UnaryExpression', 2,
sub {
#line 484 "SPARQL.yp"
 $_[2] }
#line 7523 SPARQL.pm
	],
	[#Rule UnaryExpression_186
		 'UnaryExpression', 2,
sub {
#line 485 "SPARQL.yp"
 ['-', $_[2]] }
#line 7530 SPARQL.pm
	],
	[#Rule UnaryExpression_187
		 'UnaryExpression', 1,
sub {
#line 486 "SPARQL.yp"
 $_[1] }
#line 7537 SPARQL.pm
	],
	[#Rule PrimaryExpression_188
		 'PrimaryExpression', 1,
sub {
#line 489 "SPARQL.yp"
 $_[1] }
#line 7544 SPARQL.pm
	],
	[#Rule PrimaryExpression_189
		 'PrimaryExpression', 1,
sub {
#line 490 "SPARQL.yp"
 $_[1] }
#line 7551 SPARQL.pm
	],
	[#Rule PrimaryExpression_190
		 'PrimaryExpression', 1,
sub {
#line 491 "SPARQL.yp"
 $_[1] }
#line 7558 SPARQL.pm
	],
	[#Rule PrimaryExpression_191
		 'PrimaryExpression', 1,
sub {
#line 492 "SPARQL.yp"
 $_[1] }
#line 7565 SPARQL.pm
	],
	[#Rule PrimaryExpression_192
		 'PrimaryExpression', 1,
sub {
#line 493 "SPARQL.yp"
 $_[1] }
#line 7572 SPARQL.pm
	],
	[#Rule PrimaryExpression_193
		 'PrimaryExpression', 1,
sub {
#line 494 "SPARQL.yp"
 $_[1] }
#line 7579 SPARQL.pm
	],
	[#Rule PrimaryExpression_194
		 'PrimaryExpression', 1,
sub {
#line 495 "SPARQL.yp"
 $_[1] }
#line 7586 SPARQL.pm
	],
	[#Rule BrackettedExpression_195
		 'BrackettedExpression', 3,
sub {
#line 498 "SPARQL.yp"
 $_[2] }
#line 7593 SPARQL.pm
	],
	[#Rule BuiltInCall_196
		 'BuiltInCall', 4,
sub {
#line 500 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sop:str'), $_[3] ) }
#line 7600 SPARQL.pm
	],
	[#Rule BuiltInCall_197
		 'BuiltInCall', 4,
sub {
#line 501 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sparql:lang'), $_[3] ) }
#line 7607 SPARQL.pm
	],
	[#Rule BuiltInCall_198
		 'BuiltInCall', 6,
sub {
#line 502 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sparql:langmatches'), $_[3], $_[5] ) }
#line 7614 SPARQL.pm
	],
	[#Rule BuiltInCall_199
		 'BuiltInCall', 4,
sub {
#line 503 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sparql:datatype'), $_[3] ) }
#line 7621 SPARQL.pm
	],
	[#Rule BuiltInCall_200
		 'BuiltInCall', 4,
sub {
#line 504 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sop:isBound'), $_[3] ) }
#line 7628 SPARQL.pm
	],
	[#Rule BuiltInCall_201
		 'BuiltInCall', 6,
sub {
#line 505 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sparql:sameTerm'), $_[3], $_[5] ) }
#line 7635 SPARQL.pm
	],
	[#Rule BuiltInCall_202
		 'BuiltInCall', 4,
sub {
#line 506 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sop:isIRI'), $_[3] ) }
#line 7642 SPARQL.pm
	],
	[#Rule BuiltInCall_203
		 'BuiltInCall', 4,
sub {
#line 507 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sop:isURI'), $_[3] ) }
#line 7649 SPARQL.pm
	],
	[#Rule BuiltInCall_204
		 'BuiltInCall', 4,
sub {
#line 508 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sop:isBlank'), $_[3] ) }
#line 7656 SPARQL.pm
	],
	[#Rule BuiltInCall_205
		 'BuiltInCall', 4,
sub {
#line 509 "SPARQL.yp"
 $_[0]->new_function_expression( $_[0]->new_uri('sop:isLiteral'), $_[3] ) }
#line 7663 SPARQL.pm
	],
	[#Rule BuiltInCall_206
		 'BuiltInCall', 1,
sub {
#line 510 "SPARQL.yp"
 $_[1] }
#line 7670 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-48', 2,
sub {
#line 513 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 7677 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-49', 1,
sub {
#line 513 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 7684 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-49', 0,
sub {
#line 513 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7691 SPARQL.pm
	],
	[#Rule RegexExpression_210
		 'RegexExpression', 7,
sub {
#line 514 "SPARQL.yp"

		my @data	= ('~~', $_[3], $_[5]);
		if (scalar(@{ $_[6]->{children} })) {
			push(@data, $_[6]->{children}[0]);
		}
		return \@data;
	}
#line 7704 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-50', 1,
sub {
#line 522 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 7711 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-50', 0,
sub {
#line 522 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7718 SPARQL.pm
	],
	[#Rule IRIrefOrFunction_213
		 'IRIrefOrFunction', 2,
sub {
#line 523 "SPARQL.yp"

		my $self	= $_[0];
		my $uri		= $_[1];
		my $args	= $_[2]{children}[0];
		
		if (defined($args)) {
			return $self->new_function_expression( $uri, @$args )
		} else {
			return $uri;
		}
	}
#line 7735 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-51', 1,
sub {
#line 535 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 7742 SPARQL.pm
	],
	[#Rule _OPTIONAL
		 'OPTIONAL-51', 0,
sub {
#line 535 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 7749 SPARQL.pm
	],
	[#Rule RDFLiteral_216
		 'RDFLiteral', 2,
sub {
#line 535 "SPARQL.yp"

											my $self	= $_[0];
											my %extra	= @{ $_[2]{children}[0] || [] };
											$self->new_literal( $_[1], @extra{'lang','datatype'} );
										}
#line 7760 SPARQL.pm
	],
	[#Rule LiteralExtra_217
		 'LiteralExtra', 1,
sub {
#line 541 "SPARQL.yp"
 [ lang => $_[1] ] }
#line 7767 SPARQL.pm
	],
	[#Rule LiteralExtra_218
		 'LiteralExtra', 2,
sub {
#line 542 "SPARQL.yp"
 [ datatype => $_[2] ] }
#line 7774 SPARQL.pm
	],
	[#Rule NumericLiteral_219
		 'NumericLiteral', 1,
sub {
#line 545 "SPARQL.yp"
 my $self = $_[0]; my ($value, $type) = @{$_[1]}; $self->new_literal( $value, undef, $self->new_uri($type) ) }
#line 7781 SPARQL.pm
	],
	[#Rule NumericLiteral_220
		 'NumericLiteral', 1,
sub {
#line 546 "SPARQL.yp"
 my $self = $_[0]; my ($value, $type) = @{$_[1]}; $self->new_literal( $value, undef, $self->new_uri($type) ) }
#line 7788 SPARQL.pm
	],
	[#Rule NumericLiteral_221
		 'NumericLiteral', 1,
sub {
#line 547 "SPARQL.yp"
 my $self = $_[0]; my ($value, $type) = @{$_[1]}; $self->new_literal( $value, undef, $self->new_uri($type) ) }
#line 7795 SPARQL.pm
	],
	[#Rule NumericLiteralUnsigned_222
		 'NumericLiteralUnsigned', 1,
sub {
#line 550 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#integer'] }
#line 7802 SPARQL.pm
	],
	[#Rule NumericLiteralUnsigned_223
		 'NumericLiteralUnsigned', 1,
sub {
#line 551 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#decimal'] }
#line 7809 SPARQL.pm
	],
	[#Rule NumericLiteralUnsigned_224
		 'NumericLiteralUnsigned', 1,
sub {
#line 552 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#double'] }
#line 7816 SPARQL.pm
	],
	[#Rule NumericLiteralPositive_225
		 'NumericLiteralPositive', 1,
sub {
#line 556 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#integer'] }
#line 7823 SPARQL.pm
	],
	[#Rule NumericLiteralPositive_226
		 'NumericLiteralPositive', 1,
sub {
#line 557 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#decimal'] }
#line 7830 SPARQL.pm
	],
	[#Rule NumericLiteralPositive_227
		 'NumericLiteralPositive', 1,
sub {
#line 558 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#double'] }
#line 7837 SPARQL.pm
	],
	[#Rule NumericLiteralNegative_228
		 'NumericLiteralNegative', 1,
sub {
#line 562 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#integer'] }
#line 7844 SPARQL.pm
	],
	[#Rule NumericLiteralNegative_229
		 'NumericLiteralNegative', 1,
sub {
#line 563 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#decimal'] }
#line 7851 SPARQL.pm
	],
	[#Rule NumericLiteralNegative_230
		 'NumericLiteralNegative', 1,
sub {
#line 564 "SPARQL.yp"
 [$_[1], 'http://www.w3.org/2001/XMLSchema#double'] }
#line 7858 SPARQL.pm
	],
	[#Rule BooleanLiteral_231
		 'BooleanLiteral', 1,
sub {
#line 567 "SPARQL.yp"
 $_[0]->new_literal( 'true', undef, $_[0]->new_uri( 'http://www.w3.org/2001/XMLSchema#boolean' ) ) }
#line 7865 SPARQL.pm
	],
	[#Rule BooleanLiteral_232
		 'BooleanLiteral', 1,
sub {
#line 568 "SPARQL.yp"
 $_[0]->new_literal( 'false', undef, $_[0]->new_uri( 'http://www.w3.org/2001/XMLSchema#boolean' ) ) }
#line 7872 SPARQL.pm
	],
	[#Rule IRIref_233
		 'IRIref', 1,
sub {
#line 573 "SPARQL.yp"
 $_[1] }
#line 7879 SPARQL.pm
	],
	[#Rule IRIref_234
		 'IRIref', 1,
sub {
#line 574 "SPARQL.yp"
 $_[1] }
#line 7886 SPARQL.pm
	],
	[#Rule PrefixedName_235
		 'PrefixedName', 1,
sub {
#line 577 "SPARQL.yp"
 $_[1] }
#line 7893 SPARQL.pm
	],
	[#Rule PrefixedName_236
		 'PrefixedName', 1,
sub {
#line 578 "SPARQL.yp"
 $_[0]->new_uri([$_[1],'']) }
#line 7900 SPARQL.pm
	],
	[#Rule BlankNode_237
		 'BlankNode', 1,
sub {
#line 581 "SPARQL.yp"
 $_[1] }
#line 7907 SPARQL.pm
	],
	[#Rule BlankNode_238
		 'BlankNode', 1,
sub {
#line 582 "SPARQL.yp"
 $_[1] }
#line 7914 SPARQL.pm
	],
	[#Rule IRI_REF_239
		 'IRI_REF', 1,
sub {
#line 585 "SPARQL.yp"
 $_[0]->new_uri($_[1]) }
#line 7921 SPARQL.pm
	],
	[#Rule PNAME_NS_240
		 'PNAME_NS', 2,
sub {
#line 589 "SPARQL.yp"

			return $_[1];
		}
#line 7930 SPARQL.pm
	],
	[#Rule PNAME_NS_241
		 'PNAME_NS', 1,
sub {
#line 593 "SPARQL.yp"

			return '__DEFAULT__';
		}
#line 7939 SPARQL.pm
	],
	[#Rule PNAME_LN_242
		 'PNAME_LN', 2,
sub {
#line 598 "SPARQL.yp"

	return $_[0]->new_uri([$_[1], $_[2]]);
}
#line 7948 SPARQL.pm
	],
	[#Rule BLANK_NODE_LABEL_243
		 'BLANK_NODE_LABEL', 2,
sub {
#line 602 "SPARQL.yp"

											my $self	= $_[0];
											my $name	= $_[2];
											$self->register_blank_node( $name );
											return $self->new_blank( $name );
										}
#line 7960 SPARQL.pm
	],
	[#Rule PN_LOCAL_244
		 'PN_LOCAL', 2,
sub {
#line 610 "SPARQL.yp"

			my $name	= $_[1];
			my $extra	= $_[2];
			return join('',$name,$extra);
		}
#line 7971 SPARQL.pm
	],
	[#Rule PN_LOCAL_245
		 'PN_LOCAL', 3,
sub {
#line 615 "SPARQL.yp"

			my $int		= $_[1];
			my $name	= $_[2];
			my $extra	= $_[3];
			return join('',$int,$name,$extra);
		}
#line 7983 SPARQL.pm
	],
	[#Rule PN_LOCAL_246
		 'PN_LOCAL', 2,
sub {
#line 621 "SPARQL.yp"

			my $int		= $_[1];
			my $name	= $_[2];
			return join('',$int,$name);
		}
#line 7994 SPARQL.pm
	],
	[#Rule PN_LOCAL_247
		 'PN_LOCAL', 1,
sub {
#line 626 "SPARQL.yp"
 $_[1] }
#line 8001 SPARQL.pm
	],
	[#Rule PN_LOCAL_EXTRA_248
		 'PN_LOCAL_EXTRA', 1,
sub {
#line 629 "SPARQL.yp"
 return $_[1] }
#line 8008 SPARQL.pm
	],
	[#Rule PN_LOCAL_EXTRA_249
		 'PN_LOCAL_EXTRA', 2,
sub {
#line 630 "SPARQL.yp"
 return "-$_[2]" }
#line 8015 SPARQL.pm
	],
	[#Rule PN_LOCAL_EXTRA_250
		 'PN_LOCAL_EXTRA', 2,
sub {
#line 631 "SPARQL.yp"
 return "_$_[2]" }
#line 8022 SPARQL.pm
	],
	[#Rule VAR1_251
		 'VAR1', 2,
sub {
#line 634 "SPARQL.yp"
 ['VAR',$_[2]] }
#line 8029 SPARQL.pm
	],
	[#Rule VAR2_252
		 'VAR2', 2,
sub {
#line 636 "SPARQL.yp"
 ['VAR',$_[2]] }
#line 8036 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-52', 2,
sub {
#line 638 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 8043 SPARQL.pm
	],
	[#Rule _PLUS_LIST
		 'PLUS-52', 1,
sub {
#line 638 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_single }
#line 8050 SPARQL.pm
	],
	[#Rule _PAREN
		 'PAREN-53', 2,
sub {
#line 638 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYBuildAST }
#line 8057 SPARQL.pm
	],
	[#Rule _STAR_LIST_54
		 'STAR-54', 2,
sub {
#line 638 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 8064 SPARQL.pm
	],
	[#Rule _STAR_LIST_54
		 'STAR-54', 0,
sub {
#line 638 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 8071 SPARQL.pm
	],
	[#Rule LANGTAG_258
		 'LANGTAG', 3,
sub {
#line 638 "SPARQL.yp"
 join('-', $_[2], map { $_->{children}[0]{attr} } @{ $_[3]{children} }) }
#line 8078 SPARQL.pm
	],
	[#Rule INTEGER_POSITIVE_259
		 'INTEGER_POSITIVE', 2,
sub {
#line 642 "SPARQL.yp"
 $_[2] }
#line 8085 SPARQL.pm
	],
	[#Rule DOUBLE_POSITIVE_260
		 'DOUBLE_POSITIVE', 2,
sub {
#line 643 "SPARQL.yp"
 $_[2] }
#line 8092 SPARQL.pm
	],
	[#Rule DECIMAL_POSITIVE_261
		 'DECIMAL_POSITIVE', 2,
sub {
#line 644 "SPARQL.yp"
 $_[2] }
#line 8099 SPARQL.pm
	],
	[#Rule VARNAME_262
		 'VARNAME', 1,
sub {
#line 649 "SPARQL.yp"
 $_[1] }
#line 8106 SPARQL.pm
	],
	[#Rule VARNAME_263
		 'VARNAME', 1,
sub {
#line 650 "SPARQL.yp"
 $_[1] }
#line 8113 SPARQL.pm
	],
	[#Rule VARNAME_264
		 'VARNAME', 1,
sub {
#line 651 "SPARQL.yp"
 $_[1] }
#line 8120 SPARQL.pm
	],
	[#Rule VARNAME_265
		 'VARNAME', 1,
sub {
#line 652 "SPARQL.yp"
 $_[1] }
#line 8127 SPARQL.pm
	],
	[#Rule VARNAME_266
		 'VARNAME', 1,
sub {
#line 653 "SPARQL.yp"
 $_[1] }
#line 8134 SPARQL.pm
	],
	[#Rule VARNAME_267
		 'VARNAME', 1,
sub {
#line 654 "SPARQL.yp"
 $_[1] }
#line 8141 SPARQL.pm
	],
	[#Rule VARNAME_268
		 'VARNAME', 1,
sub {
#line 655 "SPARQL.yp"
 $_[1] }
#line 8148 SPARQL.pm
	],
	[#Rule VARNAME_269
		 'VARNAME', 1,
sub {
#line 656 "SPARQL.yp"
 $_[1] }
#line 8155 SPARQL.pm
	],
	[#Rule VARNAME_270
		 'VARNAME', 1,
sub {
#line 657 "SPARQL.yp"
 $_[1] }
#line 8162 SPARQL.pm
	],
	[#Rule VARNAME_271
		 'VARNAME', 1,
sub {
#line 658 "SPARQL.yp"
 $_[1] }
#line 8169 SPARQL.pm
	],
	[#Rule VARNAME_272
		 'VARNAME', 1,
sub {
#line 659 "SPARQL.yp"
 $_[1] }
#line 8176 SPARQL.pm
	],
	[#Rule VARNAME_273
		 'VARNAME', 1,
sub {
#line 660 "SPARQL.yp"
 $_[1] }
#line 8183 SPARQL.pm
	],
	[#Rule VARNAME_274
		 'VARNAME', 1,
sub {
#line 661 "SPARQL.yp"
 $_[1] }
#line 8190 SPARQL.pm
	],
	[#Rule VARNAME_275
		 'VARNAME', 1,
sub {
#line 662 "SPARQL.yp"
 $_[1] }
#line 8197 SPARQL.pm
	],
	[#Rule VARNAME_276
		 'VARNAME', 1,
sub {
#line 663 "SPARQL.yp"
 $_[1] }
#line 8204 SPARQL.pm
	],
	[#Rule VARNAME_277
		 'VARNAME', 1,
sub {
#line 664 "SPARQL.yp"
 $_[1] }
#line 8211 SPARQL.pm
	],
	[#Rule VARNAME_278
		 'VARNAME', 1,
sub {
#line 665 "SPARQL.yp"
 $_[1] }
#line 8218 SPARQL.pm
	],
	[#Rule VARNAME_279
		 'VARNAME', 1,
sub {
#line 666 "SPARQL.yp"
 $_[1] }
#line 8225 SPARQL.pm
	],
	[#Rule VARNAME_280
		 'VARNAME', 1,
sub {
#line 667 "SPARQL.yp"
 $_[1] }
#line 8232 SPARQL.pm
	],
	[#Rule VARNAME_281
		 'VARNAME', 1,
sub {
#line 668 "SPARQL.yp"
 $_[1] }
#line 8239 SPARQL.pm
	],
	[#Rule VARNAME_282
		 'VARNAME', 1,
sub {
#line 669 "SPARQL.yp"
 $_[1] }
#line 8246 SPARQL.pm
	],
	[#Rule VARNAME_283
		 'VARNAME', 1,
sub {
#line 670 "SPARQL.yp"
 $_[1] }
#line 8253 SPARQL.pm
	],
	[#Rule VARNAME_284
		 'VARNAME', 1,
sub {
#line 671 "SPARQL.yp"
 $_[1] }
#line 8260 SPARQL.pm
	],
	[#Rule VARNAME_285
		 'VARNAME', 1,
sub {
#line 672 "SPARQL.yp"
 $_[1] }
#line 8267 SPARQL.pm
	],
	[#Rule VARNAME_286
		 'VARNAME', 1,
sub {
#line 673 "SPARQL.yp"
 $_[1] }
#line 8274 SPARQL.pm
	],
	[#Rule VARNAME_287
		 'VARNAME', 1,
sub {
#line 674 "SPARQL.yp"
 $_[1] }
#line 8281 SPARQL.pm
	],
	[#Rule VARNAME_288
		 'VARNAME', 1,
sub {
#line 675 "SPARQL.yp"
 $_[1] }
#line 8288 SPARQL.pm
	],
	[#Rule VARNAME_289
		 'VARNAME', 1,
sub {
#line 676 "SPARQL.yp"
 $_[1] }
#line 8295 SPARQL.pm
	],
	[#Rule VARNAME_290
		 'VARNAME', 1,
sub {
#line 677 "SPARQL.yp"
 $_[1] }
#line 8302 SPARQL.pm
	],
	[#Rule VARNAME_291
		 'VARNAME', 1,
sub {
#line 678 "SPARQL.yp"
 $_[1] }
#line 8309 SPARQL.pm
	],
	[#Rule VARNAME_292
		 'VARNAME', 1,
sub {
#line 679 "SPARQL.yp"
 $_[1] }
#line 8316 SPARQL.pm
	],
	[#Rule VARNAME_293
		 'VARNAME', 1,
sub {
#line 680 "SPARQL.yp"
 $_[1] }
#line 8323 SPARQL.pm
	],
	[#Rule VARNAME_294
		 'VARNAME', 1,
sub {
#line 681 "SPARQL.yp"
 $_[1] }
#line 8330 SPARQL.pm
	],
	[#Rule VARNAME_295
		 'VARNAME', 1,
sub {
#line 682 "SPARQL.yp"
 $_[1] }
#line 8337 SPARQL.pm
	],
	[#Rule _STAR_LIST_55
		 'STAR-55', 2,
sub {
#line 685 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 8344 SPARQL.pm
	],
	[#Rule _STAR_LIST_55
		 'STAR-55', 0,
sub {
#line 685 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 8351 SPARQL.pm
	],
	[#Rule NIL_298
		 'NIL', 3,
sub {
#line 685 "SPARQL.yp"
 $_[0]->new_uri('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil') }
#line 8358 SPARQL.pm
	],
	[#Rule _STAR_LIST_56
		 'STAR-56', 2,
sub {
#line 687 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_TX1X2 }
#line 8365 SPARQL.pm
	],
	[#Rule _STAR_LIST_56
		 'STAR-56', 0,
sub {
#line 687 "SPARQL.yp"
 goto &Parse::Eyapp::Driver::YYActionforT_empty }
#line 8372 SPARQL.pm
	],
	[#Rule ANON_301
		 'ANON', 3,
sub {
#line 687 "SPARQL.yp"
 $_[0]->new_blank() }
#line 8379 SPARQL.pm
	],
	[#Rule INTEGER_302
		 'INTEGER', 1,
sub {
#line 691 "SPARQL.yp"
 $_[1] }
#line 8386 SPARQL.pm
	],
	[#Rule INTEGER_303
		 'INTEGER', 1,
sub {
#line 692 "SPARQL.yp"
 $_[1] }
#line 8393 SPARQL.pm
	]
],
#line 8396 SPARQL.pm
                                  yybypass => 0,
                                  @_,);
    bless($self,$class);

    
    $self;
}

#line 705 "SPARQL.yp"


# RDF::Query::Parser::SPARQL
# -------------
# $Revision: 194 $
# $Date: 2007-04-18 22:26:36 -0400 (Wed, 18 Apr 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Parser::SPARQL - A SPARQL parser for RDF::Query

=cut

package RDF::Query::Parser::SPARQL;

use strict;
use warnings;
use base qw(RDF::Query::Parser);

use RDF::Query::Error qw(:try);

use Data::Dumper;
# use Parse::Eyapp;
use Carp qw(carp croak confess);
use Scalar::Util qw(reftype blessed);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 0 || $RDF::Query::Parser::debug;
	$VERSION	= do { my $REV = (qw$Revision: 194 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
	$lang		= 'sparql';
	$languri	= 'http://www.w3.org/TR/rdf-sparql-query/';
}


######################################################################

=head1 METHODS

=over 4

=cut

our %EXPECT_DESC	= (
	'{'			=> 'GroupGraphPattern or ConstuctTemplate',
	'('			=> 'ArgList, Collection, BrackettedExpression or NIL',
	map { $_ => $_ } qw(SELECT ASK DESCRIBE CONSTRUCT FILTER GRAPH OPTIONAL),
);


=item C<< new () >>

Returns a new SPARQL parser object.

=begin private

=item C<< Run >>

Internal Parse::Eyapp method.

=end private



=item C<< parse ( $query ) >>

Parses the supplied SPARQL query string, returning a parse tree.

=cut

sub parse {
	my $self	= shift;
	my $query	= shift;
	undef $self->{error};
	$self->YYData->{INPUT} = $query;
	$self->{blank_ids}		= 1;
	my $t = eval { $self->Run };                    # Parse it!
	
	if ($@) {
#		warn $@;	# XXX
		return;
	} else {
		my $ok	= $self->fixup_triples( $t->{triples} );
#		warn "fixup ok? <$ok>\n";
		return unless $ok;
		return $t;
	}
}

=begin private

=item C<< fixup_triples ( \@triples ) >>

Checks all triples recursively for proper use of blank node labels (the same
labels cannot be re-used across different BGPs). Returns true if the blank
node label use is proper, false otherwise.

=end private

=cut

sub fixup_triples {
	my $self	= shift;
	my $triples	= shift;
	my $block	= $triples;
	my $part	= 1;
	unless (reftype($triples) eq 'ARRAY') {
		confess Dumper($triples);
	}
	
	foreach my $triple (@$triples) {
		my $context	= join('', $block, $part);
		my $type	= $self->fixup( $context, $triple );
		return unless $type;
		$part++ if ($type =~ /OPTIONAL|GRAPH|UNION|GGP/);
	}
	return 1;
}

=begin private

=item C<< fixup ( $context, $triple ) >>

Takes a triple or parse-tree atom, and returns true if the triple conforms
to the SPARQL spec regarding the re-use of blank node labels.
C<<$context>> is an opaque string representing the enclosing BGP of the triple.

=end private

=cut

sub fixup {
	my $self	= shift;
	my $context	= shift;
	my $triple	= shift;
	
	Carp::confess Dumper($triple) unless (reftype($triple) eq 'ARRAY');
	my $type	= $triple->[0];
	if (ref($type)) {
		my ($s,$p,$o)	= @$triple;
		foreach my $node ($s,$p,$o) {
			no warnings 'uninitialized';
			if (reftype($node) eq 'ARRAY') {
				if ($node->[0] eq 'BLANK' and $self->{__blank_nodes}{$node->[1]}) {
					my $name	= $node->[1];
#					warn "GOT A BLANK NODE ($name) in context: $context!";
					if (not exists ($self->{__registered_blank_nodes}{$name})) {
#						warn "\thaven't seen this blank node before\n";
						$self->{__registered_blank_nodes}{$name}	= "$context";
					}
					
					if ($self->{__registered_blank_nodes}{$name} ne "$context") {
#						warn "\tblank node conflicts with previous use\n";
						$self->{error}	= "Syntax error; Same blank node identifier ($name) used in more than one basic graph pattern.";
						return;
					}
				}
			} else {
				warn "unknown fixup type: " . Dumper($node);
			}
		}
		return 'TRIPLE';
	} else {
		no warnings 'uninitialized';
		if ($triple->[0] =~ /^(VAR|URI|LITERAL)$/) {
			return 1;
		} elsif ($triple->[0] eq 'GGP') {
			return unless $self->fixup( $triple->[1], $triple->[1] );
			return 'GGP';
		} elsif ($triple->[0] eq 'OPTIONAL') {
			return unless $self->fixup_triples( $triple->[1] );
			return 'OPTIONAL';
		} elsif ($triple->[0] eq 'GRAPH') {
			return unless $self->fixup_triples( $triple->[2] );
			return 'GRAPH';
		} elsif ($triple->[0] eq 'FILTER') {
			return unless $self->fixup( $context, $triple->[1] );
			return 'FILTER';
		} elsif ($triple->[0] eq 'UNION') {
			return unless $self->fixup_triples( $triple->[1] );
			return unless $self->fixup_triples( $triple->[2] );
			return 'UNION';
		} elsif ($triple->[0] =~ qr#^[=~<>!&|*/+-]# || $triple->[0] eq 'FUNCTION') {
			return unless $self->fixup_triples([ @{$triple}[1..$#{$triple}] ]);
			return 1;
		} else {
			warn "unrecognized triple: " . Dumper($triple);
			return 0;
		}
	}
}

=begin private

=item C<< register_blank_node ( $name ) >>

Used during parsing, this method registers the names of blank nodes that are
used in the query so that they may be checked after the parse.

=end private

=cut

sub register_blank_node {
	my $self	= shift;
	my $name	= shift;
	no warnings 'uninitialized';
	$self->{__blank_nodes}{$name}++;
}



=item C<< error >>

Returns the latest parse error string.

=cut

sub error {
	my $self	= shift;
	if (defined($self->{error})) {
		return $self->{error};
	} else {
		return;
	}
}


# package RDF::Query::Parser::SPARQL::Value;
# 
# use overload '""' => sub { $_[0][0] };
# 
# sub new {
# 	my $class	= shift;
# 	my $data	= [ @_ ];
# 	return bless($data, $class);
# }

{
my $last;
sub _Lexer {
	my $self	= shift;
	my ($type,$value)	= __Lexer( $self, $last );
#	warn "$type\t=> $value\n";
#	warn "pos => " . pos($self->YYData->{INPUT}) . "\n";
#	warn "len => " . length($self->YYData->{INPUT}) . "\n";
	$last	= [$type,$value];
	no warnings 'uninitialized';
	return ($type,"$value");
}
}

sub __new_value {
	my $parser	= shift;
	my $value	= shift;
	my $ws		= shift;
	return $value;
#		return RDF::Query::Parser::SPARQL::Value->new( $token, $value );
}

sub _literal_escape {
	my $value	= shift;
	for ($value) {
		s/\\t/\t/g;
		s/\\n/\n/g;
		s/\\r/\r/g;
		s/\\b/\b/g;
		s/\\f/\f/g;
		s/\\"/"/g;
		s/\\'/'/g;
		s/\\\\/\\/g;
	}
	return $value;
}

sub __Lexer {
	my $parser	= shift;
	my $last	= shift;
	my $lasttok	= $last->[0];
	
	for ($parser->YYData->{INPUT}) {
		my $index	= pos($_) || -1;
		return if ($index == length($parser->YYData->{INPUT}));
		
		my $ws	= 0;
#		warn "lexing at: " . substr($_,$index,20) . " ...\n";
		while (m{\G\s+}gc or m{\G#(.*)}gc) {	# WS and comments
			$ws	= 1;
		}
			
#		m{\G(\s*|#(.*))}gc and return('WS',$1);	# WS and comments
		
		m{\G(
				ASC\b
			|	ASK\b
			|	BASE\b
			|	BOUND\b
			|	CONSTRUCT\b
			|	DATATYPE\b
			|	DESCRIBE\b
			|	DESC\b
			|	DISTINCT\b
			|	FILTER\b
			|	FROM[ ]NAMED\b
			|	FROM\b
			|	GRAPH\b
			|	LANGMATCHES\b
			|	LANG\b
			|	LIMIT\b
			|	NAMED\b
			|	OFFSET\b
			|	OPTIONAL\b
			|	ORDER[ ]BY\b
			|	PREFIX\b
			|	REDUCED\b
			|	REGEX\b
			|	SELECT\b
			|	STR\b
			|	UNION\b
			|	WHERE\b
			|	isBLANK\b
			|	isIRI\b
			|	isLITERAL\b
			|	isURI\b
			|	sameTerm\b
			|	true\b
			|	false\b
		)}xigc and return(uc($1), $parser->__new_value( $1, $ws ));
		m{\G(
				a(?=(\s|[#]))\b
		
		)}xgc and return($1,$parser->__new_value( $1, $ws ));
		
		
		m{\G'''((?:('|'')?(\\([tbnrf\\"'])|[^'\x92]))*)'''}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
		m{\G"""((?:(?:"|"")?(?:\\(?:[tbnrf\\"'])|[^"\x92]))*)"""}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
		m{\G'((([^\x27\x5C\x0A\x0D])|\\([tbnrf\\"']))*)'}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
		m{\G"((([^\x22\x5C\x0A\x0D])|\\([tbnrf\\"']))*)"}gc and return('STRING',$parser->__new_value( _literal_escape($1), $ws ));
		
		
		m{\G<([^<>"{}|^`\x92]*)>}gc and return('URI',$parser->__new_value( $1, $ws ));
		
		m{\G(
				!=
			|	&&
			|	<=
			|	>=
			|	\Q||\E
			|	\Q^^\E
			|	_:
		)}xgc and return($1,$parser->__new_value( $1, $ws ));
		
		m{\G([_A-Za-z][._A-Za-z0-9]*)}gc and return('NAME',$parser->__new_value( $1, $ws ));
		m{\G([_A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{02FF}\x{0370}-\x{037D}\x{037F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]+)}gc and return('NAME',$parser->__new_value( $1, $ws ));
		
		
		m{\G([-]?(\d+)?[.](\d+)[eE][+-]?[0-9]+)}gc and return('DOUBLE',$parser->__new_value( $1, $ws ));
		m{\G([-]?\d+[eE][+-]?[0-9]+)}gc and return('DOUBLE',$parser->__new_value( $1, $ws ));
		m{\G([-]?(\d+[.]\d*|[.]\d+))}gc and return('DECIMAL',$parser->__new_value( $1, $ws ));
		if ($ws) {
			m{\G([-]?\d+)}gc and return('INTEGER_WS',$parser->__new_value( $1, $ws ));
		} else {
			m{\G([-]?\d+)}gc and return('INTEGER_NO_WS',$parser->__new_value( $1, $ws ));
		}
		
		
		m{\G([@!$()*+,./:;<=>?\{\}\[\]\\-])}gc and return($1,$parser->__new_value( $1, $ws ));
		
		my $p	= pos();
		my $l	= length();
		if ($p < $l) {
			warn "uh oh! input = '" . substr($_, $p, 10) . "'";
		}
		return ('', undef);
	}
};

sub Run {
	my($self)=shift;
	for ($self->YYData->{INPUT}) {
		s/\\u([0-9a-fA-F]{4})/chr(hex($1))/ge;
		s/\\U([0-9a-fA-F]{8})/chr(hex($1))/ge;
	}
	$self->YYParse(
		yylex	=> \&_Lexer,
		yyerror	=> \&_Error,
		yydebug	=> 0,#0x01 | 0x04, #0x01 | 0x04,	# XXX
	);
}

sub _Error {
	my $parser	= shift;
	my($token)=$parser->YYCurval;
	my($what)	= $token ? "input: '$token'" : "end of input";
	my @expected = $parser->YYExpect();
	
	my $error;
	if (scalar(@expected) == 1 and $expected[0] eq '') {
		$error	= "Syntax error; Remaining input";
	} else {
		our %EXPECT_DESC;
		if (exists $EXPECT_DESC{ $expected[0] }) {
			my @expect	= @EXPECT_DESC{ @expected };
			if (@expect > 1) {
				my $a	= pop(@expect);
				my $b	= pop(@expect);
				no warnings 'uninitialized';
				push(@expect, "$a or $b");
			}
			
			my $expect	= join(', ', @expect);
			if ($expect eq 'DESCRIBE, ASK, CONSTRUCT or SELECT') {
				$expect	= 'query type';
			}
			$error	= "Syntax error; Expecting $expect near $what";
		} else {
			use utf8;
			$error	= "Syntax error; Expected one of the following terminals (near $what): " . join(', ', map {"«$_»"} @expected);
		}
	}
	
	$parser->{error}	= $error;
	Carp::confess $error;
}



1;

__END__

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut


#line 8850 SPARQL.pm

1;
