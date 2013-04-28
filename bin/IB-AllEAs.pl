#!/usr/bin/env perl

# Export hosts with EA 
# Modified from exportHostnamesNetworks by Jason Gorrie
# itself based on some of my code, based on ibcli by Geoff Horne and code by Daniel Allen
# Mike Patterson <mike.patterson@uwaterloo.ca> IST-ISS April 2013

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Config::General;
use Data::Dumper;
use Infoblox;
use LWP::UserAgent;
use HTTP::Request;
use Net::IPv4Addr qw( :all );
use ISSIBX;
use vars qw/$opt_f $opt_v $opt_h/;
use Getopt::Std;

my %config;
getopts('v:f:h');
if($opt_h){
    print "Options: -f(config file), -v(debug)\n";
    exit 0;
}
my $debug = $opt_v || 0;
if($opt_f){
	%config = ISSIBX::GetConfig($opt_f);
} else {
	%config = ISSIBX::GetConfig();
}
if($debug){ print "DEBUG $debug\n"; }

sub hostpprint() {
	if($debug > 2){
		print "DEBUG $debug dumping host\n";
		print Dumper($_[0]);
	}
	my $obj_host = $_[0];
	my $v4address;
	my @eas;

	# Skip disabled hosts
	my $disable = $obj_host->disable();
	if ( $disable eq "true" ) {
		return;
	}

	# array reference that might contain Infoblox::DHCP::FixedAddr objects
	# or it might contain a 
	return unless defined($obj_host->ipv4addrs());
	my @ipv4addrs = @{ $obj_host->ipv4addrs() };
	$v4address = ($ipv4addrs[0]); #->ipv4addr());

	# Now extract the name, the FQDN and the hostname from the data
	my $name = ($obj_host->name());
	@eas = ($obj_host->extensible_attributes());
	if (defined($eas[0]{"Pol8-Classification"} ) ){
		print qq|$name\t$v4address\t$eas[0]{"Pol8-Classification"}\n|;
	}
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
my $ua = LWP::UserAgent->new(
	useragent => [
		ssl_opts => {
			SSL_verify_mode => 'SSL_VERIFY_NONE' # this doesn't seem to work? :~(
		}
	]
);
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
