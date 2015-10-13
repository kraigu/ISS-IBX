ISS-IBX
=======

*** This project is considered both obsolete and incomplete.

Waterloo ISS tools to talk to an Infoblox appliance.

IBDump.pl gets all the extensible attributes for a given host and has options to dump just particular ones.

IB-AllEAs.pl prints just a few extensible attributes in a different format. It's probably mis-named, at least for its present function.

Configuration File
==================

Goes in ~/.infobloxrc and must be mode 0600.

	username=(infoblox username with API access)
	hostname=(infoblox device)
	password=(guess)
	uqdomain=(the domain name to use in certain unqualified queries)

LICENSE
=======

BSD-new.
