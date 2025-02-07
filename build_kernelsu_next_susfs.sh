#!/usr/bin/env bash
#
# 本脚本用于在本地 Ubuntu 系统上进行内核编译，逻辑参考自给定的 GitHub Actions workflow。
#
# 传参说明：
#   1) CPU             - 对应在上游Manifest中的分支 (如 sm8550)
#   2) FEIL            - 对应的 xml 配置文件名称 (如 oneplus_11_v)
#   3) CPUD            - 处理器代号 (如 kalama)
#   4) ANDROID_VERSION - 内核安卓版本 (如 android13)
#   5) KERNEL_VERSION  - 内核版本 (如 5.15)
#
# 例如：./build_local.sh sm8550 oneplus_11_v kalama android13 5.15
#

# 如果脚本没有传参，那么在这里定义默认值
CPU_DEFAULT="sm8550"
FEIL_DEFAULT="oneplus_11_v"
CPUD_DEFAULT="kalama"
ANDROID_VERSION_DEFAULT="android13"
KERNEL_VERSION_DEFAULT="5.15"

# 读取命令行参数或使用默认值
CPU="${1:-$CPU_DEFAULT}"
FEIL="${2:-$FEIL_DEFAULT}"
CPUD="${3:-$CPUD_DEFAULT}"
ANDROID_VERSION="${4:-$ANDROID_VERSION_DEFAULT}"
KERNEL_VERSION="${5:-$KERNEL_VERSION_DEFAULT}"

echo "==> 编译参数:"
echo "    CPU: $CPU"
echo "    FEIL: $FEIL"
echo "    CPUD: $CPUD"
echo "    ANDROID_VERSION: $ANDROID_VERSION"
echo "    KERNEL_VERSION: $KERNEL_VERSION"
echo

#---------------------------#
#     1. 设置环境/依赖      #
#---------------------------#

echo "==> [1/9] 安装依赖"

# 更新系统并安装所需依赖
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y python3 git curl

#---------------------------#
#     2. 配置 Git 信息      #
#---------------------------#
echo
echo "==> [2/9] 配置 Git"

git config --global user.name "build"
git config --global user.email "2722707908@qq.com"

#---------------------------#
#     3. 安装 repo 工具     #
#---------------------------#
echo
echo "==> [3/9] 安装 repo 工具"

if ! command -v repo &> /dev/null
then
  curl -s https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
  chmod a+x /tmp/repo
  sudo mv /tmp/repo /usr/local/bin/repo
else
  echo "repo 已安装，跳过..."
fi

#---------------------------#
#     4. 初始化 & 同步源码  #
#---------------------------#
echo
echo "==> [4/9] 初始化并同步源码"

# 若有旧的 kernel_workspace，先删除
rm -rf kernel_workspace
mkdir kernel_workspace
cd kernel_workspace

# 初始化 repo
repo init \
    -u "https://github.com/OnePlusOSS/kernel_manifest.git" \
    -b "refs/heads/oneplus/${CPU}" \
    -m "${FEIL}.xml" \
    --depth=1

# 同步
repo sync
rm kernel_platform/common/android/abi_gki_protected_exports_* || echo "No protected exports!"
rm kernel_platform/msm-kernel/android/abi_gki_protected_exports_* || echo "No protected exports!"
sed -i 's/ -dirty//g' kernel_platform/common/scripts/setlocalversion
sed -i 's/ -dirty//g' kernel_platform/msm-kernel/scripts/setlocalversion
sed -i '$s|echo "\$res"|echo "$res-Mortis"|' kernel_platform/common/scripts/setlocalversion            
sed -i '$s|echo "\$res"|echo "$res-Mortis"|' kernel_platform/msm-kernel/scripts/setlocalversion

#---------------------------#
#     5. 设置 KernelSU Next #
#---------------------------#
echo
echo "==> [5/9] 设置 KernelSU-Next"

cd kernel_platform
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next

cd KernelSU-Next

# 计算 KSU 版本（可根据实际情况自行调整计算逻辑）
KSU_VERSION=$(expr $(git rev-list --count HEAD) + 10200)
echo "KSU_VERSION: $KSU_VERSION"

# 替换 Makefile 中的 DKSU_VERSION (默认脚本中原来为 16，这里直接修改)
sed -i "s/DKSU_VERSION=16/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile

# 返回到 kernel_platform
cd ..

#---------------------------#
#     6. 设置 susfs         #
#---------------------------#
echo
echo "==> [6/9] 设置 susfs 及相关补丁"

cd ..

# 克隆 susfs4ksu
git clone "https://gitlab.com/simonpunk/susfs4ksu.git" \
    -b "gki-${ANDROID_VERSION}-${KERNEL_VERSION}" \

# 克隆其他可能需要的内核补丁
git clone https://github.com/TheWildJames/kernel_patches.git

cd kernel_platform

# 拷贝并应用补丁
cp ../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch KernelSU-Next/
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch common/
cp ../kernel_patches/KernelSU-Next-Implement-SUSFS-v1.5.5-Universal.patch KernelSU-Next/
cp ../susfs4ksu/kernel_patches/fs/* common/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo "----> 应用 KernelSU-Next-Implement-SUSFS-v1.5.5-Universal.patch"
cd KernelSU-Next
patch -p1 < KernelSU-Next-Implement-SUSFS-v1.5.5-Universal.patch || true
cd ..

echo "----> 应用 50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch"
cd common
patch -p1 < 50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch || true

# 拷贝并应用 69_hide_stuff.patch
cp ../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch || true

cp ../../kernel_patches/apk_sign.c_fix.patch ./
patch -p1 -F 3 < apk_sign.c_fix.patch || true

cp ../../kernel_patches/core_hook.c_fix.patch ./
patch -p1 -F 3 < core_hook.c_fix.patch || true

cp ../../kernel_patches/selinux.c_fix.patch ./
patch -p1 -F 3 < selinux.c_fix.patch || true

#---------------------------#
#     7. 编译内核           #
#---------------------------#
echo
echo "==> [7/9] 开始编译内核"

cd ..
# 同级目录里有 ./oplus/build/oplus_build_kernel.sh
./kernel_platform/oplus/build/oplus_build_kernel.sh "$CPUD" gki

#---------------------------#
#     8. 打包 AnyKernel3    #
#---------------------------#
echo
echo "==> [8/9] 打包 AnyKernel3"

git clone https://github.com/Kernel-SU/AnyKernel3 --depth=1
rm -rf ./AnyKernel3/.git

# 将编译生成的 Image 放入 AnyKernel3 目录
cp kernel_platform/out/msm-kernel-"${CPUD}"-gki/dist/Image ./AnyKernel3/

# 生成最终的打包文件（简单示例，可自行修改 zip 名称）
cd AnyKernel3
zip -r9 "../AnyKernel3_KernelSU_Next_${KSU_VERSION}_${FEIL}.zip" ./*
cd ..

#---------------------------#
#     9. 收尾/结果查看      #
#---------------------------#
echo
echo "==> [9/9] 编译完成，结果存放在以下位置："
echo "    1) 内核 zImage/Image: kernel_platform/out/msm-kernel-${CPUD}-gki/dist/Image"
echo "    2) 可直接刷入设备的刷机包: AnyKernel3_KernelSU_Next_${KSU_VERSION}_${FEIL}.zip"
echo
echo "脚本执行完毕。"
