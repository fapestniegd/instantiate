#!/usr/bin/perl -w
use Data::Dumper;
use strict;
$|=1;

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
    my $home=$ENV{'HOME'};
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
    my $base = join(",",@dn);
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
    $base =~s/, */,/g;
    $self->connection() unless $self->{'ldap'};
    $mesg = $self->{'ldap'}->search('base' => $base, 'filter' => $filter, 'scope' => 'sub');
    print STDERR "seearch $filter: ". $mesg->error."\n" if($mesg->code && $self->{'debug'});
    my $allsets = undef ;
    foreach my $entry ($mesg->entries) { 
        my $set = $entry->dn();
        $set =~s/, */,/g;
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
my $debug = 0;
my @trace_hosts = @ARGV;
print "Tracing ".join(", ",@trace_hosts)."\n" if($#trace_hosts>=0);
my $cfg = {
            'debug'    => $debug,
            'domain'   => 'eftdomain.net',
            'tftpboot' => '/opt/local/tftpboot',
            'sets_ou'  => 'ou=Sets',
          };

################################################################################
#  subroutines
################################################################################
sub ln {
    my ($link, $target) = (@_);
    if(readlink($link)){
        unlink($link) unless(readlink($link) eq $target);
      }else{
        symlink($target,$link);
   }
}

################################################################################
# First we query our Configuration Management meta-data repository (LDAP)
################################################################################
my $ldap = Net::LDAP::CMDB->new($cfg);
my $entries = $ldap->search("(objectClass=dhcpHost)");

# assemble the global DHCP config.
my $hosts = [];
foreach my $entry (@{ $entries }){ 
    my $host = {};
    if($entry->get_value( 'cn' )){
        $host->{'id'} =  $entry->get_value( 'cn' );
    }
    if($entry->get_value( 'dhcpHWAddress' )){
        $host->{'hardware'} =  $entry->get_value( 'dhcpHWAddress' );
    }
    if($entry->get_value( 'dhcpStatements' )){
        foreach my $statement (@{  $entry->get_value( 'dhcpStatements', asref => 1 ) }){
            if($statement=~m/(\S+)\s+(.*)/){
                $host->{$1} =  $2;
            }
        }
    }
    my @fqdn = split(/\./,$host->{'id'});
    if($#fqdn >0){
        my $hostname = shift(@fqdn);
        my $hostdn = "cn=".$hostname.",ou=Hosts,dc=".join(",dc=",@fqdn);
        my $hostentry = $ldap->get_dn_entry($hostdn);
        print "filename: $host->{'filename'}\n" if(grep(/$host->{'id'}/,@trace_hosts));
        if($host->{'filename'}){
           if($host->{'filename'} eq qq("pxelinux.install")){ 
               if(!defined($hostentry)){
                   print STDERR "$hostdn does not exist in LDAP\n" if(grep(/$host->{'id'}/,@trace_hosts));
               }else{
                   my $sets = $ldap->sets_for($hostentry->dn());
                   print "sets: ".Data::Dumper->Dump([$sets])."\n" if(grep(/$host->{'id'}/,@trace_hosts));
                   foreach my $set (@{ $sets }){
                   print "set: $set\n" if(grep(/$host->{'id'}/,@trace_hosts));
                       my($category, $member)=split(/::/,$set);
                       if($category eq "Operating Systems"){
                           $host->{'os'} = $member;
                       }
                   }
               }
           }
       }
    }else{ 
        print STDERR "cn=$host->{'id'},cn=DHCP,... should be a fully-qualified domain name.\n" if $debug;
    } 
    push(@{ $hosts },$host);
}
print STDERR Data::Dumper->Dump([$hosts]);

################################################################################
# link-chain
################################################################################
chdir("$cfg->{'tftpboot'}/pxelinux.cfg");
foreach my $h (@{ $hosts }){
   if($h->{'filename'}){
       next unless $h->{'id'};
       $h->{'hardware'}=~s/.*ethernet\s+//g;
       my @macocts=split(/:/,$h->{'hardware'});
       for(my $o=0;$o<=$#macocts;$o++){
          if(length($macocts[$o]) == 1){ $macocts[$o]="0".$macocts[$o];} 
       }
       $h->{'hardware'}=join("-",@macocts);
       $h->{'hardware'}="01-".$h->{'hardware'};
       #$symlink_exists = eval { symlink("/usr/local",""); 1 }; 
       $h->{'id'}=$h->{'id'}.".$cfg->{'domain'}" unless($h->{'id'}=~m/$cfg->{'domain'}/);
       my $hexval;
       my @octets=split(/\./,$h->{'fixed-address'});
       foreach my $oct (@octets){
           my $hex = sprintf("%02x", $oct);
           $hexval.=$hex;
        }
        $hexval=~tr/a-z/A-Z/;
        ########################################################################
        # now we create the symlink chain that pxe expects to find.
        ########################################################################
        # 01-00-50-56-95-00-58 -> zabel.lab.eftdomain.net
        ln( $h->{'hardware'}, $h->{'id'} );
        # link  hostname.eftdomain.net -> 192.168.n.m if not already
        ln( $h->{'id'}, $h->{'fixed-address'} );
        # link  192.168.n.m -> C0A8NNMM if not already
        ln( $h->{'fixed-address'}, $hexval );

        ########################################################################
        # and the template the links all point to
        ########################################################################
        # Template out our OS PXE menu
        if($h->{'filename'} eq '"pxelinux.install"'){
            if(defined($h->{'os'})){
                print STDERR "Templating ../pxelinux.menus/install_$h->{'id'}\n";
                my $template = Template->new({'INCLUDE_PATH' => $cfg->{'tftpboot'}."/pxelinux.menus/templates"});
                my $tpl_file = "install_".$h->{'os'}.".tpl"; $tpl_file=~tr/A-Z/a-z/; $tpl_file=~s/\s/_/g;
                my $hostname=$h->{'id'};
                $hostname=~s/\..*//;
                my $vars = { 
                             'hostname'   => $hostname, 
                             'fqdn'       => $h->{'id'}, 
                             'domainname' => $cfg->{'domain'},
                             'next_server' => $h->{'next-server'},
                             'ip'          => $h->{'fixed-address'},
                           };
                $template->process($tpl_file, $vars, "../pxelinux.menus/install_$h->{'id'}");
                ################################################################
                # and make the final link
                ################################################################
                # link C0A8NNMM -> <installer>
                print STDERR "$hexval -> ../pxelinux.menus/install_$h->{'id'}\n";
                ln( $hexval, "../pxelinux.menus/install_$h->{'id'}" );
             }else{
                 # link C0A8NNMM -> main_menu
                 ln( $hexval, "../pxelinux.menus/main_menu" );
                 print STDERR "$h->{'id'} is set to install but has no Operating System Defined.\n";
             }
        }else{
             ln( $hexval, "../pxelinux.menus/main_menu" );
             $hexval='';
        }
    }
}
