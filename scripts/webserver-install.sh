#!/bin/sh

sudo apt-get install lighttpd
# Install PHP5 packages and reload to enable changes
sudo apt-get install php5-common php5-cgi php5
sudo lighty-enable-mod fastcgi-php
sudo service lighttpd force-reload

sudo chown www-data:www-data /var/www
sudo usermod -a -G www-data $USER

