#!/bin/bash

if test $(id -u) != "0"; then
  echo "Please supply root's password to install this package. "
  su -c "$0"
  ret=$?
  exit $ret
fi

export DEBIAN_FRONTEND=noninteractive

MODNAME=rr3740a
#`grep TARGETNAME product/*/linux/Makefile | sed s'# ##'g | cut -d\= -f2 | sed s'#\r##'`

#echo $MODNAME

if [ "$MODNAME" == "" ]; then
  echo "Could not determine driver name"
fi

rm -rf product/*/linux/*.ko
rm -rf product/*/linux/.build

rm -rf /usr/share/hptdrv/$MODNAME
mkdir -p /usr/share/hptdrv/
cp -R `pwd` /usr/share/hptdrv/$MODNAME
rm -f /usr/share/hptdrv/$MODNAME/install.sh
chown -R 0:0 /usr/share/hptdrv/$MODNAME

#touch /etc/sysconfig/hptdrv || exit 1
#echo MODLIST=\"$MODNAME\" > /etc/sysconfig/hptdrv

rm -f /etc/init.d/hptdrv-monitor
cp dist/hptdrv-function /usr/share/hptdrv/
cp dist/hptdrv-monitor /etc/init.d/
cp dist/hptdrv-rebuild /usr/sbin/
cp dist/hptdrv-update /etc/cron.daily/
if ! cp dist/hptunin /sbin/hptunin${MODNAME}; then
  echo "Failed to install uninstaller /sbin/hptunin${MODNAME}, quit now."
  exit 1
fi

sed -i s#^MODNAME=#MODNAME=${MODNAME}# /sbin/hptunin${MODNAME}
chmod 755 /etc/init.d/hptdrv-monitor /usr/sbin/hptdrv-rebuild /etc/cron.daily/hptdrv-update /usr/share/hptdrv/hptdrv-function /sbin/hptunin${MODNAME}

if test -d /usr/lib/dracut/modules.d; then
  if test -f /usr/lib/dracut/modules.d/40hptdrv/dracut-hptdrv.sh; then
    if ! grep -s -q "^modprobe $MODNAME" /usr/lib/dracut/modules.d/40hptdrv/dracut-hptdrv.sh; then
      echo "modprobe $MODNAME 2> /dev/null" >> /usr/lib/dracut/modules.d/40hptdrv/dracut-hptdrv.sh
    fi
  else
    mkdir -p /usr/lib/dracut/modules.d/40hptdrv
    cp dist/dracut-hptdrv.sh /usr/lib/dracut/modules.d/40hptdrv/
    cp dist/module-setup.sh /usr/lib/dracut/modules.d/40hptdrv/
    chmod +x /usr/lib/dracut/modules.d/40hptdrv/dracut-hptdrv.sh
    chmod +x /usr/lib/dracut/modules.d/40hptdrv/module-setup.sh
  fi
fi

if test -e /etc/debian_version; then
  rm -f /etc/init.d/hptmod
  install -m 755 -o root -g root dist/hptmod /etc/init.d/
  str_sed=`sed -n '/Required-Start:.*hptmod/p' /etc/init.d/udev`
  if test "$str_sed" = "" ;then
    sed -i '/Required-Start:/s/.*/& hptmod/' /etc/init.d/udev
  fi
fi

. /usr/share/hptdrv/hptdrv-function
echo "Checking and installing required toolchain and utility ..."

checkandinstall() {
  if ! type $1 >/dev/null 2>&1; then
    #echo "Installing program $1 ..."
    installtool $1
    if ! type $1 >/dev/null 2>&1; then
      missing=1
    fi
  else
    echo "Found program $1 (`type -p $1`)"
    return 0
  fi
}

missing=0
checkandinstall make
checkandinstall gcc
checkandinstall perl
checkandinstall wget

case "$dist" in
  fedora )
    if ! installlib elfutils-libelf-devel; then
      missing=1
    fi
    ;;
  *)
    ;;
esac

OS=
[ -f /etc/lsb-release ] && OS=`sed -n '/DISTRIB_ID/p' /etc/lsb-release | cut -d'=' -f2 | tr [[:upper:]] [[:lower:]]` 
if [ "${OS}" = "ubuntu" ] ;then
  type upstart-udev-bridge > /dev/null  2>&1
  if [ "$?" = 0 ] ;then
    install -m 755 -o root -g root dist/hptdrv.conf /etc/init/
    install -m 755 -o root -g root dist/udev.override /etc/init/
  fi 
fi

if type update-rc.d >/dev/null 2>&1; then
  update-rc.d -f hptdrv-monitor remove >/dev/null 2>&1
  update-rc.d hptdrv-monitor defaults >/dev/null 2>&1

  if test -e /etc/debian_version; then 
    update-rc.d -f hptmod remove >/dev/null 2>&1
    if test -s /etc/init.d/.depend.boot; then
      update-rc.d hptmod defaults >/dev/null 2>&1
      update-rc.d hptmod enable S >/dev/null 2>&1
    else
      # start it before udev
      update-rc.d hptmod start 03 S . >/dev/null 2>&1
    fi
  fi
elif type systemctl >/dev/null 2>&1; then
  rm -f /sbin/hptdrv-monitor
  cp dist/hptdrv-monitor /sbin/
  chmod +x /sbin/hptdrv-monitor

  if test -d "/lib/systemd/system"; then
    rm -f /lib/systemd/system/systemd-hptdrv.service
    rm -f /lib/systemd/system/hptdrv-monitor.service

    systemctl list-units | grep -s -q networking.service # ubuntu14.10
    if [ "$?" = 0 ] ;then    
       cp dist/hptdrv-monitor-debian.service /lib/systemd/system/hptdrv-monitor.service
    else
       cp dist/hptdrv-monitor.service /lib/systemd/system/hptdrv-monitor.service
    fi
    cp dist/systemd-hptdrv.service /lib/systemd/system/
  else
    rm -f /usr/lib/systemd/system/systemd-hptdrv.service
    rm -f /usr/lib/systemd/system/hptdrv-monitor.service

    systemctl list-units | grep -s -q networking.service
    if [ "$?" = 0 ] ;then    
      cp dist/hptdrv-monitor-debian.service /usr/lib/systemd/system/hptdrv-monitor.service
    else
      cp dist/hptdrv-monitor.service /usr/lib/systemd/system/hptdrv-monitor.service
    fi
    cp dist/systemd-hptdrv.service /usr/lib/systemd/system/	
  fi
  # suse 13.1 bug
  if test -f "/usr/lib/systemd/system/network@.service"; then
    mkdir -p "/usr/lib/systemd/system/network@.service.d/"
    cp dist/50-before-network-online.conf "/usr/lib/systemd/system/network@.service.d/"
  fi

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable hptdrv-monitor
  systemctl enable systemd-hptdrv >/dev/null 2>&1
  systemctl start  hptdrv-monitor > /dev/null 2>&1

  rm -f /etc/init.d/hptmod
  cp dist/hptmod /etc/init.d/
  chmod 755 /etc/init.d/hptmod
elif type insserv >/dev/null 2>&1; then
  insserv -r /etc/init.d/hptdrv-monitor
  insserv /etc/init.d/hptdrv-monitor
elif type chkconfig >/dev/null 2>&1; then
  chkconfig --add hptdrv-monitor
else
  ln -sf ../init.d/hptdrv-monitor /etc/rc0.d/K01hptdrv-monitor
  ln -sf ../init.d/hptdrv-monitor /etc/rc6.d/K01hptdrv-monitor
  ln -sf ../init.d/hptdrv-monitor /etc/rc1.d/S01hptdrv-monitor
  ln -sf ../init.d/hptdrv-monitor /etc/rc2.d/S01hptdrv-monitor
  ln -sf ../init.d/hptdrv-monitor /etc/rc3.d/S01hptdrv-monitor
  ln -sf ../init.d/hptdrv-monitor /etc/rc4.d/S01hptdrv-monitor
  ln -sf ../init.d/hptdrv-monitor /etc/rc5.d/S01hptdrv-monitor
fi

if [ -d /etc/initramfs-tools/scripts/init-top ]; then
  if test -f /etc/initramfs-tools/scripts/init-top/hptdrv; then
    if ! grep -s -q "modprobe $MODNAME" /etc/initramfs-tools/scripts/init-top/hptdrv; then
      cat dist/hptdrv.part >> /etc/initramfs-tools/scripts/init-top/hptdrv
    fi
  else
    install -m 755 -o root -g root dist/hptdrv /etc/initramfs-tools/scripts/init-top/
  fi
fi

touch /var/lib/hptdrv.rebuild

if type systemctl >/dev/null 2>&1; then
  systemctl start hptdrv-monitor
else
  /etc/init.d/hptdrv-monitor start
fi

if [ "$missing" != "0" ]; then
  echo "Toolchain to built the driver is incomplete, please install the missing package to build the driver."
  echo "Exit."
  exit 1
fi

if type systemctl >/dev/null 2>&1; then
  systemctl stop hptdrv-monitor
  # restart service in case kernel updated later in this sesssion.
  systemctl start hptdrv-monitor
else
  /etc/init.d/hptdrv-monitor stop
  # restart service in case kernel updated later in this sesssion.
  /etc/init.d/hptdrv-monitor start
fi

if [ -f /tmp/hptdrv-$MODNAME-nostart.lck ]; then
  exit 0
fi

echo ""
echo "Please run hptunin${MODNAME} to uninstall the driver files."
echo ""
echo "Please restart the system for the driver to take effect."

# vim: expandtab ts=2 sw=2 ai
