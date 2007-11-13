# RDF::Query::Node
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Node - Base class for RDF Nodes

=cut

package RDF::Query::Node;

use strict;
use warnings;


use RDF::Query::Node::Blank;
use RDF::Query::Node::Literal;
use RDF::Query::Node::Resource;
use RDF::Query::Node::Variable;

1;

__END__

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
