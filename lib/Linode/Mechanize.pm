package Linode::Mechanize;
use strict;
use YAML;
use WWW::Mechanize;
use FileHandle;
use HTML::BlockParser;

#################################################################################
# This module is responsible for either fetching the html from Linode, 
# or retrieving it from a local file cache. The latter is more for debugging
# HTML::BlockParser without hammering linode.com with requests.
# Page Content is then sent through HTML::BlockParser to scrape the data we need.
#################################################################################
sub new{
    my $class=shift;
    my $self = {};
    bless $self;
    my $construct = shift if @_;
    $self->{'url_base'}="https://www.linode.com/members";
    $self->{'cfg'}->{'live'}  = $construct->{'live'}  if $construct->{'live'};
    $self->{'cfg'}->{'writecache'}  = $construct->{'writecache'}  if $construct->{'writecache'};
    $self->{'cfg'}->{'cache'} = $construct->{'cache'} if $construct->{'cache'};
    $self->{'debug'} = $construct->{'debug'} if $construct->{'debug'};

    # Get the Linode Credentials from the .linode_credentials file
    if($self->{'cfg'}->{'live'} == 1){ 
        if (-f "$ENV{'HOME'}/.linode_credentials"){ 
           my $creds=YAML::LoadFile("$ENV{'HOME'}/.linode_credentials");   
           $self->{'cfg'}->{'creds'}->{'userid'} = $creds->{'userid'} if $creds->{'userid'};
           $self->{'cfg'}->{'creds'}->{'passwd'} = $creds->{'passwd'} if $creds->{'passwd'};
        }
        # Or from the environment failing that...
        if(! defined($self->{'cfg'}->{'creds'}->{'userid'})){
            $self->{'cfg'}->{'creds'}->{'userid'}=$ENV{'LINODE_USERID'} if $ENV{'LINODE_USERID'};
        }
        if(! defined($self->{'cfg'}->{'creds'}->{'passwd'})){
            $self->{'cfg'}->{'creds'}->{'passwd'}=$ENV{'LINODE_PASSWD'} if $ENV{'LINODE_PASSWD'};
        }
    }else{
        if(!defined($self->{'cfg'}->{'cache'})){
            print STDERR "I need to know where the file 'cache' is if live=0\n" if($self->{'debug'});
            return undef if(!defined($self->{'cfg'}->{'cache'}));
        }
    }
    print STDERR "Logging in using [ $self->{'cfg'}->{'creds'}->{'userid'} : $self->{'cfg'}->{'creds'}->{'passwd'} ]\n";
    $self->{'mech'} = WWW::Mechanize->new(agent => 'WWW-Mechanize/1.34', cookie_jar => {});
    print STDERR "Instanciated WWW::Mechanize object.\n" if($self->{'mech'} && $self->{'debug'});
    ######## Logging in ########
    if( $self->{'cfg'}->{'live'} == 1 ){
        $self->{'mech'}->get( $self->{'url_base'} );
        if($self->{'mech'}->success()){
            print STDERR "Fetched $self->{'url_base'}/.\n" if($self->{'debug'});
        }
        $self->{'mech'}->submit_form( 
                                      with_fields => { 
                                                       auth_username  => $self->{'cfg'}->{'creds'}->{'userid'},
                                                       auth_password  => $self->{'cfg'}->{'creds'}->{'passwd'},
                                                     },
                                      button      => ''
                                     );
        if($self->{'mech'}->success()){
            print STDERR "Posted login on $self->{'url_base'}.\n" if($self->{'debug'});
            if($self->{'mech'}->content=~m/Login incorrect/){
                my $cookie_string=$self->get_session_cookie_from_file("$ENV{'HOME'}/tmp/cookies.txt");
                print "Unable to log in with WWW::Mechanize->submit. Trying session in cookies.txt...\n";
                print "$cookie_string\n";
                $self->{'mech'}->add_header( Cookie => "$cookie_string");
                $self->{'mech'}->get( "https://www.linode.com/members/linode" );
                if($self->{'mech'}->success()){
                    if($self->{'mech'}->content=~m/Login incorrect/){
                         die "The stored cookie didn't work either.";
                    }
                }
            }
        }
    }
    return $self;
}

################################################################################
# This is an added kludge to work around the some behavior between linode and
# www::mechanize, where it just stopped getting the session cookie from the
# linode.com authentication page. You have to download the Export Cookies
# Plug-in from https://addons.mozilla.org/en-US/firefox/addon/8154 and log into
# linode once, export your cookies to a cookies.txt file, and then import it
# by scraping the cookies.txt with the method below. I know... weak... lame...
#################################################################################
sub get_session_cookie_from_file{
    my $self=shift;
    my $exported_cookies=shift;
    return undef unless defined($exported_cookies);
    my $fh = new FileHandle;
    my $cookies;
    if ($fh->open("< $exported_cookies")) {
        while (my $line = $fh->getline){
            $line=~s///g;
            if($line=~m/.www.linode.com\s+TRUE\s+\/\s+TRUE\s+0\s+CFTOKEN\s+(.*)/){
                $cookies->{'cftoken'}=$1;
            }
            if($line=~m/.www.linode.com\s+TRUE\s+\/\s+TRUE\s+0\s+CFID\s+(.*)/){
                $cookies->{'cfid'}=$1;
            }
        }
        $fh->close;
    }
    return undef unless(defined($cookies->{'cfid'})&&defined($cookies->{'cftoken'}));
    return "CFID=$cookies->{'cfid'}; CFTOKEN=$cookies->{'cftoken'}";
}
 
sub load_page{
    my $self=shift;
    my $page=shift if @_;
    my $cachepage=$page;
    $cachepage=~s/\//_/g;
    my $content;
    if( $self->{'cfg'}->{'live'} == 1 ){
        $self->{'mech'}->get($self->{'url_base'}."/".$page);
        if($self->{'mech'}->success()){
            print STDERR "Successfully fetched $self->{'url_base'}/$page.\n" if($self->{'debug'});
        }
        $content=$self->{'mech'}->content();
        if(defined $self->{'cfg'}->{'writecache'}){
            if( $self->{'cfg'}->{'writecache'} == 1 ){
                open FH, ">$self->{'cfg'}->{'cache'}/$cachepage";
                print FH $content;
                close FH;
            }
        }
    }else{
        print STDERR "loading $self->{'cfg'}->{'cache'}/$cachepage from file..\n" if($self->{'debug'});
        my $fh = new FileHandle;
        if ($fh->open("< $self->{'cfg'}->{'cache'}/$cachepage")) {
            while(my $line=<$fh>){ $content.=$line; }
            $fh->close;
        }else{
            print STDERR "loading $self->{'cfg'}->{'cache'}/$cachepage FAILED.\n" if($self->{'debug'});
        }
    }
    $self->{'currentpage'}=$content;
    return $self;
}

sub load_machines{
    my $self=shift;
    my $parser = new HTML::BlockParser();
    my $count=0;
    my $bad_parse=1;
    my $table_data;
    while(($count<3)&&($bad_parse==1)){
        $self->load_page("linode/index.cfm");
        $self->{'machines'}=();
        #################################################################################
        # Find the block of HTML with the given properties.
        #
        # In this specific example, the block must have a tag: <table<" that contains a
        # "tag: tr" that contains a "tag: td" that contains text with the /regexp/ in
        # it the object may have more properties, but *all* the ones listed  *must*
        # match. This only locates the block we want. It returns it in an anon struct
        #################################################################################
        $table_data = $parser->get_blocks( 
                                              $self->{'currentpage'}, {
                                                          'block' => 'table',
                                                          'match' => [ 
                                                                       'tr:td:\s*Linode\s*$',
                                                                       'tr:td:\s*Status\s*$',
                                                                       'tr:td:\s*Plan\s*$',
                                                                       'tr:td:\s*IP Address\s*$',
                                                                       'tr:td:\s*Location\s*$',
                                                                       'tr:td:\s*Host\s*$',
                                                                     ]
                                                        }
                                            );
        
        $bad_parse=$parser->parse_err();
        $count++;
        if($bad_parse == 1){
            print STDERR "Page failed to parse correctly. Attempting Again try($count/3)\n" if($self->{'debug'});
            #sleep 3;
        }
    }
    return undef if ($bad_parse);
    #################################################################################
    # This method will convert an anon struct of a table to a  
    # $list->[$row]->[$col]->{<anonstruct of cell contents> 
    # such that the cell contents can be referenced directly
    #################################################################################
    my $machine_table;
    if($#{ $table_data } == 0){
        $machine_table = $parser->table_array($table_data->[0]);
    }else{
        print STDERR $#{ $table_data } + 1 ." tables matched. Something went wrong\n" if($self->{'debug'});
        print STDERR Data::Dumper->Dump([$table_data]) if($self->{'debug'});
        #print STDERR Data::Dumper->Dump([$self->{'currentpage'}]) if($self->{'debug'});
        exit -1;
    }
    #################################################################################
    # The systems are in rows 1-(n-1) (with row 0 being the headers
    # the first column has 2 links, one for the host page, one to rename the host
    # we want to be careful not to click the wrong one...
    #################################################################################
    for(my $row=1;$row<$#{ $machine_table };$row++){
        my $hostname;
        foreach my $link (@{ $machine_table->[$row]->[0]->{'links'} }){
           if($link->{'text'} ne "rename"){
               $hostname=$link->{'text'};
               $self->{'machines'}->{ $hostname }->{'href'} = $link->{'href'};
           }
        }
        for(my $col=1;$col<=($#{ $machine_table->[$row] } - 2) ;$col++){
          $self->{'machines'}->{ $hostname }->{ $machine_table->[0]->[$col]->{'text'} } = $machine_table->[$row]->[$col]->{'text'};
        }
    }
    return $self;
}

sub load_config{
    my $self=shift;
    my $host_id = shift if @_;
    my $parser = new HTML::BlockParser();
    return undef unless(defined($self->{'machines'}->{$host_id}->{'href'}));
    $self->load_page("linode/$self->{'machines'}->{$host_id}->{'href'}");
    my $table_data = $parser->get_blocks(
                                          $self->{'currentpage'}, {
                                                      'block' => 'table',
                                                      'match' => [
                                                                   "tr:td:Delete",
                                                                   "tr:td:Configuration Profiles",
                                                                   "tr:td:RAM",
                                                                   "tr:td:Action"
                                                                 ]
                                                    }
                                        );

    if(defined($table_data)){
        my $queue_table = $parser->table_array($table_data->[0]);
        #print STDERR YAML::Dump($queue_table) if($self->{'debug'});
        #$parser->dump_table_array($queue_table);
    }
        
    return $self;
}

sub shutdown_host{
    my $self=shift;
    return undef unless $self->{'cfg'}->{'live'};
    my $host_id = shift if @_;
    $self->load_machines();
    $self->load_dashboard($host_id);
    return undef unless(defined($self->{'machines'}->{$host_id}));
    if($self->{'machines'}->{$host_id}->{'Status'} eq  "Powered Off"){
        print STDERR "Host Already Powered Off.\n" if($self->{'debug'});
        return $self;
    }
    my $parser = new HTML::BlockParser();
    return undef unless(defined($self->{'machines'}->{$host_id}->{'href'}));
    $self->load_page("linode/$self->{'machines'}->{$host_id}->{'href'}");
    my $table_data = $parser->get_blocks(
                                          $self->{'currentpage'}, {
                                                      'block' => 'table',
                                                      'match' => [
                                                                   "tr:td:$host_id Status.*"
                                                                 ]
                                                    }
                                        );
    if(defined($table_data)){
        $self->{'mech'}->get($self->{'url_base'}."/linode/machine_control.cfm?action=shutdown");
        if($self->{'mech'}->success()){
            print STDERR "Successfully sent $host_id a Shutdown Command.\n" if($self->{'debug'});
        }
    }
    $self->wait_for_queue($host_id);
    #print STDERR YAML::Dump($parser->{'matches'}) if($self->{'debug'});
    return $self;
}

##############################################
# This needs to be changed to target specific
# configuration profiles. that's where the 
# "boot_58387" argument comes from...
##############################################
sub startup_host_config{
    my $self=shift;
    return undef unless $self->{'cfg'}->{'live'};
    my $host_id = shift if @_;
    my $cfg_id = shift if @_;
    $self->load_machines();
    $self->load_dashboard($host_id);
    return undef unless(defined($self->{'machines'}->{$host_id}));
    if($self->{'machines'}->{$host_id}->{'Status'} eq  "Running"){
        print STDERR "Host Already Powered On.\n" if($self->{'debug'});
        return $self;
    }
    foreach my $cfg (@{ $self->{'machines'}->{$host_id}->{'configs'} }){
        my $nokernel_label=$cfg->{'label'};
        print STDERR "( $cfg->{'label'} )\n" if($self->{'debug'});
        $nokernel_label=~s/\(.*\)//g;
        print STDERR "[ $nokernel_label == $cfg_id ]\n" if($self->{'debug'});
        if($nokernel_label eq $cfg_id){
            print STDERR "found $cfg_id as configuration $cfg->{'config_id'}\n" if($self->{'debug'});
            $self->{'mech'}->get($self->{'url_base'}."/linode/dashboard.cfm?boot_$cfg->{'config_id'}=Boot");
        }
    }
    $self->load_dashboard($host_id);
    $self->wait_for_queue($host_id);
    return $self;
}

sub wait_for_queue{
    my $self=shift;
    return undef unless $self->{'cfg'}->{'live'};
    my $host_id = shift if @_;
    print STDERR "waitqueue -=[$host_id]=-\n" if($self->{'debug'});
    if(!defined($self->{'machines'}->{$host_id})){
        $self->load_machines();
    }
    print STDERR "Re-Loading dashboard to get job queue.\n" if($self->{'debug'});
    $self->load_dashboard($host_id);
    if($self->{'debug'}){
        print STDERR "cannot find $host_id queue. Aborting wait...\n" unless(defined($self->{'machines'}->{$host_id}));
    }
    return undef unless(defined($self->{'machines'}->{$host_id}));
    $self->load_dashboard($host_id);
    print STDERR "[A:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'active'}  } if($self->{'debug'});
    print STDERR "|P:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'pending'} } if($self->{'debug'});
    print STDERR "|Q:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'queued'}  } if($self->{'debug'});
    print STDERR "|C:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'complete'}  }."]\n" if($self->{'debug'});
    while( (
            ($#{ $self->{'machines'}->{$host_id}->{'queues'}->{'active'} } >= 0)||
            ($#{ $self->{'machines'}->{$host_id}->{'queues'}->{'pending'} } >= 0)||
            ($#{ $self->{'machines'}->{$host_id}->{'queues'}->{'queued'} } >= 0)
           )||
            ($#{ $self->{'machines'}->{$host_id}->{'queues'}->{'complete'} } < 0)
         )
    {
        print STDERR "Waiting 5 seconds for $host_id queue to complete.\n" if($self->{'debug'});
        print STDERR "[A:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'active'}  } if($self->{'debug'});
        print STDERR "|P:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'pending'} } if($self->{'debug'});
        print STDERR "|Q:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'queued'}  } if($self->{'debug'});
        print STDERR "|C:".$#{ $self->{'machines'}->{$host_id}->{'queues'}->{'complete'}  }."]\n" if($self->{'debug'});
        sleep 5;
        $self->load_dashboard($host_id);
    }
}

sub load_dashboard{
    #     network summary *TODO*
    #     storage summary *TODO*
    #     host summary *TODO*
    #     cpu graph *TODO*
    #     network graph *TODO*
    #     disk io graph *TODO*

    my $self=shift;
    $self->{'active_host'}= shift if @_;
    my $host_id=$self->{'active_host'};
    if(!defined($self->{'machines'}->{$host_id})){
        $self->load_machines();
    }
    if($self->{'debug'}){
        print STDERR "undefined href for [$host_id]\n"  unless(defined($self->{'machines'}->{$host_id}->{'href'}));
    }
    return undef unless(defined($self->{'machines'}->{$host_id}->{'href'}));
    my $all_queues_empty=1;
    my $attempt=0;
    while(($all_queues_empty)&&($attempt<3)){
        print STDERR "Reload linode/$self->{'machines'}->{$host_id}->{'href'}\n" if($self->{'debug'});
        $self->load_page("linode/$self->{'machines'}->{$host_id}->{'href'}");

            # Put Configuration in $self->{'machines'}->{$host_id}
        $self->get_configdisks();

        # Put Jobs in $self->{'machines'}->{$host_id}
        $self->get_job_queue();
        foreach my $queue (keys(%{ $self->{'machines'}->{$host_id}->{'queues'} })){
            if($#{ $self->{'machines'}->{$host_id}->{'queues'}->{$queue} } > 0){
                $all_queues_empty=0;
            }
        }
        $attempt++;
        if($all_queues_empty==0){ 
            print STDERR "All job queues are empty. Re-loading Dashboard ($attempt/3)\n" if($self->{'debug'}); 
            #sleep 3; 
            }else{
                print STDERR "Jobs found.\n" if($self->{'debug'});
                #print STDERR YAML::Dump([$self->{'machines'}->{$host_id}->{'queues'}]) if($self->{'debug'});
            }
    }
    return $self;
}

sub get_configdisks{
    my $self=shift;
    my $parser = new HTML::BlockParser();
    my $table_data = $parser->get_blocks(
                                              $self->{'currentpage'}, {
                                                                        'block' => 'table',
                                                                        'match' => [
                                                                                     "tr:td:Delete",
                                                                                     "tr:td:Configuration Profiles",
                                                                                     "tr:td:RAM",
                                                                                     "tr:td:Action"
                                                                                   ]
                                                                       }
                                             );
    my $in_configs=0;
    my $in_disks=0;
    my $in_options=0;
    my $host_id=$self->{'active_host'};
    $self->{'machines'}->{$host_id}->{'configs'}=();
    $self->{'machines'}->{$host_id}->{'cfgopts'}=();
    $self->{'machines'}->{$host_id}->{'disks'}=();
    if(defined($table_data)){
        my $config_table = $parser->table_array($table_data->[0]);
#$parser->dump_table_array($config_table);
        for(my $row=0;$row<=$#{ $config_table };$row++){

################################################################
# Set the mode by what the second column pattern matches
################################################################
            if($parser->subtext([ $config_table->[$row]->[0] ])=~m/Delete/){
                if($parser->subtext([ $config_table->[$row]->[1] ])=~m/Configuration Profiles/){
                    $in_configs=1; $row++;
                }elsif($parser->subtext([ $config_table->[$row]->[1] ])=~m/Disk Images/){
                    $in_configs=0; $in_disks=1; $row++
                }
            }elsif($parser->subtext([ $config_table->[$row]->[1] ])=~m/More Options:/){
                $in_configs=0; $in_disks=0; $in_options=1;
            }

################################################################
# Insert into the machines struct based on what mode we're in.
################################################################
            my $configid='';
            my $diskid='';
            if($in_configs){
                my $label=$parser->subtext([ $config_table->[$row]->[1] ]);
                $label=~s/\n//g;
                $label=~s/-\s+Last Booted\s+-//g;
                $label=~s/ //g;
                foreach my $link (@{ $config_table->[$row]->[1]->{'links'} }){
                    if($link->{'href'}=~m/config_edit.cfm.id=([0-9]+)/){ 
                        $configid=$1; 
                    }
                }
                push(@{ $self->{'machines'}->{$host_id}->{'configs'} },
                        { 
                        'label' => $label,
                        'config_id' => $configid,
                        'links' => $config_table->[$row]->[1]->{'links'}->[0]
                        }
                    ) if($configid ne ''); 
            }elsif($in_disks){
                my $type="unknown";
                my $label=$parser->subtext([ $config_table->[$row]->[1] ]);
                $label=~s/\n//g;
                if($label=~m/\((.*)\)/){ $type=$1; }
                $label=~s/\(.*\)//g;
                $label=~s/ //g;
                foreach my $link (@{ $config_table->[$row]->[1]->{'links'} }){
                    if($link->{'href'}=~m/image_edit.cfm.id=([0-9]+)/){ 
                        $diskid=$1; 
                    }
                }
                push(@{ $self->{'machines'}->{$host_id}->{'disks'} },
                        { 
                        'label' => $label,
                        'disk_id' => $diskid,
                        'links' => ($config_table->[$row]->[1]->{'links'}),
                        'size' => $parser->subtext([ $config_table->[$row]->[2] ]),
                        'type' => $type
                        }
                    ) if($diskid ne ''); 
            }elsif($in_options){
                push(@{ $self->{'machines'}->{$host_id}->{'cfgopts'}->{'links'} },($config_table->[$row]->[1]->{'links'}));
            }
        }
    }
    return $self;
}

sub get_job_queue{
    my $self=shift;
    my $parser = new HTML::BlockParser();
    my $table_data = $parser->get_blocks(
                                          $self->{'currentpage'}, {
                                                                    'block' => 'table',
                                                                    'match' => [
                                                                                 "tr:td:Job Entered"
                                                                               ]
                                                                  }
                                        );
    my $host_id=$self->{'active_host'};
    $self->{'machines'}->{$host_id}->{'queues'}=();
    if(defined($table_data)){
        my $config_table = $parser->table_array($table_data->[0]);
        #$parser->dump_table_array($config_table);
        for(my $row=0;$row<=$#{ $config_table };$row++){
            ################################################################
            # This table is pretty strongly formatted so we can use row
            # offsets to target our objects
            ################################################################
            my $queue_status="unknown";
            my ($jobid,$jobdesc);
            if($parser->subtext([ $config_table->[$row]->[0] ])=~m/JobID:\s+([0-9]+)\s+-\s+(.*)/){
                $jobid=$1; 
                $jobdesc=$2; 
                if($parser->subtext([ $config_table->[$row+1]->[3] ]) eq "Success"){
                    $queue_status="complete";
                }elsif($parser->subtext([ $config_table->[$row+1]->[3] ]) eq "In Queue"){
                    $queue_status="queued";
                }elsif($parser->subtext([ $config_table->[$row+1]->[3] ]) eq "In Progress"){
                    $queue_status="active";
                }elsif($parser->subtext([ $config_table->[$row+1]->[3] ]) eq "Failed"){
                    $queue_status="failed";
                }
                push(@{ $self->{'machines'}->{$host_id}->{'queues'}->{$queue_status} },
                        {
                        'job_id'             => $jobid,
                        'job_desc'           => $jobdesc,
                        'job_entered'        => $parser->subtext([ $config_table->[$row+1]->[1] ]),
                        'status'             => $parser->subtext([ $config_table->[$row+1]->[3] ]),
                        'host_start_date'    => $parser->subtext([ $config_table->[$row+2]->[1] ]),
                        'host_finish_date'   => $parser->subtext([ $config_table->[$row+2]->[3] ]),
                        'host_duration_date' => $parser->subtext([ $config_table->[$row+3]->[1] ]),
                        'host_message'       => $parser->subtext([ $config_table->[$row+3]->[3] ]) 
                        }
                    );
                $row+=4;
            }
        }
    }
    return $self;
}

sub delete_config{
    my $self=shift;
    my $host_id=shift;
    my $host_cfg=shift;
    return $self unless(defined($host_id));
    return $self unless(defined($host_cfg));
    if(!defined($self->{'machines'}->{$host_id})){
        $self->load_machines();
        $self->load_dashboard($host_id);
    }
    return $self unless(defined($self->{'machines'}->{$host_id}->{'configs'}));
    my $cfg_id='';

    foreach my $cfg (@{ $self->{'machines'}->{$host_id}->{'configs'} }){
       my $nokernel_label=$cfg->{'label'};
       print STDERR "( $cfg->{'label'} )\n" if($self->{'debug'});
       $nokernel_label=~s/\(.*\)//g;
       print STDERR "[ $nokernel_label == $host_cfg ]\n" if($self->{'debug'});
       if($nokernel_label eq $host_cfg) { 
           $cfg_id=$cfg->{'config_id'};
           print STDERR "Found host config $host_cfg on host $host_id. ID is [$cfg_id]\n" if($self->{'debug'});
       }
    }
    if($cfg_id ne ''){
        print STDERR $self->{'url_base'}."/linode/dashboard.cfm?action=Delete&delete_configID_$cfg_id=$cfg_id\n" if($self->{'debug'});
        $self->{'mech'}->get($self->{'url_base'}."/linode/dashboard.cfm?action=Delete&delete_configID_$cfg_id=$cfg_id");
    }
    $self->wait_for_queue($host_id);
    return $self;
}

sub delete_disk{
    my $self=shift;
    my $host_id=shift;
    my $disk_label=shift;
    return $self unless(defined($host_id));
    return $self unless(defined($disk_label));
    if(!defined($self->{'machines'}->{$host_id})){
        $self->load_machines();
        $self->load_dashboard($host_id);
    }
    return $self unless(defined($self->{'machines'}->{$host_id}->{'disks'}));
    my $disk_id='';
    foreach my $cfg (@{ $self->{'machines'}->{$host_id}->{'disks'} }){
       if($cfg->{'label'} eq $disk_label) { 
           $disk_id=$cfg->{'disk_id'};
           print STDERR "Found disk labeled $disk_label on host $host_id. ID is [$disk_id]\n" if($self->{'debug'});
       }
    }
    if($disk_id ne ''){
        print STDERR $self->{'url_base'}."/linode/dashboard.cfm?action=Delete&delete_imageID_$disk_id=$disk_id\n" if($self->{'debug'});
        $self->{'mech'}->get($self->{'url_base'}."/linode/dashboard.cfm?action=Delete&delete_imageID_$disk_id=$disk_id");
    }
    $self->wait_for_queue($host_id);
    return $self;
}

sub deploy_host{
    my $self=shift;
    my $host_id=shift;
    my $cfg_label=shift;
    return $self unless(defined($host_id));
    return $self unless(defined($cfg_label));
    $self->load_machines();
    $self->load_dashboard($host_id);
    # don't deploy if there is already a configuration
    return $self if(defined($self->{'machines'}->{$host_id}->{'config_id'}));
    $self->{'mech'}->get($self->{'url_base'}."/linode/wizard.cfm");
    $self->{'root_password'}=$self->randomPassword(15);
    $self->{'mech'}->submit_form( 
                                  form_number => 1,
                                  fields      => { 
                                                   DistributionID => 50,
                                                   imageSize      => 4096,
                                                   swap           => 'new',
                                                   swapSize       => 512,
                                                   rootPassword   => $self->{'root_password'},
                                                   rootPassword2  => $self->{'root_password'},
                                                   username       => '',
                                                   userPassword   => '',
                                                   userPassword2  => '',
                                                   ''              => "Create Profile"
                                                 }
                                 );
    if( $self->{'mech'}->success() ){
        print STDERR "Profile Created\n" if($self->{'debug'});
    }else{
        print STDERR Data::Dumper->Dump([$self->{'mech'}]) if($self->{'debug'});
    }
    $self->wait_for_queue($host_id);
    return $self;
}

sub create_disk{
    my $self=shift;
    my $host_id=shift;
    my $disk_label=shift;
    return $self unless(defined($host_id));
    return $self unless(defined($disk_label));
    $self->load_machines();
    $self->load_dashboard($host_id);
    # don't deploy if there is already an opt disk
    my $have_disk=0;
    foreach my $disk (@{ $self->{'machines'}->{$host_id}->{'disks'} }){
        if($disk->{'label'} eq "$disk_label"){ $have_disk=1; }
    }
    return $self if($have_disk);
    $self->{'mech'}->get($self->{'url_base'}."/linode/image_create.cfm");
    my @page=split(/\n/,$self->{'mech'}->content());
    my $maximum_size=0;
    foreach my $line (@page){
        if($line=~m/You\s+have\s+([0-9]+)\s+MiB\s+of\s+unallocated\s+disk\s+space/){
            $maximum_size=$1;
        }
    }
    return $self if ($maximum_size==0);
    print STDERR "Size detected: $maximum_size\n" if($self->{'debug'});
    
    $self->{'mech'}->submit_form( 
                                  form_number => 1,
                                  fields      => { 
                                                   Label     => $disk_label,
                                                   imageSize => $maximum_size,
                                                   type      => "ext3",
                                                   ''        => "Create Disk"
                                                 }
                                 );
    if( $self->{'mech'}->success() ){
        print STDERR "Disk [$disk_label] Created\n" if($self->{'debug'});
    }else{
        print STDERR Data::Dumper->Dump([$self->{'mech'}]) if($self->{'debug'});
    }
    $self->wait_for_queue($host_id);
    return $self;
}

sub relabel_disk{
    my $self=shift;
    my $host_id=shift;
    my $src_disk_label=shift;
    my $tgt_disk_label=shift;
    return $self unless(defined($host_id));
    return $self unless(defined($src_disk_label));
    return $self unless(defined($tgt_disk_label));
    $self->load_machines();
    $self->load_dashboard($host_id);

    my $have_src=0;
    my $have_tgt=0;
    my $src_disk_id;

    foreach my $disk (@{ $self->{'machines'}->{$host_id}->{'disks'} }){
        if($disk->{'label'} eq "$src_disk_label"){ $have_src=1; $src_disk_id=$disk->{'disk_id'}; }
        if($disk->{'label'} eq "$tgt_disk_label"){ $have_tgt=1; }
    }

    return $self if($have_tgt);
    return $self unless($have_src);
    return $self unless($src_disk_id);

    $self->{'mech'}->get($self->{'url_base'}."/linode/image_edit.cfm?id=$src_disk_id");

    my @page=split(/\n/,$self->{'mech'}->content());
    my $original_size=0;
    foreach my $line (@page){
        if($line=~m/input\s+name="newSize".*value="([0-9]+)"/){
            $original_size=$1;
        }
    }
    return $self if ($original_size==0);
    print STDERR "Size detected: $original_size\n" if($self->{'debug'});
    $self->{'mech'}->submit_form( 
                                  form_number => 1,
                                  fields      => { 
                                                   ImageID   => "$src_disk_id",
                                                   label     => "$tgt_disk_label",
                                                   newSize   => $original_size,
                                                   readonly  => '0',
                                                 },
                                  button => 'save'
                                 );
    if( $self->{'mech'}->success() ){
        print STDERR "Form Submit Succeeded.\n" if($self->{'debug'});
    }else{
        print STDERR Data::Dumper->Dump([$self->{'mech'}]) if($self->{'debug'});
    }
    $self->wait_for_queue($host_id);
    return $self;
}

sub relabel_config{
    my $self=shift;
    my $host_id=shift;
    my $src_cfg_label=shift;
    my $tgt_cfg_label=shift;

    return $self unless(defined($host_id));
    return $self unless(defined($src_cfg_label));
    return $self unless(defined($tgt_cfg_label));

    $self->load_machines();
    $self->load_dashboard($host_id);
    my $have_src=0;
    my $have_tgt=0;
    my $src_cfg_id;

    foreach my $cfg (@{ $self->{'machines'}->{$host_id}->{'configs'} }){
        my $nokernel_label=$cfg->{'label'};
        print STDERR "( $cfg->{'label'} )\n" if($self->{'debug'});
        $nokernel_label=~s/\(.*\)//g;
        print STDERR "[ $nokernel_label == $src_cfg_label ]\n" if($self->{'debug'});
        if($nokernel_label eq $src_cfg_label){ $have_src=1; $src_cfg_id=$cfg->{'config_id'}; }
        if($cfg->{'label'} eq $tgt_cfg_label){ $have_tgt=1; }
    }

    return $self if($have_tgt);
    return $self unless($have_src);
    return $self unless($src_cfg_id);

    $self->{'mech'}->get($self->{'url_base'}."/linode/config_edit.cfm?id=$src_cfg_id");

    my ($hd1,$hd2,$hd3);
    foreach my $disk (@{ $self->{'machines'}->{$host_id}->{'disks'} }){
print STDERR "[ $disk->{'label'} == $host_id-root ]? $disk->{'disk_id'}\n" if($self->{'debug'});
        if($disk->{'label'} eq "$host_id-root"){ $hd1 = $disk->{'disk_id'}; }
        if($disk->{'label'} eq "$host_id-swap"){ $hd2 = $disk->{'disk_id'}; }
        if($disk->{'label'} eq "$host_id-opt"){ $hd3 = $disk->{'disk_id'}; }
    }

    print STDERR "root:[$hd1] swap:[$hd2] opt:[$hd3]\n" if($self->{'debug'});
    return $self if($hd1 eq ''||$hd2 eq ''||$hd3 eq '');

    $self->{'mech'}->submit_form( 
                                  form_number => 1,
                                  fields      => { 
                                                   LinodeConfigID => "$src_cfg_id",
                                                   Label           => "$tgt_cfg_label",
                                                   KernelID        => 60,
                                                   limitRam        => 0,
                                                   runLevel        => "default",
                                                   rootSelect      => "ubd",
                                                   rootPerms       => "rw",
                                                   disableUpdatedb => "1",
                                                   helper_xen      => "1",
                                                   helper_depmod   => "1",
                                                   hd_1            => $hd1,
                                                   hd_2            => $hd2,
                                                   hd_3            => $hd3,
                                                   hd_4            => '',
                                                   hd_5            => '',
                                                   hd_6            => '',
                                                   hd_7            => '',
                                                   hd_8            => '',
                                                   hd_9            => '',
                                                 },
                                  button => 'save'
                                 );
    if( $self->{'mech'}->success() ){
        print STDERR "Form Submit Succeeded.\n" if($self->{'debug'});
    }else{
        print STDERR Data::Dumper->Dump([$self->{'mech'}]) if($self->{'debug'});
    }
    $self->wait_for_queue($host_id);
    return $self;
}

sub randomPassword {
    my $self=shift;
    my $password_length=shift if @_;
    my $password;
    my $_rand;
    if (!$password_length) {
        $password_length = 16;
    }
    my @chars = split(" ", "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z - _ % # | 0 1 2 3 4 5 6 7 8 9");
    srand;
    for (my $i=0; $i <= $password_length ;$i++) {
        $_rand = int(rand 41);
        $password .= $chars[$_rand];
    }
    return $password;
}

sub get_root_passwd {
    my $self=shift;
    return $self->{'root_password'};
}

1;
