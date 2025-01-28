#!/bin/bash

# 配置参数（可按需修改）
CPU="sm8550"
FEIL="oneplus_11_v"
CPUD="kalama"
ANDROID_VERSION="android13"
KERNEL_VERSION="5.15"

# 初始化环境
set -e
sudo apt update
sudo apt upgrade -y
sudo apt install -y python3 git curl coreutils

# 配置Git
git config --global user.name "build"
git config --global user.email "2722707908@qq.com"

# 安装repo工具
sudo apt-get install repo

# 清理旧构建
rm -rf kernel_workspace

# 初始化代码仓库
mkdir kernel_workspace && cd kernel_workspace
repo init -u https://github.com/OnePlusOSS/kernel_manifest.git \
    -b refs/heads/oneplus/$CPU \
    -m $FEIL.xml \
    --depth=1

repo sync

# 预处理代码
rm kernel_platform/common/android/abi_gki_protected_exports_* || echo "No protected exports!"
rm kernel_platform/msm-kernel/android/abi_gki_protected_exports_* || echo "No protected exports!"
sed -i 's/ -dirty//g' kernel_platform/common/scripts/setlocalversion
sed -i 's/ -dirty//g' kernel_platform/msm-kernel/scripts/setlocalversion

# 安装KernelSU Next
cd kernel_platform
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next

cd KernelSU-Next
KSU_VERSION=$(expr $(git rev-list --count HEAD) "+" 10200)
sed -i "s/DKSU_VERSION=16/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
cd ..

# 安装susfs
cd ..
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-$ANDROID_VERSION-$KERNEL_VERSION
git clone https://github.com/TheWildJames/kernel_patches.git

# 应用补丁
cp susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch kernel_platform/KernelSU-Next/
cp susfs4ksu/kernel_patches/50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch kernel_platform/common/
cp -r susfs4ksu/kernel_patches/fs/* kernel_platform/common/fs/
cp -r susfs4ksu/kernel_patches/include/linux/* kernel_platform/common/include/linux/

cd kernel_platform/KernelSU-Next
patch -p1 --forward < 10_enable_susfs_for_ksu.patch || true

cd ../common
patch -p1 < 50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch || true
cp ../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch
git add -A && git commit -a -m "BUILD Kernel"

cd ..
cd msm-kernel && git add -A && git commit -a -m "BUILD Kernel"
cd ..

# 应用额外补丁
cp ../kernel_patches/apk_sign.c_fix.patch ./
patch -p1 -F 3 < apk_sign.c_fix.patch

cp ../kernel_patches/core_hook.c_fix.patch ./
patch -p1 --fuzz=3 < core_hook.c_fix.patch

cp ../kernel_patches/selinux.c_fix.patch ./
patch -p1 -F 3 < selinux.c_fix.patch

# 构建内核
cd ..
./kernel_platform/oplus/build/oplus_build_kernel.sh $CPUD gki

# 准备AnyKernel3
git clone https://github.com/Kernel-SU/AnyKernel3 --depth=1
rm -rf AnyKernel3/.git
cp kernel_platform/out/msm-kernel-$CPUD-gki/dist/Image AnyKernel3/

# 输出结果
echo "=============================================="
echo "构建完成！结果保存在："
echo "内核镜像: $(pwd)/kernel_platform/out/msm-kernel-$CPUD-gki/dist/Image"
echo "AnyKernel3包: $(pwd)/AnyKernel3"
echo "KernelSU版本: $KSU_VERSION"
