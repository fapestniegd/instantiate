#!/usr/bin/perl
BEGIN { unshift @INC, './lib' if -d './lib'; }
use WebSages::Configure;
use Data::Dumper;
$ENV{'IFS'}  = ' \t\n';
$ENV{'HOME'} = $1 if $ENV{'HOME'}=~m/(.*)/;
$ENV{'PATH'} = "/usr/local/bin:/usr/bin:/bin";
my $fqdn='vili.websages.com';
my $wc = WebSages::Configure->new({
                                     'fqdn'           => $fqdn,
                                     'ldap'           => {
                                                           'bind_dn'  => $ENV{'LDAP_BINDDN'},
                                                           'password' => $ENV{'LDAP_PASSWORD'}
                                                         },

                                 });
$dns_entry=$wc->get_dns_record('vili.websages.com');
print "\n".Data::Dumper->Dump([$dns_entry]);
