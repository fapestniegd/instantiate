#!/usr/bin/perl -w
use Template;
my $template = Template->new({'INCLUDE_PATH' => "/opt/local/kickstart/_TEMPLATES_"});
my $tpl_file = "kickstart_centos_5.tpl"; 
my $vars = { 
             'ip'               => '192.168.13.162',
             'gateway'          => '192.168.13.1',
             'fqdn'             => 'badger.lab.eftdomain.net',
             'hostname'         => 'badger',
             'domainname'       => 'eftdomain.net',
             'nameservers'      => '192.168.1.54',
             'crypt_root_paswd' => '$1$/TWX24ae$82zOJF5hk.IiKw8PbMKoP0',
           };
my $content;
$template->process($tpl_file, $vars, \$content);
print "Content-type: text/plain\n\n";
print $content;
exit 0;
