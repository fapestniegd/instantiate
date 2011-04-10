#!/usr/bin/perl -w

use strict;
use warnings;
use VMware::VIRuntime;
use VMware::VILib;
use Data::Dumper;
$Data::Dumper::Indent = 1;

my %opts = (
    entity => {
        type => "=s",
        help => "ManagedEntity type: HostSystem, etc",
        required => 0,
    },
    name => {
        type => "=s",
        help => "The name of the entity (vm display name)",
        required => 1,
    },
    powerstate => {
        type => "=s",
        help => "The state into which to put the Virtual Machine.",
        required => 1,
    }
);
Opts::add_options(%opts);

Opts::parse();
Opts::validate();
Util::connect();

my $entity_type = Opts::get_option('entity');
my $entity_name = Opts::get_option('name');
my $power_state = Opts::get_option('powerstate');
$power_state=~tr/A-Z/a-z/;

$entity_type = "VirtualMachine" unless $entity_type;
my $entity_views = Vim::find_entity_views(view_type => $entity_type, 'filter'=> { 'name' => $entity_name});

foreach my $entity_view (@$entity_views) { 
    if( $power_state eq "on" ){
        if($entity_view->runtime->powerState->val ne 'poweredOff' && $entity_view->runtime->powerState->val ne 'suspended' ){
            print "The current state of the VM " . $entity_view->name . " is ".
            $entity_view->runtime->powerState->val." "."The poweron operation is not supported in this state\n";
            next ;
        }
        print "Powering on " . $entity_view->name . "\n";
        $entity_view->PowerOnVM();
        print "Poweron successfully completed\n";
    }elsif($power_state eq "off"){
        if($entity_view->runtime->powerState->val ne 'poweredOn'){
            print "The current state of the VM " . $entity_view->name . " is ".
            $entity_view->runtime->powerState->val." "."The poweroff operation is not supported in this state\n";
            next ;
        }
        print "Powering off " . $entity_view->name . "\n";
        $entity_view->PowerOffVM();
        print "Poweroff successfully completed\n";
    }
};

# Disconnect from the server
Util::disconnect();
