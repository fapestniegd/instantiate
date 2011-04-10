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
                         'actions'    => 'Linode',
                         'connection' => {
                                           'username' => $ENV{'LINODE_USERNAME'},
                                           'password' => $ENV{'LINODE_PASSWORD'},
                                         },
                       },
             'cb'   => { # clipboard passed from task to task
                         'hostname'      => 'loki',
                         'fqdn'          => 'loki.websages.com',
                         'datacenter'    => 'Atlanta',
                         'guestid'       => 'Debian 6',
                         'linode'        => 512,
                         'sshpubkeyfile' => "$ENV{HOME}/.ssh/id_dsa.pub",
                         'gitosis-admin' => 'gitosis@freyr.websages.com:gitosis-admin.git',
                       },
             'task' => 'redeploy', # what we're asking it to do with $data->{'cb'}
         };
################################################################################

################################################################################
# get the handle to the controller, issue the work to be done and on what
sub _start {
    my ( $self, $kernel, $heap, $sender, @args) = 
     @_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0 .. $#_];
    $heap->{'control'} = POE::Component::Instantiate->new($data);
    #$kernel->delay('tick',5) if $heap->{'count'} < 30;
    $kernel->post( $heap->{'control'}, $data->{'task'});
  }

# tear down the connection to the service provider/vcenter server
sub _stop {
    my ( $self, $kernel, $heap, $sender, @args) = 
     @_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0 .. $#_];
    $kernel->post( $heap->{'control'}, '_stop' );
}

sub tick { # a little something to ensure nothing is actually blocking...
    my ( $self, $kernel, $heap, $sender, @args) = 
     @_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0 .. $#_];
    if($heap->{'count'} < 30){
        print "tick...\n";
        $heap->{'count'}+=1;
        $kernel->delay('tick',3) 
    }else{
        print "*** BOOM! ***\n";
    }
}
################################################################################

################################################################################
# Do it now
POE::Session->create(
                      inline_states => {
                                         _start   => \&_start,
                                         tick     => \&tick,
                                         _stop    => \&_stop,
                                       }
                    );

POE::Kernel->run();
exit 0;
################################################################################
