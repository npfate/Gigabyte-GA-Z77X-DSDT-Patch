#/bin/bash
#
# GA-Z77X-UD5H Post Installation Script

REPO=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
GIT_DIR="${REPO}"

git_update()
{
	cd ${REPO}
	echo "[GIT]: Updating local data to latest version"
	
	echo "[GIT]: Updating to latest Gigabyte-GA-Z77X-UD5H-DSDT-Patch git master"
	git pull
	
	echo "[GIT]: Initializing Gigabyte-GA-Z77X-Graphics-DSDT-Patch"
	git submodule update --init --recursive
	
	echo "[GIT]: Updating Gigabyte-GA-Z77X-Graphics-DSDT-Patch"
	git submodule foreach git pull origin master
}

decompile_dsdt()
{
	installerVolume=$(df / | grep "/dev/disk" | cut -d ' ' -f1)
	efiVolume=$(diskutil list "$installerVolume" | grep EFI | cut -d 'B' -f2 | sed -e 's/^[ \t]*//')
	if [ -z "$(mount | grep $efiVolume | sed -e 's/^[ \t]*//')" ]; then
		diskutil mount "$efiVolume" > /dev/null
		mountPoint=$(diskutil info "$efiVolume" | grep "Mount Point" | cut -d ':' -f2 | sed -e 's/^[ \t]*//')
		echo "EFI partition ($efiVolume) mounted at $mountPoint."
	else
		mountPoint=$(diskutil info "$efiVolume" | grep "Mount Point" | cut -d ':' -f2 | sed -e 's/^[ \t]*//')
		echo "EFI partition ($efiVolume) is already mounted at $mountPoint."
	fi

	printf "[DSDT]: Decompiling original DSDT from Clover..."
	cd "${REPO}"
	tools/iasl /$mountPoint/EFI/CLOVER/ACPI/origin/DSDT.aml &> logs/dsdt_decompile.log
	echo "complete."
	echo "Decompilation log available at logs/dsdt_decompile.log"
	mv /$mountPoint/EFI/CLOVER/ACPI/origin/DSDT.dsl DSDT/decompiled/DSDT.dsl
}

patch_dsdt()
{
	cd "${REPO}"

	echo "[DSDT]: Applying GA-Z77X-UD5H main patch"
	tools/patchmatic DSDT/decompiled/DSDT.dsl DSDT/patches/main.txt DSDT/decompiled/DSDT.dsl

	if [[ -z $(system_profiler -detailLevel mini | grep "GeForce") ]] && [[ -z $(system_profiler -detailLevel mini | grep "Radeon") ]]; then
		echo "[DSDT]: No discrete GPU detected, assuming integrated GPU only"
		echo "[DSDT]: Applying Intel HD Graphics 4000 patch"
		tools/patchmatic DSDT/decompiled/DSDT.dsl externals/Gigabyte-GA-Z77X-Graphics-DSDT-Patch/Intel-HD-Graphics-4000.txt DSDT/decompiled/DSDT.dsl
	else
		echo "[DSDT]: Discrete GPU detected, assuming both integrated+discrete GPUs"
		echo "[DSDT]: Applying Intel HD Graphics 4000 (AirPlay) patch"
		tools/patchmatic DSDT/decompiled/DSDT.dsl externals/Gigabyte-GA-Z77X-Graphics-DSDT-Patch/Intel-HD-Graphics-4000-AirPlay.txt DSDT/decompiled/DSDT.dsl
	fi
}

inject_hda()
{
	cd "${REPO}"

	echo "[HDA]: Creating AppleHDA injector kext for Realtek ALC 898"
	mkdir -p audio/AppleHDA898.kext/Contents
	mkdir audio/AppleHDA898.kext/Contents/MacOS

	echo "[HDA]: Creating symbolic link to AppleHDA binary in AppleHDA898.kext"
	ln -s /System/Library/Extensions/AppleHDA.kext/Contents/MacOS/AppleHDA audio/AppleHDA898.kext/Contents/MacOS/AppleHDA

	echo "[HDA]: Copying XML files to AppleHDA898.kext"
	mkdir audio/AppleHDA898.kext/Contents/Resources
	cp -R audio/*.zlib audio/AppleHDA898.kext/Contents/Resources/

	echo "[HDA]: Modifying Info.plist in AppleHDA898.kext"
	plist=audio/AppleHDA898.kext/Contents/Info.plist
	cp /System/Library/Extensions/AppleHDA.kext/Contents/Info.plist $plist
	replace=`/usr/libexec/plistbuddy -c "Print :NSHumanReadableCopyright" $plist | perl -Xpi -e 's/(\d*\.\d*)/9\1/'`
	/usr/libexec/plistbuddy -c "Set :NSHumanReadableCopyright '$replace'" $plist
	replace=`/usr/libexec/plistbuddy -c "Print :CFBundleGetInfoString" $plist | perl -Xpi -e 's/(\d*\.\d*)/9\1/'`
	/usr/libexec/plistbuddy -c "Set :CFBundleGetInfoString '$replace'" $plist
	replace=`/usr/libexec/plistbuddy -c "Print :CFBundleVersion" $plist | perl -Xpi -e 's/(\d*\.\d*)/9\1/'`
	/usr/libexec/plistbuddy -c "Set :CFBundleVersion '$replace'" $plist
	replace=`/usr/libexec/plistbuddy -c "Print :CFBundleShortVersionString" $plist | perl -Xpi -e 's/(\d*\.\d*)/9\1/'`
	/usr/libexec/plistbuddy -c "Set :CFBundleShortVersionString '$replace'" $plist
	/usr/libexec/plistbuddy -c "Add ':HardwareConfigDriver_Temp' dict" $plist
	/usr/libexec/plistbuddy -c "Merge /System/Library/Extensions/AppleHDA.kext/Contents/PlugIns/AppleHDAHardwareConfigDriver.kext/Contents/Info.plist ':HardwareConfigDriver_Temp'" $plist
	/usr/libexec/plistbuddy -c "Copy ':HardwareConfigDriver_Temp:IOKitPersonalities:HDA Hardware Config Resource' ':IOKitPersonalities:HDA Hardware Config Resource'" $plist
	/usr/libexec/plistbuddy -c "Delete ':HardwareConfigDriver_Temp'" $plist
	/usr/libexec/plistbuddy -c "Delete ':IOKitPersonalities:HDA Hardware Config Resource:HDAConfigDefault'" $plist
	/usr/libexec/plistbuddy -c "Delete ':IOKitPersonalities:HDA Hardware Config Resource:PostConstructionInitialization'" $plist
	/usr/libexec/plistbuddy -c "Add ':IOKitPersonalities:HDA Hardware Config Resource:IOProbeScore' integer" $plist
	/usr/libexec/plistbuddy -c "Set ':IOKitPersonalities:HDA Hardware Config Resource:IOProbeScore' 2000" $plist
	/usr/libexec/plistbuddy -c "Merge audio/hdacd.plist ':IOKitPersonalities:HDA Hardware Config Resource'" $plist

	echo "[HDA]: Installing created AppleHDA898.kext"
	sudo cp -R audio/AppleHDA898.kext /System/Library/Extensions

	echo "[HDA]: Rebuilding kext caches"
	sudo kextcache -prelinked-kernel
}

RETVAL=0

case "$1" in
	--update)
		git_update
		RETVAL=1;;
	--decompile-dsdt)
		decompile_dsdt
		RETVAL=1;;
	--patch-dsdt)
		patch_dsdt
		RETVAL=1;;
	--inject-hda)
		inject_hda
		RETVAL=1;;
	*) echo "swag";;
esac

exit $RETVAL