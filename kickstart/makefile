all: install_cgi test

install: install_cgi

test:
	wget -qO - "http://newton/cgi-bin/kickstart.cgi"

install_cgi: kickstart.cgi
	scp -p kickstart.cgi root@newton:/var/www/cgi-bin/kickstart.cgi

kickstart.cgi:
	chmod 755 kickstart.cgi
	touch dhcplinks.cgi
