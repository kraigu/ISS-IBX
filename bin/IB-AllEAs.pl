#!/usr/bin/env perl

# Export hosts with EA 
# Modified from exportHostnamesNetworks by Jason Gorrie
# itself based on some of my code, based on ibcli by Geoff Horne and code by Daniel Allen
# Mike Patterson <mike.patterson@uwaterloo.ca> IST-ISS April 2013

use strict;
use warnings;
use IO::Socket::SSL;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Config::General;
use Data::Dumper;
use Infoblox qw ( :hostaddress );
use LWP::UserAgent;
use HTTP::Request;
use Net::IPv4Addr qw( :all );
use ISSIBX;
use vars qw/$opt_f $opt_v $opt_h $opt_f/;
use Getopt::Std;

my %config;
getopts('v:f:h');
if($opt_h){
    print "Options: -f(config file), -v(debug)\n";
    exit 0;
}
my $debug = $opt_v || 0;
if($debug){ print "DEBUG $debug\n"; }
if($opt_f){
	%config = ISSIBX::GetConfig($opt_f);
	if($debug > 1) {
		print "DEBUG using configuration file $opt_f\n";
	}
} else {
	%config = ISSIBX::GetConfig();
}

sub hostpprint() {
	if($debug > 2){
		print "DEBUG $debug dumping host\n";
		print Dumper($_[0]);
	}
	my $obj_host = $_[0];
	my ($v4address,$top);
	my @eas;

	# Skip disabled hosts
	my $disable = $obj_host->disable();
	if ( $disable eq "true" ) {
		return;
	}

	# array reference that might contain Infoblox::DHCP::FixedAddr objects
	return unless defined($obj_host->ipv4addrs());
	my @ipv4addrs = @{ $obj_host->ipv4addrs() };

	$v4address = ($ipv4addrs[0]->ipv4addr());

	my $name = ($obj_host->name());
	if($debug > 3) {
		print "DEBUG dumping ipv4addrs for $name\n" . Dumper(@ipv4addrs) . "\n";
	}
	@eas = ($obj_host->extensible_attributes());
	$top = qq|"$name","$v4address",|;
	if (defined($eas[0]{"Pol8 Classification"} ) ){
		$top = $top . qq|"$eas[0]{"Pol8 Classification"}"|;
	} else {
		$top = $top . qq|""|;
	}
	print "$top\n";
}

sub getHosts() {
	my ($ibsession) = @_;
	my $current_record;

	my $cursor=$ibsession->new_cursor(
		fetch_size => 1000,
		object => "Infoblox::DNS::Host",
		return_methods => ['name', 'ipv4addrs', 'extensible_attributes'],
	);
	if($debug > 3){
		print "DEBUG dumping cursor\n" . Dumper($cursor) . "\n";
	}
	while ($current_record = $cursor->fetch()) {
		if($debug > 2){
			print "DEBUG dumping current record\n" . Dumper($current_record) . "\n";
		}
		&hostpprint($current_record);
	}
}

## main routine
if($opt_f){
	%config = ISSIBX::GetConfig($opt_f);
} else {
	%config = ISSIBX::GetConfig();
}

# Verify that the remote is responding. This may not be strictly necessary.
my $timeout = 10;
my $ua = LWP::UserAgent->new();
$ua->ssl_opts( verify_hostname => 0); # security guys still hating security
if($debug > 2){
	print "DEBUG Dumping ua\n" . Dumper($ua) . "\n";
}
my $request = HTTP::Request->new(GET => "https://$config{hostname}");
eval {
	local $SIG{ALRM} = sub { die "timeout exceeded\n" };
	alarm $timeout;
	my $response = $ua->request($request);
	alarm 0;
	if ( $response->is_error ) {
		my $error = $response->status_line;
		die $error;
	}
};

if ($@) {
	if($debug > 0){
		print "Dumping something:\n" . Dumper($@) . "Dumped something\n";
	}
	die "Error: server $config{hostname} not responding\n";
}

my $ibsession = Infoblox::Session->new(
	"master" => $config{hostname},
	"username" => $config{username},
	"password" => $config{password},
	"timeout" => 36000
);
if ($debug > 2){
	print "Dumping session:\n";
	print Dumper(\$ibsession);
	print "Dumped session\n";
}
if ( my $herp = $ibsession->status_code() ){
	my $diemsg = "Session failed.\n" . $herp . ": " . $ibsession->status_detail() . "\n";
	if ($herp == 1009){
		$diemsg = $diemsg . "Hint: https://$config{hostname}/api/dist/CPAN/authors/id/INFOBLOX/\n";
	}
	die($diemsg);
}

# Do the actual work
&getHosts($ibsession);

# OK, so, yeah, we hate security and stuff.
BEGIN {
    IO::Socket::SSL::set_defaults(
        verify_mode => Net::SSLeay->VERIFY_NONE(),
    );
}
