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
use vars qw/ $opt_i  $opt_v $opt_h $opt_c $opt_b $opt_t $opt_f/;
use Getopt::Std;

getopts('i:v:f:chbt');
if($opt_h){
    print "Options: -i(Address, network, or hostname), -f(config file), -c(contacts), -b(business contacts), -t(technical contacts) -v(debug)\n";
    exit 0;
}
my $debug = $opt_v || 0;

my $uqdomain = ".uwaterloo.ca"; # set to your own!
my $toSearch;

my ($searchName, $searchIP,%config);
my $res = Net::DNS::Resolver->new;

if($opt_f){
	%config = ISSIBX::GetConfig($opt_f);
} else {
	%config = ISSIBX::GetConfig();
}


sub pprint() {
     #check if an array has duplicated elements
     sub uniq2 {
        my %seen = ();
        my @r = ();
        foreach my $a (@_) {
        unless ($seen{$a}) {
            push @r, $a;
            $seen{$a} = 1;
         }
       }
    @r= join( ',', @r );
    my $s = join('',@r);
    return $s;
    }
  if($opt_c){
       sub buildcontact() {
	my ($ctype,$tbtc) = @_;
  # should take two arguments, a string and an array thingie
	if($debug > 0) {
		print "buildcontact type $ctype called with a btc\n";
	}
       }
	my $tmpstr = "";
	my @eas;
	my $btc;
	@eas = ($_[0]->extensible_attributes());
	if (defined($eas[0]{"Pol8-Classification"} ) ){
		print qq|Classification: $eas[0]{"Pol8-Classification"}\n|;
	}
	# Business and Technical Contact can have multiple values
	if(defined($eas[0]{"Business Contact"})) {
		$btc = $eas[0]{"Business Contact"};
		&buildcontact('Business Contact',$btc);
		 if (ref($btc) eq 'ARRAY') {
		 	foreach my $contact (@$btc) {
		 		if($tmpstr) {
		 			$tmpstr = $tmpstr . "," . $contact;
		 		} else {
		 			$tmpstr = $contact;
		 		}
			}
			print "Business Contact: $tmpstr\n";
		} else {
			print "Business Contact: $btc\n";
		}
	}
	$btc = undef;
	if(defined($eas[0]{"Technical Contact"})) {
		$btc = $eas[0]{"Technical Contact"};
		if($debug > 0){
			print "Calling buildcontact('Technical Contact',btc) here\n";
		}
		 if (ref($btc) eq 'ARRAY') {
		 	foreach my $contact (@$btc) {
		 		if($tmpstr) {
		 			$tmpstr = $tmpstr . "," . $contact;
		 		} else {
		 			$tmpstr = $contact;
		 		}
			}
			print "Technical Contact: $tmpstr\n";
		} else {
			print "Technical Contact: $btc\n";
		}
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
}elsif (!$opt_c && !$opt_b && !$opt_t){
# This routine is complicated somewhat by the fact that at least a few EAs can have multiple values
	my $tmpstr = "";
	my @eas = ($_[0]->extensible_attributes());
	if($debug > 0){
		print "----\nAll extensible attributes:\n";
		print Dumper($eas[0]);
		print "\n-----End of extensible attributes\n";
	}
	# $eas[0] should be a hash, innit? So howcome I can't sort the keys? Just dump them out as they came in, for now.
	if ($eas[0]){
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
			 		}else{
		 			      $tmpstr = $contact;
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
 }elsif($opt_b && $opt_t){
 	my $tmpstr = "";
  	my $string ="";
  	my $btc;
	my @eas = ($_[0]->extensible_attributes());
	if ($eas[0]){
	   	 if(defined($eas[0]{"Business Contact"})) {
		      $btc = $eas[0]{"Business Contact"};
		      &buildcontact('Business Contact',$btc);
		      if (ref($btc) eq 'ARRAY') {
		 	foreach my $contact (@$btc) {
		 		if($tmpstr) {
		 			$tmpstr = $tmpstr . "," . $contact;
		 		} else {
		 			$tmpstr = $contact;
		 		}
			}
			  $string = $tmpstr;
		   } else {
			  $string = $btc;
		  }
	        }
	        $btc = undef;
	        if(defined($eas[0]{"Technical Contact"})) {
		    $btc = $eas[0]{"Technical Contact"};
		    if($debug > 0){
			print "Calling buildcontact('Technical Contact',btc) here\n";
		    }
		    if (ref($btc) eq 'ARRAY') {
		 	foreach my $contact (@$btc) {
		 		if($tmpstr) {
		 			$tmpstr = $tmpstr . "," . $contact;
		 		} else {
		 			$tmpstr = $contact;
		 		}
			}
			$string = $string.",".$tmpstr;
		    } else {
			$string = $string.",".$btc;
		    }
	      }
	      if ($string ne ""){
	      my @str = split(",", $string);
	      print uniq2(@str)."\n";
	      } 	
	   }	
 }elsif($opt_b || $opt_t){
  	my $tmpstr = "";
  	my $string;
  	my $btc;
	my @eas = ($_[0]->extensible_attributes());
	if ($eas[0]){	
	      while(my ($key, $value) = each($eas[0])){
	           if ($opt_b && !$opt_t){
	    	       $string = "Business Contact";}
	           elsif($opt_t && !$opt_b){
	    	       $string = "Technical Contact";
	           }	 
	    # Special case for the Business and Technical Contact fields, which we know may have multi-values
	           if($key eq $string && $string ne ""){
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
			 		}else{
		 			      $tmpstr = $contact;
		 		        }
			 	}				
			} else {
				$tmpstr = $value;
			}
			print "$tmpstr\n";
	     }
	   } 
	}
  }	
 
 
}

if($#ARGV == 0){
	$toSearch = $ARGV[0];
} else {
	die "Address, network, or hostname required with -i argument\n" unless ($toSearch = $opt_i);
}

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
if((!$opt_b) &&  (!$opt_t)){
print ("$searchIP $searchName\n");
}
if (@result_array) {
	for my $res (@result_array) {
		&pprint($res);
	}
}

