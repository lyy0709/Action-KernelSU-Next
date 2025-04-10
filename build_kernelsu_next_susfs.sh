#!/usr/bin/env bash
#
# 本脚本用于在本地 Ubuntu 系统上进行内核编译，逻辑参考自给定的 GitHub Actions workflow。
# 修复了与 GitHub Actions 工作流的差异，解决可能导致编译错误的问题。
# 来源于lyy0709
# 传参说明：
#   1) CPU             - 对应在上游Manifest中的分支 (如 sm8550)
#   2) FEIL            - 对应的 xml 配置文件名称 (如 oneplus_11_v)
#   3) CPUD            - 处理器代号 (如 kalama)
#   4) ANDROID_VERSION - 内核安卓版本 (如 android13)
#   5) KERNEL_VERSION  - 内核版本 (如 5.15)
#   6) BUILD_METHOD    - 编译方式 (如 gki)
#
# 例如：./build_local_fixed.sh sm8550 oneplus_11_v kalama android13 5.15 gki
#

# 如果脚本没有传参，那么在这里定义默认值
CPU_DEFAULT="sm8550"
FEIL_DEFAULT="oneplus_11_v"
CPUD_DEFAULT="kalama"
ANDROID_VERSION_DEFAULT="android13"
KERNEL_VERSION_DEFAULT="5.15"
BUILD_METHOD_DEFAULT="gki"

# 读取命令行参数或使用默认值
CPU="${1:-$CPU_DEFAULT}"
FEIL="${2:-$FEIL_DEFAULT}"
CPUD="${3:-$CPUD_DEFAULT}"
ANDROID_VERSION="${4:-$ANDROID_VERSION_DEFAULT}"
KERNEL_VERSION="${5:-$KERNEL_VERSION_DEFAULT}"
BUILD_METHOD="${6:-$BUILD_METHOD_DEFAULT}"

echo "==> 编译参数:"
echo "    CPU: $CPU"
echo "    FEIL: $FEIL"
echo "    CPUD: $CPUD"
echo "    ANDROID_VERSION: $ANDROID_VERSION"
echo "    KERNEL_VERSION: $KERNEL_VERSION"
echo "    BUILD_METHOD: $BUILD_METHOD"
echo

#---------------------------#
#     1. 设置环境/依赖      #
#---------------------------#

echo "==> [1/9] 安装依赖"

# 更新系统并安装所需依赖（添加了缺失的依赖）
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y python3 git curl patch bc bison flex libssl-dev

#---------------------------#
#     2. 配置 Git 信息      #
#---------------------------#
echo
echo "==> [2/9] 配置 Git"

git config --global user.name "build"
git config --global user.email "2722707908@qq.com"  # 使用与 GitHub Actions 相同的邮箱

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
# 删除 abi_gki_protected_exports_*
rm kernel_platform/common/android/abi_gki_protected_exports_* 2>/dev/null || echo "No protected exports in common."
rm kernel_platform/msm-kernel/android/abi_gki_protected_exports_* 2>/dev/null || echo "No protected exports in msm-kernel."

# 去掉 -dirty
cd kernel_platform
sed -i 's/ -dirty//g' common/scripts/setlocalversion 2>/dev/null || true
sed -i 's/ -dirty//g' msm-kernel/scripts/setlocalversion 2>/dev/null || true
sed -i 's/ -dirty//g' external/dtc/scripts/setlocalversion 2>/dev/null || true
# 添加与 GitHub Actions 相同的额外处理
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' common/scripts/setlocalversion 2>/dev/null || true
cd ..

#---------------------------#
#     5. 设置 KernelSU Next #
#---------------------------#
echo
echo "==> [5/9] 设置 KernelSU-Next"

cd kernel_platform
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next

cd KernelSU-Next

# 计算 KSU 版本
KSU_VERSION=$(expr $(git rev-list --count HEAD) + 10200)
echo "KSU_VERSION: $KSU_VERSION"

# 使用硬编码的默认值进行替换
sed -i "s/DKSU_VERSION=11998/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile

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
    -b "gki-${ANDROID_VERSION}-${KERNEL_VERSION}"

# 克隆其他可能需要的内核补丁（使用与 GitHub Actions 相同的仓库）
git clone https://github.com/WildPlusKernel/kernel_patches.git

cd kernel_platform

# 拷贝并应用补丁
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch ./common/
cp ../kernel_patches/next/0001-kernel-patch-susfs-v1.5.5-to-KernelSU-Next-v1.0.5.patch ./KernelSU-Next/
cp ../kernel_patches/next/syscall_hooks.patch ./common/
cp ../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

echo "----> 应用 0001-kernel-patch-susfs-v1.5.5-to-KernelSU-Next-v1.0.5.patch"
cd ./KernelSU-Next
# 移除 --forward 参数，与 GitHub Actions 保持一致
patch -p1 < 0001-kernel-patch-susfs-v1.5.5-to-KernelSU-Next-v1.0.5.patch || true

echo "----> 应用 50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch"
cd ../common
patch -p1 < 50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch || true

# 拷贝并应用 69_hide_stuff.patch
cp ../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch || true
patch -p1 -F 3 < syscall_hooks.patch || true

#---------------------------#
#     7. 应用配置           #
#---------------------------#
echo
echo "==> [7/9] 应用内核配置"

cd ..
echo "CONFIG_KSU=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_WITH_KPROBES=n" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_SU=n" >> ./common/arch/arm64/configs/gki_defconfig
sed -i '2s/check_defconfig//' ./common/build.config.gki

# 移除额外的 git 提交步骤，与 GitHub Actions 保持一致

#---------------------------#
#     8. 编译内核           #
#---------------------------#
echo
echo "==> [8/9] 开始编译内核"

cd ..
# 使用传入的 BUILD_METHOD 参数
./kernel_platform/oplus/build/oplus_build_kernel.sh "$CPUD" "$BUILD_METHOD"

#---------------------------#
#     9. 打包 AnyKernel3    #
#---------------------------#
echo
echo "==> [9/9] 打包 AnyKernel3"

git clone https://github.com/Numbersf/AnyKernel3 --depth=1
rm -rf ./AnyKernel3/.git

# 将编译生成的 Image 放入 AnyKernel3 目录
cp kernel_platform/out/msm-kernel-"${CPUD}"-"${BUILD_METHOD}"/dist/Image ./AnyKernel3/

# 下载 SUSFS 模块（与 GitHub Actions 保持一致）
wget https://github.com/sidex15/ksu_module_susfs/releases/latest/download/ksu_module_susfs_1.5.2+.zip
cp ksu_module_susfs_1.5.2+.zip ./AnyKernel3/

# 生成最终的打包文件
cd AnyKernel3
zip -r9 "../AnyKernel3_KernelSU_Next_${KSU_VERSION}_${FEIL}.zip" ./*
cd ..

#---------------------------#
#     10. 收尾/结果查看     #
#---------------------------#
echo
echo "==> [10/10] 编译完成，结果存放在以下位置："
echo "    1) 内核 zImage/Image: kernel_platform/out/msm-kernel-${CPUD}-${BUILD_METHOD}/dist/Image"
echo "    2) 可直接刷入设备的刷机包: AnyKernel3_KernelSU_Next_${KSU_VERSION}_${FEIL}.zip"
echo
echo "脚本执行完毕。"
