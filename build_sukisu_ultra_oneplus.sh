#!/bin/bash

# 脚本：build_sukisu_ultra_oneplus.sh
# 描述：在本地Ubuntu环境中构建SukiSU Ultra内核
# 基于GitHub Actions工作流：Build SukiSU Ultra OnePlus.yml

# 设置错误处理
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --cpu CPU              设置CPU分支 (sm7550, sm7675, sm8450, sm8475, sm8550, sm8650, sm8750)"
    echo "  --feil FEIL            设置配置文件 (oneplus_ace2pro_v, oneplus_11_v, oneplus12_v, 等)"
    echo "  --cpud CPUD            设置处理器代号 (crow, waipio, kalama, pineapple, sun)"
    echo "  --android-version VER  设置内核安卓版本 (android12, android13, android14, android15)"
    echo "  --kernel-version VER   设置内核版本 (5.10, 5.15, 6.1, 6.6)"
    echo "  --build-method METHOD  设置编译方式 (gki, perf)"
    echo "  --susfs-ci BOOL        SUSFS模块下载是否调用CI (true, false)"
    echo "  --lz4 BOOL             是否启用lz4 (true, false)"
    echo "  --vfs BOOL             是否启用VFS (true, false)"
    echo "  --help                 显示此帮助信息"
    echo ""
    echo "示例: $0 --cpu sm8550 --feil oneplus_ace2pro_v --cpud kalama --android-version android13 --kernel-version 5.15 --build-method gki --susfs-ci true --lz4 false --vfs true"
    exit 0
}

# 默认参数值
CPU="sm8550"
FEIL="oneplus_11_v"
CPUD="kalama"
ANDROID_VERSION="android13"
KERNEL_VERSION="5.15"
BUILD_METHOD="gki"
SUSFS_CI="true"
LZ4="false"
VFS="true"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --cpu)
            CPU="$2"
            shift 2
            ;;
        --feil)
            FEIL="$2"
            shift 2
            ;;
        --cpud)
            CPUD="$2"
            shift 2
            ;;
        --android-version)
            ANDROID_VERSION="$2"
            shift 2
            ;;
        --kernel-version)
            KERNEL_VERSION="$2"
            shift 2
            ;;
        --build-method)
            BUILD_METHOD="$2"
            shift 2
            ;;
        --susfs-ci)
            SUSFS_CI="$2"
            shift 2
            ;;
        --lz4)
            LZ4="$2"
            shift 2
            ;;
        --vfs)
            VFS="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "未知参数: $1"
            show_help
            ;;
    esac
done

# 验证参数
validate_param() {
    local param_name=$1
    local param_value=$2
    local valid_values=$3
    
    if [[ ! $valid_values =~ (^|,)$param_value(,|$) ]]; then
        print_error "无效的 $param_name: $param_value"
        print_error "有效值: $valid_values"
        exit 1
    fi
}

validate_param "CPU" "$CPU" "sm7550,sm7675,sm8450,sm8475,sm8550,sm8650,sm8750"
validate_param "CPUD" "$CPUD" "crow,waipio,kalama,pineapple,sun"
validate_param "ANDROID_VERSION" "$ANDROID_VERSION" "android12,android13,android14,android15"
validate_param "KERNEL_VERSION" "$KERNEL_VERSION" "5.10,5.15,6.1,6.6"
validate_param "BUILD_METHOD" "$BUILD_METHOD" "gki,perf"
validate_param "SUSFS_CI" "$SUSFS_CI" "true,false"
validate_param "LZ4" "$LZ4" "true,false"
validate_param "VFS" "$VFS" "true,false"

# 显示选择的参数
print_info "选择的参数:"
echo "CPU: $CPU"
echo "FEIL: $FEIL"
echo "CPUD: $CPUD"
echo "ANDROID_VERSION: $ANDROID_VERSION"
echo "KERNEL_VERSION: $KERNEL_VERSION"
echo "BUILD_METHOD: $BUILD_METHOD"
echo "SUSFS_CI: $SUSFS_CI"
echo "LZ4: $LZ4"
echo "VFS: $VFS"

# 创建工作目录
WORKSPACE=$(pwd)
print_info "工作目录: $WORKSPACE"

# 步骤1: 安装依赖
print_info "安装依赖..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 git curl wget jq unzip zip build-essential bc bison flex libssl-dev libelf-dev

# 步骤2: 配置Git
print_info "配置Git..."
git config --global user.name "lyy0709"
git config --global user.email "2722707908@qq.com"

# 步骤3: 安装repo工具
print_info "安装repo工具..."
if ! command -v repo &> /dev/null; then
    curl https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
    chmod a+x ~/repo
    sudo mv ~/repo /usr/local/bin/repo
else
    print_info "repo工具已安装，检查更新..."
    # 创建临时目录并初始化repo以检查版本
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    repo init >/dev/null 2>&1 || true
    
    if [ -f .repo/repo/repo ]; then
        NEW_REPO=$(readlink -f .repo/repo/repo)
        if [ -f "$NEW_REPO" ]; then
            print_info "发现新版本，正在更新repo..."
            sudo cp "$NEW_REPO" /usr/local/bin/repo
            print_success "repo更新完成"
        fi
    fi
    
    # 清理临时目录
    cd - >/dev/null
    rm -rf $TEMP_DIR
fi

# 步骤4: 初始化repo并同步
print_info "初始化repo并同步..."
rm -rf kernel_workspace && mkdir -p kernel_workspace && cd kernel_workspace
repo init -u https://github.com/OnePlusOSS/kernel_manifest.git -b refs/heads/oneplus/$CPU -m $FEIL.xml --depth=1
repo sync

print_info "修改BUILD.bazel文件..."
sed -i '/^[[:space:]]*"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",$/d' kernel_platform/common/BUILD.bazel
sed -i '/^[[:space:]]*"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",$/d' kernel_platform/msm-kernel/BUILD.bazel
rm kernel_platform/common/android/abi_gki_protected_exports_* || echo "No protected exports!"
rm kernel_platform/msm-kernel/android/abi_gki_protected_exports_* || echo "No protected exports!"

# 步骤5: 删除 -dirty 后缀
print_info "删除 -dirty 后缀..."
cd kernel_platform
sed -i 's/ -dirty//g' common/scripts/setlocalversion
sed -i 's/ -dirty//g' msm-kernel/scripts/setlocalversion
sed -i 's/ -dirty//g' external/dtc/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' common/scripts/setlocalversion
git add -A
git commit -m "Force remove -dirty suffix from kernel version"

# 步骤6: 添加 SukiSU Ultra
print_info "添加 KernelSU-SukiSU Ultra..."
curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-dev
cd ./KernelSU
KSU_VERSION=$(expr $(git rev-list --count main) "+" 10606)
export KSU_VERSION=$KSU_VERSION
sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
cd ..

# 步骤7: 应用 Patches SukiSU Ultra
print_info "应用 Patches SukiSU Ultra..."
cd $WORKSPACE/kernel_workspace
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-$ANDROID_VERSION-$KERNEL_VERSION
git clone https://github.com/ShirkNeko/SukiSU_patch.git
cd kernel_platform
echo "正在给内核打susfs补丁"
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch ./common/
cp ../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

if [ "$LZ4" = "true" ]; then
    echo "正在给内核打lz4补丁"
    cp -r ../SukiSU_patch/other/lz4k/include/linux/* ./common/include/linux
    cp -r ../SukiSU_patch/other/lz4k/lib/* ./common/lib
    cp -r ../SukiSU_patch/other/lz4k/crypto/* ./common/crypto
fi

cd ./common
patch -p1 < 50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch || true
echo "完成"

# 步骤8: 应用 Hide Stuff Patches
print_info "应用 Hide Stuff Patches..."
cd $WORKSPACE/kernel_workspace/kernel_platform/common
cp ../../SukiSU_patch/69_hide_stuff.patch ./
echo "正在打隐藏应用补丁"
patch -p1 -F 3 < 69_hide_stuff.patch

# 步骤9: 应用 VFS 和 LZ4KD
print_info "应用 VFS 和 LZ4KD..."
cd $WORKSPACE/kernel_workspace/kernel_platform/common
if [ "$VFS" = "true" ]; then
    cp ../../SukiSU_patch/hooks/syscall_hooks.patch ./
    echo "正在打vfs补丁"
    patch -p1 -F 3 < syscall_hooks.patch
    echo "vfs_patch完成"
fi

if [ "$LZ4" = "true" ]; then
    cp ../../SukiSU_patch/other/lz4k_patch/$KERNEL_VERSION/lz4kd.patch ./
    echo "正在打lz4kd补丁"
    patch -p1 -F 3 < lz4kd.patch || true
    echo "lz4_patch完成"
fi

# 步骤10: 添加配置设置
print_info "添加配置设置..."
cd $WORKSPACE/kernel_workspace/kernel_platform
CONFIG_FILE=./common/arch/arm64/configs/gki_defconfig

# SukiSU Ultra config
echo "CONFIG_KSU=y" >> "$CONFIG_FILE"
echo "CONFIG_KPM=y" >> "$CONFIG_FILE"
if [ "$VFS" = "false" ]; then
    echo "CONFIG_KPROBES=y" >> "$CONFIG_FILE"
fi

# VFS config
if [ "$VFS" = "true" ]; then
    echo "CONFIG_KSU_SUSFS_SUS_SU=n" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$CONFIG_FILE"
fi

if [ "$VFS" = "false" ]; then
    echo "CONFIG_KSU_SUSFS_SUS_SU=y" >> "$CONFIG_FILE"
fi

# SUSFS config
if [ "$VFS" = "true" ]; then
    echo "CONFIG_KSU_SUSFS=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >> "$CONFIG_FILE"
    echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >> "$CONFIG_FILE"
fi

# Remove check_defconfig
if [ "$LZ4" = "false" ]; then
    sed -i 's/check_defconfig//' ./common/build.config.gki
fi

# 添加 LZ4 Config
if [ "$LZ4" = "true" ]; then
    if [ "$KERNEL_VERSION" = "5.10" ]; then
        echo "CONFIG_ZSMALLOC=y" >> "$CONFIG_FILE"
        echo "CONFIG_ZRAM=y" >> "$CONFIG_FILE"
        echo "CONFIG_MODULE_SIG=n" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_LZO=y" >> "$CONFIG_FILE"
        echo "CONFIG_ZRAM_DEF_COMP_LZ4KD=y" >> "$CONFIG_FILE"
    fi

    if [ "$KERNEL_VERSION" != "6.6" ] && [ "$KERNEL_VERSION" != "5.10" ]; then
        sed -i 's/CONFIG_MODULE_SIG=y/CONFIG_MODULE_SIG=n/g' "$CONFIG_FILE"
        sed -i 's/CONFIG_ZSMALLOC=m/CONFIG_ZSMALLOC=y/g' "$CONFIG_FILE"
        sed -i 's/CONFIG_ZRAM=m/CONFIG_ZRAM=y/g' "$CONFIG_FILE"
    fi

    if [ "$KERNEL_VERSION" = "6.6" ]; then
        echo "CONFIG_ZSMALLOC=y" >> "$CONFIG_FILE"
        sed -i 's/CONFIG_ZRAM=m/CONFIG_ZRAM=y/g' "$CONFIG_FILE"
    fi

    if grep -q "CONFIG_ZSMALLOC=y" "$CONFIG_FILE" && grep -q "CONFIG_ZRAM=y" "$CONFIG_FILE"; then
        echo "CONFIG_CRYPTO_LZ4HC=y" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_LZ4K=y" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_LZ4KD=y" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_842=y" >> "$CONFIG_FILE"
        # Remove check_defconfig
        sed -i 's/check_defconfig//' ./common/build.config.gki
    fi
fi

# 步骤11: 构建内核
print_info "构建内核..."
cd $WORKSPACE/kernel_workspace
if [ "$CPU" = "sm8650" ] || [ "$CPU" = "sm7675" ]; then
    ./kernel_platform/build_with_bazel.py -t $CPUD $BUILD_METHOD
else
    LTO=full ./kernel_platform/oplus/build/oplus_build_kernel.sh $CPUD $BUILD_METHOD
fi

# 步骤12: 制作 AnyKernel3
print_info "制作 AnyKernel3..."
cd $WORKSPACE
git clone https://github.com/Numbersf/AnyKernel3 --depth=1
rm -rf ./AnyKernel3/.git

dir1="./kernel_workspace/kernel_platform/out/msm-kernel-$CPUD-$BUILD_METHOD/dist/"
dir2="./kernel_workspace/kernel_platform/common/out/arch/arm64/boot/"
dir3="./kernel_workspace/kernel_platform/out/msm-$CPUD-$CPUD-$BUILD_METHOD/dist/"
target1="./AnyKernel3/"
target2="./kernel_workspace/kernel"

# 查找 Image 文件
if find "$dir1" -name "Image" | grep -q "Image"; then
    image_path="$dir1"Image
elif find "$dir2" -name "Image" | grep -q "Image"; then
    image_path="$dir2"Image
elif find "$dir3" -name "Image" | grep -q "Image"; then
    image_path="$dir3"Image
else
    image_path=$(find "./kernel_workspace/kernel_platform/common/out/" -name "Image" | head -n 1)
fi

# 拷贝 Image
if [ -n "$image_path" ] && [ -f "$image_path" ]; then
    mkdir -p "$dir1"
    if [ "$(realpath "$image_path")" != "$(realpath "$dir1"Image)" ]; then
        cp "$image_path" "$dir1"
    else
        echo "源文件与目标相同，跳过复制"
    fi
    cp "$dir1"Image ./AnyKernel3/Image
else
    print_error "未找到 Image 文件，构建可能失败"
    exit 1
fi

# 可选复制其它新文件（如果存在）
if [ "$CPUD" = "sm8750" ]; then
    for file in dtbo.img system_dlkm.erofs.img vendor_dlkm.img vendor_boot.img; do
        if [ -f "$dir1$file" ]; then
            target_name="$file"
            # 特殊处理 system_dlkm.erofs.img 的目标名
            if [ "$file" = "system_dlkm.erofs.img" ]; then
                target_name="system_dlkm.img"
            fi
            cp "$dir1$file" "./AnyKernel3/$target_name"
        else
            print_warning "$file 不存在，跳过复制"
        fi
    done
fi

# 步骤13: 应用 patch_linux 并替换 Image
print_info "应用 patch_linux 并替换 Image..."
cd $WORKSPACE/kernel_workspace/kernel_platform/out/msm-kernel-$CPUD-$BUILD_METHOD/dist
curl -LO https://raw.githubusercontent.com/Numbersf/Action-Build/main/patch_linux
chmod +x patch_linux
./patch_linux
rm -f Image
mv oImage Image
cp Image $WORKSPACE/AnyKernel3/Image

# 步骤14: 下载 SUSFS 模块
if [ "$SUSFS_CI" = "true" ]; then
    print_info "从CI下载最新的SUSFS模块..."
    cd $WORKSPACE
    
    # 获取GitHub个人访问令牌
    echo "请输入您的GitHub个人访问令牌（如果没有，请访问 https://github.com/settings/tokens 创建一个）:"
    read -s GITHUB_TOKEN
    
    LATEST_RUN_ID=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
        "https://api.github.com/repos/sidex15/susfs4ksu-module/actions/runs?status=success" | \
        jq -r '.workflow_runs[] | select(.head_branch == "v1.5.2+") | .id' | head -n 1)

    if [ -z "$LATEST_RUN_ID" ]; then
        print_error "未找到分支v1.5.2+的成功运行"
        print_info "尝试从Release下载SUSFS模块..."
        wget https://github.com/sidex15/ksu_module_susfs/releases/latest/download/ksu_module_susfs_1.5.2+.zip
        cp ksu_module_susfs_1.5.2+.zip ./AnyKernel3/
    else
        ARTIFACT_URL=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
            "https://api.github.com/repos/sidex15/susfs4ksu-module/actions/runs/$LATEST_RUN_ID/artifacts" | jq -r '.artifacts[0].archive_download_url')

        curl -L -H "Authorization: Bearer $GITHUB_TOKEN" -o ksu_module_susfs.zip "$ARTIFACT_URL"
        cp ksu_module_susfs.zip ./AnyKernel3/
    fi
else
    print_info "从Release下载最新的SUSFS模块..."
    cd $WORKSPACE
    wget https://github.com/sidex15/ksu_module_susfs/releases/latest/download/ksu_module_susfs_1.5.2+.zip
    cp ksu_module_susfs_1.5.2+.zip ./AnyKernel3/
fi

# 步骤15: 设置后缀并创建最终ZIP
print_info "设置后缀并创建最终ZIP..."
cd $WORKSPACE

# 设置后缀
SUFFIX=""
if [ "$VFS" = "true" ]; then
    SUFFIX="${SUFFIX}_VFS"
fi
if [ "$LZ4" = "true" ]; then
    SUFFIX="${SUFFIX}_LZ4KD"
fi

# 清理FEIL名称
FEIL_CLEAN="${FEIL}"
FEIL_CLEAN="${FEIL_CLEAN%_v}"  # 去掉结尾的 _v（如果有）
FEIL_CLEAN="${FEIL_CLEAN%_u}"  # 去掉结尾的 _u（如果有）

# 创建最终ZIP
cd $WORKSPACE/AnyKernel3
zip -r9 ../AnyKernel3_SukiSUUltra_${KSU_VERSION}_${FEIL_CLEAN}_KPM${SUFFIX}.zip *

print_success "构建完成！"
print_success "输出文件: $WORKSPACE/AnyKernel3_SukiSUUltra_${KSU_VERSION}_${FEIL_CLEAN}_KPM${SUFFIX}.zip"
