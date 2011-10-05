package VMware::ESX::Actions;
use strict;
use warnings;
use POE qw( Wheel::Run );

use FindBin;
use lib "$FindBin::Bin/../";

use VMware::VIRuntime;
use XML::LibXML;
use AppUtil::XMLInputUtil;
use AppUtil::HostUtil;
use Data::Dumper;

our $tracelevel = 0;
our $tracefilter;

$Util::script_version = "1.0";

sub new{
    my $class = shift;
    my $self = bless { }, $class;
    my $cnstr = shift if @_;
    $self->{'vicfg'}->{'VI_PROTOCOL'}    = $cnstr->{'protocol'}    || $ENV{'VI_PROTOCOL'}    || "https";
    $self->{'vicfg'}->{'VI_PORTNUMBER'}  = $cnstr->{'port'}        || $ENV{'VI_PORTNUMBER'}  || "443";
    $self->{'vicfg'}->{'VI_SERVER'}      = $cnstr->{'server'}      || $ENV{'VI_SERVER'}      || "virtualcenter";
    $self->{'vicfg'}->{'VI_SERVICEPATH'} = $cnstr->{'servicepath'} || $ENV{'VI_SERVICEPATH'} || "/sdk";
    $self->{'vicfg'}->{'VI_USERNAME'}    = $cnstr->{'username'}    || $ENV{'VI_USERNAME'}    || $ENV{'LOGNAME'};
    $self->{'vicfg'}->{'VI_PASSWORD'}    = $cnstr->{'password'}    || $ENV{'VI_PASSWORD'}    || $ENV{'AD_PASSWORD'};
    $self->{'actions'} = $cnstr->{'actions'} if($cnstr->{'actions'});
    return $self;
}

sub do{
    my $self = shift;
    my $method = shift if @_;
    my $clipboard = shift if @_;
    $self->load_env();
    Opts::parse();
    #foreach my $key (keys (%ENV)){
    #   if($key=~m/VI_/){
    #       print STDERR "$key $ENV{$key}\n";
    #   }
    #}
    Opts::validate();
    Util::connect();
    $self->$method($clipboard);
    Util::disconnect();
    $self->flush_env();
}

################################################################################
# Wrappers for the non-blocking API, takes clipboard, prints clipboard on stdout
################################################################################
sub shutdown{
    my $self = shift;
    my $cb = shift if @_;
    $self->do('power_off',$cb);
    return $self;
}

sub startup{
    my $self = shift;
    my $cb = shift if @_;
    $self->do('power_on',$cb);
    return $self;
}

sub destroy{
    my $self = shift;
    my $cb = shift if @_;
    $self->do('destroy_vm',$cb);
    return $self;
}

sub deploy{
    my $self = shift;
    my $cb = shift if @_;
    print STDERR Data::Dumper->Dump([ 'cb' => $cb]);
    $self->do('create_vm',$cb);
    return $self;
}

sub get_macaddrs{
    my $self = shift;
    my $cb = shift if @_;
    $self->do('vm_macaddrs',$cb);
    return $self;
}
################################################################################
#
################################################################################

################################################################################
# The blocking API for top-down "[Do It Now]" scripts. (Heavy Lifting Done Here)
################################################################################
sub trace{
   my ($self, $level, $text) = @_;
   if (($level <= $tracelevel) && (defined $text)) {
      if (defined($tracefilter)) {
         if ($text !~ $tracefilter) {
            print STDERR $text;
         }
      } else {
         print STDERR $text;
      }
   }
   return;
}

sub power_on {
    my $self = shift;
    my $clipboard = shift;
    my $name = $clipboard->{'vmname'} if $clipboard->{'vmname'};
    return undef unless $name;
    my $vm = $self->vm_handle({ 'displayname' => $name });
    return undef if($vm->runtime->powerState->val eq 'poweredOn');
    my $mor_host = $vm->runtime->host;
    my $hostname = Vim::get_view(mo_ref => $mor_host)->name;
    eval {
           $vm->PowerOnVM();
           $self->trace(0, "\nvirtual machine '" . $vm->name .
                          "' under host $hostname powered on \n");
         };
    if($@){
        if(ref($@) eq 'SoapFault'){
            $self->trace (2, "\nError in '" . $vm->name . "' under host $hostname: ");
            if(ref($@->detail) eq 'NotSupported'){
                $self->trace(2,"Virtual machine is marked as a template ");
            }elsif(ref($@->detail) eq 'InvalidPowerState'){
                $self->trace(2, "The attempted operation cannot be performed in the current state" );
            }elsif(ref($@->detail) eq 'InvalidState'){
                $self->trace(2,"Current State of the virtual machine is not supported for this operation");
            }else{
                $self->trace(2, "VM '"  .$vm->name. "' can't be powered on \n" . $@ . "" );
            }
        }else{
            $self->trace(2, "VM '"  .$vm->name. "' can't be powered on \n" . $@ . "" );
        }
    }
}

sub power_off{
    my $self = shift;
    my $clipboard = shift;
    my $name = $clipboard->{'vmname'} if $clipboard->{'vmname'};
    return undef unless $name;
    my $vm = $self->vm_handle({ 'displayname' => $name });
    return undef unless $vm;
    return undef if($vm->runtime->powerState->val eq 'poweredOff');
    my $mor_host = $vm->runtime->host;
    my $hostname = Vim::get_view(mo_ref => $mor_host)->name;
    eval {
           $vm->PowerOffVM();
           $self->trace (0, "\nvirtual machine '" . $vm->name . "' under host $hostname powered off ");
         };
    if($@){
        if(ref($@) eq 'SoapFault'){
            $self->trace (0, "\nError in '" . $vm->name . "' under host $hostname: ");
            if (ref($@->detail) eq 'InvalidPowerState'){
                $self->trace(0, "The attempted operation". " cannot be performed in the current state" );
            }elsif(ref($@->detail) eq 'InvalidState'){
                $self->trace(0,"Current State of the"." virtual machine is not supported for this operation");
            }elsif(ref($@->detail) eq 'NotSupported'){
                $self->trace(0,"Virtual machine is marked as template");
            }else{
                $self->trace(0, "VM '"  .$vm->name. "' can't be powered off \n". $@ . "" );
            }
        }else{
            $self->trace(0, "VM '"  .$vm->name. "' can't be powered off \n" . $@ . "" );
        }
    }
}

# The vi perl toolkit can read these from the environment
sub load_env{
    my $self = shift;
    foreach my $env (keys(%{ $self->{'vicfg'} })){
        $self->{'env_cache'} = $ENV{$env}||undef;
        $ENV{$env} = $self->{'vicfg'}->{ $env };
    }
    return $self;
}

# flush the environment if we set it
sub flush_env{
    my $self = shift;
    foreach my $env (keys(%{ $self->{'vicfg'} })){
        $ENV{$env} = $self->{'env_cache'}||'';
    }
    return $self;
}

sub vm_handle{
    my $self = shift;
    my $cnstr = shift if @_;
    my $vm_displayname = $cnstr->{'displayname'};
    return undef unless $vm_displayname;
    $self->load_env();
    my $vm_view = Vim::find_entity_view( 
                                         'view_type' => 'VirtualMachine',
                                         'filter'    => { 'config.name' => $vm_displayname }
                                       );
    $self->flush_env();
    return $vm_view;
}

sub vm_macaddrs{
    my $self = shift;
    my $cb = shift if @_;
    my $vm = $cb->{'vmname'} if  $cb->{'vmname'};
    my $macaddrs;
    if(ref($vm) ne 'VirtualMachine'){
        $vm = $self->vm_handle({ 'displayname' => $vm });
    }
    return undef unless(ref($vm) eq 'VirtualMachine');
    my $config = $vm->config if $vm->config;
    my $hardware = $config->hardware if $config->hardware;
    my $device=$hardware->device if $hardware->device;
    foreach my $dev (@{ $device }){
        #print ref($dev)."\n";
        my $type=ref($dev);
        #print grep(/$type/,("VirtualEthernetCard", "VirtualE1000", "VirtualPCNet32", "VirtualVmxnet"))."\n";
        if(grep(/$type/,("VirtualEthernetCard", "VirtualE1000", "VirtualPCNet32", "VirtualVmxnet"))>0){
            push(@{ $macaddrs },$dev->macAddress);
        }
    }
    $cb->{'macaddrs'} = $macaddrs;
    print YAML::Dump($cb);
}

sub destroy_vm{
    my $self = shift;
    my $clipboard = shift;
    my $vm = $clipboard->{'vmname'} if $clipboard->{'vmname'};
    if(ref($vm) ne 'VirtualMachine'){
        $vm = $self->vm_handle({ 'displayname' => $vm });
    }
    return undef unless(ref($vm) eq 'VirtualMachine');
    $self->load_env();
    my $res = $vm->Destroy();
    $self->flush_env();
    return $res;
}

# create a virtual machine
# ========================
sub create_vm {
   my $self = shift;
   my $args = shift if @_;
   print STDERR Data::Dumper->Dump([ 'args' => $args]);
   my @vm_devices;
   $self->load_env();
   my $host_view = Vim::find_entity_view(view_type => 'HostSystem',
                                         filter    => {'name' => $args->{'vmhost'}});
   if (!$host_view) {
       $self->trace(0, "\nError creating VM '$args->{'vmname'}': " 
                      . "Host '$args->{'vmhost'}' not found\n");
       return;
   }

   my %ds_info = HostUtils::get_datastore(
                                           host_view => $host_view,
                                           datastore => $args->{'datastore'},
                                           disksize  => $args->{'disksize'}
                                         );

   if ($ds_info{mor} eq 0) {
      if ($ds_info{name} eq 'datastore_error') {
         $self->trace(0, "\nError creating VM '$args->{'vmname'}': "
                      . "Datastore $args->{'datastore'} not available.\n");
         return;
      }
      if ($ds_info{name} eq 'disksize_error') {
         $self->trace(0, "\nError creating VM '$args->{'vmname'}': The free space "
                      . "available is less than the specified disksize.\n");
         return;
      }
   }
   my $ds_path = "[" . $ds_info{name} . "]";

   my $controller_vm_dev_conf_spec = $self->create_conf_spec();
   my $disk_vm_dev_conf_spec = $self->create_virtual_disk({
                                                            ds_path => $ds_path, 
                                                            disksize => $args->{'disksize'}
                                                          });
   my %net_settings = $self->get_network({
                                           network_name => $args->{'nic_network'},
                                           poweron      => $args->{'nic_poweron'},
                                           host_view    => $host_view
                                         });

   if($net_settings{'error'} eq 0) {
      push(@vm_devices, $net_settings{'network_conf'});
   } elsif ($net_settings{'error'} eq 1) {
      $self->trace(0, "\nError creating VM '$args->{'vmname'}': "
                    . "Network '$args->{'nic_network'}' not found\n");
      return;
   }

   push(@vm_devices, $controller_vm_dev_conf_spec);
   push(@vm_devices, $disk_vm_dev_conf_spec);

   my $files = VirtualMachineFileInfo->new(logDirectory => undef,
                                           snapshotDirectory => undef,
                                           suspendDirectory => undef,
                                           vmPathName => $ds_path);
   my $vm_config_spec = VirtualMachineConfigSpec->new(
                                             name => $args->{'vmname'},
                                             memoryMB => $args->{'memory'},
                                             files => $files,
                                             numCPUs => $args->{'num_cpus'},
                                             guestId => $args->{'guestid'},
                                             deviceChange => \@vm_devices);

   my $datacenter_views = Vim::find_entity_views (
                                                   view_type => 'Datacenter',
                                                   filter => { name => $args->{'datacenter'} }
                                                 );

   unless (@$datacenter_views) {
      $self->trace(0, "\nError creating VM '$args->{'vmname'}': "
                   . "Datacenter '$args->{'datacenter'}' not found\n");
      return;
   }

   if ($#{$datacenter_views} != 0) {
      $self->trace(0, "\nError creating VM '$args->{'vmname'}': "
                   . "Datacenter '$args->{'datacenter'}' not unique\n");
      return;
   }
   my $datacenter = shift @$datacenter_views;
   my $vm_folder_view = Vim::get_view(mo_ref => $datacenter->vmFolder);
   my $comp_res_view = Vim::get_view(mo_ref => $host_view->parent);
   my $respool_handle = $comp_res_view->resourcePool;
   my $respool_res_view = Vim::get_view(mo_ref => $comp_res_view->resourcePool);
   for my $subpool (@{ $respool_res_view->resourcePool }){
       my $respool = Vim::get_view(mo_ref => $subpool);
       if($respool->name eq $args->{'resource_pool'}){
           $respool_handle = $respool;
       }
   }
   eval {
      $vm_folder_view->CreateVM(
                                 config => $vm_config_spec, 
                                 pool => $respool_handle
                               );
      $self->trace(0, "\nSuccessfully created virtual machine: "
                       ."'$args->{'vmname'}' under host $args->{'vmhost'}\n");
    };
    if ($@) {
       $self->trace(0, "\nError creating VM '$args->{'vmname'}': ");
       print Data::Dumper->Dump([$@]);
       if (ref($@) eq 'SoapFault') {
          if (ref($@->detail) eq 'PlatformConfigFault') {
             $self->trace(0, "Invalid VM configuration: "
                            . ${$@->detail}{'text'} . "\n");
          }
          elsif (ref($@->detail) eq 'InvalidDeviceSpec') {
             $self->trace(0, "Invalid Device configuration: "
                            . ${$@->detail}{'property'} . "\n");
          }
           elsif (ref($@->detail) eq 'DatacenterMismatch') {
             $self->trace(0, "DatacenterMismatch, the input arguments had entities "
                          . "that did not belong to the same datacenter\n");
          }
           elsif (ref($@->detail) eq 'HostNotConnected') {
             $self->trace(0, "Unable to communicate with the remote host,"
                         . " since it is disconnected\n");
          }
          elsif (ref($@->detail) eq 'InvalidState') {
             $self->trace(0, "The operation is not allowed in the current state\n");
          }
          elsif (ref($@->detail) eq 'DuplicateName') {
             $self->trace(0, "Virtual machine already exists.\n");
          }
        }
        else {
              $self->trace(0, "\n" . $@ . "\n");
        }
   }
   $self->flush_env();
}

# create virtual device config spec for controller
# ================================================
sub create_conf_spec {
   my $self = shift; 
   my $controller =
      VirtualLsiLogicController->new(
                                      key => 0,
                                      device => [0],
                                      busNumber => 0,
                                      sharedBus => VirtualSCSISharing->new('noSharing')
                                    );

   my $controller_vm_dev_conf_spec =
      VirtualDeviceConfigSpec->new(
                                    device => $controller,
                                    operation => VirtualDeviceConfigSpecOperation->new('add')
                                  );
   return $controller_vm_dev_conf_spec;
}

# create virtual device config spec for disk
# ==========================================
sub create_virtual_disk {
   my $self = shift;
   my $args = shift if @_;
   my $ds_path = $args->{'ds_path'};
   my $disksize = $args->{'disksize'};

   my $disk_backing_info =
      VirtualDiskFlatVer2BackingInfo->new(diskMode => 'persistent',
                                          fileName => $ds_path);

   my $disk = VirtualDisk->new(
                                backing => $disk_backing_info,
                                controllerKey => 0,
                                key => 0,
                                unitNumber => 0,
                                capacityInKB => $disksize
                              );

   my $disk_vm_dev_conf_spec =
      VirtualDeviceConfigSpec->new(
                                    device        => $disk,
                                    fileOperation => VirtualDeviceConfigSpecFileOperation->new('create'),
                                    operation     => VirtualDeviceConfigSpecOperation->new('add')
                                  );
   return $disk_vm_dev_conf_spec;
}
 
# get network configuration
# =========================
sub get_network {
   my $self = shift;
   my $args = shift if @_;
   my $network_name = $args->{'network_name'};
   my $poweron = $args->{'poweron'};
   my $host_view = $args->{'host_view'};
   my $network = undef;
   my $unit_num = 1;  # 1 since 0 is used by disk

   if($network_name) {
      my $network_list = Vim::get_views(mo_ref_array => $host_view->network);
      foreach (@$network_list) {
         if($network_name eq $_->name) {
            $network = $_;
            my $nic_backing_info =
               VirtualEthernetCardNetworkBackingInfo->new(
                                                           deviceName => $network_name,
                                                           network => $network
                                                         );

            my $vd_connect_info =
               VirtualDeviceConnectInfo->new(allowGuestControl => 1,
                                             connected => 0,
                                             startConnected => 1);

            my $nic = VirtualPCNet32->new(backing => $nic_backing_info,
                                          key => 0,
                                          unitNumber => $unit_num,
                                          addressType => 'generated',
                                          connectable => $vd_connect_info);

            my $nic_vm_dev_conf_spec =
               VirtualDeviceConfigSpec->new(device => $nic,
                     operation => VirtualDeviceConfigSpecOperation->new('add'));

            return (error => 0, network_conf => $nic_vm_dev_conf_spec);
         }
      }
      if (!defined($network)) {
      # no network found
       return (error => 1);
      }
   }
    # default network will be used
    return (error => 2);
}
################################################################################
#
################################################################################
1;
