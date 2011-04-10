#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
use VMware::VIRuntime;
use VMware::VILib;

# cdromDisconnect.pl
#	To get usage, run pod2html.
#
#	Copyright 2007, VMware Inc.  All rights reserved.
#	Script provided as a sample.
#	DISCLAIMER. THIS SCRIPT IS PROVIDED TO YOU "AS IS" WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
#     WHETHER ORAL OR WRITTEN, EXPRESS OR IMPLIED. THE AUTHOR SPECIFICALLY DISCLAIMS ANY IMPLIED WARRANTIES 
#     OR CONDITIONS OF MERCHANTABILITY, SATISFACTORY QUALITY, NON-INFRINGEMENT AND FITNESS FOR A PARTICULAR PURPOSE. 
#
my %opts = (
   host  => {
      type     => "=s",
      variable => "host",
      help     => "Host Name",
      required => 0},
   op  => {
      type     => "=s",
      variable => "operation",
      help     => "Operation (list|disconnect)",
      default  => 'list',
      required => 0},

);

my $env;						# a static variable to cache $env MO
my $login = 0;					# keep track if you logged in.
# validate options, and connect to the server
Opts::add_options(%opts);
Opts::parse();
Opts::validate();
my $op = Opts::get_option ('op');
Fail ("Usage: Op must be list, or disconnect.\n") 
   unless ($op =~ /^list|disconnect$/);
Util::connect();
$login = 1;							# used by Fail.
$| = 1;							# set to unbuffered I/O, improves messages to console

#######################################################################################
#	Decide what type of connection that you have
#		... If through VC, then you need to get the host name argument
#           ... If through ESX, then collect the ESX host view
#######################################################################################
my $host_name;
my $host;
my $sc = Vim::get_service_content();
if ($sc->about->apiType eq "VirtualCenter") {
    Fail ("Please supply the --host parameter.\n") unless (Opts::option_is_set ('host'));
    $host_name = Opts::get_option('host');
    $host = Vim::find_entity_view(view_type => 'HostSystem', filter => {'name' => "$host_name\$"});
    Fail ("Host $host_name not found.\n") unless ($host);
    die "Host ". $opts{host}. " not host found." unless ($host);
    }
else {
    $host = Vim::find_entity_view(view_type => 'HostSystem');
     }    
my $host_moRef = $host->{mo_ref}{value};
#######################################################################################
#	Get all VMs that are currently running on that ESX Server
#######################################################################################

my $vm_views = Vim::find_entity_views(view_type => 'VirtualMachine', filter => {'runtime.host' => $host_moRef});
my $numDevices = 0;
foreach my $vm_view (@$vm_views) {
    next unless ($vm_view->runtime->powerState->val eq 'poweredOn');	# ignore if VM is not powered on
    my $devices = $vm_view->config->hardware->device;
    my $vm_name = $vm_view->name;
    foreach my $device (@$devices) {
        my $name = $device->deviceInfo->label;
        next unless ($device->isa ('VirtualCdrom'));					# look of only CDROM's
        next unless ($device->backing->isa ('VirtualCdromAtapiBackingInfo')); # only connected to host devices
        next unless ($device->connectable->connected == 1);				# only those who are connected
        if ($op eq 'list') {
            print "Virtual Machine      Device\n----------------------------\n" if ($numDevices == 0);
            printf "%-20.20s %s\n", $vm_name, 
                                    $name;
            }
        else {											# simply change the connected flag
            $device->connectable->connected(0);
            my $devSpec = VirtualDeviceConfigSpec->new(
                             operation => VirtualDeviceConfigSpecOperation->new('edit'),
                             device => $device);
            Reconfig ($vm_view, $devSpec, "Disconnecting $name on $vm_name");
            }
         $numDevices++;
        }
    }
print $numDevices, " devices found.\n";
# logout
Util::disconnect();

#########################################################################################
#  Reconfig calls ReconfigVM and interprets status /errors
#########################################################################################

sub Reconfig {
    my ($vm, $devSpec, $msg) = @_;
    print ("$msg ... ");
    my $vmspec = VirtualMachineConfigSpec->new( deviceChange => [$devSpec] );
    eval {
        $vm->ReconfigVM( spec => $vmspec );
         };
    if ($@) {
        print "reconfiguration failed.\n ";
        if ($@->isa ('SoapFault')) {
            print $@->fault_string, "\n";
            }
        else {
            print $@;
            }
        }
    else {
        print "succeeded.\n";
        }
    }

sub Fail {
    my ($msg) = @_;
    Util::disconnect() if ($login);
    die ($msg);
    exit ();
}

__END__

=head1 NAME

cdromDisconnect.pl - Lists or disconnects cd/dvd from all VMs on a host. 

=head1 SYNOPSIS

cdromDisconnect.pl [--host <name>] [--op list|disconnect]

=head1 DESCRIPTION

This script lists or disconnects all cd/dvd devices for all Virtual Machines on a host.

=head1 OPTIONS

=over

=item B<host> I<(optional)>

The target host name.  If connected to an ESX Server, then uses the ESX Server as the target host. Must be specified if you 
connect through VC.

=item B<op> I<(optional)>

The operation to be performed.  Valid operations are: I<list>, and I<disconnect>.

=back

=head1 EXAMPLES

List all of the connected cdrom devices on host abc.

      cdromDisconnect.pl --host abc --op list 

Disconnects all connected cdrom devices on host abc.

      cdromDisconnect.pl --host abc --op disconnect

=head1 SUPPORTED PLATFORMS

All operations are supported on ESX 3.0 and VirtualCenter 2.0 and better.







    

