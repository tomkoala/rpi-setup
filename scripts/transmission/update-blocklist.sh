#!/bin/bash
 
# blocklist directory
BLOCKLISTDIR=/var/lib/transmission-daemon/info/blocklists
 
cd ${BLOCKLISTDIR}
if [ $? -eq 0 ]; then
  if [ -f level1 ]; then
    rm level1
  fi
  # if no blocklist file exist update blocklist
  if [ ! -f level1 ]; then
    wget -q -O level1.gz http://list.iblocklist.com/?list=ijfqtofzixtwayqovmxn&fileformat=p2p&archiveformat=gz
    # if download successful unzip it
    if [ -f level1.gz ]; then
          gunzip level1.gz
          # if file extracted successfully reload transmission
          if [ $? -eq 0 ]; then
            chmod go+r level1
            /etc/init.d/transmission-daemon reload
          else
                rm -f level1*
          fi
        fi
  fi
  cd - 2>&1 >/dev/null
fi