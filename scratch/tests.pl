#!/usr/bin/perl 
BEGIN { unshift @INC, './lib' if -d './lib'; }
$ENV{'IFS'}  = ' \t\n';
$ENV{'HOME'} = $1 if $ENV{'HOME'}=~m/(.*)/;
$ENV{'PATH'} = "/usr/local/bin:/usr/bin:/bin";
use Data::Dumper;
use EC2::Actions;
use LinodeAPI::Actions;
use WebSages::Configure;
use Getopt::Long;
    Getopt::Long::Configure ("Bundling");

my $fqdn='vili.websages.com';
my $wc = WebSages::Configure->new({
                                     'fqdn'   => $fqdn,
                                     'ldap'   => {
                                                   'bind_dn'  => $ENV{'LDAP_BINDDN'},
                                                   'password' => $ENV{'LDAP_PASSWORD'}
                                                 },
                                     'github' => {
                                                   'login'    => $ENV{'GITHUB_LOGIN'},
                                                   'password' => $ENV{'GITHUB_PASSWORD'}
                                                 }
                                  });
exit unless(defined  $wc);
$wc->get_host_record;

print Data::Dumper->Dump([$wc]);
