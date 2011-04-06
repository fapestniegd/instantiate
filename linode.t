#!/usr/bin/perl
BEGIN { unshift @INC, './lib' if -d './lib'; }
$ENV{'IFS'}  = ' \t\n';
$ENV{'HOME'} = $1 if $ENV{'HOME'}=~m/(.*)/;
$ENV{'PATH'} = "/usr/local/bin:/usr/bin:/bin";
use LinodeAPI::Actions;
use Data::Dumper;
my $instance = Linode::API->new({
                                  'username' => $ENV{'LINODE_USERNAME'},
                                  'password' => $ENV{'LINODE_PASSWORD'},
                                });

print STDERR Data::Dumper->Dump([$instance]);
