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
    }
);
Opts::add_options(%opts);

Opts::parse();
Opts::validate();
Util::connect();

my $entity_type = Opts::get_option('entity');
my $entity_name = Opts::get_option('name');
$entity_type = "VirtualMachine" unless $entity_type;
my $entity_views = Vim::find_entity_views(view_type => $entity_type, 'filter'=> { 'name' => $entity_name });

foreach my $entity_view (@$entity_views) {
      my $entity_name = $entity_view->name;
      my $config=$entity_view->config if $entity_view->config;
      my $hardware=$config->hardware if $config->hardware;
      my $device=$hardware->device if $hardware->device;
      foreach my $dev (@{ $device }){
          #print ref($dev)."\n";
          my $type=ref($dev);
          #print grep(/$type/,("VirtualEthernetCard", "VirtualE1000", "VirtualPCNet32", "VirtualVmxnet"))."\n";
          if(grep(/$type/,("VirtualEthernetCard", "VirtualE1000", "VirtualPCNet32", "VirtualVmxnet"))>0){
              print $dev->macAddress."\n"
          }
      }
}
# Disconnect from the server
Util::disconnect();
