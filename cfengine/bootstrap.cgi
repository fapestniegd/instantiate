#!/usr/bin/perl -w
################################################################################
# put this on a webserver that is running cfengine, it will serve up the 
# boostrap files to other servers
#
# To pull down the files and bootstrap run: "curl -s <hostname>/inputs | bash" 
#
#    RewriteEngine on
#    RewriteRule   ^/inputs$ /cgi-bin/bootstrap.cgi [P,L]
#
use strict;
print "Content-type: text/plain\n\n";
my $inputs="/var/cfengine/inputs";
print "#!/bin/bash\n";
print "if [ ! -d \"$inputs\" ]; then /bin/mkdir -p \"$inputs\";fi\n";

if( (-f "$inputs/failsafe.cf") && (-f "$inputs/update.cf") ){
    print "/bin/cat<<EOFSC >$inputs/failsafe.cf\n";
    open(FAILSAFE,"$inputs/failsafe.cf");
    while (my $fline=<FAILSAFE>){
        $fline=~s/\$/\\\$/g;
        print $fline;
    }
    close(FAILSAFE);
    print "EOFSC\n";

    print "/bin/cat<<EOUC >$inputs/update.cf\n";
    open(UPDATE,"$inputs/update.cf");
    while (my $uline=<UPDATE>){
        $uline=~s/\$/\\\$/g;
        print $uline;
    }
    close(UPDATE);
    print "EOUC\n";
    print "/usr/local/sbin/cf-agent --bootstrap\n";
    
}else{
    print "echo \"cfengine bootstrap files could not be found.\"\n";
}
