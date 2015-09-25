#!/usr/bin/bash

CMD="$1"
ARG1="$2"
CUR_DIR=${PWD}
TEMP_DIR=temp
OUT_DIR=out

CROSS_COMPILE=${CUR_DIR}/toolchain/arm-eabi-4.7/bin/arm-eabi-
export CROSS_COMPILE

# Common defines (Arch-dependent)
case `uname -s` in
    Darwin)
        txtrst='\033[0m'  # Color off
        txtred='\033[0;31m' # Red
        txtgrn='\033[0;32m' # Green
        txtylw='\033[0;33m' # Yellow
        txtblu='\033[0;34m' # Blue
        THREADS=`sysctl -an hw.logicalcpu`
        ;;
    *)
        txtrst='\e[0m'  # Color off
        txtred='\e[0;31m' # Red
        txtgrn='\e[0;32m' # Green
        txtylw='\e[0;33m' # Yellow
        txtblu='\e[0;34m' # Blue
        THREADS=`cat /proc/cpuinfo | grep processor | wc -l`
        ;;
esac

mkdir -p ${TEMP_DIR}
mkdir -p ${OUT_DIR}

build_kernel() {
    rm -f ${CUR_DIR}/kernel/arch/arm/boot/zImage

    pushd kernel
    make mrproper
    popd

    pushd kernel/drivers/vendor/hisi/build
    python obuild.py product=hi3630_udp acore-oam_ps -j${THREADS}
    popd

    pushd kernel
    make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} merge_hi3630_defconfig
    make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} -j${THREADS}
    popd

    if [ ! -e ${CUR_DIR}/kernel/arch/arm/boot/zImage ]; then
        echo -e "${txtred}Failed to build zImage!"
        echo -e "${txtrst}"
        exit 1
    fi

    cp ${CUR_DIR}/kernel/arch/arm/boot/zImage ${CUR_DIR}/${TEMP_DIR}
}

case "$CMD" in
    clean)
        echo -e "${txtylw}Cleaning ..."
        echo -e "${txtrst}"
        pushd kernel
        make mrproper
        rm -f drivers/vendor/hisi/build/delivery/hi3630_udp/log/obuild.log
        rm -f drivers/vendor/hisi/build/delivery/hi3630_udp/timestamp.log
        rm -f drivers/vendor/hisi/modem/ps/build/tl/APP_CORE/.tmp_versions/LPS.mod
        rm -rf ${TEMP_DIR}/*
        rm -rf ${OUT_DIR}/*
        popd
        echo -e "${txtgrn}Done!"
        echo -e "${txtrst}"
        ;;
    kernel)
        echo -e "${txtylw}Building zImage..."
        echo -e "${txtrst}"
        build_kernel

        echo -e "${txtgrn}Done! -> ${TEMP_DIR}/zImage"
        echo -e "${txtrst}"
        ;;
    bootimage)
        echo -e "${txtylw}Creating bootimage..."
        echo -e "${txtrst}"
        rm -f ${TEMP_DIR}/ramdisk.cpio.gz
        rm -f ${OUT_DIR}/boot.img

        if [ ! -e ${CUR_DIR}/${TEMP_DIR}/zImage ]; then
            echo -e "${txtylw}No zImage found. Building ..."
            echo -e "${txtrst}"
            build_kernel
        else
            echo -e "${txtylw}zImage already present, not rebuilding!"
            echo -e "${txtrst}"
        fi

        case "$ARG1" in
            l02)
                echo -e "${txtylw}Target: l02"
                echo -e "${txtrst}"
                ram_dir="ramdisk_l02"
                ;;
            l04)
                echo -e "${txtylw}Target: l04"
                echo -e "${txtrst}"
                ram_dir="ramdisk_l04"
                ;;
            l12)
                echo -e "${txtylw}Target: l12"
                echo -e "${txtrst}"
                ram_dir="ramdisk_l12"
                ;;
            *)
                echo -e "${txtred}No target given."
                echo -e "${txtblu}Usage: ./build.sh bootimage l04"
                echo -e "${txtblu}Supported variants: l02 l04 l12"
                echo -e "${txtrst}"
                exit 1
                ;;
        esac

        if [ ! -d "${ram_dir}" ]; then
            echo -e "${txtred}Ramdisk directory ${ram_dir} doesn't exist!"
            echo -e "${txtrst}"
            exit 1
        fi

        echo -e "${txtylw}Creating ramdisk.cpio.gz ..."
        echo -e "${txtrst}"
        pushd ${ram_dir}
        mkdir -p data
        mkdir -p dev
        mkdir -p proc
        mkdir -p sys
        mkdir -p system
        find . | cpio -o -H newc | gzip > ../${TEMP_DIR}/ramdisk.cpio.gz
        popd

        echo -e "${txtylw}Creating boot.img ..."
        echo -e "${txtrst}"
        mkbootimg --kernel ${TEMP_DIR}/zImage --ramdisk ${TEMP_DIR}/ramdisk.cpio.gz --cmdline "ro.boot.hardware=hi3630 vmalloc=384M coherent_pool=512K mem=2044m@0x200000 psci=enable mmcparts=mmcblk0:p1(vrl),p2(vrl_backup),p7(modemnvm_factory),p18(splash),p22(dfx),p23(modemnvm_backup),p24(modemnvm_img),p25(modemnvm_system),p26(modem),p27(modem_dsp),p28(modem_om),p29(modemnvm_update),p31(3rdmodem),p32(3rdmodemnvm),p33(3rdmodemnvmbkp) user_debug=7 androidboot.selinux=enforcing enter_recovery=1 enter_erecovery=0" --base 0x00000000 --kernel_offset 0x00608000 --ramdisk_offset 0x00300000 --second_offset 0x01500000 --tags_offset 0x00200000 -o ${OUT_DIR}/boot.img
        
        echo -e "${txtgrn}Done! -> ${OUT_DIR}/boot.img"
        echo -e "${txtrst}"
        ;;
    unpack)
        if [ -z "${ARG1}" ]; then
            echo -e "${txtred}No image given. "
            echo -e "${txtblu}Usage: ./build.sh unpack boot.img"
            echo -e "${txtrst}"
            exit 1
        fi

        if [ ! -e ${CUR_DIR}/${ARG1} ]; then
            echo -e "${txtred}File ${ARG1} doesn't exist!"
            echo -e "${txtrst}"
            exit 1
        fi

        echo -e "${txtylw}Unpacking ${ARG1} ..."
        echo -e "${txtrst}"
        unpackbootimg-h60 -i ${ARG1} -o ${OUT_DIR} -p 2048
        echo -e "${txtgrn}Done! -> ${OUT_DIR}"
        echo -e "${txtrst}"
        ;;
    *)
        echo -e "${txtblu}Usage: ./build.sh clean            ->    runs mrproper"
        echo -e "${txtblu}       ./build.sh kernel           ->    builds zImage"
        echo -e "${txtblu}       ./build.sh bootimage l04    ->    creates boot.img for l04. Supported variants: l04"
        echo -e "${txtblu}       ./build.sh unpack boot.img  ->    unpacks boot/recovery images"
        echo -e "${txtrst}"
        ;;
esac

exit 0
