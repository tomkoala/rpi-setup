#!/bin/sh
# ------------------------------------------------------------------
## [Author] tomkoala
## Description: This script will install and configure a seedbox on Raspian 
## Version: 2014-01-15
## Usage: seedbox-install [no-options] commands
##
## Options:
##   -h,                        Display help.
## Commands:
##   update,                    Update the APT packets
##   configure-freebox          Configure the Freebox HDD
##   install-transmission       Install transmission bittorrent daemon binaries
##   configure-transmission     Configure transmission bittorrent client
##   install-ovpn               Install OpenVPN client
##   configure-ovpn             Configure OpenVPN client
##
## ------------------------------------------------------------------

USAGE="Usage: seedbox-install [options] commands"

# --- Options processing -------------------------------------------
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo seedbox-install'\n"
  exit 1
fi

tmp=${TMPDIR:-/tmp}/prog.$$
trap "rm -f $tmp.?; exit 1" 0 1 2 3 13 15
RETVAL=0

# --- Body --------------------------------------------------------

### Update the APT packets
update() {
  apt-get update &&
  apt-get upgrade &&
  echo "To start seedbox-install again, do 'seedbox-install'. Now exiting\n"
  exit 0
}

### Configure Freebox HDD
configure_freebox() {
  FB_VOLUME=/media/freebox
  echo "Configuring Freebox HDD..."
  # Create mount point if necessary
  if [ ! -d $FB_VOLUME ]; then
    mkdir $FB_VOLUME
  else
    echo 'The directory /media/freebox already exists'
	return 1
  fi
  # Backup fstab file then editing
  cp -n /etc/fstab /etc/fstab.bak
  if grep -q '/media/freebox' /etc/fstab; then
    echo 'Entry already exists in fstab'
	return 1
  else
    echo 'Adding entry to fstab'
    #fstabentry="//mafreebox.freebox.fr/disque\\\040dur/\t/media/freebox\tcifs\t_netdev,rwx,uid=1000,gid=1000,credentials=/root/.smbcredentials,iocharset=utf8\t0\t0"
    FSTAB_ENTRY="//mafreebox.freebox.fr/Disque\\\040dur /media/freebox cifs _netdev,rw,users,iocharset=utf8,uid=1000,sec=none,file_mode=0777,dir_mode=0777 0 0"
    echo $FSTAB_ENTRY |  tee -a /etc/fstab
  fi
  # Create samba credentials
  SMB_CRD_FILE=/root/.smbcredentials
  if [ ! -f $SMB_CRD_FILE ]; then
    echo 'Creating samba credentials'
    echo 'username=' |  tee -a $SMB_CRD_FILE
    echo 'password=' |  tee -a $SMB_CRD_FILE
  else
    echo 'Samba credentials already exists'
  fi
  # Mount Volume
  echo 'Mounting Freebox volume'
  mount $FB_VOLUME
  # Check if /media/freebox is actually a mountpoint
  mountpoint -q /media/freebox || return 1
  return 0
}

install_transmission() {
  apt-get install transmission-daemon
}
	
### Configure Transmission
configure_transmission() {
  echo "Configuring Transmission..."
  TM_SETTINGS_TMP=/etc/transmission-daemon/settings_template.json
  TM_SETTINGS=/etc/transmission-daemon/settings.json
  if [ ! -f $TM_SETTINGS ]; then
	echo 'Please install first Transmission'
	return 1
  fi
  # Stop transmission daemon
  service transmission-daemon stop
  # Update the settings template with chosen username/pwd
  echo 'Please choose credentials for Transmission RPC: '
  read -p "Username: " RPC_USERNAME
  read -p "Password: " RPC_PASSWORD
  sed -e 's/USERNAME/'$RPC_USERNAME/ -e 's/PASSWORD/'$RPC_PASSWORD/ config/transmission/settings_template.json > $tmp.1
  mv $tmp.1 $TM_SETTINGS
  echo 'Applying new configuration'
  # Automatically update Transmission's block list
  chmod +x scripts/transmission/update-blocklist.sh
  echo 'Adding blocklist update to cron'
  cp scripts/transmission/update-blocklist.sh /etc/cron.weekly/update-blocklist
  service transmission-daemon start
  # Update the template with the Hashed RPC password
  sed -e 's/0.0.0.0/IP_ADRESS/' $TM_SETTINGS > $tmp.2
  mv $tmp.2 $TM_SETTINGS_TMP
  return 0
}
  
install_ovpn() {
  apt-get install openvpn
}
 
get_publicip() {
  curl ifconfig.me/ip
} 
 
### Configure OpenVPN
configure_ovpn() {
  echo 'Configuring OpenVPN...' 
  OVPN_DAEMON=/usr/sbin/openvpn
  if [ ! -x $OVPN_DAEMON ]; then
    echo "Please install first OpenVPN"
    return 1
  fi
  # Unzip and copy the config files
  VPN_PROVIDER=vpnfacile
  VPN_CFG_FILES=VPNFacile_configfiles.zip
  unzip config/openvpn/$VPN_CFG_FILES -d /etc/openvpn/$VPN_PROVIDER
  cp /etc/openvpn/$VPN_PROVIDER/VPNFacile\ -\ Pays-Bas\ \#3.ovpn /etc/openvpn/vpnfacile/NL3.ovpn
  # Copy the credentials file
  mv config/openvpn/credentials /etc/openvpn/credentials
  chmod 700 /etc/openvpn/credentials
  # Patch config with VPN credentials
  sed -e 's/auth-user-pass/auth-user-pass credentials/' /etc/openvpn/vpnfacile/NL3.ovpn > $tmp.3
  mv $tmp.3 /etc/openvpn/NL3.conf
  cp /etc/openvpn/vpnfacile/ca.crt /etc/openvpn/
  cp /etc/openvpn/vpnfacile/ta.key /etc/openvpn/
  # Copy the startup script and install it
  # cp scripts/openvpn/startovpn.sh /etc/init.d/startovpn.sh
  # chmod +x /etc/init.d/startovpn.sh
  # update-rc.d startovpn.sh defaults
  # Set AUTOSTART on
  sed -e 's/#AUTOSTART="all"/AUTOSTART="all"/' /etc/default/openvpn > $tmp.4
  mv $tmp.4 /etc/default/openvpn
  # Restart the OpenVPN service
  service openvpn restart
  return 0
}

### Configure Transmission through OpenVPN
configure_transmission_over_ovpn() {
  # Check if Transmission is currently installed
  TM_SETTINGS_FILE=/etc/transmission-daemon/settings.json
  if [ ! -f $TM_SETTINGS_FILE ]; then
    echo "Transmission is not installed"
    return 1
  fi
  OVPN_DAEMON=/usr/sbin/openvpn
  if [ ! -x $OVPN_DAEMON ]; then
    echo "OpenVPN is not installed"
    return 1
  fi
  # Prevent Transmission daemon service from starting at startup
  update-rc.d -f transmission-daemon remove
  # Disable openvpn service at startup
  update-rc.d openvpn disable
  # Copy openvpn up script
  cp scripts/openvpn/up.sh /etc/openvpn/up.sh
  chmod +x /etc/openvpn/up.sh
  # Update the config
  #script-security 2
  #up /etc/openvpn/up.sh
}

finish() {
  rm -f $tmp.?
  trap 0
  exit 0
}

while test -n "$@"; do
   case "$@" in
      "")
         echo $USAGE
         exit 1;;
      "test")
         echo 'test'
         exit 0;;
      "update"|"configure-freebox"|"install-transmission"|"configure-transmission"|"install-ovpn"|"configure-ovpn")
         CMD=$(echo $@ | sed 's/-/_/g')
         ${CMD}
         RETVAL=$?
         shift
         exit $RETVAL;;
      *)
        echo 'Unknown command '$@
        exit 1;;
   esac
done
exit $RETVAL