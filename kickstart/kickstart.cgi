#!/usr/bin/perl -w
################################################################################
# a package to query LDAP with our conventions
################################################################################
package Net::LDAP::CMDB;
use Cwd;
use FileHandle;
use Net::LDAP;
sub new{ 
    my $class = shift;
    my $cnstr = shift if(@_);
    my $self = {};
    foreach my $key (keys(%{ $cnstr })){
        $self->{'cfg'}->{ $key } = $cnstr->{$key};
    }
    bless ($self, $class);
    print STDERR "No LDAP configuration file found.\n" unless $self->ldaprc();
    return $self;
}

sub ldaprc{
    my $self = shift;
    my $cwd = cwd();
    my $home=$ENV{'HOME'}||"/etc";
    my $found = 0;
    foreach my $file ("$cwd/ldaprc", "$home/ldaprc", "$home/.ldaprc", "/etc/ldap.conf", "/etc/openldap/ldap.conf"){
        if(-f "$file"){
            $found = 1;
            my $fh = FileHandle->new;
            if($fh->open("< $file")){
                while(my $line=<$fh>){
                    $line=~s/#.*//g;
                    $line=~s/^\s+//g;
                    $line=~s/\s+$//g;
                    next if($line=~m/^$/);
                    if($line=~m/(\S+)\s+(\S+)/){
                        my ($key,$value) = ($1,$2);
                        $key=~tr/A-Z/a-z/;
                        $self->{'cfg'}->{$key} = $value;
                    } 
                }
                $fh->close;
            }
            last;
        }
    }
    return undef unless $found;
    return 1;
}

sub connection{
    my $self = shift;
    if(!defined($self->{'cfg'}->{'uri'})){
        print STDERR "No URI defined. I don't know to what to connect.\n";
        $self->{'ldap'} = undef;
        return $self;
    }
    $self->{'ldap'} = Net::LDAP->new( $self->{'cfg'}->{'uri'} ) or warn "$@";
    my $mesg = undef;
    if(defined($self->{'cfg'}->{'binddn'}) && defined($self->{'cfg'}->{'bindpw'})){
        $mesg = $self->{'ldap'}->bind( $self->{'cfg'}->{'binddn'}, password => ,$self->{'cfg'}->{'bindpw'} );
    }else{
        $mesg = $self->{'ldap'}->bind();
    }
    #print STDERR "connection: ".$mesg->error."\n" if $mesg->code;
    return $self;
}

sub search{
    my $self = shift;
    my $filter = shift;
    if(!defined($self->{'cfg'}->{'base'})){
        print STDERR "No basedn defined. Results will vary.\n";
    }
    my $mesg;
    $self->connection() unless $self->{'ldap'};
    $mesg = $self->{'ldap'}->search(base => $self->{'cfg'}->{'base'}, filter => $filter);
    print STDERR "seearch $filter:". $mesg->error."\n" if($mesg->code);
    my $entries = [ $mesg->entries() ];
    return $entries;
}

sub get_dn_entry{
    my $self = shift;
    my $dn = shift if(@_);
    return undef unless $dn;
    my $mesg;
    my @dn = split(/,/,$dn);
    my $filter = shift(@dn);
    my $base = "ou=Hosts,".join(",",@dn);
    $self->connection() unless $self->{'ldap'};
    $mesg = $self->{'ldap'}->search('base' => $base, 'filter' => $filter, 'scope' => 'one');
    print STDERR "seearch $filter: ". $mesg->error."\n" if($mesg->code && $self->{'debug'});
    foreach my $entry ($mesg->entries) { return $entry; } # there should be only one
    return undef;
}

sub sets_for{
    my $self = shift;
    my $dn = shift if(@_);
    return undef unless $dn;
    my $mesg;
    my $filter = "uniqueMember=$dn";
    my $base = $self->{'cfg'}->{'sets_ou'}.",".$self->{'cfg'}->{'base'};
    $self->connection() unless $self->{'ldap'};
    $mesg = $self->{'ldap'}->search('base' => $base, 'filter' => $filter, 'scope' => 'sub');
    print STDERR "seearch $filter: ". $mesg->error."\n" if($mesg->code && $self->{'debug'});
    my $allsets = undef ;
    foreach my $entry ($mesg->entries) { 
        my $set = $entry->dn();
        $set=~s/,$base$//;
        my @sets_tree=split(/,/,$set);
        my @newset;
        foreach my $subset (reverse(@sets_tree)){
            $subset=~s/^[^=]+=//;
            push(@newset,$subset);
        }
        push(@{$allsets},join("::",@newset));
    }
    return $allsets if( $allsets);
    return undef;
}
1;
################################################################################
#
################################################################################
use Template;
use Data::Dumper;
use strict;

sub validate{
    my $form = shift;
    # It will fail unless you either specify the host or the ip has a PTR
    if(!defined($form->{'host'})){
        $form->{'host'} = ptr($ENV{'REMOTE_ADDR'});
    }
    $form->{'sets'} = sets($form->{'host'});
    return $form;
}
sub ptr{
    use Net::DNS;
    my $ip = shift;
    my $res   = Net::DNS::Resolver->new;
    my $query = $res->search($ip);
  
    if ($query) {
        foreach my $rr ($query->answer) {
            next unless $rr->type eq "PTR";
            return $rr->ptrdname;
        }
    } else {
        warn "query failed: ", $res->errorstring, "\n";
    }
    return undef;
}

sub a{
    use Net::DNS;
    my $ip = shift;
    my $res   = Net::DNS::Resolver->new;
    my $query = $res->search($ip);
  
    if ($query) {
        foreach my $rr ($query->answer) {
            next unless $rr->type eq "A";
            return $rr->address;
        }
    } else {
        warn "query failed: ", $res->errorstring, "\n";
    }
    return undef;
}

sub get_form{
    my ($form, $buffer);
    $ENV{'REQUEST_METHOD'} = 'get' unless defined($ENV{'REQUEST_METHOD'});
    
    $ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
    if ($ENV{'REQUEST_METHOD'} eq "POST"){
        read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
    }else{
	$buffer = $ENV{'QUERY_STRING'};
    }
    # Split information into name/value pairs
    my @pairs = split(/&/, $buffer);
    foreach my $pair (@pairs){
	my ($name, $value) = split(/=/, $pair);
	$value =~ tr/+/ /;
	$value =~ s/%(..)/pack("C", hex($1))/eg;
	$form->{$name} = $value;
    }
    return $form;
}

################################################################################
# 
################################################################################
sub sets{
    my $id = shift;
    my $host;
    my $debug = 0;
    my $cfg = {
                'debug'    => $debug,
                'domain'   => 'eftdomain.net',
                'tftpboot' => '/opt/local/tftpboot',
                'sets_ou'  => 'ou=Sets',
              };

    my $ldap = Net::LDAP::CMDB->new($cfg);
    my $entries = $ldap->search("(objectClass=dhcpHost)");
    ############################################################################
    # Now we look up the individual host's record to get it's os if it's file is
    # pxelinux.install, so we can template out their installer, otherwise (if 
    # the file is pxelinux.0) they just get symlinked to main_menu
    ############################################################################
     my @fqdn = split(/\./,$id);
     if($#fqdn >0){
         my $hostname = shift(@fqdn);
         my $hostdn = "cn=".$hostname.",dc=".join(",dc=",@fqdn);
         my $hostentry = $ldap->get_dn_entry($hostdn);
         if(!defined($hostentry)){
             print STDERR "$hostdn does not exist in LDAP\n" if $debug;
         }else{
             my $sets = $ldap->sets_for($hostentry->dn());
             foreach my $set (@{ $sets }){
                 my($category, $member)=split(/::/,$set);
                 push(@{ $host->{$category} },$member);
             }
         }
    }else{ 
        print STDERR "cn=$host->{'id'},cn=DHCP,... should be a fully-qualified domain name.\n" if $debug;
    } 
    return $host;
}

################################################################################
#
################################################################################
print "Content-type: text/plain\n\n";
my $form = validate( get_form() );
my $fqdn = $form->{'host'};
my @fqdn = split('\.',$fqdn);
my $hostname = shift(@fqdn);
my $domain = join('.',@fqdn);
my $ip = a($fqdn);
my @gateway = split('\.',$ip);
pop(@gateway); push(@gateway, '1');
my $gateway =  join('.',@gateway);
my $tpl_file = "kickstart_".$form->{'sets'}->{'Operating Systems'}->[0].".tpl";
$tpl_file=~tr/A-Z/a-z/;
$tpl_file=~s/\s/_/g;

my $template = Template->new({'INCLUDE_PATH' => "/opt/local/kickstart/templates"});
my $vars = { 
             'ip'          => $ip,
             'gateway'     => $gateway,
             'fqdn'        => $fqdn,
             'hostname'    => $hostname,
             'domainname'  => $domain,
             'nameservers' => '192.168.1.54',
             'rootpw'      => '$1$/TWX24ae$82zOJF5hk.IiKw8PbMKoP0',
             'ldap_srvs'   => 'ldaps://maxwell.eftdomain.net:636 ldaps://faraday.eftdomain.net:636',
           };
my $content;
$template->process($tpl_file, $vars, \$content);
#print Data::Dumper->Dump([$form,$vars,$tpl_file]);
print $content if $content;
exit 0;
################################################################################
#
################################################################################
