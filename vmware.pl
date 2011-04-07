#!/usr/bin/perl
################################################################################
BEGIN { 
        if(-d "/usr/local/lib/vmware-vcli/apps"){
            unshift(@INC,"/usr/local/lib/vmware-vcli/apps") 
        }
        unshift @INC, './lib' if -d './lib'; 
      }

$ENV{'IFS'}  = ' \t\n';
$ENV{'HOME'} = $1 if $ENV{'HOME'}=~m/(.*)/;
$ENV{'PATH'} = "/usr/local/bin:/usr/bin:/bin";
use VMware::ESX::Actions;
#use POE::Component::Instantiate;

# First, get our Design

my $instance = VMware::ESX::Actions->new({ });

if($instance->vm_handle({ 'displayname' => 'badger.eftdomain.net' })){
    $instance->destroy_vm({ 'displayname' => 'badger.eftdomain.net' });
}

$instance->create_vm({
                       'vmname'        => 'badger.eftdomain.net',
                       'vmhost'        => 'lab01.eftdomain.net',
                       'datacenter'    => 'Nashville',
                       'guestid'       => 'rhel5Guest',
                       'datastore'     => 'LUN_300',
                       'disksize'      => 10485760,
                       'memory'        => 512,
                       'num_cpus'      => 1,
                       'nic_network'   => 'VLAN_113',
                       'nic_poweron'   => 0,
                       'resource_pool' => 'Deployment_Lab',
                    });

