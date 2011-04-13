all: install test

install: install_cgi install_templates

test:
	wget -qO - "http://newton/cgi-bin/kickstart.cgi"

install_templates: 
	scp -p templates/* root@newton:/opt/local/kickstart/templates/

install_cgi: kickstart.cgi
	scp -p kickstart.cgi root@newton:/var/www/cgi-bin/kickstart.cgi

kickstart.cgi:
	chmod 755 kickstart.cgi
	touch dhcplinks.cgi
