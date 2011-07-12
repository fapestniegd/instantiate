all: install test

install: install_cgi install_pl install_watcher install_templates

install_templates: 
	scp tftpboot/pxelinux.menus/templates/*.tpl root@newton:/opt/local/tftpboot/pxelinux.menus/templates/
	scp tftpboot/pxelinux.menus/templates/*.tpl root@oppenheimer:/opt/local/tftpboot/pxelinux.menus/templates/

install_cgi: dhcplinks.cgi
	scp -p dhcplinks.cgi root@newton:/var/www/cgi-bin/dhcplinks.cgi
	scp -p dhcplinks.cgi root@oppenheimer:/var/www/cgi-bin/dhcplinks.cgi

install_pl: dhcplinks.pl
	scp -p dhcplinks.pl root@newton:/usr/local/sbin/dhcplinks
	scp -p dhcplinks.pl root@oppenheimer:/usr/local/sbin/dhcplinks

install_watcher: fifo_watcher
	scp -p fifo_watcher root@newton:/usr/local/sbin/fifo_watcher
	ssh root@newton pkill -HUP fifo_watcher;
	scp -p fifo_watcher root@oppenheimer:/usr/local/sbin/fifo_watcher
	ssh root@oppenheimer pkill -HUP fifo_watcher;

test: install
	wget -qO - "http://newton/cgi-bin/dhcplinks.cgi" | html2text -nobs
	wget -qO - "http://oppenheimer/cgi-bin/dhcplinks.cgi" | html2text -nobs

dhcplinks.cgi:
	chmod 755 dhcplinks.cgi
	touch dhcplinks.cgi

dhcplinks.pl:
	chmod 755 dhcplinks.pl
	touch dhcplinks.pl

fifo_watcher:
	chmod 755 fifo_watcher
	touch fifo_watcher

	
