#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make distclean
    #make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- clean
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- mrproper
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
    echo building the kernel ...
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu-
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/
echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir -p ${OUTDIR}/rootfs && cd ${OUTDIR}/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
else
    cd busybox
fi

#make distclean
make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu-
make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- install
# TODO: Make and install busybox
cd ${OUTDIR}/rootfs
pwd

echo "Library dependencies"
sysroot=$(${CROSS_COMPILE}gcc --print-sysroot)
prog_interpreter=$(${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter" | tr -d "[]")
delem=":"
path_to_interpreter=${prog_interpreter#*$delem}
interpreter=$(basename $path_to_interpreter | tr -d " ")
path_prefix_interpret=${prog_interpreter%%$interpreter*}
path_prefix_interpret=$(echo ${path_prefix_interpret#*$delem} | tr -d " ")
echo path_to_interpreter is $path_to_interpreter
echo interpreter is $interpreter
echo path_prefix_interpret is $path_prefix_interpret
final_path=${OUTDIR}/rootfs/$path_prefix_interpret
echo $final_path
sudo cp $(find $sysroot -name $interpreter) $final_path
ls $final_path

#basename $prog_interpreter
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library" | tr -d "[]" >tmp.txt
int=0
echo $sysroot

while read -r line
do
shared=$(echo ${line#*$delem} | tr -d " ")
path_to_shared=$(find $sysroot -name $shared)
realtive=${path_to_shared#*$sysroot}
tmp_path=${realtive%%$shared*}
final_path=${OUTDIR}/rootfs/$tmp_path
echo "copy from $path_to_shared  to $final_path"
sudo cp $path_to_shared $final_path
done < tmp.txt

rm tmp.txt
ls $final_path
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1
sudo chown -R root:root *
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
cd ${OUTDIR}
gzip -f initramfs.cpio
# TODO: Add library dependencies to rootfs

# TODO: Make device nodes

# TODO: Clean and build the writer utility

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs

# TODO: Chown the root directory

# TODO: Create initramfs.cpio.gz
