#!/usr/bin/perl
use strict;
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
################################################################################

use POE;
use POE::Component::Instantiate;

################################################################################
# This is our clipboard, it has the job wer're going to pass around
################################################################################
my $data = { 
             'sp'   => { # servic provider we call actions against
                         'actions'    => 'VMware::ESX',
                         'connection' => {
                                           'server'   => 'virtualcenter',
                                           'username' => $ENV{'WINDOWS_USERNAME'},
                                           'password' => $ENV{'WINDOWS_PASSWORD'},
                                         },
                       },
             'cb'   => { # clipboard passed from task to task
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
                       },
             'task' => 'redeploy', # what we're asking it to do with $data->{'cb'}
         };
################################################################################

################################################################################
# get the handle to the controller, issue the work to be done and on what
sub _start {
    my ( $self, $kernel, $heap, $sender, @args) = 
     @_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0 .. $#_];
    $heap->{'control'} = POE::Component::Instantiate->new($data->{'sp'});
    $kernel->post( $heap->{'control'}, $data->{'task'}, $data->{'cb'} );
  }

# tear down the connection to the service provider/vcenter server
sub _stop {
    my ( $self, $kernel, $heap, $sender, @args) = 
     @_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0 .. $#_];
    $kernel->post( $heap->{'control'}, '_stop' );
}
################################################################################

################################################################################
# Do it now
POE::Session->create(
                      inline_states => {
                                         _start   => \&_start,
                                         _stop    => \&_stop,
                                       }
                    );

POE::Kernel->run();
exit 0;
################################################################################
