# INSTALL MENU #
SERIAL 0 19200 0
prompt 0
noescape 1
timeout 10
default install_[% hostname %]_serial

LABEL install_[% hostname %]
    menu label Install Debian (squeeze) with FAI
	kernel pxelinux.kernels/squeeze/fai/vmlinuz-2.6.32-5-486
	append ip=dhcp boot=live netboot=nfs nfsroot=[% next_server %]:/opt/local/nfsroot/squeeze-fai root=/dev/nfs initrd=pxelinux.kernels/squeeze/fai/initrd.img-2.6.32-5-486 FAI_FLAGS="createvt,sshd,verbose" secret=[% secret %] FAI_ACTION=install -- panic=60

LABEL install_[% hostname %]_serial
    menu label Install Debian (squeeze) with FAI
	kernel pxelinux.kernels/squeeze/fai/vmlinuz-2.6.32-5-486
	append ip=dhcp boot=live netboot=nfs nfsroot=[% next_server %]:/opt/local/nfsroot/squeeze-fai root=/dev/nfs initrd=pxelinux.kernels/squeeze/fai/initrd.img-2.6.32-5-486 FAI_FLAGS="createvt,sshd,verbose" secret=[% secret %] FAI_ACTION=install -- console=ttyS0,19200n8 panic=60
