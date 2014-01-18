#!/bin/sh

/etc/init.d/transmission-daemon stop
sed s/IP_ADDRESS/$4/ /etc/transmission-daemon/settings_template.json > /etc/transmission-daemon/settings.json
/etc/init.d/transmission-daemon start