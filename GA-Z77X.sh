#!/bin/bash
# Gigabyte GA-Z77X OS X Post-Install Script by theracermaster
# Supports various Gigabyte GA-Z77X motherboards
# Gigabyte GA-Z77X DSDT Patch Repo - http://git.io/vIatr

# Initialize global variables

## The script version
gScriptVersion="1.6"

## The user ID
gID=$(id -u)

## The motherboard, will be properly initialized later
gMotherboard="Unknown"

## The folder containing the repo
gRepo=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

## The SMBIOS product name
gProductName="iMac13,2"

## The location where the EFI partition is mounted
gEFIMount="Unknown"

## Styling stuff
STYLE_RESET="\e[0m"
STYLE_BOLD="\e[1m"
STYLE_UNDERLINED="\e[4m"

## Colors
COLOR_BLACK="\e[1m"
COLOR_RED="\e[1;31m"
COLOR_GREEN="\e[32m"
COLOR_DARK_YELLOW="\e[33m"
COLOR_MAGENTA="\e[1;35m"
COLOR_PURPLE="\e[35m"
COLOR_CYAN="\e[36m"
COLOR_BLUE="\e[1;34m"
COLOR_ORANGE="\e[31m"
COLOR_GREY="\e[37m"
COLOR_END="\e[0m"

#-------------------------------------------------------------------------------#
function _identifyMotherboard()
{
	# Initialize variables
	motherboard=$(tools/bdmesg | grep "Z77X" | cut -d '-' -f2 | sed 's/[[:space:]]//g')

	# Identify the motherboard
	case $motherboard in
		'D3H')
			gMotherboard="D3H";;
		'UD3H')
			gMotherboard="UD3H";;
		'UD5H')
			gMotherboard="UD5H";;
		'UP5 TH')
			gMotherboard="UP5-TH";;
		'UP7')
			gMotherboard="UP5-TH";;
		*)
			echo "ERROR: "$motherboard" motherboard is unsupported by this script. Exiting..." && exit 1;;
	esac
}

function _printHeader()
{
	# Initialize variables
	args="$1"

	clear

	# Print the header & info
	echo "Gigabyte GA-Z77X.sh Post-Install Script v$gScriptVersion by theracermaster"
	echo "Updates & Info: https://github.com/theracermaster/Gigabyte-GA-Z77X-DSDT-Patch"
	echo "--------------------------------------------------------------------------------"
	printf "Detected motherboard: Gigabyte ${STYLE_BOLD}GA-${COLOR_CYAN}Z77X-${COLOR_DARK_YELLOW}$gMotherboard${STYLE_RESET}\n"
	printf "Script arguments: ./GA-Z77X.sh $args\n"
	echo "--------------------------------------------------------------------------------"
}

function _checkRoot()
{
	if [ $gID -ne 0 ]; then
		# Re-run the script as root
		printf "This part of the script ${STYLE_UNDERLINED}needs${STYLE_RESET} to be run as root.\n"
		sudo clear
	fi
}

function _installKextEFI()
{
	# Initialize variables
	kext="$1"

	# Copy the kext to the Clover kexts folder on the EFI partition
	cp -R "$kext" "$gEFIMount/EFI/CLOVER/kexts/Other"
}

function _detectAtherosNIC()
{
	# Initialize variables
	atherosNIC=$("$gRepo/tools/dspci" | grep "Ethernet controller" | grep "1969" | cut -d ':' -f 4 | cut -d ']' -f 1)

	# Gigabyte shipped different revisions of boards with different Atheros NICs
	# AtherosL1cEthernet supports AR8151, while AtherosE2200Ethernet supports AR8161
	# Install the correct Atheros kext if an Atheros NIC is detected
	if [[ ! -z $atherosNIC ]]; then
		case $atherosNIC in
			1083) # Atheros AR8151 v2.0 GbE - use AtherosL1cEthernet
				echo " - Atheros AR8151 v2.0 [1969:1083] detected, installing AtherosL1cEthernet.kext..."
				_installKextEFI "$gRepo/kexts/AtherosL1cEthernet.kext";;
			1091) # Atheros AR8161 GbE - use AtherosE2200Ethernet
				echo " - Atheros AR8161 [1969:1091] detected, installing AtherosE2200Ethernet.kext..."
				_installKextEFI "$gRepo/kexts/AtherosE2200Ethernet.kext";;
		esac
	fi
}

function _detectIntelNIC()
{
	# Initialize variables
	intelNIC=$("$gRepo/tools/dspci" | grep "Ethernet controller" | grep "8086" | cut -d ':' -f 4 | cut -d ']' -f 1)

	# Install IntelMausiEthernet.kext if an Intel NIC is detected
	if [[ ! -z $intelNIC ]]; then
		case $intelNIC in
			1503) # Intel 82579V GbE
				echo " - Intel 82579V [8086:1503] detected, installing IntelMausiEthernet.kext..."
				_installKextEFI "$gRepo/kexts/IntelMausiEthernet.kext";;
		esac
	fi
}

function _detectRealtekNIC()
{
	# Initialize variables
	realtekNIC=$("$gRepo/tools/dspci" | grep "Ethernet controller" | grep "10ec" | cut -d ':' -f 4 | cut -d ']' -f 1)
	
	# Install RealtekRTL8111.kext if a Realtek NIC is detected
	if [[ ! -z $realtekNIC ]]; then
		case $realtekNIC in
			8168) # Realtek RTL8168/RTL8111 GbE
				echo " - Realtek RTL8168/RTL8111 [10ec:8168] detected, installing RealtekRTL8111.kext..."
				_installKextEFI "$gRepo/kexts/RealtekRTL8111.kext";;
		esac
	fi
}

function _detectMarvellSATA()
{
	# Initialize variables
	marvellSATA=$("$gRepo/tools/dspci" | grep "SATA controller" | grep "1b4b")

	# Install AHCI_3rdParty_SATA if Marvell SATA controllers are detected
	if [[ ! -z $marvellSATA ]]; then
		echo " - Marvell SATA controller detected, installing AHCI_3rdParty_SATA.kext..."
		_installKextEFI "$gRepo/kexts/AHCI_3rdParty_SATA.kext"
	fi
}

function _detectXHCI()
{
	# Initialize variables
	plist="$gEFIMount/EFI/CLOVER/config.plist"
	xhciList=$("$gRepo/tools/dspci" | grep "xHCI Host Controller\|USB 3.0 Host Controller")
	nonIntelXHCI=$(echo $xhciList | grep -Fv "Intel")

	if [ ! -f "$plist" ]; then
		printf "${COLOR_RED}${STYLE_BOLD}ERROR: ${STYLE_RESET}${STYLE_BOLD}config.plist not found!${STYLE_RESET} Exiting...\n"
		exit 1
	fi

	# Add the kext patches to the plist if non-Intel XHCI controllers are detected
	if [[ ! -z $nonIntelXHCI ]]; then
		/usr/libexec/PlistBuddy -c "Merge $gRepo/patches/AppleUSBXHCI.plist ':KernelAndKextPatches:KextsToPatch'" $plist
	fi
}

function _detectPS2()
{
	case $gMotherboard in
		"D3H" | "UD3H" | "UP7") # Motherboards that have a PS/2 port
			echo " - PS/2 hardware present, installing VoodooPS2Controller..."
			_installKextEFI "$gRepo/kexts/VoodooPS2Controller.kext"
			cp org.rehabman.voodoo.driver.Daemon.plist /Library/LaunchDaemons
			cp VoodooPS2Controller /usr/bin
	esac	
}

function _genSMBIOSData()
{
	# Initialize variables
	printf "${STYLE_BOLD}Generating SMBIOS data${STYLE_RESET}:\n"
	plist="$gEFIMount/EFI/CLOVER/config.plist"

	if [ ! -f "$plist" ]; then
		printf "${COLOR_RED}${STYLE_BOLD}ERROR: ${STYLE_RESET}${STYLE_BOLD}config.plist not found!${STYLE_RESET} Exiting...\n"
		exit 1
	fi

	serialNumber=$(externals/simpleMacSerial.sh/simpleMacSerial.sh iMac13,2)
	MLB=$(externals/simpleMLB.sh/simpleMLB.sh $serialNumber)
	SmUUID=$(uuidgen)

	echo " - Product Name: $gProductName"
	echo " - Serial Number: $serialNumber"
	echo " - MLB Serial Number: $MLB"
	echo " - System UUID: $SmUUID"

	# TODO: If plist doesn't exist, exit with error

	# Copy the generated data to the plist
	/usr/libexec/plistbuddy -c "Set :SMBIOS:ProductName '$gProductName'" $plist
	/usr/libexec/plistbuddy -c "Set :SMBIOS:SerialNumber '$serialNumber'" $plist
	/usr/libexec/plistbuddy -c "Set :RtVariables:MLB '$MLB'" $plist
	/usr/libexec/plistbuddy -c "Set :SMBIOS:SmUUID '$SmUUID'" $plist

	printf "\n${STYLE_BOLD}Press enter to continue...${STYLE_RESET}\n" && read
}
#-------------------------------------------------------------------------------#



#-------------------------------------------------------------------------------#
function _gitUpdate()
{
	# Make sure we're in the repo folder
	cd "$gRepo"

	# Update the repo files
	echo "Updating local data to latest version"
	echo "Updating to latest Gigabyte-GA-Z77X-DSDT-Patch git master"
	git pull

	# Update the external repos
	echo "Initializing external repos"
	git submodule update --init --recursive
	echo "Updating external repos"
	git submodule foreach git pull origin master
}

function _installSSDT()
{
	# Clear the output and print the header
	_printHeader "${STYLE_BOLD}--install-ssdt: ${COLOR_GREEN}Downloading Custom SSDT${STYLE_RESET}"

	# Initialize variables
	fileName="SSDT-GA-Z77X-$gMotherboard.dsl"
	url="https://raw.githubusercontent.com/theracermaster/DSDT/master/$fileName"

	# Download the file
	printf "${STYLE_BOLD}Downloading $fileName${STYLE_RESET}:\n"
	curl --output "/tmp/$fileName" --progress-bar --location "$url"

	# Download the file
	# _download $url "SSDT-GA-Z77X-$gMotherboard.dsl" /tmp/SSDT.dsl

	# Compile the SSDT and move it to the right directory
	printf "${STYLE_BOLD}Compiling $fileName${STYLE_RESET}:\n"
	iasl "/tmp/$fileName"
	mv "/tmp/SSDT-GA-Z77X-$gMotherboard.aml" "$gRepo/EFI/CLOVER/ACPI/patched/SSDT.aml"

	printf "\n${STYLE_BOLD}Compilation complete.${STYLE_RESET} Exiting...\n"
	exit 0
}

function _injectHDA()
{
	# Initialize variables
	plist="$gRepo/EFI/CLOVER/config.plist"

	# Load AppleHDA.kext so we can ID the codec
	sudo kextload "/System/Library/Extensions/AppleHDA.kext"

	# Run the HDA injector script
	sudo "$gRepo/externals/hdaInjector.sh/hdaInjector.sh"

	# Copy config.plist and add the kext patches to it
	cp "$gRepo/config-generic.plist" "$plist"
	/usr/libexec/PlistBuddy -c "Merge /tmp/ktp.plist ':KernelAndKextPatches:KextsToPatch'" $plist
}

function _installClover()
{
	# Clear the output and print the header
	_printHeader "${STYLE_BOLD}--install-clover: ${COLOR_GREEN}Installing Clover Bootloader${STYLE_RESET}"

	# Find the BSD device name for the current OS disk
	osVolume=$(df / | grep "/dev/disk" | cut -d ' ' -f1)

	# Find the EFI partition of the disk
	efiVolume=$(diskutil list "$osVolume" | grep EFI | cut -d 'B' -f2 | sed -e 's/^[ \t]*//')

	# Check if the EFI partition is already mounted; if not, mount it
	if [ -z "$(mount | grep $efiVolume | sed -e 's/^[ \t]*//')" ]; then
		diskutil mount "$efiVolume" > /dev/null
		mountPoint=$(diskutil info "$efiVolume" | grep "Mount Point" | cut -d ':' -f2 | sed -e 's/^[ \t]*//')
		echo "EFI system partition ($efiVolume) mounted at $mountPoint."
	else
		mountPoint=$(diskutil info "$efiVolume" | grep "Mount Point" | cut -d ':' -f2 | sed -e 's/^[ \t]*//')
		echo "EFI system partition ($efiVolume) is already mounted at $mountPoint."
	fi
	gEFIMount="$mountPoint"

	# Check if there is an existing bootloader install; if so, ask the user if it can be overwritten
	if [ -d "$gEFIMount/EFI" ]; then
		
		efiBoot=$(ls "$gEFIMount/EFI"| grep -Fv 'APPLE' | grep -Fv 'BOOT')
		case $efiBoot in 
			CLOVER)
				efiBoot=$(printf ${COLOR_GREEN}${STYLE_BOLD}$efiBoot${STYLE_RESET});;
			Microsoft)
				efiBoot=$(printf ${COLOR_BLUE}${STYLE_BOLD}$efiBoot${STYLE_RESET});;
		esac

		echo "An existing UEFI bootloader ($efiBoot) was found on the EFI system partition."
		printf "${STYLE_BOLD}Do you want to overwrite it (y/n)?${STYLE_RESET} "
		read choice
		case "$choice" in
			y|Y)
				echo "Removing existing $efiBoot UEFI bootloader..."
				rm -rf "$gEFIMount/EFI";;
			n|N)
				echo "Renaming EFI directory to EFIbackup..."
				mv "$gEFIMount/EFI" "$gEFIMount/EFIbackup";;
		esac
	fi

	# Clear the output and reprint the header
	_printHeader "${STYLE_BOLD}--install-clover: ${COLOR_GREEN}Installing Clover Bootloader${STYLE_RESET}"

	# Copy the directories to the EFI partition & create the kext directory
	cp -R "$gRepo/EFI" "$gEFIMount"
	mkdir -p "$gEFIMount/EFI/CLOVER/kexts/Other"

	# Install the required kexts to the EFI partition
	printf "${STYLE_BOLD}Installing kexts to EFI partition${STYLE_RESET}:\n"
	## Install FakeSMC
	_installKextEFI "$gRepo/kexts/FakeSMC.kext"
	## Check what other kexts/patches are needed and install them
	_detectAtherosNIC
	_detectIntelNIC
	_detectRealtekNIC
	_detectMarvellSATA
	_detectXHCI
	_detectPS2

	# Generate the SMBIOS data
	_genSMBIOSData

	# Clear the output and reprint the header
	_printHeader "${STYLE_BOLD}--install-clover: ${COLOR_GREEN}Installing Clover Bootloader${STYLE_RESET}"

	# Rebuld kext caches
	printf "${STYLE_BOLD}Rebuilding kext caches${STYLE_RESET}:\n"
	sudo kextcache -system-prelinked-kernel
	sudo kextcache -system-caches

	# We're done here, let's prompt the user to reboot
	printf "\n${STYLE_BOLD}Installation complete. Do you want to reboot now (y/n)?${STYLE_RESET} "
	read choice
	case "$choice" in
		y|Y) # User said yes, so let's reboot
			echo "Rebooting..."
			sudo reboot;;
		*) # Anything else, let's just quit
			echo "Exiting..."
			exit 0;;
	esac
}

function _cleanup()
{
	_printHeader "${STYLE_BOLD}--cleanup: ${COLOR_GREEN}Deleting Generated Repo Files${STYLE_RESET}"

	# Make sure we're in the repo folder
	cd "$gRepo"

	# Delete the generated files
	printf "${STYLE_BOLD}Deleting generated files in repo folders${STYLE_RESET}:\n"
	rm -f EFI/CLOVER/ACPI/patched/*.aml
	rm -f EFI/CLOVER/config.plist
	rm -f /tmp/*.aml
	rm -f /tmp/*.dsl
	sudo rm -rf /tmp/*.plist

	# Exit once it's done
	printf "\n${STYLE_BOLD}Cleaning complete.${STYLE_RESET} Exiting...\n"
	exit 0
}
#-------------------------------------------------------------------------------#

RETVAL=0

case "$1" in
	--git-update)
		_gitUpdate
		RETVAL=1;;
	--install-ssdt)
		_identifyMotherboard
		_installSSDT
		RETVAL=1;;
	--inject-hda)
		_checkRoot
		_injectHDA
		RETVAL=1;;
	--install-clover)
		_identifyMotherboard
		_checkRoot
		_installClover
		RETVAL=1;;
	--cleanup)
		_checkRoot
		_cleanup
		RETVAL=1;;
	*)
		echo "Gigabyte GA-Z77X.sh Post-Install Script v$gScriptVersion by theracermaster"
		echo "Supports various Gigabye GA-Z77X motherboards"
		echo
		echo "Usage: ./GA-Z77X.sh <command>, where <command> is one of the following:"
		echo
		echo "     --git-update         Update the repo & helper files to the latest version"
		echo "     --install-ssdt       Install the SSDT for your motherboard"
		echo "     --inject-hda         Install injector kext for your audio codec"
		echo "     --install-clover     Install Clover to your EFI partition"
		echo "     --cleanup            Delete files generated by this script in repo folders"
		echo
		echo "Updates & Info: https://github.com/theracermaster/Gigabyte-GA-Z77X-DSDT-Patch"
esac

exit $RETVAL
