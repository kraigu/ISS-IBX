#!/usr/bin/env perl

# Dump all Infoblox Extensible Attributes from Waterloo IPAM system
# Mike Patterson <mike.patterson@uwaterloo.ca> May 2012
# based on ibtest.pl developed by same, w/ thanks to drallen@uwaterloo.ca and Geoff Horne

# Expects $HOME/.infobloxrc to exist, to be mode 0600, and to contain:
# username=your username
# hostname=grid master name or IP
# password=guess what goes here

use strict;
use warnings;
use Config::General;
use Data::Dumper;
use Infoblox;
use LWP::UserAgent;
use HTTP::Request;
use Net::IPv4Addr qw( :all ); # EXPORTS NOTHING BY DEFAULT
use Net::IPv6Addr; # WHY DOES THIS MODULE EXPORT NOTHING AT ALL ARHGAHRGHAGR
use Net::DNS; # HOW IRONICAL

my $uqdomain = ".uwaterloo.ca"; # set to your own!
my $toSearch;

my $debug = 0;
my ($searchName, $searchIP);
my $res = Net::DNS::Resolver->new;

my $configfile = '';
if($debug > 2) {
	$configfile = qq|$ENV{"HOME"}/.ibtestrc|;
} else {
	$configfile = qq|$ENV{"HOME"}/.infobloxrc|;
}

sub pprint() {
# This routine is complicated somewhat by the fact that at least a few EAs can have multiple values
	my $tmpstr = "";
	my @eas = ($_[0]->extensible_attributes());
	if($debug > 0){
		print "----\nAll extensible attributes:\n";
		print Dumper($eas[0]);
		print "\n-----End of extensible attributes\n";
	}
	# $eas[0] should be a hash, innit? So howcome I can't sort the keys? Just dump them out as they came in, for now.
	while(my ($key, $value) = each($eas[0])){
		# Special case for the Business and Technical Contact fields, which we know may have multi-values
		if($key eq "Business Contact" || $key eq "Technical Contact"){
			if($debug > 1){
				print "Found a $key\n";
			}
			if(ref($value) eq 'ARRAY'){
			 	foreach my $contact (@$value) {
			 		if($debug > 1){
			 			print "Contact for $key was $contact\n";
			 		}
			 		if($tmpstr) {
			 			$tmpstr = $tmpstr . "," . $contact;
			 		}
			 	}				
			} else {
				$tmpstr = $value;
			}
			print "$key: $tmpstr\n";
		}
		# Derps if anything not handled above is also an array reference...
		else {
			print "$key: $value\n";
		}
	}
}

die "Address, network, or hostname required\n" unless ($toSearch = $ARGV[0]);

if( ! -e $configfile){ 
	die "\n$configfile does not exist\n";
}
my $perms = sprintf("%o",(stat($configfile))[2] & 07777);
if($debug > 1){ print Dumper($perms); }
die "\nConfig file must not have any more than owner rw\n"
	unless ($perms == '600' || $perms == '0400');

my $conf = new Config::General($configfile);
my %config = $conf->getall;
if($debug > 1){ print Dumper(\%config); }

die "\nNo password!\n" unless $config{password};
die "\nNo hostname!\n" unless $config{hostname};
die "\nNo username!\n" unless $config{username};

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
if ($debug > 1){
	print "Dumping session:\n";
	print Dumper(\$ibsession);
	print "Dumped session\n";
}
if ( my $herp = $ibsession->status_code() ){
	my $diemsg = "Session failed.\n" . $herp . ": " . $ibsession->status_detail() . "\n";
	if ($herp == 1009){
		$diemsg = $diemsg . "Hint: https://IBXAPPLIANCE/api/dist/CPAN/authors/id/INFOBLOX/\n";
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
print ("$searchIP $searchName\n");
if (@result_array) {
	for my $res (@result_array) {
		&pprint($res);
	}
}
