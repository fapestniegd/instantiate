# Accept the VMware End User License Agreement
vmaccepteula

# Set the root password for the DCUI and Tech Support Mode
rootpw --iscrypted [% rootpw %]

# Choose the first discovered disk to install onto
#autopart --firstdisk --overwritevmfs
autopart --firstdisk=megaraid_sas,local --overwritevmfs

# The installation media is retrieved via http
install url https://oppenheimer.eftdomain.net/recollections/vmware/HEAD/esxi/4.1 

# Set the network to DHCP on the first network adapater
network --bootproto=static --addvmportgroup=false --device=vmnic0 --ip=[% ip %] --netmask=255.255.255.0 --gateway=[% gateway %]  --nameserver=[% nameservers %] --hostname=[% fqdn %] --vlanid=12

#reboot after install, without prompting
reboot

# A sample post-install script
%firstboot --unsupported --interpreter=busybox

# Configure a vmkernel portgroup on vSwitch0 and enable vmotion
esxcfg-vswitch -A VMkernel vSwitch0
esxcfg-vswitch -p VMkernel -v 201 vSwitch0
#esxcfg-vmknic -a -i 10.20.33.24 -n 255.255.255.0 -p VMkernel
esxcfg-vswitch -L vmnic3 vSwitch0


esxcfg-vswitch -a vSwitch1
esxcfg-vswitch -L vmnic1 vSwitch1
esxcfg-vswitch -L vmnic2 vSwitch1
esxcfg-vswitch -A VLAN_8 vSwitch1
esxcfg-vswitch -p VLAN_8 -v 11 vSwitch1
esxcfg-vswitch -A VLAN_11 vSwitch1
esxcfg-vswitch -p VLAN_11 -v 11 vSwitch1
esxcfg-vswitch -A VLAN_12 vSwitch1
esxcfg-vswitch -p VLAN_12 -v 12 vSwitch1
esxcfg-vswitch -A VLAN_13 vSwitch1
esxcfg-vswitch -p VLAN_13 -v 13 vSwitch1
esxcfg-vswitch -A VLAN_15 vSwitch1
esxcfg-vswitch -p VLAN_15 -v 15 vSwitch1
esxcfg-vswitch -A VLAN_17 vSwitch1
esxcfg-vswitch -p VLAN_17 -v 17 vSwitch1
esxcfg-vswitch -A VLAN_18 vSwitch1
esxcfg-vswitch -p VLAN_18 -v 18 vSwitch1
esxcfg-vswitch -A VLAN_100 vSwitch1
esxcfg-vswitch -p VLAN_100 -v 100 vSwitch1
esxcfg-vswitch -A VLAN_112 vSwitch1
esxcfg-vswitch -p VLAN_112 -v 112 vSwitch1
esxcfg-vswitch -A VLAN_114 vSwitch1
esxcfg-vswitch -p VLAN_114 -v 114 vSwitch1
esxcfg-vswitch -A VLAN_115 vSwitch1
esxcfg-vswitch -p VLAN_115 -v 115 vSwitch1
esxcfg-vswitch -A VLAN_150 vSwitch1
esxcfg-vswitch -p VLAN_150 -v 150 vSwitch1
esxcfg-vswitch -A VLAN_151 vSwitch1
esxcfg-vswitch -p VLAN_151 -v 151 vSwitch1
esxcfg-vswitch -A VLAN_400 vSwitch1
esxcfg-vswitch -p VLAN_400 -v 400 vSwitch1
esxcfg-vswitch -A VLAN_401 vSwitch1
esxcfg-vswitch -p VLAN_401 -v 401 vSwitch1

esxcfg-vswitch -a NULL_Switch
esxcfg-vswitch -A NULL_Portgroup NULL_Switch

sleep 10

#vim-cmd hostsvc/vmotion/vnic_set vmk1
vim-cmd hostsvc/net/refresh

vim-cmd hostsvc/net/portgroup_set --nicorderpolicy-active=vmnic0 --nicorderpolicy-standby=vmnic1 vSwitch0 'Management Network'
vim-cmd hostsvc/net/portgroup_set --nicorderpolicy-active=vmnic1 --nicorderpolicy-standby=vmnic0 vSwitch0 VMkernel

# configure DNS
vim-cmd hostsvc/net/dns_set --ip-addresses=192.168.2.8,192.168.1.54,192.168.7.4

#enable SSH
vim-cmd hostsvc/enable_remote_tsm
vim-cmd hostsvc/start_remote_tsm
vim-cmd hostsvc/net/refresh

#configure NTP
cat > /etc/ntp.conf <<NTPCONF
# Permit time synchronization with our time source, but do not
# permit the source to query or modify the service on this system.
restrict default kod nomodify notrap nopeer noquery

# Permit all access over the loopback interface.  This could
# be tightened as well, but to do so would effect some of
# the administrative functions.
restrict 127.0.0.1

# Hosts on local network are less restricted.
restrict 192.168.0.0 mask 255.255.0.0 nomodify notrap
restrict 17.16.0.0   mask 255.240.0.0 nomodify notrap
restrict 10.0.0.0    mask 255.0.0.0   nomodify notrap

# Use public servers from the pool.ntp.org project.
# Please consider joining the pool (http://www.pool.ntp.org/join.html).
server 192.168.1.24 
server 192.168.1.25 
server 192.168.1.26 
server 192.168.1.27 

# Undisciplined Local Clock. This is a fake driver intended for backup
# and when no outside source of synchronized time is available.
server  127.127.1.0     # local clock
fudge   127.127.1.0 stratum 10

# Drift file.  Put this in a directory which the daemon can write to.
# No symbolic links allowed, either, since the daemon updates the file
# by creating a temporary in the same directory and then rename()'ing
# it to the file.
#driftfile /etc

# Key file containing the keys and key identifiers used when operating
# with symmetric key cryptography.
#keys /etc

# Specify the key identifiers which are trusted.
#trustedkey 4 8 42

# Specify the key identifier to use with the ntpdc utility.
#requestkey 8

# Specify the key identifier to use with the ntpq utility.
#controlkey 8
NTPCONF

chkconfig ntpd on
/etc/init.d/ntpd start

# enable syslog
#vim-cmd hostsvc/advopt/update Syslog.Remote.Hostname string loghost.eftdomain.net 
#vim-cmd hostsvc/advopt/update Syslog.Remote.Port int 514

# rename the local datastore
vim-cmd hostsvc/datastore/rename datastore1 "$(hostname -s)-localstorage"

reboot
