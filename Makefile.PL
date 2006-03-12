
use ExtUtils::MakeMaker;
WriteMakefile(
				NAME			=> 'RDF::Query',
				VERSION_FROM	=> 'lib/RDF/Query.pm',
				AUTHOR			=> 'Gregory Williams <gwilliams@cpan.org>',
				PREREQ_PM		=> {
										'RDF::Core'					=> 0,
										'Parse::RecDescent'			=> 0,
										'LWP::Simple'				=> 0,
										'Test::More'				=> 0.61,
										'Test::Exception'			=> 0,
										'DateTime::Format::W3CDTF'	=> 0,
										'Scalar::Util'				=> 0,
										'Error'						=> 0,
								}
			);
