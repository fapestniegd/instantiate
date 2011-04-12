all: install test

install: install_cgi install_sh install_watcher

install_cgi: dhcplinks.cgi
	scp -p dhcplinks.cgi root@newton:/var/www/cgi-bin/dhcplinks.cgi

install_sh: dhcplinks.sh
	scp -p dhcplinks.sh root@newton:/usr/local/sbin/dhcplinks

install_watcher: fifo_watcher
	scp -p fifo_watcher root@newton:/usr/local/sbin/fifo_watcher
	ssh root@newton pkill -HUP fifo_watcher;

test: install
	wget -qO - "http://newton/cgi-bin/dhcplinks.cgi" | html2text -nobs

dhcplinks.cgi:
	chmod 755 dhcplinks.cgi
	touch dhcplinks.cgi

dhcplinks.sh:
	chmod 755 dhcplinks.sh
	touch dhcplinks.sh

fifo_watcher:
	chmod 755 fifo_watcher
	touch fifo_watcher

	
