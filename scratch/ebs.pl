#!/usr/bin/perl -T
################################################################################  
#
################################################################################  
BEGIN { unshift @INC, './lib' if -d './lib'; }
$ENV{'IFS'}  = ' \t\n';
$ENV{'HOME'} = $1 if $ENV{'HOME'}=~m/(.*)/;
$ENV{'PATH'} = "/usr/local/bin:/usr/bin:/bin";

use Data::Dumper;
use EC2::Actions;
$instance = EC2::Actions->new({
                                'access_key' => $ENV{'AWS_ACCESS_KEY_ID'},
                                'secret_key' => $ENV{'AWS_SECRET_ACCESS_KEY'}
                              });
my $ebs_volumes = { 
                    'vol-db7abeb2' => '/dev/sdb',
                    'vol-691eeb00' => '/dev/sdc',
                    'vol-971feafe' => '/dev/sdd',
                    'vol-cdd05aa4' => '/dev/sde',
                  };
my $index=0;
my $instance_id = $instance->id_from_ip('75.101.177.76');
foreach my $reservationinfo ( @{ $instance->describe_instance($instance_id) } ){
    foreach my $runninginstance (@{ $reservationinfo->instances_set() }){
        if( $runninginstance->instance_id == $instance_id ){
            if( ! defined ($runninginstance->block_device_mapping()) ){
                foreach my $volume ( @{ $instance->list_volumes() } ){
                    if(defined($ebs_volumes->{$volume->volume_id()})){
                        my $result = $instance->{'ec2'}->attach_volume({
                                                                         'VolumeId'   => $volume->volume_id(),
                                                                         'InstanceId' => $instance_id,
                                                                         'Device'     => $ebs_volumes->{ $volume->volume_id() },
                                                                       });
                        print Data::Dumper->Dump([$result]);
                    }
                }
            }else{
                foreach my $bdm (@{ $runninginstance->block_device_mapping() } ){
                    my $device_name = $bdm->device_name();
                    my $ebs = $bdm->ebs();
                    my $volume_id = $ebs->volume_id();
                    my $result = $instance->{'ec2'}->detach_volume({
                                                                     'VolumeId'   => $volume_id,
                                                                     'InstanceId' => $instance_id,
                                                                     'Device'     => $device_name,
                                                                   });
                    print Data::Dumper->Dump([$result]);
                }
            }
        }
    }
}
exit 0;
