package Plugins::OE1::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);
use base qw(Slim::Utils::Log);
use base qw(Slim::Formats::XML);
use Date::Parse;
use File::Spec::Functions qw(:ALL);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.oe1',
    'defaultLevel' => 'ERROR',
});

my $broadcastsUrl = 'https://audioapi.orf.at/oe1/api/json/current/broadcasts';
my $loopStreamUrl = 'http://loopstream01.apa.at/?channel=oe1&shoutcast=0&offset=0&id=';

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

	my $url = $passthrough->{'url'};
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
		if (/^broadcasts$/) { return parseBroadcasts($data); }
		if (/^broadcastsday_.+$/) { return parseBroadcastsDay($data, $parserParams); }
		if (/^broadcast$/) { return parseBroadcast($data); }
		die "Invalid parserParams '$parserParams'";
	}
}

sub parseBroadcasts {
	my ($data) = @_;

	my @items = map {
		{
			'title' => formatDay(Slim::Formats::XML::unescapeAndTrim($_->{'day'})),
			'url' => \&Plugins::OE1::Plugin::getData,
			'passthrough' => [{
				'url' => $broadcastsUrl,
				'level' => 'broadcastsday_'.$_->{'day'}
			}],
		}
	} reverse(@{$data});
	
	my $feed = {
		'title' => Slim::Formats::XML::unescapeAndTrim('7 Tage'),
		'nocache' => 1,
		'items' => \@items
	};
	
	return $feed;
}

sub parseBroadcastsDay {
	my ($data, $parserParams) = @_;
	$parserParams =~ /^broadcastsday_(.+)$/;
	my $day = $1;

	my @dayData = grep { $_->{'day'} eq $1 } reverse(@{$data});
	my $broadcasts = $dayData[0]->{'broadcasts'};
	my @completedBroadcasts = grep { $_->{'state'} eq 'C' } @{$broadcasts};

	my @items = map {
		{
			'title' => Slim::Formats::XML::unescapeAndTrim(formatTime($_->{'scheduledStartISO'}).' '.$_->{'title'}),
			'url' => \&Plugins::OE1::Plugin::getData,
			'passthrough' => [{
				'url' => $_->{'href'},
				'level' => 'broadcast'
			}],
		}
	} @completedBroadcasts;
	
	my $feed = {
		'title' => Slim::Formats::XML::unescapeAndTrim('Tag'),
		'nocache' => 1,
		'items' => \@items
	};
	
	return $feed;
}

sub parseBroadcast {
	my ($data) = @_;

	my $description = Slim::Formats::XML::unescapeAndTrim($data->{'subtitle'});
	my $title = Slim::Formats::XML::unescapeAndTrim(formatTime($data->{'scheduledStartISO'}).' '.$data->{'title'});

	my @items = map {
		{
			'description' => $description,
			'title' => $title,
			'enclosure' => {
				'url' => $loopStreamUrl.$_->{'loopStreamId'},
				'type' => 'audio'
			}
		}
	} @{$data->{'streams'}};
	
	my $feed = {
		'title' => $title,
		'nocache' => 1,
		'items' => \@items
	};

	return $feed;
}

sub formatTime {
	my ($isoString) = @_;

	my ($ss, $mm, $hh, $day, $month, $year, $zone) = strptime($isoString);

	return sprintf("%02d:%02d", $hh, $mm)
}

sub formatDay {
	my ($dateString) = @_;

	my ($year, $month, $day) = $dateString =~ /^(\d{4})(\d{2})(\d{2})$/;

	return sprintf("%04d-%02d-%02d", $year, $month, $day)
}

1;