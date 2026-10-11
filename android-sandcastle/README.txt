Project Sandcastle - Android build
Projectsandcastle.org

Android instructions :
Caution - This will create a new volume on APFS. This should not hurt your ability to boot iOS. But if you are not willing to restore your device. Do not try this as it's still beta.

MAC:
You must have checkra1n installed in Applications to run this. Use checkra1n to boot your device into iOS. Run ./setup.sh - This is a one time setup and doesn’t need to be repeated for the same device. Once setup is complete you can put your device into DFU mode and run ./start.sh to boot Android.


Linux:
Checkra1n boot your device and login to it via SSH. Scp isetup file to /tmp on your iPhone and run chmod 755 /tmp/setup.sh && /tmp/setup.sh
Once setup is complete grab the latest loadlinux.c source code from our github https://github.com/corellium/projectsandcastle/ and compile it and run ./loadlinux Android.lzma dtbpack


Removing it:
If you wish to remove the Android NAND image and reclaim the space you can login via SSH to your checkra1ned device and mount the final volume and remove the nand file. To do this run ls /dev/disk0s1s* and find the last volume. You can verify its the right volume by running /System/Library/Filesystems/apfs.fs/apfs.util -p VOLUME_HERE and if it says Android, that's the correct one. Once you have the volume path you can then run 
mkdir -p /tmp/mnt 
mount -t apfs VOLUME_HERE /tmp/mnt 
rm -rf /tmp/mnt/nand
umount /tmp/mnt
sync

And that will reclaim the space for you. 

