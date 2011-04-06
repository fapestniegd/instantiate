#!/usr/bin/perl -w
#
# Copyright (c) 2007 VMware, Inc.  All rights reserved.
#

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../";

use VMware::VIM2Runtime;
use VMware::VILib;
use AppUtil::VMUtil;

$Util::script_version = "1.0";

my %opts = (
	
   host => {
      type => "=s",
      help => "Ip of the Host machine",
      required => 1,
      default => "",
   },
   vm => {
      type => "=s",
      help => "Name of the virtual machine",
      required => 1,
      default => "",
   },
   cdrom => {
      type => "=s",
      help => "The Label of the CD Drive",
      required => 0,
      default => "CD/DVD Drive ",
   }
);

Opts::add_options(%opts);
Opts::parse();
Opts::validate();

Util::connect();

my %filterhash = ();
my @device_config_specs;
my $vm_views = VMUtils::get_vms('VirtualMachine',
                                   Opts::get_option('vm'),
                                   undef,
                                   undef,
                                   undef,
                                   Opts::get_option('host'),
                                   %filterhash);
my $vm_view = shift (@$vm_views);

if($vm_view) {
   @device_config_specs = createISO_cd_spec($vm_view,
                                            Opts::get_option('cdrom'),
                                            'edit');
   reconfig_vm();
}

sub reconfig_vm {
   my $vmspec;
   if(@device_config_specs) {
      $vmspec = VirtualMachineConfigSpec->new(deviceChange => \@device_config_specs);
   }
   else {
      Util::trace(0,"\nNo reconfiguration performed as there "
                  . "is no device config spec created.\n");
      return;
   }

   eval {
      $vm_view->ReconfigVM( spec => $vmspec );
      Util::trace(0,"\nVirtual machine '" . $vm_view->name
                  . "' is reconfigured successfully.\n");
   };
   if ($@) {
       Util::trace(0, "\nReconfiguration failed: ");
       if (ref($@) eq 'SoapFault') {
          if (ref($@->detail) eq 'TooManyDevices') {
             Util::trace(0, "\nNumber of virtual devices exceeds "
                          . "the maximum for a given controller.\n");
          }
          elsif (ref($@->detail) eq 'InvalidDeviceSpec') {
             Util::trace(0, "The Device configuration is not valid\n");
             Util::trace(0, "\nFollowing is the detailed error: \n\n$@");
          }
          elsif (ref($@->detail) eq 'FileAlreadyExists') {
             Util::trace(0, "\nOperation failed because file already exists");
          }
          else {
             Util::trace(0, "\n" . $@ . "\n");
          }
       }
       else {
          Util::trace(0, "\n" . $@ . "\n");
       }
   }
}

sub createISO_cd_spec {
   my ($vm_view, $name) = @_;
   my $config_spec_operation;
   my $cd;

   $config_spec_operation = VirtualDeviceConfigSpecOperation->new('edit');
   $cd = VMUtils::find_device(vm => $vm_view,
                                  controller => $name);
# You can get the below fileName value from the user either in the form of parameter or in the XML
   my $vcdisobi = VirtualCdromIsoBackingInfo->new(
                      fileName => '[storage1] /vmimages/ISO/Win2K.iso');
   $cd->{backing} = $vcdisobi;
   if($cd) {
      my $devspec = VirtualDeviceConfigSpec->new(operation => $config_spec_operation,
                                                 device => $cd);
      return $devspec;
   }
   return undef;
}
