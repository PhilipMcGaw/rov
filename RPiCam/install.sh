#!/bin/bash

# Copyright (c) 2015, Bob Tidey
# All rights reserved.

# Redistribution and use, with or without modification, are permitted provided
# that the following conditions are met:
#  * Redistributions of source code must retain the above copyright
#  notice, this list of conditions and the following disclaimer.
#  * Neither the name of the copyright holder nor the
#  names of its contributors may be used to endorse or promote products
#  derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Description
# This script installs a browser-interface to control the RPi Cam. It can be run on any Raspberry Pi with a newly installed raspbian and enabled camera-support.
#
# RPI_Cam_Web_Interface installer by Silvan Melchior
# Edited by jfarcher to work with github
# Edited by slabua to support custom installation folder
# Additions by btidey, miraaz, gigpi
# Rewritten and split up by Bob Tidey
# Repurpiosed by Philip McGaw

#Debug enable next 3 lines
exec 5> install.txt
BASH_XTRACEFD="5"
set -x

# moves to the folder the script is in, not from where it was called.
cd $(dirname $(readlink -f $0))

# Legacy support Bullseye
read -d . VERSION < /etc/debian_version
echo $VERSION
if [ $VERSION  -eq 10 ]; then
  phpversion=7.3
elif [ $VERSION -eq 11 ]; then
  phpversion=7.4
#following is done by enable legacy camera in updates raspi-config
  sudo sed -i 's/^camera_auto_detect=1/#camera_auto_detect=1/g' /boot/config.txt
  sudo grep -qxF 'start_x=1' /boot/config.txt || sudo sed -i '$ a start_x=1' /boot/config.txt
  sudo grep -qxF 'gpu_mem=128' /boot/config.txt || sudo sed -i '$ a gpu_mem=128' /boot/config.txt
  sudo mkdir -p /opt/vc/bin
else
  phpversion=7.0
fi

# Terminal colors
color_red="tput setaf 1"
color_green="tput setaf 2"
color_reset="tput sgr0"

# Version stuff moved out functions as we need it more when one time.
versionfile="./www/config.php"
version=$(cat $versionfile | grep "'APP_VERSION'" | cut -d "'" -f4)
backtitle="Copyright (c) 2023, Bob Tidey. RPi Cam $version"
jpglink="no"

# Config options located in ./config.txt. In first run script makes that file for you.
if [ ! -e ./config.txt ]; then
  sudo echo "#This is config file for main installer. Put any extra options in here." > ./config.txt
  sudo echo "rpicamdir=\"html\"" >> ./config.txt
  sudo echo "webserver=\"lighttpd\"" >> ./config.txt
  sudo echo "webport=\"80\"" >> ./config.txt
  sudo echo "user=\"\"" >> ./config.txt
  sudo echo "webpasswd=\"\"" >> ./config.txt
  sudo echo "autostart=\"yes\"" >> ./config.txt
  sudo echo "jpglink=\"no\"" >> ./config.txt
  sudo echo "phpversion=\"$phpversion\"" >> ./config.txt
  sudo echo "" >> ./config.txt
  sudo chmod 664 ./config.txt
fi

source ./config.txt
rpicamdirold=$rpicamdir
if [ ! "${rpicamdirold:0:1}" == "" ]; then
  rpicamdirold=/$rpicamdirold
fi

#Allow for a quiet install
rm exitfile.txt >/dev/null 2>&1
if [ $# -eq 0 ] || [ "$1" != "q" ]; then
  exec 3>&1
  dialog  \
  --separate-widget $'\n'  \
  --title "Configuration Options"  \
  --backtitle "$backtitle"					  \
  --form ""  \
  0 0 0  \
  "Cam subfolder:"  1 1  "$rpicamdir"  1 32 15 0  \
  "Autostart:(yes/no)"  2 1  "$autostart"  2 32 15 0  \
  "Server:(apache/nginx/lighttpd)" 3 1  "$webserver"  3 32 15 0  \
  "Webport:"  4 1  "$webport"  4 32 15 0  \
  "User:(blank=nologin)"  5 1  "$user"  5 32 15 0  \
  "Password:"  6 1  "$webpasswd"  6 32 15 0  \
  "jpglink:(yes/no)"  7 1  "$jpglink"  7 32 15 0  \
  "php:(stretch 7.0,buster 7.3)"  8 1  "$phpversion"  8 32 15 0  \
  2>&1 1>&3 | {
  read -r rpicamdir
  read -r autostart
  read -r webserver
  read -r webport
  read -r user
  read -r webpasswd
	  read -r jpglink
	  read -r phpversion
  if [ -n "$webport" ]; then
  sudo echo "#This is edited config file for main installer. Put any extra options in here." > ./config.txt
  sudo echo "rpicamdir=\"$rpicamdir\"" >> ./config.txt
  sudo echo "webserver=\"$webserver\"" >> ./config.txt
  sudo echo "webport=\"$webport\"" >> ./config.txt
  sudo echo "user=\"$user\"" >> ./config.txt
  sudo echo "webpasswd=\"$webpasswd\"" >> ./config.txt
  sudo echo "autostart=\"$autostart\"" >> ./config.txt
  sudo echo "jpglink=\"$jpglink\"" >> ./config.txt
  sudo echo "phpversion=\"$phpversion\"" >> ./config.txt
  sudo echo "" >> ./config.txt
  else
  echo "exit" > ./exitfile.txt
  fi
  }
  exec 3>&-

  if [ -e exitfile.txt ]; then
  rm exitfile.txt
  exit
  fi

  source ./config.txt
fi

if [ ! "${rpicamdir:0:1}" == "" ]; then
  rpicamdir=/$rpicamdir
  rpicamdirEsc=${rpicamdir//\//\\\/}
else
  rpicamdirEsc=""
fi

fn_stop ()
{ # This is function stop
  sudo killall raspimjpeg 2>/dev/null
  sudo killall php 2>/dev/null
  sudo killall motion 2>/dev/null
}

fn_reboot ()
{
# This is function reboot system
  dialog --title "Start camera system now" --backtitle "$backtitle" --yesno "Start now?" 5 33
  response=$?
  case $response in
  0) ./start.sh;;
  1) dialog --title 'Start or Reboot message' --colors --infobox "\Zb\Z1"'Manually run ./start.sh or reboot!' 4 28 ; sleep 2;;
  255) dialog --title 'Start or Reboot message' --colors --infobox "\Zb\Z1"'Manually run ./start.sh or reboot!' 4 28 ; sleep 2;;
  esac
}

fn_motion ()
{
sudo sed -i "s/^daemon.*/daemon on/g" /etc/motion/motion.conf
sudo sed -i "s/^logfile.*/;logfile \/tmp\/motion.log /g" /etc/motion/motion.conf
sudo sed -i "s/^; netcam_url.*/netcam_url/g" /etc/motion/motion.conf
sudo sed -i "s/^netcam_url.*/netcam_url http:\/\/localhost:$webport$rpicamdirEsc\/cam_pic.php/g" /etc/motion/motion.conf
if [ "$user" == "" ]; then
  sudo sed -i "s/^netcam_userpass.*/; netcam_userpass value/g" /etc/motion/motion.conf
else
  sudo sed -i "s/^; netcam_userpass.*/netcam_userpass/g" /etc/motion/motion.conf
  sudo sed -i "s/^netcam_userpass.*/netcam_userpass $user:$webpasswd/g" /etc/motion/motion.conf
fi
sudo sed -i "s/^; on_event_start.*/on_event_start/g" /etc/motion/motion.conf
sudo sed -i "s/^on_event_start.*/on_event_start echo -n \'1\' >\/var\/www$rpicamdirEsc\/FIFO1/g" /etc/motion/motion.conf
sudo sed -i "s/^; on_event_end.*/on_event_end/g" /etc/motion/motion.conf
sudo sed -i "s/^on_event_end.*/on_event_end echo -n \'0\' >\/var\/www$rpicamdirEsc\/FIFO1/g" /etc/motion/motion.conf
sudo sed -i "s/control_port.*/control_port 6642/g" /etc/motion/motion.conf
sudo sed -i "s/control_html_output.*/control_html_output off/g" /etc/motion/motion.conf
sudo sed -i "s/^output_pictures.*/output_pictures off/g" /etc/motion/motion.conf
sudo sed -i "s/^ffmpeg_output_movies on/ffmpeg_output_movies off/g" /etc/motion/motion.conf
sudo sed -i "s/^ffmpeg_cap_new on/ffmpeg_cap_new off/g" /etc/motion/motion.conf
sudo sed -i "s/^stream_port.*/stream_port 0/g" /etc/motion/motion.conf
sudo sed -i "s/^webcam_port.*/webcam_port 0/g" /etc/motion/motion.conf
sudo sed -i "s/^process_id_file/; process_id_file/g" /etc/motion/motion.conf
sudo sed -i "s/^videodevice/; videodevice/g" /etc/motion/motion.conf
sudo sed -i "s/^event_gap 60/event_gap 3/g" /etc/motion/motion.conf
sudo chown motion:www-data /etc/motion/motion.conf
sudo chmod 664 /etc/motion/motion.conf
}

fn_autostart ()
{
tmpfile=$(mktemp)
sudo sed '/#START/,/#END/d' /etc/rc.local > "$tmpfile" && sudo mv "$tmpfile" /etc/rc.local
# Remove to growing plank lines.
sudo awk '!NF {if (++n <= 1) print; next}; {n=0;print}' /etc/rc.local > "$tmpfile" && sudo mv "$tmpfile" /etc/rc.local
if [ "$autostart" == "yes" ]; then
  if ! grep -Fq '#START RASPIMJPEG SECTION' /etc/rc.local; then
  sudo sed -i '/exit 0/d' /etc/rc.local
  sudo bash -c "cat >> /etc/rc.local" << EOF
#START RASPIMJPEG SECTION
mkdir -p /dev/shm/mjpeg
chown www-data:www-data /dev/shm/mjpeg
chmod 777 /dev/shm/mjpeg
sleep 4;su -c 'raspimjpeg > /dev/null 2>&1 &' www-data
if [ -e /etc/debian_version ]; then
  sleep 4;su -c 'php /var/www$rpicamdir/schedule.php > /dev/null 2>&1 &' www-data
else
  sleep 4;su -s '/bin/bash' -c 'php /var/www$rpicamdir/schedule.php > /dev/null 2>&1 &' www-data
fi
#END RASPIMJPEG SECTION

exit 0
EOF
  else
  tmpfile=$(mktemp)
  sudo sed '/#START/,/#END/d' /etc/rc.local > "$tmpfile" && sudo mv "$tmpfile" /etc/rc.local
  # Remove to growing plank lines.
  sudo awk '!NF {if (++n <= 1) print; next}; {n=0;print}' /etc/rc.local > "$tmpfile" && sudo mv "$tmpfile" /etc/rc.local
  fi

fi
sudo chown root:root /etc/rc.local
sudo chmod 755 /etc/rc.local
}

#Main install)
fn_stop

sudo mkdir -p /var/www$rpicamdir/media
#move old material if changing from a different install folder
if [ ! "$rpicamdir" == "$rpicamdirold" ]; then
  if [ -e /var/www$rpicamdirold/index.php ]; then
  sudo mv /var/www$rpicamdirold/* /var/www$rpicamdir
  fi
fi

sudo cp -r www/* /var/www$rpicamdir/
if [ -e /var/www$rpicamdir/index.html ]; then
  sudo rm /var/www$rpicamdir/index.html
fi

if [[ "$phpversion" == "7.3" ]]; then
  phpv=php7.3
else
  phpv=php$phpversion
fi

  sudo lighty-enable-mod fastcgi-php
  sudo sed -i "s/^server.document-root.*/server.document-root  = \"\/var\/www$rpicamdirEsc\"/g" /etc/lighttpd/lighttpd.conf
  sudo sed -i "s/^server.port.*/server.port  = $webport/g" /etc/lighttpd/lighttpd.conf
  sudo /etc/init.d/lighttpd force-reload

#Make sure user www-data has bash shell
sudo sed -i "s/^www-data:x.*/www-data:x:33:33:www-data:\/var\/www:\/bin\/bash/g" /etc/passwd

if [ ! -e /var/www$rpicamdir/FIFO ]; then
  sudo mknod /var/www$rpicamdir/FIFO p
fi
sudo chmod 666 /var/www$rpicamdir/FIFO

if [ ! -e /var/www$rpicamdir/FIFO11 ]; then
  sudo mknod /var/www$rpicamdir/FIFO11 p
fi
sudo chmod 666 /var/www$rpicamdir/FIFO11

if [ ! -e /var/www$rpicamdir/FIFO1 ]; then
  sudo mknod /var/www$rpicamdir/FIFO1 p
fi

sudo chmod 666 /var/www$rpicamdir/FIFO1

if [ ! -d /dev/shm/mjpeg ]; then
  mkdir /dev/shm/mjpeg
fi

if [ "$jpglink" == "yes" ]; then
	if [ ! -e /var/www$rpicamdir/cam.jpg ]; then
	  sudo ln -sf /dev/shm/mjpeg/cam.jpg /var/www$rpicamdir/cam.jpg
	fi
fi

if [ -e /var/www$rpicamdir/status_mjpeg.txt ]; then
  sudo rm /var/www$rpicamdir/status_mjpeg.txt
fi
if [ ! -e /dev/shm/mjpeg/status_mjpeg.txt ]; then
  echo -n 'halted' > /dev/shm/mjpeg/status_mjpeg.txt
fi
sudo chown www-data:www-data /dev/shm/mjpeg/status_mjpeg.txt
sudo ln -sf /dev/shm/mjpeg/status_mjpeg.txt /var/www$rpicamdir/status_mjpeg.txt

sudo chown -R www-data:www-data /var/www$rpicamdir
sudo cp etc/sudoers.d/RPI_Cam_Web_Interface /etc/sudoers.d/
sudo chmod 440 /etc/sudoers.d/RPI_Cam_Web_Interface

sudo cp -r bin/raspimjpeg /opt/vc/bin/
sudo chmod 755 /opt/vc/bin/raspimjpeg
if [ ! -e /usr/bin/raspimjpeg ]; then
  sudo ln -s /opt/vc/bin/raspimjpeg /usr/bin/raspimjpeg
fi

sed -e "s/www/www$rpicamdirEsc/" etc/raspimjpeg/raspimjpeg.1 > etc/raspimjpeg/raspimjpeg
if [[ `cat /proc/cmdline |awk -v RS=' ' -F= '/boardrev/ { print $2 }'` == "0x11" ]]; then
  sed -i 's/^camera_num 0/camera_num 1/g' etc/raspimjpeg/raspimjpeg
fi
if [ -e /etc/raspimjpeg ]; then
  $color_green; echo "Your custom raspimjpg backed up at /etc/raspimjpeg.bak"; $color_reset
  sudo cp -r /etc/raspimjpeg /etc/raspimjpeg.bak
fi
sudo cp -r etc/raspimjpeg/raspimjpeg /etc/
sudo chmod 644 /etc/raspimjpeg
if [ ! -e /var/www$rpicamdir/raspimjpeg ]; then
  sudo ln -s /etc/raspimjpeg /var/www$rpicamdir/raspimjpeg
fi

sudo usermod -a -G video www-data
if [ -e /var/www$rpicamdir/uconfig ]; then
  sudo chown www-data:www-data /var/www$rpicamdir/uconfig
fi

fn_motion
fn_autostart

if [ -e /var/www$rpicamdir/uconfig ]; then
  sudo chown www-data:www-data /var/www$rpicamdir/uconfig
fi

if [ -e /var/www$rpicamdir/schedule.php ]; then
  sudo rm /var/www$rpicamdir/schedule.php
fi

sudo sed -e "s/www/www$rpicamdirEsc/g" www/schedule.php > www/schedule.php.1
sudo mv www/schedule.php.1 /var/www$rpicamdir/schedule.php
sudo chown www-data:www-data /var/www$rpicamdir/schedule.php

if [ $# -eq 0 ] || [ "$1" != "q" ]; then
  fn_reboot
fi
