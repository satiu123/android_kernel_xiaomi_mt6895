#!/usr/bin/env bash
set -euo pipefail

VARIANT="${1:-KSU-SUSFS}"
echo "=========================================="
echo " Building ESK Kernel for xaga (MT6895)"
echo " Variant: ${VARIANT}"
echo "=========================================="

export PATH=/clang/bin:$PATH
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER=satiu
export KBUILD_BUILD_HOST=archlinux

mkdir -p out dist

# 1. Setup KernelSU & SuSFS if requested
if [ "$VARIANT" = "KSU-SUSFS" ] || [ "$VARIANT" = "KSU-SUSFS-LXC" ]; then
    if [ ! -d "drivers/kernelsu" ]; then
        echo "== Setting up BakaSU =="
        git clone https://github.com/Baka-SU/BakaSU.git drivers/kernelsu || \
        git clone https://github.com/ENGRahsepar/BakaSU.git drivers/kernelsu
    fi

    if [ ! -d "fs/susfs" ]; then
        echo "== Setting up SuSFS =="
        git clone https://github.com/ENGRahsepar/susfs4ksu.git -b gki-android12-5.10 /tmp/susfs || \
        git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android12-5.10 /tmp/susfs
        cp -r /tmp/susfs/kernel_patches/fs/* fs/ 2>/dev/null || true
        cp -r /tmp/susfs/kernel_patches/include/* include/ 2>/dev/null || true
        patch -p1 --fuzz=3 < /tmp/susfs/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch 2>/dev/null || true
    fi
fi

# 2. Merge Defconfig into out/.config
echo "== Merging Defconfigs =="
./scripts/kconfig/merge_config.sh -m -r -O out \
    arch/arm64/configs/gki_defconfig \
    arch/arm64/configs/vendor/xiaomi_mt6895.config \
    arch/arm64/configs/vendor/xaga.config

if [ "$VARIANT" = "KSU-SUSFS" ] || [ "$VARIANT" = "KSU-SUSFS-LXC" ]; then
    cat << 'EOF' >> out/.config
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
EOF
fi

if [ "$VARIANT" = "KSU-SUSFS-LXC" ]; then
    cat << 'EOF' >> out/.config
CONFIG_NAMESPACES=y
CONFIG_NET_NS=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_UTS_NS=y
CONFIG_USER_NS=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_SCHED=y
CONFIG_CPUSETS=y
CONFIG_MEMCG=y
CONFIG_POSIX_MQUEUE=y
CONFIG_SYSVIPC=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
fi

make O=out ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    olddefconfig

# 3. Compile Kernel & Modules
echo "== Compiling Kernel & Modules =="
make -j"$(nproc)" O=out ARCH=arm64 CC=clang HOSTCC=clang \
    LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    KBUILD_MODPOST_WARN=1 \
    KCFLAGS="-Wno-error=implicit-function-declaration -Wno-error=macro-redefined -Wno-error=incompatible-function-pointer-types -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=declaration-after-statement" \
    Image modules vendor/mediatek/mt6895.dtb vendor/mediatek/xaga.dtbo

# 4. Package Modules
echo "== Packaging Modules =="
make O=out ARCH=arm64 INSTALL_MOD_PATH=out/modules_install DEPMOD=true modules_install
mkdir -p dist/modules_pack/vendor_dlkm/lib/modules
find out/modules_install/lib/modules/ -name "*.ko" -exec cp -f {} dist/modules_pack/vendor_dlkm/lib/modules/ \;

if [ -d "mali-r54/blobs/vendor_dlkm" ]; then
    echo "Overlaying Mali r54 and updated GED/GPUEB modules..."
    cp -vf mali-r54/blobs/vendor_dlkm/*.ko dist/modules_pack/vendor_dlkm/lib/modules/
fi

llvm-strip --strip-debug dist/modules_pack/vendor_dlkm/lib/modules/*.ko || true
tar -cJf dist/module.tar.xz -C dist/modules_pack vendor_dlkm
echo "== module.tar.xz created =="
ls -lh dist/module.tar.xz

# 5. Build AnyKernel3 Flashable Zip
echo "== Building AnyKernel3 Zip =="
if [ ! -d "anykernel3" ]; then
    git clone https://github.com/ESK-Project/AnyKernel3.git -b xaga anykernel3
fi

zstd -19 out/arch/arm64/boot/Image -o anykernel3/Image.zst --force
sha256sum anykernel3/Image.zst | cut -d' ' -f1 > anykernel3/Image.zst.sha256
cp -f dist/module.tar.xz anykernel3/module.tar.xz

if [ -f "out/arch/arm64/boot/dts/vendor/mediatek/mt6895.dtb" ]; then
    cp -f out/arch/arm64/boot/dts/vendor/mediatek/mt6895.dtb anykernel3/dtb || true
fi
if [ -f "out/arch/arm64/boot/dts/vendor/mediatek/xaga.dtbo" ]; then
    cp -f out/arch/arm64/boot/dts/vendor/mediatek/xaga.dtbo anykernel3/dtbo.img || true
fi

SHA12=$(git rev-parse --short=12 HEAD || echo "local")
ZIP_NAME="ESK-Reborn-5.10.272-${VARIANT}-${SHA12}-AnyKernel3.zip"
(cd anykernel3 && zip -r9 "../dist/${ZIP_NAME}" * -x .git README.md *placeholder)

echo "=========================================="
echo " BUILD SUCCESSFUL!"
echo " Flashable Zip: dist/${ZIP_NAME}"
echo "=========================================="
ls -lh "dist/${ZIP_NAME}"
