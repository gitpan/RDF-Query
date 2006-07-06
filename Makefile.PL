
use ExtUtils::MakeMaker;
WriteMakefile(
				NAME			=> 'RDF::Query',
				VERSION_FROM	=> 'lib/RDF/Query.pm',
				AUTHOR			=> 'Gregory Todd Williams <gwilliams@cpan.org>',
				PREREQ_PM		=> {
										'Storable'					=> 0,
										'RDF::Core'					=> 0,
										'Parse::RecDescent'			=> 0,
										'DateTime::Format::W3CDTF'	=> 0,
										'Scalar::Util'				=> 0,
										'Error'						=> 0,
										'JSON'						=> 0,
										'Test::JSON'				=> 0,
										'Test::More'				=> 0.61,
										'Test::Exception'			=> 0,
								}
			);
