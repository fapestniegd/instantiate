package EC2::Actions;
use strict;
use MIME::Base64;
use Net::Amazon::EC2;
use Data::Dumper;

sub new{
    my $class = shift;
    my $construct = shift if @_;
    my $self  = {};
    bless $self;
    $self->{'access_key'} = $construct->{'access_key'} if $construct->{'access_key'};
    $self->{'secret_key'} = $construct->{'secret_key'} if $construct->{'secret_key'};
    $self->{'ec2'} = Net::Amazon::EC2->new(
                                            AWSAccessKeyId  => $self->{'access_key'},
                                            SecretAccessKey =>  $self->{'secret_key'}
                                          );
    if(! defined $self->{'ec2'}){ 
        print STDERR $self->error("unable to instanciate Net::Amazon::EC2 handle");
        return undef;
    }
    return $self;
}

sub error{
    my $self=shift;
    if(@_){
        push(@{ $self->{'ERROR'} }, @_);
    }
    if($#{ $self->{'ERROR'} } >= 0 ){
        return join('\n',@{ $self->{'ERROR'} });
    }
    return undef;
}

sub setsecret{
    my $self=shift;
    $self->{'root_password'} = shift if @_;
    if(!defined $self->{'root_password'}){
        my $_rand;
        my $password_length = 15;
        my @chars = split(" ", "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z - _ % # | 0 1 2 3 4 5 6 7 8 9");
        srand;
        for (my $i=0; $i <= $password_length ;$i++) {
            $_rand = int(rand 41);
            $self->{'root_password'} .= $chars[$_rand];
        }
     }
     return $self->{'root_password'};
}

sub get_root_passwd {
    my $self=shift;
    return $self->{'root_password'};
}

sub ssh_pubkey{
use FileHandle;
    my $self = shift;
    my $keyfile = shift if @_;
    my $pubkey;
    if(-f $keyfile){
        my $fh = new FileHandle;
        if ($fh->open("< $keyfile")) {
           $pubkey=<$fh>;
           $pubkey=~m/(.*)/;
           $self->{'ssh_pubkey'}=$1;
           $fh->close;
        }
    }else{
        print STDERR "Please create an $keyfile\n";
    }
}

sub deploy_instance{
    my $self=shift;
    my $label=shift if @_;
    my $instance = $self->{'ec2'}->run_instances(
                                                  #'ImageId'                        => 'ami-4c986d25',
                                                  'ImageId'                        => 'ami-de1fe9b7',
                                                  'MinCount'                       => 1,
                                                  'MaxCount'                       => 1,
                                                  'KeyName'                        => 'eir',
                                                  'SecurityGroup'                  => [ 'sec.ruby.rails' ],
                                                  'InstanceType'                   => 'm1.small',
                                                  'Placement.AvailabilityZone'     => 'us-east-1d',
                                                  'UserData'                       => encode_base64( 
                                                                                                     "fqdn: $label.websages.com\n".
                                                                                                     "label: $label\n".
                                                                                                     "secret:$self->{'root_password'}\n".
                                                                                                      "string: null\n"
                                                                                                   )
                                      );
    my $state;
    my $instance_id = $instance->instances_set->[0]->instance_id;
    $self->{'handle'}=$instance_id;
    my $running_instances = $self->{'ec2'}->describe_instances( 'InstanceId' => $instance_id );
    foreach my $reservation (@$running_instances) {
        foreach my $instance ($reservation->instances_set) {
            $state=$instance->instance_state->name;
            #my $state=$stateobj->name;
        }
    }
    while ($state ne 'running'){
        my $instance_id = $instance->instances_set->[0]->instance_id;
        my $running_instances = $self->{'ec2'}->describe_instances( 'InstanceId' => $instance_id );
        foreach my $reservation (@$running_instances) {
            foreach my $instance ($reservation->instances_set) {
                $state=$instance->instance_state->name;
                print STDERR $instance->instance_id ." : ".$state."\n";
                if($state eq 'running'){
                    $self->{'public_dns'}=$instance->dns_name;
                    $self->{'private_dns'}=$instance->private_dns_name;
                }
                #my $state=$stateobj->name;
            }
        }
        sleep 10 if($state ne 'running');
    }
    return $self;
}

# an instance handle is a hostname -f for linode and the instance-id for ec2
sub handle{
    my $self=shift;
    return $self->{'handle'} if $self->{'handle'};
    return undef;
}


sub get_remote_pub_ip{
use Net::DNS;
    my $self = shift;
    my $label = shift if @_;
    my $a_list;
    my $name;
    my $running_instances = $self->{'ec2'}->describe_instances();
    foreach my $reservation (@$running_instances) {
        foreach my $instance ($reservation->instances_set) {
            my $state=$instance->instance_state->name;
            if($label eq $instance->{'instance_id'}){
                $name=$instance->{'dns_name'};
                return undef unless $name;
                my $res = Net::DNS::Resolver->new;
                my $query = $res->search($name);
                if ($query){
                    foreach my $rr ($query->answer) {
                        next unless $rr->type eq "A";
                        push(@{ $a_list },$rr->address);
                    }
                } else {
                    warn "query failed: ", $res->errorstring, "\n";
                }
                return $a_list if $a_list;
            }
        }
    }
    return undef;
}

sub wait_for_console{
    my $self=shift;
    my $console_output;
    my $count=0;
    my $got_console=0;
    while((! $got_console)&&($count<=10)){
        print STDERR "Waiting for console login: " if($count>0);
        for(my $i=0; $i<$count; $i++){ print "."; }
        print STDERR "\n" if($count>0);
        $count++;
        eval { 
               # why won't the ec2 module errors die?
               no warnings;
               local *STDERR;
               $SIG{'__WARN__'} = sub {};
               open(STDERR,'>','NUL');
               my $console=$self->{'ec2'}->get_console_output(InstanceId => $self->{'handle'});
               $console_output=$console->output; 
             };
        #sometimes login: never shows up. wtf amazon?
        if($console_output=~m/Starting OpenBSD Secure Shell server:/){ $got_console=1; }
        #print STDERR Data::Dumper->Dump([$console->output]);
        sleep 30 unless $got_console; 
    }
    return $self;
}

# loop through all running instances, look up their IP addresses
# if they match the one given, return the instance_id
sub id_from_ip{
use Net::DNS;
     my $self=shift;
     my $ipaddr=shift if @_; 
     return undef unless $ipaddr;
     my $running_instances = $self->{'ec2'}->describe_instances();
     foreach my $reservation (@$running_instances) {
         foreach my $instance ($reservation->instances_set) {
             my $state=$instance->instance_state->name;
             if($state eq 'running'){
                 my $name=$instance->{'dns_name'};
                 next unless $name;
                 my $res = Net::DNS::Resolver->new;
                 my $query = $res->search($name);
                 if ($query){
                     foreach my $rr ($query->answer) {
                         next unless $rr->type eq "A";
                         if($rr->address eq $ipaddr){
                            return $instance->instance_id; 
                         }
                     }  
                 }
             }
         }
     }
     # if we get here we didn't find it
     return undef;
}

sub terminate{
    my $self = shift;
    my $instance_id=shift if @_;
    return undef unless $instance_id;
    print STDERR "Terminating $instance_id\n";
    $self->{'ec2'}->terminate_instances(InstanceId => $instance_id);
    $self = undef;
    return $self;
}

sub describe_instance{
    my $self = shift;
    my $instance_id = shift if @_;
    return undef unless defined($instance_id);
    return $self->{'ec2'}->describe_instances({ 'InstanceId' => $instance_id });
}

sub list_volumes{
    my $self = shift;
    return $self->{'ec2'}->describe_volumes();
}

sub add_volumes{
    my $self = shift;
#    $self->{'ec2'}->attach_volume({
#                                    'VolumeId'   =>
#                                    'InstanceId' =>
#                                    'Device'     =>
#                                  });
    return $self;
}

1;
