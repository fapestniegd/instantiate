#!/usr/bin/perl -wT
# This script just waitd for a request, and upon receiving one, it echoes the work "dhcplinks" to a named pipe.
$ENV{'PATH'}='/usr/kerberos/sbin:/usr/kerberos/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin';
use FileHandle;
print "Content-type: text/plain\n\n";
my $cmd_fifo="/var/run/httpd.cmd";

if(system("/bin/ps -ef | /bin/grep -q fifo_wa[t]ch")){
    print "/usr/local/sbin/fifo_watcher not running. This will not work unless it is.\n";
    exit 1;
}

if(! -p $cmd_fifo){
    print "Command FIFO does not exist.\n";
    exit 1;
}

$fh = FileHandle->new("$cmd_fifo", O_RDWR|O_NONBLOCK);

if (defined $fh) {
   print $fh "dhcplinks\n";
   undef $fh; # automatically closes the file
}
print "OK\n";
