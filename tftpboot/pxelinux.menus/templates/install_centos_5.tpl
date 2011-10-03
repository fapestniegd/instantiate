menu title [% fqdn %] Quick-install
menu tabmsgrow 22
menu cmdlinerow 22
menu endrow 24

menu color title 1;34;49 #eea0a0ff #cc333355 std
menu color sel 7;37;40 #ff000000 #bb9999aa all
menu color border 30;44 #ffffffff #00000000 std
menu color pwdheader 31;47 #eeff1010 #20ffffff std
menu color hotkey 35;40 #90ffff00 #00000000 std
menu color hotsel 35;40 #90000000 #bb9999aa all
menu color timeout_msg 35;40 #90ffffff #00000000 none menu color timeout 31;47 #eeff1010 #00000000 none

prompt 0
noescape 1
timeout 50
default pxelinux.kernels/com32/menu.c32

label [% fqdn %]
       menu label Redeploy [% fqdn %] 
       kernel pxelinux.kernels/centos-latest/vmlinuz 
       append initrd=pxelinux.kernels/centos-latest/initrd.img ip=dhcp ks=http://newton.[% domainname %]/cgi-bin/kickstart.cgi text
