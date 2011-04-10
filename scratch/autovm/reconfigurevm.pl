#!/usr/bin/perl -w

use strict;
use warnings;
use VMware::VIRuntime;
use VMware::VILib;
use Data::Dumper;
$Data::Dumper::Indent = 1;

my %opts = (
    entity => {
        type => "=s",
        help => "ManagedEntity type: HostSystem, etc",
        required => 0,
    },
    name => {
        type => "=s",
        help => "The name of the entity (vm display name)",
        required => 1,
    }
);
Opts::add_options(%opts);

Opts::parse();
Opts::validate();
Util::connect();

my $entity_type = Opts::get_option('entity');
my $entity_name = Opts::get_option('name');
$entity_type = "VirtualMachine" unless $entity_type;
my $entity_views = Vim::find_entity_views(view_type => $entity_type, 'filter'=> { 'name' => $entity_name});

foreach my $entity_view (@$entity_views) {
    my $entity_name = $entity_view->name;
    my $devices = $entity_view->config->hardware->device;
    foreach my $device (@$devices) {
        my $name = $device->deviceInfo->label;
        next unless ($device->isa ('VirtualCdrom'));                                    # look of only CDROM's
        next unless ($device->backing->isa ('VirtualCdromIsoBackingInfo'));             # Only ISOs
        next unless ($device->connectable->connected == 1);                             # only those who are connected
        my $controller_key=$device->{'controllerKey'};
        my $devspec = VirtualDeviceConfigSpec->new(
                          device  => VirtualCdrom->new(
                              backing => VirtualCdromAtapiBackingInfo->new( deviceName => "/dev/cdrom",
                                                                            exclusive  => 0
                                                                                ),
                             connectable => VirtualDeviceConnectInfo->new( allowGuestControl => 1,
                                                                           connected         => 0, #needed & documented as not.
                                                                           startConnected    => 0 ),
                             controllerKey => $controller_key,
                             key => int(3000),
                             unitNumber => 0),
                             operation => VirtualDeviceConfigSpecOperation->new( 'edit' ) );
        Reconfig ($entity_view, $devspec, "Disconnecting $name on $entity_name");
    }
}

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

# Disconnect from the server
Util::disconnect();
