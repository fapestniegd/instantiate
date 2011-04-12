#!/usr/bin/perl
use strict;
################################################################################
# A skeleton POE wrapper to test how the functionality will work in a bot
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
                         'connection' => { # virtualcenter uses windows creds
                                           'server'   => 'virtualcenter',
                                           'username' => $ENV{'WINDOWS_USERNAME'},
                                           'password' => $ENV{'WINDOWS_PASSWORD'},
                                         },
                       },
             'ldap' => { # credentials for updates to LDAP
                         'uri'         => $ENV{'LDAP_URI'},
                         'base_dn'     => $ENV{'BASE_DN'},
                         'bind_dn'     => $ENV{'BIND_DN'},
                         'password'    => $ENV{'LDAP_PASSWORD'},
                         'dhcp_basedn' => "cn=DHCP,$ENV{'BASE_DN'}"
                       },
         'dhcplinks'=> "http://newton.$ENV{'DOMAIN'}/cgi-bin/dhcplinks.cgi",
             'cb'   => { # clipboard passed from task to task
                         'hostname'       => 'badger',
                         'vmname'         => "badger.lab.$ENV{'DOMAIN'}",
                         'fqdn'           => "badger.lab.$ENV{'DOMAIN'}",
                         'ipaddress'      => '192.168.13.162',
                         'vmhost'         => "lab01.$ENV{'DOMAIN'}",
                         'datacenter'     => 'Nashville',
                         'guestid'        => 'rhel5Guest',
                         'datastore'      => 'LUN_300',
                         'disksize'       => 10485760,
                         'memory'         => 512,
                         'num_cpus'       => 1,
                         'nic_network'    => 'VLAN_113',
                         'nic_poweron'    => 0,
                         'resource_pool'  => 'Deployment_Lab',
                         'dhcplinks'      => "http://newton.$ENV{'DOMAIN'}/cgi-bin/dhcplinks.cgi",
                       },
             'task' => 'redeploy', # what we're asking it use the clipboard for
         };
################################################################################

################################################################################
# get the handle to the controller, issue the work to be done and on what
sub _start {
    my ( $self, $kernel, $heap, $sender, @args) = 
     @_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0 .. $#_];
    $heap->{'control'} = POE::Component::Instantiate->new($data);
    $kernel->post( $heap->{'control'}, $data->{'task'});
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
