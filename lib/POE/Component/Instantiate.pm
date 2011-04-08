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
use EC2::Actions;
use LinodeAPI::Actions;
use VMware::ESX::Actions;

sub new {
    my $class = shift;
    my $self = bless { }, $class;
    my $cnstr = shift if @_;
    $self->{'action'} = $cnstr->{'action'}."::Action" if $cnstr->{'action'};
    $self->{'credentials'} = $cnstr->{'connection'} if $cnstr->{'connection'};
    POE::Session->create(
                          options => { debug => 0, trace => 0},
                          object_states => [
                                             $self => {
                                                         _start           => "_poe_start",
                                                         add_clipboard    => "add_clipboard",
                                                         shutdown         => "shutdown",
                                                         destroy          => "destroy",
                                                         clean_keys       => "clean_keys",
                                                         deploy           => "deploy",
                                                         get_macaddr      => "get_macaddr",
                                                         ldap_pxe         =>  "ldap_pxe",
                                                         dhcplinks        => "dhcplinks",
                                                         poweron          => "poweron",
                                                         ping_until_up    => "ping_until_up",
                                                         ldap_nopxe       => "ldap_nopxe",
                                                         ping_until_down  => "ping_until_down",
                                                         post_config      => "post_config",
                                                         inspect_config   => "inspect_config",
                                                         cleanup          => "cleanup",
                                                         redeploy         => "local_redeploy",
                                                         do_nonblock      => "do_nonblock",
                                                         got_child_stdout => "on_child_stdout",
                                                         got_child_stderr => "on_child_stderr",
                                                         got_child_close  => "on_child_close",
                                                         got_child_signal => "on_child_signal",
                                                         _stop           => "_poe_stop",
                                                      },
                                           ],
                        );
    return $self;
}

sub service_provider{
    my $self = shift;
    my $type = shift||$self->{'action'};
    my $creds = shift||$self->{'credentials'};
    if($type == 'VMware::ESX'){
        return VMware::ESX::Actions->new($creds);
    }
    if($type == 'Linode'){
        return Linode::Actions->new($creds);
    }
    if($type == 'EC2'){
        return EC2::Actions->new($creds);
    }
}

sub _poe_start {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $_[KERNEL]->alias_set("$_[OBJECT]"); # set the object as an alias so it may be 'posted' to
}

sub _poe_stop {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $_[KERNEL]->alias_remove("$_[OBJECT]");
}

################################################################################
# Master Tasks
################################################################################
sub add_clipboard{
    my ($self, $kernel, $heap, $sender, $cb, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $heap->{'clipboard'} = $cb;
}

sub local_redeploy {
    my ($self, $kernel, $heap, $sender, $cb, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $heap->{'actions'} = [ 
                           "shutdown", "destroy", "clean_keys", "deploy", "get_macaddr", "ldap_pxe", 
                           "dhcplinks", "poweron", "ping_until_up", "ldap_nopxe", "ping_until_down", 
                           "ping_until_up", "post_config", "inspect_config", "cleanup"
                         ];
    # grab the first job and pass the clipboard and remaining jobs to the first job
    $kernel->yield(shift(@{ $heap->{'actions'} }), $actions, $cb) if($heap->{'actions'}->[0]);
}


################################################################################
# Worker Tasks
################################################################################
sub shutdown {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "shutdown\n";
    $kernel->yield('do_nonblock',
                   sub {
                         # Deploy if not exist
                         $self->{'instance'} = $self->service_provider();
                         $self->{'instance'}->power_off($heap->{'clipboard'}->{'vmname'});
                         $self->{'instance'}->teardown();
                       }
                  );
}

sub destroy {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "destroy\n";
    $kernel->yield('do_nonblock',
                   sub {
                         # Destroy if exist
                         $self->{'instance'} = $self->service_provider();
                         if($self->{'instance'}->vm_handle({ 'displayname' => $heap->{'clipboard'}->{'vmname'} })){
                             $self->{'instance'}->destroy_vm({ 'displayname' => $heap->{'clipboard'}->{'vmname'}});
                         }
                         $self->{'instance'}->teardown();
                       }
                  );
}

sub clean_keys {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "clean_keys\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub deploy {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "deploy\n";
    $kernel->yield('do_nonblock',
                   sub {
                         # Deploy if not exist
                         $self->{'instance'} = $self->service_provider();
                         if(! $self->{'instance'}->vm_handle({ 'displayname' => $heap->{'clipboard'}->{'vmname'} })){
                             $self->{'instance'}->create_vm($heap->{'clipboard'});
                         }
                         $self->{'instance'}->teardown();
                       }
                  );
}

sub get_macaddr {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "get_macaddr\n";
    $kernel->yield('do_nonblock',
                   sub {
                         # Deploy if not exist
                         $self->{'instance'} = $self->service_provider();
                         $heap->{'clipboard'}->{'macaddrs'} = 
                             $self->{'instance'}->vm_macaddrs($heap->{'clipboard'}->{'vmname'});
                         $self->{'instance'}->teardown();
                       }
                  );
}

sub ldap_pxe {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "ldap_pxe\n";
    # macaddr(s) should be defined in the clipboard now.
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub dhcplinks {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "dhcplinks\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub poweron {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "poweron\n";
    $kernel->yield('do_nonblock',
                   sub {
                         # Deploy if not exist
                         $self->{'instance'} = $self->service_provider();
                         $self->{'instance'}->power_on($heap->{'clipboard'}->{'vmname'});
                         $self->{'instance'}->teardown();
                       }
                  );
}

sub ping_until_up {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "ping_until_up\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub ldap_nopxe {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "ldap_nopxe\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub ping_until_down {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "ping_until_down\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub post_config {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "post_config\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub inspect_config {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "inspect_config\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

sub cleanup {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "cleanup\n";
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
}

################################################################################
# Forker Tasks
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
    #print "pid ", $child->PID, " STDOUT: $stdout_line\n";
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
        eval { $heap->{'clipboard'} = YAML::Load("$heap->{'child_output'}\n"); };
        $heap->{'child_output'} = undef;
    }
    $kernel->yield(shift(@{ $heap->{'actions'} })) if($heap->{'actions'}->[0]);
  }

sub on_child_signal {
    my ($self, $kernel, $heap, $sender, $wheel_id, $pid, $status) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "pid $pid exited with status $status.\n";
    exit if($status ne 0);
    my $child = delete $heap->{children_by_pid}{$status};
    # May have been reaped by on_child_close().
    return unless defined $child;
    delete $heap->{children_by_wid}{$child->ID};
}
1;
