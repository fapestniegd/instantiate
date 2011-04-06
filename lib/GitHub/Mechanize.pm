#!/usr/bin/perl -w
BEGIN { unshift(@INC,"./lib") if(-d "./lib"); }
package GitHub::Mechanize;
use WWW::Mechanize;
use HTML::BlockParser;
use HTTP::Cookies;


sub new {
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    $self->{'live'} = $construct->{'live'};
    $self->{'debug'} = $construct->{'debug'};
    $self->{'repo'} = $construct->{'repo'}||'';
    $self->{'cache'} = $construct->{'cache'}||".";
    $self->{'writecache'} = $construct->{'writecache'}||1;
    $self->{'cookie_jar'} = HTTP::Cookies->new( file => "/dev/shm/cookies.dat", autosave => 1,);
    bless $self, $class;
    return undef unless($self->load_credentials());
    if($self->{'live'}){
        return undef unless($self->github_login()); 
    }
    return $self;
}

sub debug {
    my $self = shift;
    my $err = shift if @_;
    print STDERR "$err\n" if $self->{'debug'};
    return $self;
}
   
sub load_credentials{
use YAML;
    my $self = shift;
    $self->debug("Loading Credentials");
    $self->{'creds'} = YAML::LoadFile("$ENV{'HOME'}/.github_credentials") if(-f "$ENV{'HOME'}/.github_credentials");
    if(!defined($self->{'creds'})){
        if(defined($ENV{'GITHUB_LOGIN'})){ $self->{'creds'}->{'login'} = $ENV{'GITHUB_LOGIN'}; }
        if(defined($ENV{'GITHUB_PASSWORD'})){ $self->{'creds'}->{'passwd'} = $ENV{'GITHUB_PASSWORD'}; }
    }
    if(defined($self->{'creds'})){
        $self->debug("Credentials Loaded.");
        return $self;
    }else{
        $self->debug("Credentials could not be loaded ");
        return undef;
    }
}

sub github_login{
    my $self = shift;
    if($self->{'live'}){
        $self->debug("Logging in live.");
        $self->{'mech'} = WWW::Mechanize->new(agent => 'WWW-Mechanize/#.##',  cookie_jar => $self->{'cookie_jar'});
        $self->{'mech'}->get('https://github.com/login');
        $self->{'mech'}->form_with_fields("login","password");
        $self->{'mech'}->submit_form(
                                      with_fields => {
                                                       login       => $self->{'creds'}->{'login'},
                                                       password    => $self->{'creds'}->{'passwd'}
                                                     },
                                      button      => 'commit'
                                    );
        $self->debug("Logging in.");
        return undef unless $self->{'mech'}->success();
    }else{
        $self->debug("Login failed.");
        return $self;
    }
}

sub load_page{
use FileHandle;
    my $self = shift;
    my $url = shift if @_;
    $url=~m/(.*)/;
    my $cache_url=$1;
    $self->{'content'}='';
    $cache_url=~s/\//_/g;
    if($self->{'live'}){
        $self->debug("Loading $url live.");
        $self->{'mech'}->get($url);
        $self->{'content'}=$self->{'mech'}->content();
        if($self->{'writecache'}){
            my $fh = new FileHandle "> $self->{'cache'}/$cache_url";
            if(defined $fh){
                print $fh $self->{'content'};
                $fh->close;
            }
        }
    }else{
        $self->debug("Loading $cache_url from cache.");
        my $fh = new FileHandle;
        if ($fh->open("< $self->{'cache'}/$cache_url")) {
            while(my $line=<$fh>){
                $self->{'content'}.=$line;
            }
            $fh->close;
        }
    }
    return $self;
}

sub list_deploy_keys{
    my $self = shift;
    $self->debug("getting deploy key list.");
    $self->load_page("https://github.com/$self->{'creds'}->{'login'}/$self->{'repo'}/edit");
    my $parser = new HTML::BlockParser();
   
   ##############################################
   # This is very page-layout specific code here.
   # It will have to change if the page does.
   ##############################################
    my $key_data = $parser->get_blocks( $self->{'content'}, { 'block' => 'div',
                                                              'match' => [ 'h1:strong:Deploy Keys', ] });
   my ($keys,$key);
   foreach my $sub_block (@{ $key_data->[0]->{'content'} }){
       foreach my $block_item (@{ $sub_block->{'content'} }){
           if($block_item->{'tag'} eq "ul"){
               foreach my $line_item (@{ $block_item->{'content'} }){
                   foreach my $line_item (@{ $line_item->{'content'} }){
                       if($line_item->{'tag'} eq "plaintext"){
                           my $nowrap=$line_item->{'text'};
                           $nowrap=~s/\n//g; $nowrap=~s/\s+$//g; $nowrap=~s/^\s+//g;
                           $key=$nowrap;
                           #print Data::Dumper->Dump([$line_item]);
                       }elsif(($line_item->{'tag'} eq "a")&&($line_item->{'text'}=~m/\(edit\)/)){
                           $keys->{$key}->{'edit'}=$line_item->{'attr'}->{'href'};
                           #print Data::Dumper->Dump([$line_item]);
                       }elsif(($line_item->{'tag'} eq "a")&&($line_item->{'text'}=~m/\(delete\)/)){
                           $keys->{$key}->{'delete'}=$line_item->{'attr'}->{'href'};
                           #print Data::Dumper->Dump([$line_item]);
                       }
                    
                   }
               }
           }
       }
   }
   ##############################################
   #
   ##############################################
   #print Data::Dumper->Dump([$keys]); 
   return $keys;
}

sub replace_deploy_key{
    my $self=shift;
    my $construct=shift if @_;
    my $key_title=$construct->{'name'} if $construct->{'name'};
    my $key_data=$construct->{'key'} if $construct->{'key'};
    if(defined($key_title)&& defined($key_data)){
        if($self->{'live'}){
            $self->delete_deploy_key($key_title);
            $self->load_page("https://github.com/$self->{'creds'}->{'login'}/$self->{'repo'}/edit");
            $self->{'mech'}->submit_form(
                                          with_fields => {
                                                           'public_key[title]' => $key_title,
                                                           'public_key[key]'   => $key_data
                                                          },
                                    );
            $self->{'content'} = $self->{'mech'}->content();
            #print $self->{'content'};
            return undef unless $self->{'mech'}->success();
        }else{
            print "Here is where I'd add $key_title if we were live\n";
        }
    }
    return $self;
}

sub delete_deploy_key{
use LWP "DELETE";
use HTTP::Cookies;
    my $self=shift;
    my $browser = LWP::UserAgent->new;
    $browser->cookie_jar($self->{'cookie_jar'});
    my $deadman = shift if @_;
    my $keys = $self->list_deploy_keys();
    if(defined($keys->{$deadman})){
        if($self->{'live'}){
            print "DELETE: https://github.com".$keys->{$deadman}->{'delete'}."\n";
            my $request = HTTP::Request->new(DELETE, "https://github.com".$keys->{$deadman}->{'delete'});
            $browser->request($request);
        }else{
            print "Here is where I'd delete $deadman with $keys->{$deadman}->{'delete'} if we were live\n";
        }
    }else{
        debug("$keys->{$deadman} not found in for delete.");
    }
    return $self;
}

1;
