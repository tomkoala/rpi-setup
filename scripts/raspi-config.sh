#!/bin/sh
# Part of raspi-config http://github.com/asb/raspi-config
#
# See LICENSE file for copyright and license details


if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo raspi-config'\n"
  exit 1
fi

ASK_TO_REBOOT=0

do_info() {
  whiptail --msgbox "\
This tool provides a straight-forward way of doing initial 
configuration of the Raspberry Pi. Although it can be run 
at any time, some of the options may have difficulties if 
you have heavily customised your installation.\
" 20 70 1
}

do_expand_rootfs() {
  # Get the starting offset of the root partition
  PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^2" | cut -f 2 -d:)
  [ "$PART_START" ] || return 1
  # Return value will likely be error for fdisk as it fails to reload the 
  # partition table because the root fs is mounted
  fdisk /dev/mmcblk0 <<EOF
p
d
2
n
p
2
$PART_START

p
w
EOF
  ASK_TO_REBOOT=1

  # now set up an init.d script
cat <<\EOF > /etc/init.d/resize2fs_once &&
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5 S
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "$1" in
  start)
    log_daemon_msg "Starting resize2fs_once" &&
    resize2fs /dev/mmcblk0p2 &&
    rm /etc/init.d/resize2fs_once &&
    update-rc.d resize2fs_once remove &&
    log_end_msg $?
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF
  chmod +x /etc/init.d/resize2fs_once &&
  update-rc.d resize2fs_once defaults &&
  whiptail --msgbox "Root partition has been resized.\n\
The filesystem will be enlarged upon the next reboot" 20 60 2
}

set_config_var() {
  lua - "$1" "$2" "$3" <<EOF > "$3.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false
for line in file:lines() do
  if line:match("^#?%s*"..key.."=.*$") then
    line=key.."="..value
    made_change=true
  end
  print(line)
end

if not made_change then
  print(key.."="..value)
end
EOF
mv "$3.bak" "$3"
}

# $1 is 0 to disable overscan, 1 to disable it
set_overscan() {
  # Stop if /boot is not a mountpoint
  if ! mountpoint -q /boot; then
    return 1
  fi

  [ -e /boot/config.txt ] || touch /boot/config.txt

  if [ "$1" -eq 0 ]; then # disable overscan
    sed /boot/config.txt -i -e "s/^overscan_/#overscan_/"
    set_config_var disable_overscan 1 /boot/config.txt
  else # enable overscan
    set_config_var disable_overscan 0 /boot/config.txt
  fi
}

do_overscan() {
  whiptail --yesno "What would you like to do with overscan" 20 60 2 \
    --yes-button Disable --no-button Enable 
  RET=$?
  if [ $RET -eq 0 ] || [ $RET -eq 1 ]; then
    ASK_TO_REBOOT=1
    set_overscan $RET;
  else
    return 1
  fi
}

do_change_pass() {
  whiptail --msgbox "You will now be asked to enter a new password for the pi user" 20 60 1
  passwd pi &&
  whiptail --msgbox "Password changed successfully" 20 60 1
}

do_configure_keyboard() {
  dpkg-reconfigure keyboard-configuration &&
  printf "Reloading keymap. This may take a short while\n" &&
  invoke-rc.d keyboard-setup start
}

do_change_locale() {
  dpkg-reconfigure locales
}

do_change_timezone() {
  dpkg-reconfigure tzdata
}

do_memory_split() {
  # Stop if /boot is not a mountpoint
  if ! mountpoint -q /boot; then
    return 1
  fi
  MEMSPLIT=$(whiptail --menu "Set memory split" 20 60 10 \
    "224" "224MiB for ARM, 32MiB for VideoCore" \
    "192" "192MiB for ARM, 64MiB for VideoCore" \
    "128" "128MiB for ARM, 128MiB for VideoCore" \
    3>&1 1>&2 2>&3)
  if [ $? -eq 0 ]; then
    cp -a /boot/arm${MEMSPLIT}_start.elf /boot/start.elf
    sync
    ASK_TO_REBOOT=1
  fi
}

do_ssh() {
  if [ -e /var/log/regen_ssh_keys.log ] && ! grep -q "^finished" /var/log/regen_ssh_keys.log; then
    whiptail --msgbox "Initial ssh key generation still running. Please wait and try again." 20 60 2
    return 1
  fi
  whiptail --yesno "Would you like the SSH server enabled or disabled?" 20 60 2 \
    --yes-button Enable --no-button Disable 
  RET=$?
  if [ $RET -eq 0 ]; then
    update-rc.d ssh enable &&
    invoke-rc.d ssh start &&
    whiptail --msgbox "SSH server enabled" 20 60 1
  elif [ $RET -eq 1 ]; then
    update-rc.d ssh disable &&
    whiptail --msgbox "SSH server disabled" 20 60 1
  else
    return $RET
  fi
}

do_boot_behaviour() {
  whiptail --yesno "Should we boot straight to desktop?" 20 60 2
  RET=$?
  if [ $RET -eq 0 ]; then # yes
    update-rc.d lightdm enable 2
    sed /etc/lightdm/lightdm.conf -i -e "s/^#autologin-user=.*/autologin-user=pi/"
    ASK_TO_REBOOT=1
  elif [ $RET -eq 1 ]; then # no
    update-rc.d lightdm disable 2
    ASK_TO_REBOOT=1
  else # user hit escape
    return 1
  fi
}

do_update() {
  apt-get update &&
  apt-get install raspi-config &&
  printf "To start raspi-config again, do 'sudo raspi-config'. Now exiting\n"
  exit 0
}

do_finish() {
  if [ -e /etc/profile.d/raspi-config.sh ]; then
    rm -f /etc/profile.d/raspi-config.sh
    sed -i /etc/inittab \
      -e "s/^#\(.*\)#\s*RPICFG_TO_ENABLE\s*/\1/" \
      -e "/#\s*RPICFG_TO_DISABLE/d"
    telinit q
  fi
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

while true; do
  FUN=$(whiptail --menu "Raspi-config" 20 80 12 --cancel-button Finish --ok-button Select \
    "info" "Information about this tool" \
    "expand_rootfs" "Expand root partition to fill SD card" \
    "overscan" "Change overscan" \
    "configure_keyboard" "Set keyboard layout" \
    "change_pass" "Change password for 'pi' user" \
    "change_locale" "Set locale" \
    "change_timezone" "Set timezone" \
    "memory_split" "Change memory split" \
    "ssh" "Enable or disable ssh server" \
    "boot_behaviour" "Start desktop on boot?" \
    "update" "Try to upgrade raspi-config" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    do_finish
  elif [ $RET -eq 0 ]; then
    "do_$FUN" || whiptail --msgbox "There was an error running do_$FUN" 20 60 1
  else
    exit 1
  fi
done