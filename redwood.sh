#!/bin/bash
clear;
env DOMAIN='eftdomain.net'                                 \
    LDAP_URI='ldaps://faraday.eftdomain.net:636'           \
    BASE_DN='dc=eftdomain,dc=net'                          \
    BIND_DN='uid=jameswhite,ou=People,dc=eftdomain,dc=net' \
    LDAP_PASSWORD='St3g4s411r11s.'                         \
    WINDOWS_USERNAME='jameswhite'                          \
    WINDOWS_PASSWORD='St3g4s411r11s.'                      \
    ./redwood.pl
