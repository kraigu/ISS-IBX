package ISSIBX;

our @EXPORT_OK = qw(GetConfig config);

use strict;
use warnings;

use Config::General;
use Data::Dumper;

my $debug = 0;

sub GetConfig{
	my $configfile = qq|$ENV{"HOME"}/.infobloxrc|;
	if($_[0]) {
		$configfile = $_[0];
	}
	if( ! -e $configfile){ 
		die "\n$configfile does not exist\n";
	}
	my $perms = sprintf("%o",(stat($configfile))[2] & 07777);
	if($debug > 3){ print "Permissions on rc file: " . Dumper($perms); }
	die "\nConfig file must not have any more than owner rw\n"
		unless ($perms == '600' || $perms == '0400');

	my $conf = new Config::General($configfile);
	my %config = $conf->getall;
	if($debug > 3){ print "Config is: \n" . Dumper(\%config) . "\n"; }

	die "\nNo password in $configfile, set password=\n" unless $config{password};
	die "\nNo hostname in $configfile, set hostname=\n" unless $config{hostname};
	die "\nNo username in $configfile, set username=\n" unless $config{username};
	die "\nNo unqualified domain in $configfile, set uqdomain=\n" unless $config{uqdomain};
	return %config;
}

1;