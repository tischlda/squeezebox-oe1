package Plugins::OE1::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);
use base qw(Slim::Utils::Log);
use base qw(Slim::Formats::XML);
use File::Spec::Functions qw(:ALL);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.oe1',
    'defaultLevel' => 'ERROR',
});

sub initPlugin {
	my $class = shift;

	my $file = catdir( $class->_pluginDataFor('basedir'), 'default.opml' );

	$class->SUPER::initPlugin(
		feed   => Slim::Utils::Misc::fileURLFromPath($file),
		tag => 'oe1',
		menu   => 'radios',
		weight => 1
	);
}

sub getDisplayName () {
	return 'PLUGIN_OE1_MODULE_NAME';
}

sub getData()
{
	my ( $client, $callback, $params, $passthrough ) = @_;

	my $url = 'http://oe1.orf.at/'.$passthrough->{'url'};
	my $level = $passthrough->{'level'};
	
	my $args = {
		'url' => $url,
		'parser' => 'Plugins::OE1::Plugin?'.$level,
		'params' => $params
	};

	my $handleResult = sub {
		my ($feed) = @_;
		$callback->($feed);
	};
	
	Slim::Formats::XML->getFeedAsync($handleResult, \&handleError, $args);
}

sub handleError {
	my ( $err, $params ) = @_;
	
	my $request = $params->{'request'};
	my $url     = $params->{'url'};
	
	logError("While retrieving [$url]: [$err]");
	
	$request->addResult("networkerror", $err);
	$request->addResult('count', 0);

	$request->setStatusDone();	
}

sub parse() {
	my ($class, $http, $parserParams) = @_;

	my $content = $http->contentRef;
	my $data = from_json($$content);

	for ($parserParams) {
		if (/^today$/) { return parseToday($data); }
		if (/^day$/) { return parseDay($data); }
		if (/^journals$/) { return parseJournals($data); }
		die "Invalid parserParams '$parserParams'";
	}
}

sub parseToday {
	my ($data) = @_;

	my @items = map {
		{
			'title' => Slim::Formats::XML::unescapeAndTrim($_->{'day_label'}),
			'url' => \&Plugins::OE1::Plugin::getData,
			'passthrough' => [{
				'url' => $_->{'url'}, 
				'level' => 'day'
			}],
		}
	} reverse(@{$data->{'nav'}});
	
	my $feed = {
		'title' => Slim::Formats::XML::unescapeAndTrim('7 Tage'),
		'nocache' => 1,
		'items' => \@items
	};
	
	return $feed;
}

sub parseDay{
	my ($data) = @_;

	my @items = map {
		{
			'description' => Slim::Formats::XML::unescapeAndTrim($_->{'info'}),
			'title' => Slim::Formats::XML::unescapeAndTrim($_->{'time'}.' '.$_->{'title'}),
			'enclosure' => {
				'url' => $_->{'url_stream'},
				'type' => 'audio'
			}
		}
	} @{$data->{'list'}};
	
	my $feed = {
		'title' => Slim::Formats::XML::unescapeAndTrim($data->{'day_label'}),
		'nocache' => 1,
		'items' => \@items
	};

	return $feed;
}

sub parseJournals{
	my ($data) = @_;

	my @items = map {
		{
			'description' => Slim::Formats::XML::unescapeAndTrim($_->{'info'}),
			'title' => Slim::Formats::XML::unescapeAndTrim($_->{'info'}.' '.$_->{'title'}),
			'enclosure' => {
				'url' => $_->{'url_stream'},
				'type' => 'audio'
			}
		}
	} @{$data->{'list'}};
	
	my $feed = {
		'title' => Slim::Formats::XML::unescapeAndTrim('Journale'),
		'nocache' => 1,
		'items' => \@items
	};

	return $feed;
}

1;