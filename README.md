# BashKVMHandler
These are scripts for handling/creating KVM VMs.

## Prerequisits
You need to have KVM already set up to how Ubuntu Docs specifies. For a script to set that up, check out my other script. https://github.com/crutchcorn/basickvmsetup

## Usage
You can use this script by following the instructions once you run the script. 

First off, you'll need to run the script in root.
You'll want to move the windows ISO into the same folder as the scripts, then run the scripts using `sudo ./scriptname.sh`
You must decide how many GBs you want to alliocate to the RAM and HDD space for the VM. Essentially it should follow this formula `sudo ./scriptname.sh <VM disk size in GB> <VM RAM size in MB> [Windows ISO name without .iso] [no checks]`. No checks meaning that it will not run MD5 hash checks on the files you are downloading (thus, making it faster)
An example of a script being ran is `sudo ./scriptname.sh 20 1024 windows7_x64.iso`
The name of the ISO will default to `windows7.iso` so if you leave the `[Windows ISO name without .iso]` area blank, it will default to using `windows7.iso`
