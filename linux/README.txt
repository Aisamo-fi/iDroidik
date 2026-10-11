Project Sandcastle Linux build with builtin ramdisk.


MAC:
Grab the latest checkra1n from http://checkra.in and run /Applications/checkra1n.app/Contents/MacOS/checkra1n -cp then
run ./load-linux.mac Linux.lzma dtbpack

Linux:
Grab the latest checkra1n from http://checkra.in and run checkra1n -cp then grab the latest load-linux.c source code from
our github https://github.com/corellium/projectsandcastle/ and compile it and run ./load-linux Linux.lzma dtbpack


The linux build comes with a baked in ramdisk. It will automatically bring up X windows after boot. It will create a
gadget usb interface on the host computer and if you set the IP address of the interface to 172.16.1.2/255.255.255.0 
you will be able to access the iPhone at 172.16.1.1. Once its booted you can login via ssh with root/alpine.

To use bluetooth -
# hciconfig hci0 up
# bt-adapter -d
Searching...
[47:29:F5:32:D1:C0]
  Name: (NULL)
  Alias: 47-29-F5-32-D1-C0
  Address: 47:29:F5:32:D1:C0
  Icon: (NULL)
  Class: 0x0
  LegacyPairing: 0
  Paired: 0
  RSSI: -70


To use Wifi -
# iw wlan0 scan
BSS 11:22:52:3c:67:20(on wlan0)
	last seen: 97.608s [boottime]
	TSF: 0 usec (0d, 00:00:00)
	freq: 2412
	beacon interval: 100 TUs
	capability: ESS Privacy Sh
……
# wpa_passphrase SSID PASSWORD > /etc/wpa_supplicant.conf
# wpa_supplicant -Dnl80211 -iwlan0 -c/etc/wpa_supplicant.conf -B
# udhcpc -i wlan0

Run doom -
# chocolate-doom

Run X windows manager -
# fluxbox
