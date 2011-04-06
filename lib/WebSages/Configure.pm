package WebSages::Configure;
use GitHub::Mechanize;
use Net::LDAP;
use File::Temp qw/ tempfile tempdir cleanup /;

sub new{
    my $class = shift;
    my $construct = shift if @_;
    my $self  = {};
    $self->{'fqdn'} = $construct->{'fqdn'} if $construct->{'fqdn'};
    $self->{'hostname'} = $construct->{'fqdn'} if $construct->{'fqdn'};
    $self->{'gitosis_base'} = $1 if($construct->{'gitosis_base'}=~m/(.*)/);
    $self->{'hostname'} = $1 if($self->{'hostname'}=~m/([^\.]+)\..*/);
    $self->{'domain'} = $construct->{'fqdn'} if $construct->{'fqdn'};
    $self->{'domain'} = $2 if($self->{'domain'}=~m/([^\.]+)\.(.*)/);
    $self->{'basedn'} = $self->{'domain'};
    $self->{'basedn'}=~s/\./,dc=/g;
    $self->{'basedn'}= "dc=".$self->{'basedn'};
    $self->{'secret'} = $construct->{'secret'} if $construct->{'secret'};
    $self->{'ipaddress'}=$construct->{'ipaddress'}||'0.0.0.0';
    ($fh, $self->{'known_hosts'}) = tempfile();
    bless $self;
    if($self->{'secret'}){ $self->setsecret($self->{'secret'}); }
    $self->{'group'} = $construct->{'groups'} if $construct->{'groups'};
    if(!defined $self->{'fqdn'}){
        $self->error('I need a fqdn.');
        print STDERR $self->error();
        return undef;
    }
    # validate all $ENV and domain/hostname variables here or retrun undef
    #
    #
    return $self;
}

sub setip{
    my $self = shift;
    my $ipaddress=shift if @_;
    if($ipaddress =~m/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/){
        $self->{'ipaddress'} = $1;
    }else{
        $self->{'ipaddress'} = undef;
    }
    return $self->{'ipaddress'};
}

sub rexec{
    my $self = shift;
    my $remote_command = shift if @_;
    #eval { 
    #       local $SIG{__WARN__} = sub {}; 
    #       local *STDERR;
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
            push(@{ $self->{'sshfp'} }, $sshfprecord);
        }
        close(SSHFP);
    }else{
        print STDERR "no /usr/bin/sshfp found. skipping sshfp DNS record\n";
    }
    return $self;
}

# this should be a puppet class
sub mount_opt{
    my $self = shift;
    # mount the opt disk
    $self->rexec("/bin/grep /dev/xvdc /etc/fstab||/bin/echo '/dev/xvdc /opt ext3 noatime,errors=remount-ro 0 1'>>/etc/fstab");
    $self->rexec("/bin/grep ' /opt ' /etc/mtab || /bin/mount -a");
    return $self;
}

sub prime_host{
    my $self = shift;
    my $LDAPSECRET_TAINT = shift if @_; # heh, taint
    my $LDAPSECRET;
    if($LDAPSECRET_TAINT=~m/(.*)/){ $LDAPSECRET=$1; }
    # fetch prime and fire it off
    $self->rexec("/usr/bin/wget --no-check-certificate -qO /root/prime https://github.com/fapestniegd/prime/raw/master/prime");
    $self->rexec("/bin/chmod 755 /root/prime");
    my $got_init=0;
    my $count=0;
    while((! $got_init)&&($count < 5)){
        $self->rexec("/root/prime $self->{'fqdn'} $LDAPSECRET > /var/log/prime-init.log 2>\&1 \&");
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

# this initializes the first git checkout from github and first puppet run
# this has been depricated in favor of prime
sub wcyd_init{
    my $self = shift;
    my $LDAPSECRET_TAINT = shift if @_; # heh, taint
    my $LDAPSECRET;
    if($LDAPSECRET_TAINT=~m/(.*)/){
        $LDAPSECRET=$1;
    }
    # fire off wcyd
    $self->rexec("/usr/bin/wget --no-check-certificate -qO /root/wcyd https://github.com/fapestniegd/superstring/raw/master/strings/scripts/wcyd");
    $self->rexec("/bin/chmod 755 /root/wcyd");
    my $got_init=0;
    my $count=0;
    while((! $got_init)&&($count < 5)){
        $self->rexec("/root/wcyd $self->{'fqdn'} $LDAPSECRET > /var/log/wcyd-init.log 2>\&1 \&");
        $count++;
        print STDERR "Verifying initialization, (try: $count);\n";
        open (SSH,"ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} ls -l /var/log/wcyd-init.log 2>/dev/null |");
        chomp(my $initlog=<SSH>); 
        $got_init=1 if($initlog);
        sleep 3 unless $got_init;
        close(SSH);
    }
    return $self;
}

sub make_remote_dsa_keypair{
    my $self = shift;
    print STDERR "Making remote dsa keypair\n";
    # regenerate a dsa public key (if there isn't one?)
    $self->rexec("if [ ! -f /root/.ssh/id_dsa.pub ];then /usr/bin/ssh-keygen -t dsa -N '' -C \"root\@\$(hostname -f)\" -f /root/.ssh/id_dsa>/dev/null 2>&1;fi");
    return $self;
}

# Save the new LDAP secret on the host
sub save_ldap_secret{
    my $self = shift;
    # save the deployment ldap_secret to the host's /etc/ldap/ldap.conf
    $self->rexec("if [ ! -d /etc/ldap ]; then /bin/mkdir -p /etc/ldap; fi");
    $self->rexec("umask 377 && echo $self->{'secret'} > /etc/ldap/ldap.secret");
    return $self;
}

sub get_ldap_secret{
    my $self = shift;
    # save the deployment ldap_secret to the host's /etc/ldap/ldap.conf
    open(CMD,"ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} \'cat /etc/ldap/ldap.secret\'|");
    my $secret=<CMD>;
    chomp($secret);
    close(CMD);
    return $secret;
}

sub get_remote_dsa_pubkey{
    my $self = shift;
    my ($ssh_key, $newkey);
    open PUBKEY, qq(ssh -o UserKnownHostsFile=$self->{'known_hosts'} root\@$self->{'ipaddress'} 'if [ -f /root/.ssh/id_dsa.pub ]; then /bin/cat /root/.ssh/id_dsa.pub ;fi'|)
        ||warn "could not open ssh for read";
    while($ssh_key=<PUBKEY>){
        chomp($ssh_key);
        if($ssh_key=~m/^ssh-dss/){ $newkey=$ssh_key; }
    }
    close(PUBKEY);
    $self->{'remote_ssh_pubkey'}=$newkey;
    return $self->{'remote_ssh_pubkey'};
}

sub add_gitosis_deployment_pubkey{
    my $self = shift;
    my $rootpubkey=shift;
    unless(defined($rootpubkey)){
        print STDERR "No pubkey supplied";
        return undef;
    }
    print STDERR "Updating gitosis deployment key to $self->{'gitosis_base'}\n"; 
    my $git_remote = undef;
    if(! -f "$self->{'gitosis_base'}/.git/config"){ 
        print STDERR "unable to locate config file: $self->{'gitosis_base'}/.git/config\n";
    }else{
        open(GITCONF,"$self->{'gitosis_base'}/.git/config");
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
    if(-f "$self->{'gitosis_base'}/gitosis.conf"){
        print STDERR "Updating gitosis.conf [group deployments]\n"; 
        open(GITOSISCONF,"$self->{'gitosis_base'}/gitosis.conf");
        open(NEWCONF,"> $self->{'gitosis_base'}/gitosis.conf.new");
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
        print STDERR "no $self->{'gitosis_base'}/gitosis.conf to modify?\n";
    }
    if($modified == 1){
        print STDERR "gitosis.conf modified.\n";
        system("/bin/mv $self->{'gitosis_base'}/gitosis.conf.new $self->{'gitosis_base'}/gitosis.conf");
    }else{
        print STDERR "Key was already in deployments, no modification needed.\n";
        system("/bin/rm $self->{'gitosis_base'}/gitosis.conf.new");
    }
    # we have to use our own known hosts file here to keep git from needing a .ssh/config, ugh.
    if(defined($git_remote)){
        system("ssh-keyscan -t dsa,rsa,rsa1 $git_remote >> $ENV{'HOME'}/.ssh/known_hosts");
    }else{
        print STDERR "ssh-keyscan -t dsa,rsa,rsa1 $git_remote >> $ENV{'HOME'}/.ssh/known_hosts\n";
        print STDERR "Unable to determine remote git server for ssh-keyscan\n";
    }
    system("(cd $self->{'gitosis_base'}; /usr/bin/git pull)");
    open(ROOTPUBKEY, "> $self->{'gitosis_base'}/keydir/root\@$self->{'fqdn'}.pub");
    print ROOTPUBKEY "$rootpubkey\n";
    close(ROOTPUBKEY);
    system("(cd $self->{'gitosis_base'}; /usr/bin/git add keydir/root\@$self->{'fqdn'}.pub)");
    system("(cd $self->{'gitosis_base'}; /usr/bin/git commit -a -m \"new $self->{'fqdn'}.pub\")");
    system("(cd $self->{'gitosis_base'}; git push)");
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

sub find_ldap_servers{
use Net::DNS;
    my $self = shift;
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

# Update LDAP with the new information from the host
sub host_record_updates{
    my $self = shift;
    my $construct = shift if @_;
    print STDERR "Updating: cn=$self->{'hostname'},ou=Hosts,$self->{'basedn'}\n";
    my ($servers,$mesg);
    $servers = [ $construct->{'server'} ] if $construct->{'server'};
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
                                                                 'userPassword' => $self->{'userPassword'},
                                                                 'ipHostNumber' => $self->{'ipaddress'}
                                                               ] 
                                                ] 
                                 );
            if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
                foreach my $ref (@{ $mesg->{'referral'} }){
                    if($ref=~m/(ldap.*:.*)\/.*/){
                        $self->update_host_record({ 'server'=> $ref });
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
                                                                $wc->{'userPassword'}
                                                              ],
                                            'cn' => [
                                                      $self->{'hostname'}
                                                    ],
                                            'iphostnumber' => [
                                                                $self->{'ipaddress'}
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
        #next unless($server eq "ldaps://freyr.websages.com:636");
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

sub get_ldap_entry{
use Net::LDAP;
    my $self = shift;
    my $search = shift if @_;
    my $filter="objectclass=*";
    my $scope = "sub";
    my $base = $self->{'basedn'};
    if(ref($search) eq ""){
        $filter=$search;
    }elsif(ref($search) eq "HASH"){
        if(defined($search->{'filter'})){ $filter=$search->{'filter'}; } 
        if(defined($search->{'scope'})){ $scope=$search->{'scope'}; } 
        if(defined($search->{'base'})){ $base=$search->{'base'}; } 
    }else{
       return undef; 
    }
    return undef unless $filter;
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
        my $records = $ldap->search('base' => $base, 'scope' => $scope, 'filter' => $filter);
        undef $servers unless $records->{'resultCode'};
        my @entries = $records->entries;
        if($#entries == 0){
            $mesg = $ldap->unbind;
            $mesg->code && print STDERR "unbind: ".$mesg->error;
            return $entries[0];
        }
    }
    return undef;
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

# Update LDAP
sub update_ldap_entry{
    my $self = shift;
    my $construct = shift if @_;
    my $entry = $construct->{'entry'} if $construct->{'entry'};
    return undef unless $entry;
    print STDERR "Updating: ".$entry->{'asn'}->{'objectName'}."\n";
    my ($servers,$mesg);
    $servers = [ $construct->{'server'} ] if $construct->{'server'};
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
                        $self->update_ldap_entry({ 'server'=> $ref, 'entry'=> $entry });
                    }
                }
            }else{
                $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
            }
            $mesg = $ldap->add( $entry );
            if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
                foreach my $ref (@{ $mesg->{'referral'} }){
                    if($ref=~m/(ldap.*:.*)\/.*/){
                        $self->update_ldap_entry({ 'server'=> $ref, 'entry'=> $entry });
                    }
                }
            }else{
                $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
            }

            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
        }elsif(($mesg->code == 10) && ($mesg->error eq "Referral received")){
                foreach my $ref (@{ $mesg->{'referral'} }){
                    if($ref=~m/(ldap.*:.*)\/.*/){
                        $self->update_ldap_entry({ 'server'=> $ref, 'entry'=> $entry });
                    }
                }
        }else{
            $mesg->code && print STDERR $mesg->code." ".$mesg->error."\n";
        }
          
    }
    print STDERR "Done updating".$entry->{'asn'}->{'objectName'}."\n";
    return $self;
}

sub wait_for_ssh{
    my $self=shift;
    my $hostname;
    my $count=0;
    my $got_hostname=0;
    while((! $got_hostname)&&($count <= 10)){
        print "Waiting for ssh login: " if($count>0);
        for(my $i=0; $i<$count; $i++){ print "."; }
        print "\n" if($count>0);
        $count++;
        open (SSH,"ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} hostname|");
        chomp(my $hostname=<SSH>);
        close(SSH);
        $got_hostname=1 if($hostname); 
        sleep 30 unless $got_hostname;
    }
    return $self;
}

sub wait_for_ssh{
    my $self=shift;
    my $hostname;
    my $count=0;
    my $got_hostname=0;
    while((! $got_hostname)&&($count <= 10)){
        print "Waiting for ssh login: " if($count>0);
        for(my $i=0; $i<$count; $i++){ print "."; }
        print "\n" if($count>0);
        $count++;
        open (SSH,"ssh -o UserKnownHostsFile=$self->{'known_hosts'} -o StrictHostKeyChecking=no root\@$self->{'ipaddress'} hostname|");
        chomp(my $hostname=<SSH>);
        close(SSH);
        $got_hostname=1 if($hostname); 
        sleep 30 unless $got_hostname;
    }
    return $self;
}
1;
