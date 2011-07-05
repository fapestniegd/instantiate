package WebSages::Configure;
use GitHub::Mechanize;
use Net::LDAP;
use Net::LDAP::Entry;
use File::Temp qw/ tempfile tempdir cleanup /;

sub new{
    my $class = shift;
    my $construct = shift if @_;
    my $self  = {};
    ############################################################################
    # Here we look at what was handed to us, and if it's "incomplete" we try
    # to assume some "sane" defaults or look them up from the infrastructure.
    ############################################################################
    foreach my $item (
                      "fqdn", "hostname", "domain", "secret",
                      "gitosis_admin_uri", "gitosis_admin_dir", "ldap",
                     ){
         $self->{$item} = $construct->{$item} if $construct->{$item};
    }
    if(!defined $self->{'fqdn'}){ # a fqdn is mandatory
        print STDERR "I need a fqdn.\n";
        return undef;
    } 
    # ldap may be handed to us directly or in an "ldap" hash
    foreach my $ldap_item ( "uri","base_dn", "bind_dn", "password", "dhcp_basedn"){
         $self->{$ldap_item} = $construct->{$ldap_item}||$construct->{'ldap'}->{$ldap_item};
    }
    delete $self->{'ldap'}; # no need to store it twice
    unless ($self->{'hostname'}){ # extract the hostname from the fqdn
        $self->{'hostname'} = $construct->{'fqdn'} if $construct->{'fqdn'};
        $self->{'hostname'} = $1 if($self->{'hostname'}=~m/([^\.]+)\..*/);
    }
    unless ($self->{'domain'}){ # exttract the domain name from the fqdn
        $self->{'domain'} = $construct->{'fqdn'} if $construct->{'fqdn'};
        $self->{'domain'} = $2 if($self->{'domain'}=~m/([^\.]+)\.(.*)/);
    }
    unless ($self->{'basedn'}){ # exttract the basedn from the domain
        $self->{'basedn'} = $self->{'domain'};
        $self->{'basedn'}=~s/\./,dc=/g;
        $self->{'basedn'}= "dc=".$self->{'basedn'};
    }
    unless ($self->{'ipaddress'}){ # look up the ipaddress from the fqdn
       print STDERR "/* FIXME Add a DNS Lookup */\n";
    }
    # Create a temp file for our ssh operations:
    # Known hosts errors are expected on redeployments.
    ($fh, $self->{'known_hosts'}) = tempfile();

    bless $self;
    return $self;
}

################################################################################
# POE::Component::Instantiate wrappers (take one arg (the clipboard) and pass 
# the clipboard back by printing YAML to STDOUT
# In the next iteration, this should be a sub-class of the blocking class
################################################################################

sub disable_monitoring{
    my $self = shift;
    print STDERR "You should really disable monitoring here.\n";
    return $self;
}

sub enable_monitoring{
    my $self = shift;
    print STDERR "You should really enable monitoring here.\n";
    return $self;
}

sub ldap_dhcp_local{
    my $self = shift;
    my $cb = shift if @_;
    $self->ldap_dhcp_install($cb,0);
}

sub sleep_10{
    my $self = shift;
    my $cb = shift if @_;
    sleep 10; 
    exit 0;
}

sub ldap_dhcp_install{
    my $self = shift;
    my $cb = shift if @_;
    my $install = shift if @_;
    $install = 1 unless(defined($install));
    my $filename = undef;
    if($install == 0){ $filename="pxelinux.0"; }else{ $filename="pxelinux.install"; }
    print STDERR "update cn=DHCP $filename\n";
    my $entries = $self->get_ldap_entries({
                                            'filter' => "(cn=$self->{'fqdn'})",
                                            'base'   => $self->{'dhcp_basedn'},
                                            'scope'  => 'sub',
                                          });
    my $entry;
    my $new_macs;
    foreach my $mac (@{ $cb->{'macaddrs'} }){
        push (@{ $new_macs }, "ethernet ".$mac);
    } 
    if($entries){
        if($#entries > 0){
            foreach $entry (@{ $entries }){
                $entry->delete;
            }
        }else{
            $entry = shift @{ $entries };
            #modify the entry with our new mac 
            $entry->replace ( 
                               'dhcpHWAddress' => $new_macs,
                               'dhcpStatements'=> [
                                                    "filename \"$filename\"",
                                                    "fixed-address $cb->{'ipaddress'}",
                                                    "next-server 192.168.1.217",
                                                    "use-host-decl-names on",
                                                  ],
                            );
        }
    }else{
        print STDERR "no entry cn=$self->{'fqdn'} in $self->{'dhcp_basedn'} with scope sub\n";
         # create new entry
         $entry = Net::LDAP::Entry->new();;
         $entry->dn("cn=$cb->{'fqdn'}, cn=DHCP,$self->{'base_dn'}");
         my $router = $cb->{'ipaddress'};
         $router=~s/\.[^\.]+$/.1/; # this is probably a bad assumption
         $entry->add( 
                                         'cn'             => "$cb->{'fqdn'}",
                                         'objectClass'    => [
                                                               "top",
                                                               "dhcpHost",
                                                               "dhcpOptions",
                                                             ],
                                          'dhcpHWAddress' => $new_macs,
                                          'dhcpStatements'=> [
                                                               "filename \"$filename\"",
                                                               "fixed-address $cb->{'ipaddress'}",
                                                               "next-server 192.168.1.217",
                                                               "use-host-decl-names on",
                                                             ],
                                          'dhcpOption'    => [
                                                               "option-233 = \"$cb->{'hostname'}\"",
                                                               "routers $router",
                                                               "subnet-mask 255.255.255.0"
                                                             ]
                                        );
    }
    # update the entry
    $self->ldap_entry_update( $entry );
    return $self;
}

sub dhcplinks{
use LWP::UserAgent;
    my $self = shift;
    my $cb = shift if @_;
    my $ua = LWP::UserAgent->new;
    $ua->agent("__PACKAGE__/0.1 ");

    # Create a request
    my $req = HTTP::Request->new(GET => $cb->{'dhcplinks'});

    # Pass request to the user agent and get a response back
    my $res = $ua->request($req);
    # Check the outcome of the response
    if ($res->is_success) {
        print STDERR $res->content;
    }else{
        print STDERR $res->status_line, "\n";
    }
}

################################################################################
# Functions below this should be standalone (not take the $clipboard as an arg)
################################################################################
sub find_ldap_servers{ # locate our ldap uris (use if not provided)
use Net::DNS;
    my $self = shift;
    return [ $self->{'uri'} ] if $self->{'uri'};
    my $res = Net::DNS::Resolver->new;
    my $servers;
    my $query = $res->query("_ldap._tcp.".$self->{'domain'}, "SRV");
    if ($query){
        foreach my $rr (grep { $_->type eq 'SRV' } $query->answer) {
            my $host=$rr->{'target'};
            if($rr->{'port'} == 636){ push(@{ $servers },"ldaps://$host:636"); }
            if($rr->{'port'} == 389){ push(@{ $servers },"ldap://$host:389"); }
        }
    }
    return $servers if $servers;
    return undef;
}

sub get_ldap_handle{
    my $self = shift;
    my $servers;
    if(@_){ # replace any handle we have with a handle to this one
        $servers = shift if @_;
        $servers = [ $servers ] unless(ref($servers) eq 'ARRAY');
    }else{
        $servers = $self->find_ldap_servers() unless $servers;
    }
    my $mesg;
    while($server=shift(@{$servers})){
        if($server=~m/(.*)/){
            $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/);
        }
        $self->{'ldap'} = Net::LDAP->new($server) || warn "could not connect to $server $@";
        next if($self->{'ldap'} == 1);
        $mesg = $self->{'ldap'}->bind( $self->{'bind_dn'}, password => $self->{'password'} );
        #$mesg->code && print STDERR $mesg->error."\n";
        print STDERR $mesg->error."\n";
        next if $mesg->code;
        return $self->{'ldap'};
    }
    return undef;
}

sub get_ldap_entries{
    my $self = shift;
    $self->{'ldap'} = $self->get_ldap_handle() unless $self->{'ldap'};
    return undef unless $self->{'ldap'};
    my $search = shift if @_;
    return undef unless $search;
    $search->{'base'} = $self->{'basdn'} unless $search->{'base'};
    $search->{'filter'} = "(objectclass=*)" unless $search->{'filter'};
    $search->{'scope'} = "sub" unless $search->{'scope'};
    my $records = $self->{'ldap'}->search( 
                                           'filter' => $search->{'filter'},
                                           'base'   => $search->{'base'},
                                           'scope'  => $search->{'scope'},
                                         );
    $records->code && die $records->error;
    undef $servers unless $records->{'resultCode'};
    my $recs;
    foreach $entry ($records->entries) { 
        push(@{ $recs }, $entry);
    }
    return $recs;
}

# Update LDAP
sub ldap_entry_update{
    my $self = shift;
    my $entry = shift if @_;
    return undef unless $entry;
    $self->{'ldap'} = $self->get_ldap_handle() unless $self->{'ldap'};
    return undef unless $self->{'ldap'};
    my $mesg = $entry->update( $self->{'ldap'} );
    #$mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
    exit $mesg->code;
#    $mesg = $ldap->add( $entry );
#        if($mesg->code == 68){
#            $mesg = $ldap->delete($entry->{'asn'}->{'objectName'});
#            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
#            if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
#                foreach my $ref (@{ $mesg->{'referral'} }){
#                    if($ref=~m/(ldap.*:.*)\/.*/){
#                        $cb->{'server'} = $ref;
#                        $cb->{'entry'} = $entry;
#                        $self->update_ldap_entry($cb);
#                    }
#                }
#            }else{
#                $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
#            }
#            $mesg = $ldap->add( $entry );
#            if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
#                foreach my $ref (@{ $mesg->{'referral'} }){
#                    if($ref=~m/(ldap.*:.*)\/.*/){
#                        $cb->{'server'} = $ref;
#                        $cb->{'entry'} = $entry;
#                        $self->update_ldap_entry($cb);
#                    }
#                }
#            }else{
#                $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
#            }
#
#            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
#        }elsif(($mesg->code == 10) && ($mesg->error eq "Referral received")){
#                foreach my $ref (@{ $mesg->{'referral'} }){
#                    if($ref=~m/(ldap.*:.*)\/.*/){
#                        $cb->{'server'} = $ref;
#                        $cb->{'entry'} = $entry;
#                        $self->update_ldap_entry($cb);
#                    }
#                }
#        }else{
#            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
#        }
#          
#    }
#    print STDERR "Done updating ".$entry->{'asn'}->{'objectName'}."\n";
#    return $self;
}

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################

sub rexec{
    my $self = shift;
    my $remote_command = shift if @_;
    #eval { 
    #       local $SIG{__WARN__} = sub {}; 
    #       local *STDERR;
           print STDERR qq(ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} "$remote_command\n");
           system qq(ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} "$remote_command");
           print SDTERR "$!\n$?\n";
    #     };
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

sub chpasswd_root{
    my $self = shift;
    my $passwd = shift if @_;
    $passwd=$passwd||$self->{'secret'};
    $self->rexec("echo 'root:$passwd' | chpasswd");
    return undef unless $passwd;
    return $self;
}

################################################################################
# Functions below this should be audited for cleanup
################################################################################

sub backup_known_hosts{
    my $self = shift;
    if(-f "$ENV{'HOME'}/.ssh/known_hosts"){
        print STDERR "Moving your $ENV{'HOME'}/.ssh out of the way...\n";
        system ("/bin/mv $ENV{'HOME'}/.ssh/known_hosts $ENV{'HOME'}/.ssh/known_hosts.predeploy-instance");
    }
    return $self;
}

sub restore_known_hosts{
    my $self = shift;
    # move the known_hosts file back
    if(-f "$ENV{'HOME'}/.ssh/known_hosts.predeploy-instance"){
        print STDERR "Moving your $ENV{'HOME'}/.ssh back...\n";
        system ("/bin/mv $ENV{'HOME'}/.ssh/known_hosts.predeploy-instance $ENV{'HOME'}/.ssh/known_hosts");
    }
    return $self;
}


sub get_remote_hostkey{
    my $self = shift;
    my $cb = shift if @_;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    # wait for ssh to become available and get it's ssh-key so it won't ask
    system qq(ssh-keyscan $self->{'ipaddress'} > $self->{'known_hosts'});
    while( -z "$self->{'known_hosts'}" ){
        print STDERR "ssh isn't up yet, sleeping 5...\n";
        sleep 5;
        system qq(ssh-keyscan $self->{'ipaddress'} > $self->{'known_hosts'});
    }
    print STDERR "-=[$self->{'ipaddress'}]=-\n";
    if( -f  "/usr/bin/sshfp"){
        open(SSHFP,"/usr/bin/sshfp $self->{'ipaddress'}|");
        while(my $sshfprecord=<SSHFP>){
            chomp($sshfprecord);
            # remove the cruft
            $sshfprecord=~s/^\S+\s+[Ii][Nn]\s+[Ss][Ss][Hh][Ff][Pp]\s+//;
            push(@{ $cb->{'sshfp'} }, $sshfprecord);
        }
        close(SSHFP);
    }else{
        print STDERR "no /usr/bin/sshfp found. skipping sshfp DNS record\n";
    }
    print YAML::Dump($cb);
    return $self;
}

# this should be a puppet class
sub mount_opt{
    my $self = shift;
    my $cb = shift;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    # mount the opt disk
    $self->rexec("/bin/grep -q /dev/xvdc /etc/fstab||/bin/echo '/dev/xvdc /opt ext3 noatime,errors=remount-ro 0 1'>>/etc/fstab");
    $self->rexec("/bin/grep -q ' /opt ' /etc/mtab || /bin/mount -a");
    return $self;
}

sub prime_host{
    my $self = shift;
    my $cb = shift if @_;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    $self->{'fqdn'} = $cb->{'fqdn'};
    $self->{'ldap_secret'} = $cb->{'password'};
    # fetch prime and fire it off
    $self->rexec("/usr/bin/wget --no-check-certificate -qO /root/prime https://github.com/fapestniegd/prime/raw/master/prime");
    $self->rexec("/bin/chmod 755 /root/prime");
    my $got_init=0;
    my $count=0;
    while((! $got_init)&&($count < 5)){
        $self->rexec("/root/prime $self->{'fqdn'} $self->{'ldap_secret'} > /var/log/prime-init.log 2>\&1 \&");
        $count++;
        print STDERR "Verifying initialization, (try: $count);\n";
        open (SSH,"ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} ls -l /var/log/prime-init.log 2>/dev/null |");
        chomp(my $initlog=<SSH>); 
        $got_init=1 if($initlog);
        sleep 3 unless $got_init;
        close(SSH);
    }
    return $self;
}

sub make_remote_dsa_keypair{
    my $self = shift;
    my $cb = shift;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    print STDERR "Making remote dsa keypair\n";
    # regenerate a dsa public key (if there isn't one?)
    $self->rexec("if [ ! -f /root/.ssh/id_dsa.pub ];then /usr/bin/ssh-keygen -t dsa -N '' -C \"root\@\$(hostname -f)\" -f /root/.ssh/id_dsa>/dev/null 2>&1;fi");
    return $self;
}

# Save the new LDAP secret on the host
sub save_ldap_secret{
    my $self = shift;
    my $cb = shift if @_;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    $self->{'secret'} = $cb->{'password'};
    # save the deployment ldap_secret to the host's /etc/ldap/ldap.conf
    $self->rexec("if [ ! -d /etc/ldap ]; then /bin/mkdir -p /etc/ldap; fi");
    $self->rexec("umask 377 && echo $self->{'secret'} > /etc/ldap/ldap.secret");
    return $self;
}

sub get_ldap_secret{
    my $self = shift;
    my $cb = shift;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    # save the deployment ldap_secret to the host's /etc/ldap/ldap.conf
    open(CMD,"ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} \'cat /etc/ldap/ldap.secret\'|");
    my $secret=<CMD>;
    chomp($secret);
    close(CMD);
    return $secret;
}

sub get_remote_dsa_pubkey{
    my $self = shift;
    my $cb = shift if @_;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    my ($ssh_key, $newkey);
    open PUBKEY, qq(ssh -o UserKnownHostsFile=$self->{'known_hosts'} root\@$self->{'ipaddress'} 'if [ -f /root/.ssh/id_dsa.pub ]; then /bin/cat /root/.ssh/id_dsa.pub ;fi'|)
        ||warn "could not open ssh for read";
    while($ssh_key=<PUBKEY>){
        chomp($ssh_key);
        if($ssh_key=~m/^ssh-dss/){ $newkey=$ssh_key; }
    }
    close(PUBKEY);
    $cb->{'remote_ssh_pubkey'}=$newkey;
    print YAML::Dump($cb);
    return $self->{'remote_ssh_pubkey'};
}

sub gitosis_deployment_key{
    my $self = shift;
    my $cb = shift if @_;
    $self->add_gitosis_deployment_pubkey( $cb->{'remote_ssh_pubkey'}, $cb->{'gitosis-admin'} );
}

sub add_gitosis_deployment_pubkey{
use File::Temp qw/ tempdir /;
    my $self = shift;
    my $rootpubkey = shift if @_;
    $self->{'gitosis-admin'} = shift if @_;
    $self->{'gitosis_base'} = tempdir( CLEANUP => 1 );
    unless(defined($rootpubkey)){
        print STDERR "No pubkey supplied";
        return undef;
    }
    print STDERR "Updating gitosis deployment key to $self->{'gitosis_base'}/gitosis-admin\n"; 
    my $git_remote = undef;
   
    # if it's not there, clone it.
    if(! -f "$self->{'gitosis_base'}/gitosis-admin/.git/config"){ 
        system("cd $self->{'gitosis_base'}; /usr/bin/git clone $self->{'gitosis-admin'} >/dev/null 2>&1");
    }

    # if it's still not there, abort;
    if(! -f "$self->{'gitosis_base'}/gitosis-admin/.git/config"){ 
        print STDERR "unable to locate config file: $self->{'gitosis_base'}/.git/config\n";
        return undef;
    }else{
        open(GITCONF,"$self->{'gitosis_base'}/gitosis-admin/.git/config");
        my $in_origin=0;
        while(my $line=<GITCONF>){
            chomp($line);
            if($on==1){
                if($line=~m/^\s*\[/){ 
                    $on=0; 
                };
            }
            if($on==1){
                if($line=~m/url\s+=\s+.*@(.*):.*/){
                    $git_remote=$1;
                }
            }
            if($line=~m/\[remote "origin"\]/){ 
                $on=1; 
            };
        }
        close(GITCONF);
    }
    my $modified=0;
    if(-f "$self->{'gitosis_base'}/gitosis-admin/gitosis.conf"){
        print STDERR "Updating gitosis.conf [group deployments]\n"; 
        open(GITOSISCONF,"$self->{'gitosis_base'}/gitosis-admin/gitosis.conf");
        open(NEWCONF,"> $self->{'gitosis_base'}/gitosis-admin/gitosis.conf.new");
        my $in_deployments=0;
        while(my $line=<GITOSISCONF>){
            chomp($line);
            if($on==1){
                if($line=~m/^\s*\[/){ 
                    $on=0; 
                };
            }
            if($on==1){
                if($line=~m/members\s+=\s+(.*)/){
                    $member_list=$1;
                    unless($member_list=~m/root\@$self->{'fqdn'}/){
                        $line=$line." root\@$self->{'fqdn'}";
                        $modified=1;
                    }
                }
            }
            if($line=~m/\[group deployments\]/){ 
                $on=1; 
            };
            print NEWCONF "$line\n";
        }
        close(NEWCONF);
        close(GITOSISCONF);
    }else{
        print STDERR "no $self->{'gitosis_base'}/gitosis-admin/gitosis.conf to modify?\n";
    }
    if($modified == 1){
        print STDERR "gitosis.conf modified.\n";
        system("/bin/mv $self->{'gitosis_base'}/gitosis-admin/gitosis.conf.new $self->{'gitosis_base'}/gitosis-admin/gitosis.conf");
    }else{
        print STDERR "Key was already in deployments, no modification needed.\n";
        system("/bin/rm $self->{'gitosis_base'}/gitosis-admin/gitosis.conf.new");
    }
    # we have to use our own known hosts file here to keep git from needing a .ssh/config, ugh.
    if(defined($git_remote)){
        system("ssh-keyscan -t dsa,rsa,rsa1 $git_remote >> $ENV{'HOME'}/.ssh/known_hosts");
    }else{
        print STDERR "ssh-keyscan -t dsa,rsa,rsa1 $git_remote >> $ENV{'HOME'}/.ssh/known_hosts\n";
        print STDERR "Unable to determine remote git server for ssh-keyscan\n";
    }
    system("(cd $self->{'gitosis_base'}/gitosis-admin; /usr/bin/git pull >/dev/null 2>&1)");
    open(ROOTPUBKEY, "> $self->{'gitosis_base'}/gitosis-admin/keydir/root\@$self->{'fqdn'}.pub");
    print ROOTPUBKEY "$rootpubkey\n";
    close(ROOTPUBKEY);
    system("(cd $self->{'gitosis_base'}/gitosis-admin; /usr/bin/git add keydir/root\@$self->{'fqdn'}.pub) >/dev/null 2>&1");
    system("(cd $self->{'gitosis_base'}/gitosis-admin; /usr/bin/git commit -a -m \"new $self->{'fqdn'}.pub\") >/dev/null 2>&1");
    system("(cd $self->{'gitosis_base'}/gitosis-admin; /usr/bin/git push >/dev/null 2>&1)");
}

sub add_github_deployment_pubkey{
    my $self = shift;
    my $newkey = shift if @_;
    # put the ssh key as a deployment key in teh GitHubs
    print STDERR "Adding ssh public key as a deploy key to our private repository on GitHub (websages)\n";
    my $gh = GitHub::Mechanize->new({
                                      'repo' => "websages",
                                      'live' => 1,
                                      'writecache' => 1,
                                      'cache' => './cache',
                                      'debug' => 1
                                    });
    if($gh){
             $gh->replace_deploy_key({
                                       'name' => "$self->{'hostname'}-root",
                                       'key' => $newkey
                                     });
    }
    return $self;
}


# Update LDAP with the new information from the host
sub host_record_updates{
    my $self = shift;
    my $cb = shift if @_;
    print STDERR "Updating: cn=$self->{'hostname'},ou=Hosts,$self->{'basedn'}\n";
    my $userPassword = $self->ssha( $cb->{'password'} );
    my ($servers,$mesg);
    $servers = [ $cb->{'server'} ] if $cb->{'server'};
    $servers = $self->find_ldap_servers() unless $servers;
    my $existing_entry=$self->get_host_record();
    while($server=shift(@{$servers})){
        if($server=~m/(.*)/){
            $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/);
        }
        next unless($server eq "ldaps://freyr.websages.com:636");
        my $ldap = Net::LDAP->new($server) || warn "could not connect to $server $@";
        next if($ldap == 1);
        $mesg = $ldap->bind( $ENV{'LDAP_BINDDN'}, password => $ENV{'LDAP_PASSWORD'});
        undef $servers unless $mesg->{'resultCode'};
        $mesg->code && print STDERR $mesg->error."\n";
        if($existing_entry){
            print STDERR "Modifying cn=$self->{'hostname'},ou=Hosts,$self->{'basedn'}\n";
            $mesg = $ldap->modify( 
                                   "cn=$self->{'hostname'},ou=Hosts,$self->{'basedn'}", 
                                   'changes' => [ 
                                                  'replace' => [ 
                                                                 'userPassword' => $userPassword,
                                                                 'ipHostNumber' => $cb->{'ipaddress'}
                                                               ] 
                                                ] 
                                 );
            if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
                foreach my $ref (@{ $mesg->{'referral'} }){
                    if($ref=~m/(ldap.*:.*)\/.*/){
                        $cb->{'server'} = $ref;
                        $self->host_record_updates($cb);
                    }
                }
            }else{
                $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
            }
        }else{
            print STDERR "Adding cn=$self->{'hostname'},ou=Hosts,$self->{'basedn'}\n";
            $mesg = $ldap->add( 
                                "cn=$self->{'hostname'},ou=Hosts,$self->{'basedn'}", 
                                'attr' => [ 
                                            'objectclass' => [
                                                               'device',
                                                               'ipHost',
                                                               'top',
                                                               'simpleSecurityObject'
                                                             ],
                                            'userpassword' => [
                                                                $userPassword,
                                                              ],
                                            'cn' => [
                                                      $cb->{'hostname'}
                                                    ],
                                            'iphostnumber' => [
                                                                $cb->{'ipaddress'}
                                                              ]
                                          ] 
                              );
            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
        }
    }
    print STDERR "Done updating cn=$self->{'hostname'},ou=Hosts,$self->{'basedn'}\n";
    return $self;
}

sub get_host_record{
use Net::LDAP;
    my $self = shift;
    my $servers=$self->find_ldap_servers();
    my $mesg;
    while($server=shift(@{$servers})){
        if($server=~m/(.*)/){
            $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/);
        }
        my $ldap = Net::LDAP->new($server) || warn "could not connect to $server $@";
        next if($ldap == 1);
        $mesg = $ldap->bind( $ENV{'LDAP_BINDDN'}, password => $ENV{'LDAP_PASSWORD'});
        $mesg->code && print STDERR $mesg->error."\n";
        next if $mesg->code;
        my $records = $ldap->search( 
                                     'base'   => "ou=Hosts,$self->{'basedn'}", 
                                     'scope'  => 'sub',
                                     'filter' => "(cn=$self->{'hostname'})",
                                   );
        undef $servers unless $records->{'resultCode'};
        my $recs;
        my @entries = $records->entries;
        if($#entries > 0){
            $mesg = $ldap->delete( "cn=$Hostname,ou=Hosts,$self->{'basedn'}");
            $mesg->code && print STDERR $mesg->error;
            return undef;
        }elsif($#entries == 0){
            $mesg = $ldap->unbind;
            $mesg->code && print STDERR $mesg->error;
            return $entries[0];
        }
    }
    return undef;
}

sub get_dns_record{
use Net::LDAP;
    my $self = shift;
    my $fqdn = shift if @_;
    my @fqdn = split(/\./,$fqdn);
    my $hostname = shift(@fqdn);
    my $dns_base="dc=".join(",dc=",@fqdn).",ou=DNS,".$self->{'basedn'};
    return $self->get_ldap_entry( 
                                 {
                                    'filter' => "relativeDomainname=$hostname",
                                    'scope'  =>  'one',
                                    'base'   =>  $dns_base,
                                  }
                                 );
}

sub ip_from_cn{
    my $self=shift;
    $self->{'hostname'}=shift if @_;
    my $entry=$self->get_host_record();
    my $ipaddress=$entry->get_value( 'ipHostNumber' );
    return $ipaddress;
}

sub new_secret{
use Digest::SHA1;
use MIME::Base64;
    my $self=shift;
    my $password_length=shift if @_;
    my ($password,$salt);
    my $_rand;
    if (!$password_length) { $password_length = 15; }
    if (!$salt_length) { $salt_length = 4; }
    my @chars = split(" ", "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z - _ % # | 0 1 2 3 4 5 6 7 8 9");
    srand;

    for (my $i=0; $i <= $password_length ;$i++) {
        $_rand = int(rand 41);
        $password .= $chars[$_rand];
    }
    $self->{'secret'}=$password;

    for (my $i=0; $i <= $salt_length ;$i++) {
        $_rand = int(rand 41);
        $salt .= $chars[$_rand];
    }
    $self->{'salt'}=$salt;

    my $ctx = Digest::SHA1->new;
    $ctx->add($self->{'secret'}); 
    $ctx->add($self->{'salt'});
    $self->{'userPassword'} = '{SSHA}' . encode_base64($ctx->digest . $self->{'salt'} ,'');
    #print STDERR "-=[ $self->{'secret'} :: $self->{'salt'} ::  $self->{'userPassword'} ]=-\n";
    return $self->{'secret'};
}

sub ssha{
    my $self = shift;
    my $plaintext = shift if @_;
    my ($salt,$userPassword);
    my $_rand;
    if (!$salt_length) { $salt_length = 4; }
    my @chars = split(" ", "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z - _ % # | 0 1 2 3 4 5 6 7 8 9");
    srand;
    for (my $i=0; $i <= $salt_length ;$i++) {
        $_rand = int(rand 41);
        $salt .= $chars[$_rand];
    }

    my $ctx = Digest::SHA1->new;
    $ctx->add($plaintext); 
    $ctx->add($salt);
    $userPassword = '{SSHA}' . encode_base64($ctx->digest . $salt ,'');
    print STDERR "\n\n\n$plaintext :: $salt :: $userPassword\n\n\n";
    return $userPassword;
}

sub configure_remote_host{
    my $self = shift;
    # get ip should this go here or elsewhere?
    #$self->add_dns_record($ip_address);
    $self->backup_known_hosts();
    $self->get_remote_hostkey();
    $self->make_remote_dsa_keypair();
    $self->get_remote_dsa_pubkey();
    $self->add_github_deployment_pubkey();
    $self->mount_opt();
    #$self->add_ldap_simplesecurityobject();
    #$self->add_ldap_group();
    $self->wcyd_init();
    $self->restore_known_hosts();
    return $self;
}

sub update_dns{
    my $self = shift;
    my $cb = shift if @_;
    print STDERR "Getting DNS entry\n" if($debug > 0);
    my $dns_entry = $self->get_dns_record($cb->{'fqdn'});
    $dns_entry->replace ( 'aRecord'     => $cb->{'ipaddress'}, 'sSHFPRecord' => $cb->{'sshfp'} );
    print STDERR "Updating LDAP entry\n" if($debug > 0);
    $self->update_ldap_entry({ 'entry' => $dns_entry });
}


# use the ipaddress here or it will cache in DNS
sub wait_for_ssh{
    my $self=shift;
    my $cb = shift if @_;
    my $ip;
    (ref($cb->{'ipaddress'}) eq 'ARRAY')?$ip=$cb->{'ipaddress'}->[0]:$ip=$cb->{'ipaddress'};
    my $hostname;
    my $count=0;
    my $got_hostname=0;
    while(($got_hostname == 0)&&($count <= 20)){
        print STDERR "Waiting for ssh login: " if($count > 0);
        # use keyauth or fail.
        open (SSH,"ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no -o PasswordAuthentication=no root\@$ip hostname|");
        chomp(my $hostname=<SSH>);
        close(SSH);

        print STDERR "hostname: $hostname\n";
        $got_hostname = 1 if($hostname ne ""); 
        sleep 10 unless $got_hostname;
        $count++;
    }
    return $self;
}

sub wait_for_reboot{
    my $self = shift;
    $self->wait_for_down(@_);
    sleep 10;
    $self->wait_for_up(@_);
    return $self;
}

# use the ipaddress here or it will cache in DNS
sub wait_for_down{
use Net::Ping::External qw(ping);
    my $self = shift;
    my $cb = shift if @_;
    my $ip;
    (ref($cb->{'ipaddress'}) eq 'ARRAY')?$ip=$cb->{'ipaddress'}->[0]:$ip=$cb->{'ipaddress'};
    my $alive = ping( host => $ip );
    while( $alive == 1 ){
        print STDERR "$ip is still up. Waiting for down.\n";
        sleep 3;
        $alive = ping( host => $ip );
    }
    return $self;
}

sub wait_for_up{
use Net::Ping::External qw(ping);
    my $self = shift;
    my $cb = shift if @_;
    my $ip;
    (ref($cb->{'ipaddress'}) eq 'ARRAY')?$ip=$cb->{'ipaddress'}->[0]:$ip=$cb->{'ipaddress'};
    my $alive = ping( host => $ip );
    while( $alive != 1 ){
        print STDERR "$ip is still down. Waiting for up.\n";
        sleep 3;
        $alive = ping( host => $ip );
    }
    return $self;
}

sub tail_prime_init_log{
    my $self = shift;
    my $cb = shift if @_;
    $self->{'ipaddress'} = $cb->{'ipaddress'}->[0];
    # wait for ssh to become available and get it's ssh-key so it won't ask
    open(SSH,"/usr/bin/ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} /usr/bin/tail -f /var/log/prime-init.log|");
        while(my $log_line=<SSH>){
            chomp($log_line);
            if($log_line=~/prime exit was (.*)/){
                my $exit=$1;
                print STDERR "prime exited with $exit\n";
                return $exit;
            }
        }
    close(SSH);
    return $self;
}


# Update LDAP
sub update_ldap_entry{
    my $self = shift;
    my $cb = shift if @_;
    my $entry = $cb->{'entry'} if $cb->{'entry'};
    return undef unless $entry;
    print STDERR "Updating: ".$entry->{'asn'}->{'objectName'}."\n";
    my ($servers,$mesg);
    $servers = [ $cb->{'server'} ] if $cb->{'server'};
    $servers = $self->find_ldap_servers() unless $servers;
    while($server=shift(@{$servers})){
        if($server=~m/(.*)/){ $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/); }
        my $ldap = Net::LDAP->new($server) || warn "could not connect to $server $@";
        next if($ldap == 1);
        $mesg = $ldap->bind( $ENV{'LDAP_BINDDN'}, password => $ENV{'LDAP_PASSWORD'});
        undef $servers unless $mesg->{'resultCode'};
        $mesg->code && print STDERR $mesg->error."\n";
        $mesg = $ldap->add( $entry );
        if($mesg->code == 68){
            $mesg = $ldap->delete($entry->{'asn'}->{'objectName'});
            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
            if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
                foreach my $ref (@{ $mesg->{'referral'} }){
                    if($ref=~m/(ldap.*:.*)\/.*/){
                        $cb->{'server'} = $ref;
                        $cb->{'entry'} = $entry;
                        $self->update_ldap_entry($cb);
                    }
                }
            }else{
                $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
            }
            $mesg = $ldap->add( $entry );
            if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
                foreach my $ref (@{ $mesg->{'referral'} }){
                    if($ref=~m/(ldap.*:.*)\/.*/){
                        $cb->{'server'} = $ref;
                        $cb->{'entry'} = $entry;
                        $self->update_ldap_entry($cb);
                    }
                }
            }else{
                $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
            }

            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
        }elsif(($mesg->code == 10) && ($mesg->error eq "Referral received")){
                foreach my $ref (@{ $mesg->{'referral'} }){
                    if($ref=~m/(ldap.*:.*)\/.*/){
                        $cb->{'server'} = $ref;
                        $cb->{'entry'} = $entry;
                        $self->update_ldap_entry($cb);
                    }
                }
        }else{
            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
        }
          
    }
    print STDERR "Done updating ".$entry->{'asn'}->{'objectName'}."\n";
    return $self;
}


1;
