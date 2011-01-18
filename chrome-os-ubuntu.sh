#!/bin/bash
#
# This script is used to install Ubuntu to CR-48 (or any other Chrome OS devices) from USB drive
#

# Display the purpose of this script
echo -e "\n==============================================================="
echo -e "This script helps you to install Ubuntu on CR-48 (or any other \nChrome OS devices) from USB drive a little easier.\n"
echo -e "NOTE: You can pass the location of your USB drive as the only \nparameter of this script"
echo -e "For example, bash chrome-os-ubuntu.sh /tmp/usb"
echo -e "================================================================="

# Disabled powerd service
echo -e "\nDisabling power management service..."
sudoV="`initctl start powerd`"
sudoV2="`initctl stop powerd`"
if [ "$sudoV" = "" -a "$sudoV2" = "" ]
then
	echo "Make sure you run this script in the root account. Enter the following to enter root:"
	echo "sudo su"
	echo "After you are in the root account, run this script again."
	exit
fi
initctl stop powerd
echo -e "Power management disabled."

echo -e "\nChecking the partitions size..."

# Do the following tasks if they were not already done
resizeV="`sudo cgpt show /dev/sda | grep 12103680`"
if [ "$resizeV" = "" ]; then

	# Resize the partitions
	echo -e "Resizing the partitions..."
	sudo umount /mnt/stateful_partition
	sudo cgpt add -i 1 -b 266240    -s 12103680 -l STATE   /dev/sda
	sudo cgpt add -i 6 -b 12369920  -s 32768    -l KERN-C  /dev/sda
	sudo cgpt add -i 7 -b 12402688  -s 10485760 -l ROOT-C  /dev/sda

	# Destory the stateful_partition
	echo -e "Clearing the stateful_partition, it will take some time..."
	sudo dd if=/dev/zero of=/dev/sda bs=131072 seek=1040 count=47280

	# Restart the notebook
	echo -e "\nYou need to reboot your notebook in order to continue.\nMake sure to press CTRL + ALT + => (Left arrow), login as chronos, and run this script one more time after Chrome OS was rebooted.\nPress ENTER to continue or wait 1 minute to reboot automatically."
	read -t 60 iputs
	sudo reboot

fi

echo -e "The partitions are resized."

# USB drive verification
usbV="`mount | grep sd | grep -v sda`"
listing="`ls /media | tail -n 1`"
if [ "$1" == "" ]; then
	usbDr="`ls /media/$listing`"
else
	usbDr="$1"
fi
while [ "$usbV" = "" -o "$usbDr" = "" ]; do
	echo -e "\nPlease insert the USB drive with rootfs.bin, make_dev_ssd.sh, and common.sh in it.\nPress ENTER when the drive is inserted.\nIf you are not signed on to Chrome OS. Please press CTRL (left) + ALT (left) + <= (left arrow) to return to the graphical interface and sign on in order to detect yout USB drive by Chrome OS. Press CTRL + ALT + => (right arrow) to return to this script and press ENTER to continue.\n";
	echo -e "Note that if you already mounted your USB driver manually, you can kill this script by pressing CTRL + Z and rerun this script with a parameter that points to the path of your USB drive.\nFor example, bash chrome-os-ubuntu.sh /tmp/usb"
	read ready
	echo -e "Detecting USB device..."
	sleep 10
	usbV="`mount | grep sd | grep -v sda`"
	listing="`ls /media | tail -n 1`"
	usbDr="`ls /media/$listing`"
done

# Mount the USB drive
echo -e "\nMounting USB drive..."
if [ "$1" == "" ]; then
	usbDir="/media/$listing"
else
	usbDir="$1"
fi
echo -e "USB drive is mounted."

# Determine the existence of three required files
rootfs="`test -e $usbDir/rootfs.bin;echo -e $?`"
makeDev="`test -e $usbDir/make_dev_ssd.sh;echo -e $?`"
commons="`test -e $usbDir/common.sh;echo -e $?`"
if [ "$rootfs" = 1 -o "$makeDev" = 1 -o "$commons" = 1 ]; then
	echo -e "\nSome of the required files cannot be found on the drive.\nMake sure rootfs.bin, make_dev_ssd.sh, and common.sh are copied to the drive and reinsert it to the notebook.\nRestart this script when you are ready."
	sudo umount $usbDir
	exit
fi

# Copy rootfs.bin in USB drive to /dev/sda7
echo -e "\nCopying rootfs.bin to /dev/sda7, this will take some time..."
sudo dd if=$usbDir/rootfs.bin of=/dev/sda7
echo -e "rootfs.bin successfully copied."

# Mount /dev/sda7
echo -e "\nMounting Ubuntu partition..."
sudo mkdir /tmp/urfs
sudo mount /dev/sda7 /tmp/urfs
echo -e "Ubuntu partition is mounted."

# Copy cgpt and /lib/modules/ to Ubuntu partition
echo -e "\nCopying necessary files to Ubuntu..."
sudo cp /usr/bin/cgpt /tmp/urfs/usr/bin/
sudo chmod a+rx /tmp/urfs/usr/bin/cgpt
sudo cp -ar /lib/modules/* /tmp/urfs/lib/modules/
echo -e "The files are copied successfully."

# Unmount /dev/sda7
echo -e "\nUnmounting Ubuntu partition..."
sudo umount /tmp/urfs
sudo rmdir /tmp/urfs
echo -e "Ubuntu partition successfully unmounted."

# Decide the rootdev
echo -e "\nDetermining the Chrome OS kernel partition..."
rootfs="`rootdev -s`"
if [ "$rootfs" = "/dev/sda3" ]; then
	ker="/dev/sda2"
else
	ker="/dev/sda4"
fi
echo -e "Your kernel partition is in $ker."

# Copy the kernel to /dev/sda6
echo -e "\nCopying $ker to /dev/sda6..."
sudo dd if=$ker of=/dev/sda6
echo -e "Copied successfully."
echo -e "\nNow is the critical time to check the above output for any errors. If there are some errors, press Ctrl+z to stop this script and correct them. By not correcting them, you might need recover image from Google to restore Chrome OS. Otherwise, press ENTER to continue."
read checkEr

# Change kernel command line
echo -e "\nChanging the kernel command line..."
cd $usbDir
sudo sh ./make_dev_ssd.sh --partitions '6' --save_config foo
echo -e "console=tty1 init=/sbin/init add_efi_memmap boot=local rootwait ro noresume noswap i915.modeset=1 loglevel=7 kern_guid=%U tpm_tis.force=1 tpm_tis.interrupts=0 root=/dev/sda7 noinitrd" > foo.6
sudo sh ./make_dev_ssd.sh --partitions '6' --set_config foo
echo -e "Changed successfully."

# Generate ubuntu alias in .profile
echo -e "\nGenerating ubuntu alias..."
echo -e "alias ubuntu=\"sudo cgpt add -i 6 -P 5 -S 1 /dev/sda;sudo cgpt add -i 2 -P 0 -S 0 /dev/sda;echo 'Swiched to Ubuntu, restart to take effect'\"\n" >> /home/chronos/.profile
echo -e "ubuntu alias generated."
echo -e "\nYou can type 'ubuntu' (without quotes) in Chrome OS command line to switch to Ubuntu from now on.\nIn Ubuntu, add the following line to .bashrc to use 'chromeos' (without quotes) to switch back to Chrome OS:"
echo -e "alias chromeos=\"sudo cgpt add -i 2 -P 5 -S 1 /dev/sda;sudo cgpt add -i 6 -P 0 -S 0 /dev/sda;echo 'Switched to Chrome OS, restart to take effect'\""
echo -e "\nPress ENTER after you copied the above alias down."
read chromeos

# Complete Ubuntu installation
sudo cgpt add -i 6 -P 5 -S 1 /dev/sda
sudo cgpt add -i 2 -P 0 -S 0 /dev/sda
echo -e "\nUbuntu installation is complete.\nPress ENTER or wait 30 seconds to enter the newly installed Ubuntu."
read -t 30 ubuntu
sudo reboot

