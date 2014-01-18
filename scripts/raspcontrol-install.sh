#!/bin/sh

# --- Options processing -------------------------------------------
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo raspcontrol-install'\n"
  exit 1
fi

apt-get install git

RASPCTRL_HOME_DIR=/var/www/raspcontrol
RASPCTRL_CFG_DIR=/etc/raspcontrol

[ -d $RASPCTRL_HOME_DIR ] || mkdir $RASPCTRL_HOME_DIR
[ -d $RASPCTRL_CFG_DIR ] || mkdir $RASPCTRL_CFG_DIR

# look for empty dir 
if [ "$(ls -A $RASPCTRL_HOME_DIR)" ]; then
  echo "$RASPCTRL_HOME_DIR is not empty"
else
  git clone https://github.com/Bioshox/Raspcontrol.git $RASPCTRL_HOME_DIR
fi

cat <<\EOF > $RASPCTRL_CFG_DIR/database.aptmnt &&
{
    "user":       "raspcontrol",
    "password":   "raspberry"
}
EOF

chmod 740 $RASPCTRL_CFG_DIR/database.aptmnt
chown www-data:www-data $RASPCTRL_CFG_DIR/database.aptmnt
usermod -a -G video www-data