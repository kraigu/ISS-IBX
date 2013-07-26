#!/usr/bin/env perl

# Dump all Infoblox Extensible Attributes from Waterloo IPAM system
# Mike Patterson <mike.patterson@uwaterloo.ca> May 2012
# based on ibtest.pl developed by same, w/ thanks to drallen@uwaterloo.ca and Geoff Horne
# with contributions from Cheng Ji Shi <cjshi@uwaterloo.ca> Winter 2013 co-op

use strict;
use warnings;
use IO::Socket::SSL;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Config::General;
use Data::Dumper;
use Infoblox;
use LWP::UserAgent;
use HTTP::Request;
use Net::IPv4Addr qw( :all ); # EXPORTS NOTHING BY DEFAULT
use Net::IPv6Addr; # WHY DOES THIS MODULE EXPORT NOTHING AT ALL ARHGAHRGHAGR
use Net::DNS; # HOW IRONICAL
use ISSIBX;
use vars qw/$opt_i $opt_v $opt_h $opt_b $opt_t $opt_f $opt_m/;
use Getopt::Std;

my $helpmsg = qq|
Options:
-i (required, or if one argument this is assumed) IP address, network, or hostname
-f config file
-b print only business contacts (conflicts with m or t)
-t print only technical contacts (conflicts with m or b)
-m look up MAC address too (conflicts with b or t)
-v Verbose/debug
Lacking either of -b or -t, will print all extensible attributes for a given host.
With -m, will print any DHCP reservation information that's available for the host.
|;

getopts('i:v:f:chbtm');
if( ($opt_h) || ( ($opt_m) && ($opt_b || $opt_t) ) ){
	print $helpmsg;
    exit 0;
}

my $debug = $opt_v || 0;

my $toSearch;

my ($searchName, $searchIP,%config);
my $res = Net::DNS::Resolver->new;

if($opt_f){
	%config = ISSIBX::GetConfig($opt_f);
} else {
	%config = ISSIBX::GetConfig();
}

sub buildcontact {
	my $tmpstr = "";
	if($debug > 0) {
		print "buildcontact argument was " . Dumper(@_);
	}
	if (ref($_[0]) eq 'ARRAY'){
 		foreach my $contact (@{$_[0]}){
 			if($tmpstr) {
 				$tmpstr = $tmpstr . "," . $contact;
 			} else {
 				$tmpstr = $contact;
 			}
		}
	} else {
		$tmpstr = $_[0];
	}
	return $tmpstr;
}

sub pprint {
	my ($string,$busi,$tech,$tmpstr) ="";
	my @eas;
	my $btc = undef;
	@eas = ($_[0]->extensible_attributes());
	if($debug > 0){
		print "----\nAll extensible attributes:\n";
		print Dumper($eas[0]);
		print "\n-----End of extensible attributes\n";
	}	
	# First check to see if we're only printing a limited amount of information.
	if($opt_b){
		print &buildcontact($eas[0]{"Business Contact"}) . "\n";
		return 0;
	}
	if($opt_t){
		print &buildcontact($eas[0]{"Technical Contact"}) . "\n";
		return 0;
	}
	# OK, we're going to print it all.
	print qq|$searchIP $searchName\n|;
	if (defined($eas[0]{"Pol8 Classification"} ) ){
		print qq|Classification: $eas[0]{"Pol8 Classification"}\n|;
	}
	# Business and Technical Contact can have multiple values
	if(defined($eas[0]{"Business Contact"})) {
		print "Business Contact: " . &buildcontact($eas[0]{"Business Contact"}) . "\n";
	}
	if(defined($eas[0]{"Technical Contact"})) {
		print "Technical Contact: " . &buildcontact($eas[0]{"Technical Contact"}) . "\n";
	}
	if(defined($eas[0]{"LEGACY-AdminID"})){
	    print "Legacy Admin: " . $eas[0]{"LEGACY-AdminID"} . "\n";
	}
	if(defined($eas[0]{"LEGACY-ContactID"})){
	    print "Legacy Contact: " . $eas[0]{"LEGACY-ContactID"} . "\n";
	}
	if(defined($eas[0]{"LEGACY-User"})){
	    print "Legacy User: " . $eas[0]{"LEGACY-User"} . "\n";
	}
}

if($#ARGV == 0){
	$toSearch = $ARGV[0];
} else {
	die "Address, network, or hostname required\n" unless ($toSearch = $opt_i);
}

my $uqdomain = "." . $config{uqdomain};

# Verify that the remote is responding. This may not be strictly necessary.
my $timeout = 10;
my $ua = LWP::UserAgent->new;
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

if($@){
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
if ($debug > 1){
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

my %searchopts = (
	"object" => "Infoblox::DNS::Host"
);

# Iterate through the various things I might have been given on the CLI
if ( my $ip = ipv4_chkip($toSearch) ){
	$searchopts{'ipv4addr'} = $toSearch;
	$searchIP = $toSearch;
	my $query = $res->search("$toSearch");
	if($query){
		foreach my $rr ($query->answer) {
			next unless $rr->type eq "PTR";
			$searchName = $rr->ptrdname;
		}
	} else {
		die "$searchIP does not have a PTR record\n";
	}
} elsif ( Net::IPv6Addr::ipv6_chkip($toSearch) ) {
	die "Don't know how to do IPv6 addresses\n";
} else {
	unless ( $toSearch =~ /\./ ) {
		if($debug > 1){ print "appending $uqdomain\n"; }
		$toSearch = $toSearch . $uqdomain;
	}
	$searchopts{'name'} = $toSearch;
	$searchName = $toSearch;
	my $query = $res->search("$searchName");
	if ($query) {
		foreach my $rr($query->answer) {
			next unless $rr->type eq "A";
			$searchIP = $rr->address;
		}
	} else {
		die "$searchName does not resolve\n";
	}
}

if($debug > 1) {
	print Dumper(%searchopts);
}

my @result_array = $ibsession->get(%searchopts);
if($debug > 1) {
	print "\nSearching for: $toSearch\n";
	print Dumper(@result_array);
	print "Code: " . $ibsession->status_code() . ":" . $ibsession->status_detail() . "\n\n";
}

if (@result_array) {
	for my $res (@result_array) {
		&pprint($res);
	}
} else { exit 1; }

if($opt_m){
	@result_array = $ibsession->get(
		object => "Infoblox::DHCP::FixedAddr",
		ipv4addr => $searchIP
	) || undef;
	if(@result_array){
		print "MAC address: " . $result_array[0]{"mac"} . "\n";
	} 
}

# OK, so, yeah, we hate security and stuff.
BEGIN {
    IO::Socket::SSL::set_defaults(
        verify_mode => Net::SSLeay->VERIFY_NONE(),
    );
}


