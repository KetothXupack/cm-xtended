#!/bin/bash

echo "$0" | grep -q bash
if [ $? -eq 0 ] || [ "${buildbot}" = "Y" ]; then
	cd ~/Downloads/cm-xtended
else
	cd "`dirname \"$0\"`"
fi

#Prerequisites

#bash
if [ ! -n "$BASH" ]; then
	echo "Try again with a bash shell"
	return
fi

#lz4
which lz4 > /dev/null
if [ $? -ne 0 ]; then
	echo "Install lz4:"
	echo ""
	echo "cd ~/Downloads"
	echo "svn checkout -r 91 http://lz4.googlecode.com/svn/trunk/ lz4"
	echo "cd lz4 && make && cp lz4demo ~/bin/lz4"
	echo ""
	return
fi

#Configuration

cm=cm10_1
patches=`pwd`
repo=`which repo`
tmp=/tmp
android=~/android/${cm}
devices="coconut iyokan mango smultron"
hdmi="haida hallon iyokan"
init=N
updates=N
debug=N

if [ "$1" = "init" ]; then
	init=Y
fi

#Linaro

linaro_name=arm-eabi-4.7-linaro
linaro_file=android-toolchain-eabi-4.7-daily-linux-x86.tar.bz2
linaro_url=https://android-build.linaro.org/jenkins/view/Toolchain/job/linaro-android_toolchain-4.7-bzr/lastSuccessfulBuild/artifact/build/out/${linaro_file}

#bootimage

kernel_mods=Y
kernel_linaro=N
kernel_clock=Y
kernel_xtended=Y
kernel_autogroup=Y
kernel_cleancache=Y
kernel_hdmi=N
kernel_otg=N			#Does not build
kernel_usb_tether=Y
kernel_wl12xx_bp=N
kernel_ti_cw=Y

bootlogo=Y
bootlogoh=logo_H_extended.png
bootlogom=logo_M_extended.png

pin=Y

#ROM

mms_fix=Y
pdroid=Y
terminfo=Y
xsettings=Y
ssh=Y
fmtools=Y
adhoc=N

#Local configuration
if [ -f ~/.cm101xtended ]; then
	. ~/.cm101xtended
fi

#Say hello
echo ""
echo "CM extended ROM/kernel"
echo "Copyright (c) 2013 Marcel Bokhorst (M66B)"
echo "http://blog.bokhorst.biz/about/"
echo ""
echo "GNU GENERAL PUBLIC LICENSE Version 3"
echo ""
echo "Patches: ${patches}"
echo "Repo: ${repo}"
echo "Tmp: ${tmp}"
echo "Android: ${android}"
echo "Devices: ${devices}"
echo "Init: ${init}"
echo "Updates: ${updates}"
echo ""

#Prompt
if [[ $- == *i* ]]
then
	read -p "Press [ENTER] to continue" dummy
	echo ""
fi

#Helper functions
do_replace() {
	sed -i "s/$1/$2/g" $3
	grep -q "$2" $3
	if [ $? -ne 0 ]; then
		echo "!!! Error replacing '$1' by '$2' in $3"
		exit
	fi
	if [ "${debug}" = "Y" ]; then
		echo "Replaced '$1' by '$2' in $3"
	fi
}

do_patch() {
	if [ -f ${patches}/$1 ]; then
		patch -p1 --forward -r- --no-backup-if-mismatch <${patches}/$1
		if [ $? -ne 0 ]; then
			echo "!!! Error applying patch $1"
			exit
		fi
	else
		echo "!!! Patch $1 not found"
		exit
	fi
}

do_patch_reverse() {
	if [ -f ${patches}/$1 ]; then
		patch -p1 --reverse -r- --no-backup-if-mismatch <${patches}/$1
		if [ $? -ne 0 ]; then
			echo "!!! Error applying reverse patch $1"
			exit
		fi
	else
		echo "!!! Patch $1 not found"
		exit
	fi
}

do_append() {
	if [ -f $2 ]; then
		echo "$1" >>$2
		if [ "${debug}" = "Y" ]; then
			echo "Appended '$1' to $2"
		fi
	else
		echo "!!! Error appending '$1' to $2"
		exit
	fi
}

do_deldir() {
	if [ -d "$1" ]; then
		chmod -R 777 $1
		rm -R $1
	else
		if [ "${debug}" = "Y" ]; then
			echo "--- $1 does not exist"
		fi
	fi
}

do_copy() {
	cp $1 $2
	if [ $? -ne 0 ]; then
		echo "!!! Error copying $1 to $2"
		exit
	fi
}

#Headless
mkdir -p ~/Downloads

#Cleanup
echo "*** Cleanup ***"

#PDroid
do_deldir ${android}/out/target/common/obj/JAVA_LIBRARIES/framework_intermediates
do_deldir ${android}/out/target/common/obj/JAVA_LIBRARIES/framework2_intermediates
do_deldir ${android}/out/target/common/obj/APPS/TelephonyProvider_intermediates
do_deldir ${android}/packages/apps/PDroidAgent

for device in ${devices}; do
	#kernel
	do_deldir ${android}/out/target/product/${device}/obj/KERNEL_OBJ/
	if [ -d "${android}/out/target/product/${device}" ]; then
		cd ${android}/out/target/product/${device}/
		rm -f ./kernel ./*.img ./*.cpio ./*.fs
	fi

	#ROM
	if [ -d "${android}/out/target/product/${device}/system" ]; then
		rm -f ${android}/out/target/product/${device}/system/build.prop
		rm -f ${android}/out/target/product/${device}/system/lib/modules/*
	fi
done

#Initialize
if [ "${init}" = "Y" ]; then
	cd ${android}
	repo init -u git://github.com/CyanogenMod/android.git -b cm-10.1
fi

#Local manifest
echo "*** Local manifest ***"
lmanifests=${android}/.repo/local_manifests
mkdir -p ${lmanifests}
curl https://raw.github.com/LegacyXperia/local_manifests/master/semc.xml >${lmanifests}/semc.xml
rm -f ${lmanifests}/cmxtended.xml	#legacy
do_copy ${patches}/xtended.xml ${lmanifests}/xtended.xml

#CMUpdater
if [ "${updates}" = "Y" ]; then
	echo "--- updates"
	sed -i "/CMUpdater/d" ${android}/vendor/cm/config/common.mk
fi

#Sync
echo "*** Repo sync ***"
cd ${android}
if [ "${init}" != "Y" ]; then
	${repo} forall -c "git remote -v | head -n 1 | tr -d '\n' && echo -n ': ' && git reset --hard && git clean -df"
	if [ $? -ne 0 ] && [ "${buildbot}" != "Y" ]; then
		exit
	fi
fi
${repo} sync
if [ $? -ne 0 ]; then
	exit
fi

#Linaro toolchain
if [ "${kernel_linaro}" = "Y" ]; then
	echo "*** Linaro toolchain: ${linaro_name} ***"
	linaro_dir=${android}/prebuilt/linux-x86/toolchain/${linaro_name}/
	if [ ! -d "${linaro_dir}" ]; then
		linaro_dl=~/Downloads/${linaro_file}
		if [ ! -f "${linaro_dl}" ]; then
			wget -O ${linaro_dl} ${linaro_url}
			if [ $? -ne 0 ]; then
				exit
			fi
		fi
		echo "--- Extracting"
		cd ${tmp}
		if [ -d "./android-toolchain-eabi/" ]; then
			chmod 777 ./android-toolchain-eabi/
			rm -R ./android-toolchain-eabi/
		fi
		tar -jxf ${linaro_dl}
		mkdir ${linaro_dir}
		echo "--- Installing"
		cp -R ./android-toolchain-eabi/* ${linaro_dir}
		if [ $? -ne 0 ]; then
			exit
		fi
	fi
fi

#Prebuilts
if [ "${pdroid}" = "Y" ]; then
	do_append "curl -L -o ${android}/vendor/cm/proprietary/PDroid2.0.apk -O -L https://github.com/CollegeDev/PDroid2.0_Manager_Compiled/raw/jellybean-devel/PDroid2.0.apk" ${android}/vendor/cm/get-prebuilts
	do_append "PRODUCT_COPY_FILES += vendor/cm/proprietary/PDroid2.0.apk:system/app/PDroid2.0.apk" ${android}/vendor/cm/config/common.mk
fi

if [ "${updates}" = "Y" ]; then
	do_append "curl -L -o ${android}/vendor/cm/proprietary/GooManager.apk -O -L https://github.com/solarnz/GooManager_prebuilt/blob/master/GooManager.apk?raw=true" ${android}/vendor/cm/get-prebuilts
	do_append "PRODUCT_COPY_FILES += vendor/cm/proprietary/GooManager.apk:system/app/GooManager.apk" ${android}/vendor/cm/config/common.mk
fi

${android}/vendor/cm/get-prebuilts
if [ $? -ne 0 ]; then
	exit
fi

#--- merge requests ---

echo "*** Merge requests ***"
. ${patches}/merge_requests.sh

#--- kernel ---

#Linaro
if [ "${kernel_linaro}" = "Y" ]; then
	echo "*** Kernel Linaro toolchain"
	for device in ${devices}; do
		do_replace "arm-eabi-4.4.3" "${linaro_name}" ${android}/device/semc/${device}/BoardConfig.mk
	done
fi

#Modifications
if [ "${kernel_mods}" = "Y" ]; then
	echo "*** Kernel ***"
	cd ${android}/kernel/semc/msm7x30/

	#compat-wireless
	if [ "${kernel_ti_cw}" = "Y" ]; then
		echo "--- TI compat-wireless"
		git remote add wl https://github.com/nobodyAtall/msm7x30-3.4.x-nAa.git
		git fetch wl
		git revert --no-commit 006d345736dc0ea07c978d109a3ba33b980ffbfb #wl12xx: Move firmware location to system
		git cherry-pick --no-commit 3441d2d617b734545a1a830398f6dee011d9453b #Remove compat-drivers
		git cherry-pick --no-commit 435d60ac34cdc6b54a37fb2a7ab29b970f0ee642 #Inline building for compat-wireless
		git cherry-pick --no-commit 7d4cc4f3cb7842fcc9948d7e6829c202884bcd77 #wl12xx: update header file
		git cherry-pick --no-commit 3c93109c08c4355f32d0b67c4ccc36ab4fc288a0 #wl12xx and compat-wireless ol_R5.SP5.01 release
		for device in ${devices}; do
			if [ -f ${android}/out/target/product/${device} ]; then
				mkdir -p ${android}/out/target/product/${device}/root/firmware
				do_copy ${patches}/wl127x-fw-4-sr.bin.6.3.10.0.136 ${android}/out/target/product/${device}/root/firmware/wl127x-fw-4-sr.bin
			fi
		done
	else
		do_patch kernel_wl12xx_fw.patch
		if [ "${kernel_wl12xx_bp}" = "Y" ]; then
			echo "--- 3.10 compat-wireless"
			do_patch kernel_wl12xx_backport-3.10.patch
		fi
		#wl127x firmware
		#wl127xfw=${android}/vendor/semc/mogami-common/proprietary/etc/firmware/ti-connectivity/wl127x-fw-5-sr.bin
		#do_copy ${patches}/wl127x-fw-4-sr.bin.6.3.10.0.136 ${wl127xfw}
	fi

	#Linaro
	if [ "${kernel_linaro}" = "Y" ]; then
		echo "--- Linaro"
		do_patch kernel_fixes.patch
		do_patch kernel_linaro.patch
	fi

	#Underclock
	if [ "${kernel_clock}" = "Y" ]; then
		echo "--- Clock"
		do_patch kernel_clock.patch
	fi

	#Xtended
	if [ "${kernel_xtended}" = "Y" ]; then
		echo "--- Xtended permissions"
		do_patch kernel_smartass_perm.patch
		do_patch kernel_autogroup_perm.patch
	fi

	#HDMI
	if [ "${kernel_hdmi}" = "Y" ]; then
		echo "--- HDMI"
		do_patch kernel_hdmi_dependencies.patch
		for device in ${hdmi}; do
			if [ -f arch/arm/configs/nAa_${device}_defconfig ]; then
				echo "--- HDMI ${device}"
				do_replace "# CONFIG_FB_MSM_DTV is not set" "CONFIG_FB_MSM_DTV=y" arch/arm/configs/nAa_${device}_defconfig
				do_replace "# CONFIG_FB_MSM_EXT_INTERFACE_COMMON is not set" "CONFIG_FB_MSM_EXT_INTERFACE_COMMON=y" arch/arm/configs/nAa_${device}_defconfig
				do_replace "# CONFIG_FB_MSM_HDMI_COMMON is not set" "CONFIG_FB_MSM_EXT_INTERFACE_COMMON=y" arch/arm/configs/nAa_${device}_defconfig
				do_replace "# CONFIG_FB_MSM_HDMI_SII9024A_PANEL is not set" "CONFIG_FB_MSM_HDMI_SII9024A_PANEL=y" arch/arm/configs/nAa_${device}_defconfig
				do_append "CONFIG_UIO=y" arch/arm/configs/nAa_${device}_defconfig
				do_append "CONFIG_UIO_PDRV_GENIRQ=y" arch/arm/configs/nAa_${device}_defconfig
			fi
		done
	fi

	#Config
	for device in ${devices}; do
		if [ -f arch/arm/configs/nAa_${device}_defconfig ]; then
			echo "--- Config ${device}"

			if [ "${kernel_ti_cw}" = "Y" ]; then
				do_append "CONFIG_WL12XX_MENU=m" arch/arm/configs/nAa_${device}_defconfig
				do_append "CONFIG_WL12XX_SDIO=m" arch/arm/configs/nAa_${device}_defconfig
				do_append "CONFIG_WL12XX_PLATFORM_DATA=y" arch/arm/configs/nAa_${device}_defconfig
				do_append "CONFIG_COMPAT_MAC80211_RC_DEFAULT=\"minstrel_ht\"" arch/arm/configs/nAa_${device}_defconfig
			fi

			#Xtended
			do_replace "CONFIG_LOCALVERSION=\"-nAa" "CONFIG_LOCALVERSION=\"-nAa-Xtd" arch/arm/configs/nAa_${device}_defconfig

			#autogroup
			if [ "${kernel_autogroup}" = "Y" ]; then
				do_replace "# CONFIG_SCHED_AUTOGROUP is not set" "CONFIG_SCHED_AUTOGROUP=y" arch/arm/configs/nAa_${device}_defconfig
			fi

			#cleancache
			if [ "${kernel_cleancache}" = "Y" ]; then
				do_replace "# CONFIG_CLEANCACHE is not set" "CONFIG_CLEANCACHE=y" arch/arm/configs/nAa_${device}_defconfig
			fi

			#OTG
			if [ "${kernel_otg}" = "Y" ]; then
				do_replace "# CONFIG_USB_OTG is not set" "CONFIG_USB_OTG=y" arch/arm/configs/nAa_${device}_defconfig
				do_replace "# CONFIG_USB_OTG_WHITELIST is not set" "CONFIG_USB_OTG_WHITELIST=y" arch/arm/configs/nAa_${device}_defconfig
			fi

			#USB tether
			if [ "${kernel_usb_tether}" = "Y" ]; then
				do_replace "# CONFIG_MII is not set" "CONFIG_MII=y" arch/arm/configs/nAa_${device}_defconfig
				do_replace "# CONFIG_USB_USBNET is not set" "CONFIG_USB_USBNET=y" arch/arm/configs/nAa_${device}_defconfig
				do_append "CONFIG_USB_NET_CDCETHER=y" arch/arm/configs/nAa_${device}_defconfig
				do_append "CONFIG_USB_NET_RNDIS_HOST=y" arch/arm/configs/nAa_${device}_defconfig
			fi

			#Linaro
			if [ "${kernel_linaro}" = "Y" ]; then
				do_replace "CONFIG_ARM_UNWIND=y" "# CONFIG_ARM_UNWIND is not set" arch/arm/configs/nAa_${device}_defconfig
			fi
		else
			echo "--- No kernel config for ${device}"
		fi
	done
fi

#--- Recovery ---

#pincode
if [ "${pin}" = "Y" ]; then
	echo "*** Pincode"
	cd ${android}/bootable/recovery
	do_patch recovery_check_pin.patch
	cd ${android}/device/semc/msm7x30-common
	do_patch msm7x30_check_pin.patch
	cd ${android}/device/semc/mogami-common
	do_patch mogami_check_pin.patch
	for device in ${devices}; do
		initrc=${android}/device/semc/${device}/recovery/init.rc
		do_replace "    restart adbd" "    #restart adbd" ${initrc}
	done
fi

#--- Device ---

#Boot logo
if [ "${bootlogo}" = "Y" ]; then
	echo "*** Boot logo ***"
	gcc -O2 -Wall -Wno-unused-parameter -Wno-unused-result -o ${tmp}/to565 ${android}/build/tools/rgb2565/to565.c

	if [ ! -f ${tmp}/logo_H_new.raw ]; then
		convert -depth 8 ${patches}/bootlogo/${bootlogoh} -fill grey -gravity south -draw "text 0,10 '`date -R`'" rgb:${tmp}/logo_H_new.raw
		if [ $? -ne 0 ]; then
			echo "imagemagick not installed?"
			exit
		fi
	fi
	${tmp}/to565 -rle <${tmp}/logo_H_new.raw >${android}/device/semc/msm7x30-common/bootlogo/480x854.rle

	if [ ! -f ${tmp}/logo_M_new.raw ]; then
		convert -depth 8 ${patches}/bootlogo/${bootlogom} -fill grey -gravity south -draw "text 0,10 '`date -R`'" rgb:${tmp}/logo_M_new.raw
		if [ $? -ne 0 ]; then
			echo "imagemagick not installed?"
			exit
		fi
	fi
	${tmp}/to565 -rle <${tmp}/logo_M_new.raw >${android}/device/semc/msm7x30-common/bootlogo/320x480.rle
fi

#goo.im
if [ "${updates}" = "Y" ]; then
	echo "*** goo.im ***"
	do_append "PRODUCT_PROPERTY_OVERRIDES += \\" ${android}/device/semc/msm7x30-common/msm7x30.mk
	do_append "    ro.goo.developerid=M66B \\" ${android}/device/semc/msm7x30-common/msm7x30.mk
	do_append "    ro.goo.rom=Xtd \\" ${android}/device/semc/msm7x30-common/msm7x30.mk
	do_append "    ro.goo.version=\$(shell date +%s)" ${android}/device/semc/msm7x30-common/msm7x30.mk
fi

#--- ROM ---

#MMS fix
if [ "${mms_fix}" = "Y" ]; then
	echo "*** MMS fix ***"
	cd ${android}/packages/apps/Mms
	do_patch mms_cursor.patch
fi

#PDroid
if [ "${pdroid}" = "Y" ]; then
	echo "*** PDroid 1.57 ***"

	cd ${android}
	pdroidurl=https://raw.github.com/CollegeDev/PDroid2.0_Framework_Patches/cm10.1
	wget -O - ${pdroidurl}/CM10.1_Mms.patch | patch -p1
	if [ $? -ne 0 ]; then
		exit
	fi
	wget -O - ${pdroidurl}/CM10.1_PDAgent.patch | patch -p1
	if [ $? -ne 0 ]; then
		exit
	fi
	wget -O - ${pdroidurl}/CM10.1_build.patch | patch -p1
	if [ $? -ne 0 ]; then
		exit
	fi
	wget -O - ${pdroidurl}/CM10.1_framework.patch | patch -p1
	if [ $? -ne 0 ]; then
		exit
	fi
	wget -O - ${pdroidurl}/CM10.1_libcore.patch | patch -p1
	if [ $? -ne 0 ]; then
		exit
	fi

	do_copy ${patches}/PDroid.jpeg ${android}/privacy
	do_append "PRODUCT_COPY_FILES += privacy/PDroid.jpeg:system/media/PDroid.jpeg" ${android}/vendor/cm/config/common.mk
fi

#terminfo
if [ "${terminfo}" = "Y" ]; then
	echo "*** Terminfo ***"
	terminfo_dl=~/Downloads/termtypes.master.gz
	if [ ! -f "${terminfo_dl}" ]; then
		wget -O ${terminfo_dl} http://catb.org/terminfo/termtypes.master.gz
		if [ $? -ne 0 ]; then
			exit
		fi
	fi

	echo "--- Extracting"
	gunzip <${terminfo_dl} >${tmp}/termtypes.master
	echo "--- Converting"
	tic -o ${android}/vendor/cm/prebuilt/common/etc/terminfo/ ${tmp}/termtypes.master
	if [ $? -ne 0 ]; then
		exit
	fi
	echo "--- Installing"
	do_append "PRODUCT_COPY_FILES += \\" ${android}/vendor/cm/config/common.mk
	cd ${android}/vendor/cm/prebuilt/common
	find etc/terminfo -type f -exec echo "    vendor/cm/prebuilt/common/{}:system/{} \\" >>${android}/vendor/cm/config/common.mk \;

	cd ${android}/vendor/cm/prebuilt/common/etc
	do_patch mkshrc.patch
fi

#Xtended settings
if [ "${xsettings}" = "Y" ]; then
	echo "*** Xtended settings ***"
	cd ${android}/packages/apps/Settings
	do_patch xsettings.patch
	cd ${android}/device/semc/mogami-common
	do_patch mogami_xtended.patch
fi

#ssh
if [ "${ssh}" = "Y" ]; then
	echo "*** sftp-server ***"
	cd ${android}/external/openssh
	do_patch sftp-server.patch
	#needs extra 'mmm external/openssh'
fi

#FM tools
if [ "${fmtools}" = "Y" ]; then
	echo "*** FM tools ***"
	do_append "PRODUCT_PACKAGES += kfmapp FmTxApp" ${android}/device/semc/mogami-common/mogami.mk
fi

#Wi-Fi ad-hoc
if [ "${adhoc}" = "Y" ];then
	echo "*** Wi-Fi ad-hoc ***"
	for device in ${devices}; do
		sed -i '6 i WifiAdhoc = 1' ${android}device/semc/${device}/config/tiwlan.ini
	done
fi

#Custom patches
if [ -f ~/.cm101xtended.sh ]; then
	. ~/.cm101xtended.sh
fi

#Environment
echo "*** Setup environment ***"
cd ${android}
. build/envsetup.sh

#Say whats next
echo ""
echo "*** Done ***"
echo ""
echo "brunch <device name>"
echo ""
echo "or"
echo ""
echo "lunch cm_<device name>-userdebug"
echo "make bootimage"
echo ""
