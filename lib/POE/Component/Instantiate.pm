################################################################################
# This is a non-blocking (forking w/Poe::Wheel::Run) wrapper around the various
# service provider libraries (EC2::Actions, Linode::Actions, and
# VMware::ESX::Actions) The theory is that the Provider libraries should provide
# A common interface for the various Actions, and this module will create task
# lists and run through the tasks sequentially, but without blocking any other
# POE events that are going on at the time...
################################################################################
package POE::Component::Instantiate;
use POE;
use POE qw( Wheel::Run );
use JSON;
$|=1;

# Things we "know how to do"
# the 'sp:*' items go here (service provider)
use EC2::Actions;
use Linode::Actions;
use VMware::ESX::Actions;

# the 'wc:*' items come from here (websages configure)
use WebSages::Configure;

sub new {
    my $class = shift;
    my $self = bless { }, $class;
    my $cnstr = shift if @_;
    $self->{'trace_clipboard'} = 0;
    # Service Provider Items
    $self->{'actions'} = $cnstr->{'sp'}->{'actions'} if $cnstr->{'sp'}->{'actions'};
    $self->{'credentials'} = $cnstr->{'sp'}->{'connection'} if $cnstr->{'sp'}->{'connection'};
    # LDAP (CMDB) Items
    $self->{'ldap'} = $cnstr->{'ldap'} if $cnstr->{'ldap'};
    # The Clipboard
    $self->{'clipboard'} = $cnstr->{'cb'} if $cnstr->{'cb'};
    # The Task
    $self->{'task'} = $cnstr->{'task'} if $cnstr->{'task'};
    # Set up the credentials
    $self->{'sp'} = $self->service_provider();
    $self->{'wc'} = WebSages::Configure->new({
                                               'fqdn'      => $self->{'clipboard'}->{'fqdn'},
                                               'ipaddress' => $self->{'clipboard'}->{'ipaddress'},
                                               'ldap'      => $self->{'ldap'},
                                               'gitosis'   => "$ENV{'GITOSIS_HOME'}",
                                            });
    exit 1 unless( $self->{'wc'} );
    # create the worker session
    POE::Session->create(
                          options => { debug => 0, trace => 0},
                          object_states => [
                                             $self => {
                                                         _start           => "_poe_start",
                                                         do_nonblock      => "do_nonblock",
                                                         redeploy         => "redeploy",
                                                         next_item        => "next_item",
                                                         got_child_stdout => "on_child_stdout",
                                                         got_child_stderr => "on_child_stderr",
                                                         got_child_close  => "on_child_close",
                                                         got_child_signal => "on_child_signal",
                                                         _stop            => "_poe_stop",
                                                      },
                                           ],
                        );
    
    return $self;
}

sub service_provider{
    my $self = shift;
    my $type = shift||$self->{'actions'};
    my $creds = shift||$self->{'credentials'};
    if($type eq 'VMware::ESX'){
        return VMware::ESX::Actions->new($creds);
    }
    if($type eq 'Linode'){
        return Linode::Actions->new($creds);
    } 
    if($type eq 'EC2'){
        return EC2::Actions->new($creds);
    }
}

sub _poe_start {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $heap->{'clipboard'} = $self->{'clipboard'} if $self->{'clipboard'};
    $_[KERNEL]->alias_set("$_[OBJECT]"); # set the object as an alias so it may be "post'ed" to
}

sub _poe_stop {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $_[KERNEL]->alias_remove("$_[OBJECT]");
}

################################################################################
# There are subtle differences in how each type is deployed, here's where we
# make those distinctions. What the service provider api does is only a 
# small part of the actual work that gets done...
#
# These functions are the *remote* function name in the sp: or wc: module
# they will be passed the clipboard when called. The module being called 
# should inspect the clipboard for what it needs before doing work.
################################################################################
sub redeploy {
    my ($self, $kernel, $heap, $sender, $cb, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $type = $self->{'actions'};
    if($type eq 'VMware::ESX'){
        $heap->{'actions'} = [ 
                               "wc:disable_monitoring",       # supress monitoring for the host
                               "sp:shutdown",                  # power off the node
                               "sp:destroy",                   # delete the node from disk
#                               "wc:clean_keys",              # remove exitsing trusted keys (cfengine ppkeys)
#                               "wc:update_AD_DNS",           # update Active Directory DNS with the host's IP
                               "sp:deploy",                    # deploy the new host
                               "sp:get_macaddrs",              # get the MAC address from the API
                               "wc:host_record_updates",       # update ou=Hosts with the new information
                               "wc:ldap_dhcp_install",         # updated the MAC address in LDAP, set do boot pxe
                               "wc:dhcplinks_install",         # call dhcplinks.cgi to generate tftpboot symlinks
                               "sp:startup",                   # power on the vm (it should PXE by default)
                               "wc:wait_for_up",               # while we install...
                               "wc:ldap_dhcp_local",           #   set the ou=DHCP to boot locally
                               "wc:dhcplinks_mainmenu",        #   and call dhcplinks.cgi again to point it to localboot 
                               "wc:wait_for_reboot",           # kickstart will reboot the node
                               "wc:wait_for_ssh",              # wait until ssh is available 
                               #"wc:ship_secret",              # ssh in and create the /usr/local/sbin/secret file
#                               "wc:post_config",               # log in and do any post configuration
#                               "wc:inspect_config",            # poke around and make sure everything looks good
#                               "wc:cleanup",                   # remove any temp files 
                               "wc:enable_monitoring",         # re-enable monitoring for the host
                             ];
    }
    if($type eq 'Linode'){
        $heap->{'actions'} = [ 
                               #"wc:determine_locks",           # abort if the node is owned by anyone other than the requestor
                               #"wc:relocate_services"          # move services that make this a primary node to a failover node
                               "wc:disable_monitoring",        # supress monitoring for the host
                               "sp:shutdown",                  # power off the node
                               "sp:destroy",                   # delete the node from disk
                               "sp:randpass",                  # add a random password to the clipboard
                               "sp:sshpubkey",                 # add the ssh pubkey to be used to the clipboard
                               "sp:deploy",                    # deploy new node
                               "sp:get_pub_ip",                # query the public IP and add it to the clipboard
                               "wc:wait_for_ssh",              # wait until ssh is available 
                               "wc:get_remote_hostkey",        # get the new ssh fingerprints
# BORKEDED no get_ldap_entry   "wc:update_dns",                # update dns sshfp / a records 
                               "wc:mount_opt",                 # log in and mount /opt, set /etc/fstab
                               "sp:set_kernel_pv_grub",        # set the kernel to boot pv_grub on the next boot
                               "wc:make_remote_dsa_keypair",   # generate a ssh-keypair for root
                               "wc:get_remote_dsa_pubkey",     # put it on the clipboard
                               "wc:host_record_updates",       # update ou=Hosts with the new information
                               "wc:save_ldap_secret",          # save the ldap secret if provided
                               "wc:gitosis_deployment_key",    # update the root's key in gitosis (for app deployments)
                               "wc:prime_host",                # download prime and run it (installs JeCM and puppet)
#                               "wc:tail_prime_init_log",      # tail the prime init log until it exits
#                               "wc:wait_for_reboot",          # puppet will install a new kernel and reboot
#                               "wc:wait_for_ssh",            # wait until ssh is available 
                               #"wc:inspect_puppet_logs",     # follow the puppet logs until they error out or complete
#                               "wc:enable_monitoring",        # re-enable monitoring for the host
                             ];
    }
    if($type eq 'EC2'){
        $heap->{'actions'} = [ 
                               "wc:disable_monitoring",        # supress monitoring for the host
                               "sp:shutdown",                  # power off the node
                               "sp:destroy",                   # terminate the instance
                               "wc:clean_keys",                # remove existing trusted keys
                               "sp:deploy",                    # deploy a new slice
                               "sp:get_pub_ip",                # get the remote public IP for the slice
                               "wc:stow_ip",                   # save the public IP in LDAP
                               "wc:ssh_keyscan",               # scan the host for it's new ssh keys
                               "wc:update_dns",                # update dns sshfp / a records
                               "sp:wait_for_ec2_console",      # wait until the node comes up
                               "wc:set_root_password",         # log in and set the root password
                               "wc:make_remote_dsa_keypair",   # create root's ssh keypair
                               "wc:ldap_host_record_update",   # update ou=Hosts with the new information
                               "wc:save_ldap_secret",          # save the LDAP secret
                               "wc:update_gitosis_key",        # update gitosis with the new root ssh-pubkey
                               "wc:prime_hosts",               # download prime and run it (installs JeCM and puppet)
                               "wc:inspect_puppet_logs",       # follow the puppet logs until they error out or complete
                               "wc:enable_monitoring",         # re-enable monitoring for the host
                             ];
    }
    # grab the first job and pass the clipboard and remaining jobs to the first job
    $kernel->yield('next_item'), if($heap->{'actions'}->[0]);
}
    
################################################################################
# Worker Tasks :
#
# any output to STDOUT will be interpreted as YAml ANd will replace the contents
# of $heap->{'clipboard'} (a metaphor for the clipboard being passed back)
################################################################################
sub next_item {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $task = shift(@{ $heap->{'actions'} });
    if($task=~m/([^:]*):(.*)/){
        my ($module, $task) = ($1, $2);
        for(my $i=0;$i<80;$i++){print '-';} 
        print "\n";
        print "$module->$task\n";
        for(my $i=0;$i<80;$i++){print '-';} 
        print "\n";
        $kernel->yield('do_nonblock',
                       sub { 
                               $self->{$module}->$task($heap->{'clipboard'});
                           }
                      );
    }else{
        # if it's not in a module then assume it's ours.
        print "$task\n";
        $kernel->yield('do_nonblock',
                   sub { 
                           $self->$task($heap->{'clipboard'});
                       }
                  );
    }
}

################################################################################
# Forker Tasks
# 
# This is just a textbook case of POE::Wheel::Run that will also re-write the
# $heap->{'clipboard'} with the YAML the child prints to STDOUT (if valid)
################################################################################

sub do_nonblock{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = POE::Wheel::Run->new(
        Program      => $args[0],
        StdoutEvent  => "got_child_stdout",
        StderrEvent  => "got_child_stderr",
        CloseEvent   => "got_child_close",
    );
    $kernel->sig_child($child->PID, "got_child_signal");
    # Wheel events include the wheel's ID.
    $heap->{children_by_wid}{$child->ID} = $child;
    # Signal events include the process ID.
    $heap->{children_by_pid}{$child->PID} = $child;
    print( "Child pid ", $child->PID, " started as wheel ", $child->ID, ".\n");
}

    # Wheel event, including the wheel's ID.
sub on_child_stdout {
    my ($self, $kernel, $heap, $sender, $stdout_line, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ($stdout_line, $wheel_id) = @_[ARG0, ARG1];
    my $child = $heap->{children_by_wid}{$wheel_id};
    $heap->{'child_output'}.="$stdout_line\n";
    print "pid ", $child->PID, " STDOUT: $stdout_line\n" if $self->{'trace_clipboard'};
}

# Wheel event, including the wheel's ID.
sub on_child_stderr {
    my ($self, $kernel, $heap, $sender, $stderr_line, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = $heap->{children_by_wid}{$wheel_id};
    print "pid ", $child->PID, " STDERR: $stderr_line\n" unless($stderr_line=~m/SSL_connect/);
}

# Wheel event, including the wheel's ID.
sub on_child_close {
    my ($self, $kernel, $heap, $sender, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = delete $heap->{children_by_wid}{$wheel_id};

    # May have been reaped by on_child_signal().
    unless (defined $child) {
      print "wid $wheel_id closed all pipes.\n";
      return;
    }
    print "pid ", $child->PID, " closed all pipes.\n";
    delete $heap->{children_by_pid}{$child->PID};
    # only proceed if we've closed
    if(defined($heap->{'child_output'})){
        # FIXME this should be done on a private set of filehandles, not on STDOUT
        my $replacement_clipboard;
        eval { $replacement_clipboard = YAML::Load("$heap->{'child_output'}\n"); };
        if(! $@){
            $heap->{'clipboard'} = $replacement_clipboard;
            print "--------------------\nNew Clipboard:\n--------------------\n$heap->{'child_output'}\n--------------------\n" if $self->{'trace_clipboard'};
        }else{
            # stop all remaining tasks if something printed out to STDOUT that wasn't YAML
            print STDERR "Non-YAML STDOUT found. Aborting work thread.\n";
            print STDERR "################################################################################\n";
            print STDERR "$@\n";
            print STDERR "################################################################################\n";
            print STDERR "$heap->{'child_output'}\n";
            print STDERR "################################################################################\n";
            $heap->{'actions'} = undef;
        }
        $heap->{'child_output'} = undef;
    }
    # move to the next item
  }

sub on_child_signal {
    my ($self, $kernel, $heap, $sender, $wheel_id, $pid, $status) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "pid $pid exited with status $status.\n";
    exit if($status ne 0);
    $kernel->yield('next_item') if($heap->{'actions'}->[0]);
    my $child = delete $heap->{children_by_pid}{$status};
    # May have been reaped by on_child_close().
    return unless defined $child;
    delete $heap->{children_by_wid}{$child->ID};
}
1;
