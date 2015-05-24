#!/bin/bash

#
# Script that helps to install Windows 7 Service Pack 1
# into a virtual machine (KVM) managed by libvirt.
#
# Original Author: Torsten Tränkner
# Port To 14.04: Corbin Crutchley
# License: GPL
#
# Encoding: UTF-8
#

SCRIPT_VERSION="v0.1 (2015-05-07)"


# check for root user
if [ "$(whoami)" != "root" ]; then
 echo "Run this script as root"
 exit 1
fi

# check for size parameter of the virtual machine
if [ $# -lt 2 ];then
 echo
 echo "Script that helps to install Windows"
 echo "into a virtual machine (KVM) managed by libvirt."
 echo
 echo "Version: $SCRIPT_VERSION"
 echo
 echo "You must have a valid Windows XP and above ISO in the same folder as this script"
 echo
 echo "Usage:"
 echo "$0 <VM disk size in GB> <VM RAM size in MB> [Windows ISO name] [no checks]"
 echo
 echo "example for a virtual machine with 20 GB virtual disk size and 1GB RAM:"
 echo "$0 20 1024"
 echo
 echo "example without checksum calculation of the downloaded files and without check for required Linux packages:"
 echo "$0 20 1024 no checks"
 echo
 echo "example with any other iso name than windows7.iso:"
 echo "$0 20 1024 nameofwindows.iso"
 echo
 echo "example without checks and an iso name with something other than windows7.iso:"
 echo "$0 20 1024 nameofwindows.iso no checks"
 echo
 exit 2
fi

echo
echo "DISCLAIMER: Please read the license agreement from Microsoft."
echo "            Only one virtual machine with the correct license"
echo "            is allowed (read the EULA)."
echo

# check for tested Linux distribution
grep -q "14\.04" /etc/issue
if [ $? -ne 0 ];then
 echo "This script was tested in Ubuntu 14.04 only."
 echo "It could work on other versions and other Linux systems with apt - but without any guarantee."
 echo "Continue anyway [y/N] ?"
 read -n 1 ANSWER
 if [ "$ANSWER" == "y" ] || [ "$ANSWER" == "Y" ]; then
  echo
 else
  echo -e "\nBye."
  exit 4
 fi
fi

if [ $# -gt 3 ];then
 NO_CHECKS="true"
else
 NO_CHECKS="false"
fi

if [ -e "$DISK_IMAGE_NAME" ];then
 diskSize=$(du -ks "$DISK_IMAGE_NAME" | sed 's|\s.*||')
 if [ $diskSize -gt 1000000 ] && [ -e /etc/libvirt/qemu/${WINDOWS_NAME}.xml ];then
  echo "Seems that Windows is already installed in a virtual machine."
  echo "Checks are ignored."
  NO_CHECKS="true"
 fi
fi

if [ $# -gt 2 ] && [ "$3" != "no" ];then
 WINDOWS_NAME="$3"
else
 WINDOWS_NAME="windows7"
fi

DISK_IMAGE_NAME="${WINDOWS_NAME}_raw_disk.img"
CURRENT_DIRECTORY="$PWD"
SHARED_DIRECTORY="$PWD/shared"
DOWNLOAD_DIRECTORY="$PWD/downloaded"
virtualMachineSizeInGB="$1"
virtualMachineRAMSizeInMB="$2"

if ! [[ "$virtualMachineSizeInGB" =~ ^[0-9]+$ ]]; then
 echo "Error: virtualMachineSizeInGB is not a number ($virtualMachineSizeInGB) ! Use a number without letters."
 exit 1
fi

if ! [[ "$virtualMachineRAMSizeInMB" =~ ^[0-9]+$ ]]; then
 echo "Error: virtualMachineRAMSizeInMB is not a number ($virtualMachineRAMSizeInMB) ! Use a number without letters."
 exit 1
fi

availableRAMinMB=$(head /proc/meminfo | head -1 | sed 's|.*:\s*\(.*\)...\skB|\1|')
if [ $availableRAMinMB -lt $virtualMachineRAMSizeInMB ];then
 echo "Available memory: $availableRAMinMB is less than $virtualMachineRAMSizeInMB."
 exit 7
fi

directorySpace=$(df -B1073741824 . | sed 's|^[^ ]*  *[^ ]* *[^ ]* *\([^ ]*\) .*|\1|g' | tail -1)

if [ "$NO_CHECKS" == "false" ];then

 # check for minimal disk space
 if [ "$directorySpace" -lt 14 ];then
  echo "You need at least 14 GB in this partition for the installation."
  exit 5
 fi

 # check for minimal VM size
 if [ "$directorySpace" -lt 10 ];then
  echo "The virtual disk should have at least 10 GB."
  exit 5
 fi

 # check the VM size against space of the current partition
 if [ "$directorySpace" -lt "$virtualMachineSizeInGB" ];then
  echo "Available in this directory: $directorySpace GB"
  echo "but you want: $virtualMachineSizeInGB GB."
  echo
  echo "Proceed anyway [y/N] ?"
  read -n 1 ANSWER
  if [ "$ANSWER" != "y" ];then
   exit 5
  else
   echo
  fi
 fi

fi


# check for necessary packages

function checkPackage() {
 package="$1"
 echo "Checking for package: $package"
 result=$(dpkg-query -W -f='${Status}' "$package")
 if [ "$result" != "install ok installed" ];then
  echo "Package $package is not installed."
  echo "Trying to install:"
  if [ "$package" == "libusbredir" ];then
   apt-get install -y qemu-kvm qemu qemu-common qemu-utils libvirt-bin ubuntu-vm-builder bridge-utils
   ln -s /etc/apparmor.d/usr.sbin.libvirtd /etc/apparmor.d/disable/
   service apparmor restart

  else
   apt-get install -y "$package"
   if [ $? -ne 0 ]; then
    echo "Installation of package: $package failed. Exiting."
    exit 6
   fi
  fi
 fi
}


function checkUbuntuPackages() {
 # libvirtd - abstraction layer for virtualization
 checkPackage "libvirt-bin"

 # kvm
 checkPackage "qemu-kvm"

 # virt-manager - GUI for comfortable VM handling
 checkPackage "virt-manager"

 # virt-viewer
 checkPackage "virt-viewer"

 # wmctrl - window manager control to maximize window
 checkPackage "wmctrl"

 # check for iconv to convert windows registry to UTF-16
 checkPackage "libc-bin"

 # to create an ISO image (mkisofs)
 checkPackage "genisoimage"
}


# calculate the checksums of the downloaded file and compare

function checkDownloadedFile() {
 if [ "$NO_CHECKS" == "true" ];then
  return
 fi

 downloadURL="$1"
 downloadName="$2"
 sha1Sum="$3"

 if [ "$sha1Sum" == "-" ];then
  return
 fi

 echo "Calculating checksum of $downloadName - please wait."
 sha1sum "$downloadName" >> checksums.txt
 grep -q "$sha1Sum  *$downloadName" checksums.txt
 if [ $? -eq 0 ]; then
  echo "Checksum of $downloadName is correct."
 else
  echo "Checksum of $downloadName should be $sha1Sum."
  echo "Found:"
  grep "$downloadName" checksums.txt
  echo
  echo "Remove the file $downloadName and check whether the download link is correct:"
  echo "$downloadURL"
  echo
  echo "Exiting."
  exit 2
 fi
}


# download a single file

function download() {
 downloadURL="$1"

 if [ "${downloadURL:0:4}" != "http" ];then
  downloadURL="${URL_FOR_WINDOWS_ISOS}${downloadURL}"
 fi
 downloadName=$(echo "$downloadURL" | sed 's|.*/\([^/]*\)|\1|')

 if [ -e "$downloadName" ];then
  checkDownloadedFile "$downloadURL" "$downloadName" 
  return
 fi

 echo "Downloading: $downloadURL - please wait."
 wget "$downloadURL" -O "$downloadName"
 if [ $? -ne 0 ]; then
  echo "Downloading failed. Please check the download url:"
  echo "$downloadURL"
  exit 1
 fi

 checkDownloadedFile "$downloadURL" "$downloadName"
}


# download all files necessary to create the virtual machine with paravirtualized drivers

function downloadFiles() {
 # Windows VirtIO Drivers
 download https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso

}


# create qemu-kvm configuration for USB 2.0

function createUSB2Configuration() {
 cat > /etc/qemu/ich9-ehci-uhci.cfg << EOF
[device "ehci"]
driver = "ich9-usb-ehci1"
addr = "1d.7"
multifunction = "on"

[device "uhci-1"]
driver = "ich9-usb-uhci1"
addr = "1d.0"
multifunction = "on"
masterbus = "ehci.0"
firstport = "0"

[device "uhci-2"]
driver = "ich9-usb-uhci2"
addr = "1d.1"
multifunction = "on"
masterbus = "ehci.0"
firstport = "2"

[device "uhci-3"]
driver = "ich9-usb-uhci3"
addr = "1d.2"
multifunction = "on"
masterbus = "ehci.0"
firstport = "4"
EOF

}

function createWindows7InstallationConfiguration() {
 vmUUID=$(uuidgen)

 cat > /etc/libvirt/qemu/${WINDOWS_NAME}.xml << EOF
<!--
WARNING: THIS IS AN AUTO-GENERATED FILE. CHANGES TO IT ARE LIKELY TO BE
OVERWRITTEN AND LOST. Changes to this xml configuration should be made using:
  virsh edit ${WINDOWS_NAME}
or other application using the libvirt API.
-->

<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <name>${WINDOWS_NAME}</name>
  <uuid>${vmUUID}</uuid>
  <memory>${virtualMachineRAMSizeInMB}000</memory>
  <currentMemory>${virtualMachineRAMSizeInMB}000</currentMemory>
  <vcpu>1</vcpu>
  <os>
    <type arch='x86_64' machine='pc-1.0'>hvm</type>
    <boot dev='cdrom'/>
    <boot dev='hd'/>
    <bootmenu enable='yes'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='localtime'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw' cache='none'/>
      <source file='${CURRENT_DIRECTORY}/${DISK_IMAGE_NAME}'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw' cache='none'/>
      <source file='${DOWNLOAD_DIRECTORY}/../${WINDOWS_NAME}.iso'/>
      <target dev='hda' bus='ide'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' unit='0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${DOWNLOAD_DIRECTORY}/virtio-win.iso'/>
      <target dev='hdb' bus='ide'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' unit='1'/>
    </disk>
    <controller type='ide' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </controller>
    <interface type='network'>
      <mac address='52:54:00:01:af:b1'/>
      <source network='default'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='tablet' bus='usb'/>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <sound model='ich6'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </sound>
    <video>
      <model type='qxl' vram='65536' heads='1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </memballoon>
  </devices>
  <qemu:commandline>
    <qemu:arg value='-readconfig'/>
    <qemu:arg value='/etc/qemu/ich9-ehci-uhci.cfg'/>
    <qemu:arg value='-chardev'/>
    <qemu:arg value='spicevmc,name=usbredir,id=usbredirchardev1'/>
    <qemu:arg value='-device'/>
    <qemu:arg value='usb-redir,chardev=usbredirchardev1,id=usbredirdev1,bus=ehci.0,debug=3'/>
    <qemu:arg value='-chardev'/>
    <qemu:arg value='spicevmc,name=usbredir,id=usbredirchardev2'/>
    <qemu:arg value='-device'/>
    <qemu:arg value='usb-redir,chardev=usbredirchardev2,id=usbredirdev2,bus=ehci.0,debug=3'/>
    <qemu:arg value='-chardev'/>
    <qemu:arg value='spicevmc,name=usbredir,id=usbredirchardev3'/>
    <qemu:arg value='-device'/>
    <qemu:arg value='usb-redir,chardev=usbredirchardev3,id=usbredirdev3,bus=ehci.0,debug=3'/>
  </qemu:commandline>
</domain>
EOF

  # create backup of the file in case virt-manager destroys the configuration:
  cp /etc/libvirt/qemu/${WINDOWS_NAME}.xml backup.${WINDOWS_NAME}.xml
}

function startVirtualMachine() {

 virsh list --inactive | grep -q "${WINDOWS_NAME}"
 if [ $? -eq 0 ];then
  virsh net-start private
  virsh start ${WINDOWS_NAME}
  sleep 1
 else
  echo "VM is already running."
 fi

 while [ ! -z "$(virsh list --inactive | grep ${WINDOWS_NAME})" ];do
  echo "Waiting for virtual machine to start."
  sleep 0.5
 done

virt-viewer -f ${WINDOWS_NAME} > /dev/null 2>&1 &
 # start ftp for shared folder
 configureFTP
}


function createVirtualMachine() {

 # create a sparse file for the virtual disk image
 dd if=/dev/zero of="$DISK_IMAGE_NAME" bs=1 count=0 seek="$virtualMachineSizeInGB"G > /dev/null 2>&1

 createUSB2Configuration

 # stop the private virtual network if it exists
 virsh net-destroy private 2> /dev/null

 # disable dnsmasq
 #killall dnsmasq

 # restart virt daemon to read the configuration
 service libvirt-bin stop
 createWindows7InstallationConfiguration
 service libvirt-bin start

 startVirtualMachine "max"

# startVirtualMachine 1024 768
}



############
### main
############

if [ "$NO_CHECKS" == "false" ];then
 # remove this for other Linux systems
 checkUbuntuPackages
fi

if [ ! -d shared ];then
 mkdir shared
 chmod 755 shared
 mkdir shared/shared
 chmod 777 shared/shared
fi

if [ ! -d downloaded ];then
 mkdir downloaded
fi
cd downloaded

downloadFiles

cd ..

echo

if [ ! -e "$DISK_IMAGE_NAME" ];then

 echo "Creating virtual machine with Windows 7 service pack 1."
 createVirtualMachine

else

 startVirtualMachine max

fi
