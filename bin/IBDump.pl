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
use vars qw/$opt_i $opt_v $opt_h $opt_c $opt_C $opt_b $opt_t $opt_f $opt_m/;
use Getopt::Std;

getopts('i:v:f:cChbtm');
if($opt_h){
    print qq|
Options:
-i (required, or if one argument this is assumed) IP address, network, or hostname
-f config file
-c print all contacts
-C IP and hostname
-b print only business contacts
-t print only technical contacts
-m look up MAC address too
-v Verbose/debug
|;
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

sub pprint() {
	#check if an array has duplicated elements
    sub printele {
		my %seen = ();
		my @a = ();
		foreach my $a (@_) {
			unless ($seen{$a}) {
				push @a, $a;
				$seen{$a} = 1;
			}
		}
		@a= join( ',', @a );
		my $s = join('',@a);
    	return $s;
	}
    sub csvoutput {
		my %seen = ();
 		my @a = ();
        foreach my $a (@_) {
           unless ($seen{$a}) {
              push @a, qq("$a");
              $seen{$a} = 1;
			}
		}
		@a= join( ',', @a );
		my $s = join('',@a);
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
        my $string ="";
		my $tmpstr = "";
		my @eas;
		my $btc;
		@eas = ($_[0]->extensible_attributes());
		if (defined($eas[0]{"Pol8 Classification"} ) ){
			print qq|Classification: $eas[0]{"Pol8 Classification"}\n|;
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
				if(!$opt_C){
					print "Business Contact: $tmpstr\n";
				}
			    if ($string ne ""){
					$string = $string ."," .$tmpstr;
				} else {
					$string = $tmpstr;
				}
			} else {
				if(!$opt_C){
					print "Business Contact: $btc\n";
				}
			if ($string ne ""){
				$string = $string ."," .$btc;
			} else {
				$string = $btc;
			}
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
			}    if(!$opt_C){		
			         print "Technical Contact: $tmpstr\n";
			     }
			     if ($string ne ""){
			           $string = $string ."," .$tmpstr
			     }  else {
			           $string = $tmpstr;
			     }  
		} else {     if(!$opt_C){
			         print "Technical Contact: $btc\n";
			     }
			     if ($string ne ""){
		                 $string = $string ."," .$btc;
	                     }  else {
		                 $string = $btc;
	                     }
		}
	}
	if(defined($eas[0]{"LEGACY-AdminID"})){
		if(!$opt_C){
		    print "Legacy Admin: " . $eas[0]{"LEGACY-AdminID"} . "\n";
		}
		if ($string ne ""){
		   $string = $string."," .$eas[0]{"LEGACY-AdminID"};
	        }else{
	           $string = $eas[0]{"LEGACY-AdminID"};
	        }
	}

	if(defined($eas[0]{"LEGACY-ContactID"})){
		if(!$opt_C){
		    print "Legacy Contact: " . $eas[0]{"LEGACY-ContactID"} . "\n";
	        }
		if ($string ne ""){
		   $string = $string."," .$eas[0]{"LEGACY-ContactID"};
	        }else{
	           $string = $eas[0]{"LEGACY-ContactID"};
	        }
	}

	if(defined($eas[0]{"LEGACY-User"})){
		if(!$opt_C){ 
		    print "Legacy User: " . $eas[0]{"LEGACY-User"} . "\n";
		}
		if ($string ne ""){
		   $string = $string."," .$eas[0]{"LEGACY-User"};
	        }else{
	           $string = $eas[0]{"LEGACY-User"};
	        }
	}
	if ($string ne ""){
	         my @str = split(",", $string);
	         if($opt_C){
	               print csvoutput(@str)."\n";
	         }
        }else{   
                 print "\n";	
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
	         if($opt_C){
	               print qq("$searchIP","$searchName",);
	               print csvoutput(@str)."\n";
	         }else{
	      	       print printele(@str)."\n";
	         }
	     }else{
	     	print "\n";
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
			 			} else {
							$tmpstr = $contact;
		 		        }
				 	}				
				} else {
					$tmpstr = $value;
				}
				if ($tmpstr ne ""){
					my @st = split(",", $tmpstr);
					if($opt_C){
						print csvoutput(@st)."\n";
					} else {
						print printele(@st)."\n";
					}
				}	
			}
		}
	}
	if($tmpstr eq "" && $opt_C){
	   	print "\n";
	}
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

if(!$opt_C && !$opt_b && !$opt_t){
	print $searchIP.",".$searchName."\n";
} elsif($opt_C){
	print qq("$searchIP","$searchName",);
}

if (@result_array) {
	for my $res (@result_array) {
		&pprint($res);
	}
} elsif(!@result_array && $opt_C) {
	print "\n";
}

# OK, so, yeah, we hate security and stuff.
BEGIN {
    IO::Socket::SSL::set_defaults(
        verify_mode => Net::SSLeay->VERIFY_NONE(),
    );
}
