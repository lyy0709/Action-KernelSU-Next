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
echo "==> [4/9] 检查并同步源码"

# 仅在首次运行时初始化仓库
if [ ! -d "kernel_workspace" ]; then
  echo "--> 首次运行，正在初始化仓库..."
  mkdir kernel_workspace
  cd kernel_workspace

  # 初始化 repo
  repo init \
      -u "https://github.com/OnePlusOSS/kernel_manifest.git" \
      -b "refs/heads/oneplus/${CPU}" \
      -m "${FEIL}.xml" \
      --depth=1

  # 同步代码（约5GB）
  repo sync
  cd ..
else
  echo "--> 检测到已有源码目录，跳过同步步骤..."
fi

# 公共清理操作（每次运行都执行）
echo "--> 清理旧编译配置..."
cd kernel_workspace
rm -f common/android/abi_gki_protected_exports_* 2>/dev/null
rm -f msm-kernel/android/abi_gki_protected_exports_* 2>/dev/null
sed -i 's/ -dirty//g' common/scripts/setlocalversion 2>/dev/null || true
sed -i 's/ -dirty//g' msm-kernel/scripts/setlocalversion 2>/dev/null || true
cd ..

#---------------------------#
#     5. 设置 KernelSU Next #
#---------------------------#
echo
echo "==> [5/9] 设置 KernelSU-Next"

# 清理旧版本KSU
rm -rf kernel_workspace/kernel_platform/KernelSU-Next

cd kernel_workspace/kernel_platform
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next

cd KernelSU-Next
KSU_VERSION=$(expr $(git rev-list --count HEAD) + 10200)
echo "KSU_VERSION: $KSU_VERSION"
sed -i "s/DKSU_VERSION=16/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
cd ..

#---------------------------#
#     6. 设置 susfs         #
#---------------------------#
echo
echo "==> [6/9] 设置 susfs 及相关补丁"

# 进入内核平台目录
cd kernel_workspace/kernel_platform

# 清理旧配置
rm -rf ../../susfs4ksu ../../kernel_patches

# 克隆最新配置
git clone "https://gitlab.com/simonpunk/susfs4ksu.git" \
    -b "gki-${ANDROID_VERSION}-${KERNEL_VERSION}" \
    ../../susfs4ksu
git clone https://github.com/TheWildJames/kernel_patches.git ../../kernel_patches

# 应用补丁
cp ../../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch KernelSU-Next/
cp ../../susfs4ksu/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch common/
cp ../../susfs4ksu/kernel_patches/fs/* common/fs/
cp ../../susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo "--> 应用内核补丁..."
cd KernelSU-Next
patch -p1 --forward < 10_enable_susfs_for_ksu.patch || true
cd ../common
patch -p1 < 50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch || true
cp ../../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch || true

#---------------------------#
#     7. 编译内核           #
#---------------------------#
echo
echo "==> [7/9] 开始编译内核"

# 关键修复步骤：进入 kernel_platform 目录执行编译
cd /home/kernelsu/Action-KernelSU-Next/kernel_workspace/kernel_platform

# 清理旧编译结果
rm -rf out

# 修复依赖文件路径问题
if [ ! -f "vendor/oplus/kernel/prebuilt/vendorsetup.sh" ]; then
  mkdir -p vendor/oplus/kernel/prebuilt
  curl -s "https://raw.githubusercontent.com/OnePlusOSS/vendor_oneplus_prebuilt/main/vendorsetup.sh" \
       -o vendor/oplus/kernel/prebuilt/vendorsetup.sh
fi

if [ ! -f "build/android/prepare_vendor.sh" ]; then
  mkdir -p build/android
  curl -s "https://raw.githubusercontent.com/OnePlusOSS/kernel_build_scripts/main/prepare_vendor.sh" \
       -o build/android/prepare_vendor.sh
  chmod +x build/android/prepare_vendor.sh
fi

# 修复时间记录函数（原脚本中的未定义变量）
build_start_time() { date +%s; }
build_end_time() { date +%s; }

# 执行编译命令
./oplus/build/oplus_build_kernel.sh "$CPUD" gki

#---------------------------#
#     8. 打包 AnyKernel3    #
#---------------------------#
echo
echo "==> [8/9] 打包 AnyKernel3"

# 清理旧打包文件
rm -rf ../AnyKernel3
git clone https://github.com/Kernel-SU/AnyKernel3 ../AnyKernel3 --depth=1
rm -rf ../AnyKernel3/.git

# 生成最终包
cp out/msm-kernel-"${CPUD}"-gki/dist/Image ../AnyKernel3/
cd ../AnyKernel3
zip -r9 "../AnyKernel3_KernelSU_Next_${KSU_VERSION}_${FEIL}.zip" ./*

#---------------------------#
#     9. 收尾/结果查看      #
#---------------------------#
echo
echo "==> [9/9] 编译完成，结果存放在以下位置："
echo "    1) 内核 zImage/Image: kernel_workspace/kernel_platform/out/msm-kernel-${CPUD}-gki/dist/Image"
echo "    2) 可直接刷入设备的刷机包: $(pwd)/../AnyKernel3_KernelSU_Next_${KSU_VERSION}_${FEIL}.zip"
echo
echo "脚本执行完毕。"
