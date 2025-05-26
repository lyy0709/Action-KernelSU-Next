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
    echo "  --feil FEIL            设置配置文件 (oneplus_nord_ce4_v, oneplus_ace_3v_v, oneplus_nord_4_v, oneplus_10_pro_v, oneplus_10t_v, oneplus_11r_v, oneplus_ace2_v, oneplus_ace_pro_v, oneplus_11_v, oneplus_12r_v, oneplus_ace2pro_v, oneplus_ace3_v, oneplus_open_v, oneplus12_v, oneplus_13r, oneplus_ace3_pro_v, oneplus_ace5, oneplus_pad2_v, oneplus_13, oneplus_ace5_pro, oneplus_13t)"
    echo "  --cpud CPUD            设置处理器代号 (crow, waipio, kalama, pineapple, sun)"
    echo "  --android-version VER  设置内核安卓版本 (android12, android13, android14, android15)"
    echo "  --kernel-version VER   设置内核版本 (5.10, 5.15, 6.1, 6.6)"
    echo "  --build-method METHOD  设置编译方式 (gki, perf)"
    echo "  --suffix SUFFIX        自定义内核后缀 (留空则使用随机字符串)"
    echo "  --susfs-ci BOOL        SUSFS模块下载是否使用CI构建 (true, false)"
    echo "  --vfs BOOL             是否启用手动钩子(VFS) (true, false)"
    echo "  --zram BOOL            是否启用添加更多的ZRAM算法 (true, false)"
    echo "  --help                 显示此帮助信息"
    echo ""
    echo "示例: $0 --cpu sm8550 --feil oneplus_ace2pro_v --cpud kalama --android-version android13 --kernel-version 5.15 --build-method gki --suffix '' --susfs-ci true --vfs true --zram false"
    exit 0
}

# 默认参数值（与GitHub Actions一致）
CPU="sm8550"
FEIL="oneplus_11_v"
CPUD="kalama"
ANDROID_VERSION="android13"
KERNEL_VERSION="5.15"
BUILD_METHOD="gki"
SUFFIX=""
SUSFS_CI="true"
VFS="true"
ZRAM="false"

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
        --suffix)
            SUFFIX="$2"
            shift 2
            ;;
        --susfs-ci)
            SUSFS_CI="$2"
            shift 2
            ;;
        --vfs)
            VFS="$2"
            shift 2
            ;;
        --zram)
            ZRAM="$2"
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
validate_param "VFS" "$VFS" "true,false"
validate_param "ZRAM" "$ZRAM" "true,false"

# 显示选择的参数（对应GitHub Actions的Show selected inputs debug步骤）
print_info "显示选择的输入参数调试信息:"
echo "Selected CPU: $CPU"
echo "Selected FEIL: $FEIL"
echo "Selected CPUD: $CPUD"
echo "Selected ANDROID_VERSION: $ANDROID_VERSION"
echo "Selected KERNEL_VERSION: $KERNEL_VERSION"
echo "Selected BUILD_METHOD: $BUILD_METHOD"
echo "Custom SUFFIX: $SUFFIX"
echo "Selected SUSFS_CI: $SUSFS_CI"
echo "Selected VFS: $VFS"
echo "Selected ZRAM: $ZRAM"

# 创建工作目录
WORKSPACE=$(pwd)
print_info "工作目录: $WORKSPACE"

# 步骤1: 安装依赖（对应Install dependencies步骤）
print_info "安装依赖..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 git curl

# 步骤3: 安装repo工具（对应Install repo tool步骤）
print_info "安装repo工具..."
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
chmod a+x ~/repo
sudo mv ~/repo /usr/local/bin/repo

# 步骤4: 初始化repo并同步（对应Initialize repo and sync步骤）
print_info "初始化repo并同步..."
mkdir kernel_workspace && cd kernel_workspace
repo init -u https://github.com/OnePlusOSS/kernel_manifest.git -b refs/heads/oneplus/$CPU -m $FEIL.xml --depth=1
repo sync -c -j$(nproc --all) --no-tags --no-clone-bundle --force-sync
if [ -e kernel_platform/common/BUILD.bazel ]; then
    sed -i '/^[[:space:]]*"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",$/d' kernel_platform/common/BUILD.bazel
fi
if [ -e kernel_platform/msm-kernel/BUILD.bazel ]; then
    sed -i '/^[[:space:]]*"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",$/d' kernel_platform/msm-kernel/BUILD.bazel
fi
rm kernel_platform/common/android/abi_gki_protected_exports_* || echo "No protected exports!"
rm kernel_platform/msm-kernel/android/abi_gki_protected_exports_* || echo "No protected exports!"

# 步骤5: 删除 -dirty 后缀（对应Force remove -dirty suffix步骤）
print_info "删除 -dirty 后缀..."
cd kernel_platform
sed -i 's/ -dirty//g' common/scripts/setlocalversion
sed -i 's/ -dirty//g' msm-kernel/scripts/setlocalversion
sed -i 's/ -dirty//g' external/dtc/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' common/scripts/setlocalversion
git add -A
git commit -m "Force remove -dirty suffix from kernel version"

# 步骤6: 修改setlocalversion后缀（如果SUFFIX已设置）（对应Modify setlocalversion suffix if SUFFIX is set步骤）
if [ "$SUFFIX" != "" ]; then
    print_info "修改setlocalversion后缀..."
    cd $WORKSPACE/kernel_workspace
    for path in \
        kernel_platform/common/scripts/setlocalversion \
        kernel_platform/msm-kernel/scripts/setlocalversion \
        kernel_platform/external/dtc/scripts/setlocalversion; do
        sed -i '/^res=/a res=$(echo "$res" | sed -E '\''s/-[0-9]+-o-g[0-9a-f]{7,}//'\'')' "$path"
        sed -i "\$s|echo \"\\\$res\"|echo \"\$res-$SUFFIX\"|" "$path"
    done
    git add -A
    git commit -m "Clean git describe suffix and append custom suffix: $SUFFIX"
fi

# 步骤7: 生成随机内核后缀（如果SUFFIX为空）（对应Generate random kernel suffix if SUFFIX is empty步骤）
if [ "$SUFFIX" = "" ]; then
    print_info "生成随机内核后缀..."
    cd $WORKSPACE/kernel_workspace

    RANDOM_DIGIT=$(od -An -N1 -tu1 < /dev/urandom | tr -d '[:space:]' | awk '{print $1 % 11}')
    RANDOM_HASH=$(od -An -N7 -tx1 /dev/urandom | tr -d ' \n')
    RANDOM_SUFFIX="${RANDOM_DIGIT}-o-g${RANDOM_HASH}"

    for path in \
        kernel_platform/common/scripts/setlocalversion \
        kernel_platform/msm-kernel/scripts/setlocalversion \
        kernel_platform/external/dtc/scripts/setlocalversion; do

        # 清理默认后缀
        sed -i '/^res=/a res=$(echo "$res" | sed -E '\''s/-[0-9]+-o-g[0-9a-fA-F]{7,}//g'\'')' "$path"

        # 替换 echo "$res" 为带随机后缀
        sed -i "\$s|echo \"\\\$res\"|echo \"\$res-$RANDOM_SUFFIX\"|" "$path"
    done

    git add -A
    git commit -m "Fix: inject random suffix"
fi

# 步骤8: 添加 KernelSU-SukiSU Ultra（对应Add KernelSU-SukiSU Ultra步骤）
print_info "添加 KernelSU-SukiSU Ultra..."
cd $WORKSPACE/kernel_workspace/kernel_platform
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-dev
cd ./KernelSU
KSU_VERSION=$(expr $(/usr/bin/git rev-list --count main) "+" 10606)
export KSUVER=$KSU_VERSION
export KSU_VERSION=$KSU_VERSION
sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile

# 步骤9: 应用 Patches SukiSU Ultra（对应Apply Patches SukiSU Ultra步骤）
print_info "应用 Patches SukiSU Ultra..."
cd $WORKSPACE/kernel_workspace
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-$ANDROID_VERSION-$KERNEL_VERSION
git clone https://github.com/ShirkNeko/SukiSU_patch.git
cd kernel_platform
echo "正在打susfs补丁"
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch ./common/
cp ../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

if [ "$ZRAM" = "true" ]; then
    echo "正在打zram补丁"
    cp -r ../SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux
    cp -r ../SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
    cp -r ../SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto
    cp -r ../SukiSU_patch/other/zram/lz4k_oplus ./common/lib/
    echo "zram_patch完成"
fi

cd ./common
if [[ "$FEIL" == "oneplus_13" || "$FEIL" == "oneplus_ace5_pro" ]]; then
    sed -i 's/-32,12 +32,38/-32,11 +32,37/g' 50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch
    sed -i '/#include <trace\/hooks\/fs.h>/d' 50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch
fi
patch -p1 < 50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch || true
echo "susfs_patch完成"

# 步骤10: 应用 Hide Stuff Patches（对应Apply Hide Stuff Patches步骤）
print_info "应用 Hide Stuff Patches..."
cd $WORKSPACE/kernel_workspace/kernel_platform/common
cp ../../SukiSU_patch/69_hide_stuff.patch ./
echo "正在打隐藏应用补丁"
patch -p1 -F 3 < 69_hide_stuff.patch
echo "隐藏应用_patch完成"

# 步骤11: 转换 HMBIRD_OGKI 到 HMBIRD_GKI（对应Convert HMBIRD_OGKI to HMBIRD_GKI步骤）
if [ "$KERNEL_VERSION" = "6.6" ]; then
    print_info "转换 HMBIRD_OGKI 到 HMBIRD_GKI..."
    cd $WORKSPACE/kernel_workspace/kernel_platform/common
    sed -i '1iobj-y += hmbird_patch.o' drivers/Makefile
    wget https://github.com/Numbersf/Action-Build/raw/main/patchs/hmbird_patch.patch
    echo "正在打OGKI转换GKI补丁"
    patch -p1 -F 3 < hmbird_patch.patch
    echo "OGKI转换GKI patch完成"
fi

# 步骤12: 应用 VFS（对应Apply VFS步骤）
print_info "应用 VFS..."
cd $WORKSPACE/kernel_workspace/kernel_platform/common
if [ "$VFS" = "true" ]; then
    cp ../../SukiSU_patch/hooks/syscall_hooks.patch ./
    echo "正在打vfs补丁"
    patch -p1 -F 3 < syscall_hooks.patch
    echo "vfs_patch完成"
fi

# 步骤13: 应用 LZ4KD（对应Apply LZ4KD步骤）
print_info "应用 LZ4KD..."
cd $WORKSPACE/kernel_workspace/kernel_platform/common
if [ "$ZRAM" = "true" ]; then
    cp ../../SukiSU_patch/other/zram/zram_patch/$KERNEL_VERSION/lz4kd.patch ./
    echo "正在打lz4kd补丁"
    patch -p1 -F 3 < lz4kd.patch || true
    echo 'lz4kd_patch完成'
    cp ../../SukiSU_patch/other/zram/zram_patch/$KERNEL_VERSION/lz4k_oplus.patch ./
    echo "正在打lz4k_oplus补丁"
    patch -p1 -F 3 < lz4k_oplus.patch || true
    echo 'lz4k_oplus_patch完成'
fi

# 步骤14: 添加配置设置（对应Add Configuration Settings步骤）
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
sed -i 's/check_defconfig//' ./common/build.config.gki

# LZ4KD配置
if [ "$ZRAM" = "true" ]; then
    CONFIG_FILE=./common/arch/arm64/configs/gki_defconfig

    if [ "$KERNEL_VERSION" = "5.10" ]; then
        echo "CONFIG_ZSMALLOC=y" >> "$CONFIG_FILE"
        echo "CONFIG_ZRAM=y" >> "$CONFIG_FILE"
        echo "CONFIG_MODULE_SIG=n" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_LZO=y" >> "$CONFIG_FILE"
        echo "CONFIG_ZRAM_DEF_COMP_LZ4KD=y" >> "$CONFIG_FILE"
    fi

    if [ "$KERNEL_VERSION" != "6.6" ] && [ "$KERNEL_VERSION" != "5.10" ]; then
        if grep -q "CONFIG_ZSMALLOC" -- "$CONFIG_FILE"; then
            sed -i 's/CONFIG_ZSMALLOC=m/CONFIG_ZSMALLOC=y/g' "$CONFIG_FILE"
        else
            echo "CONFIG_ZSMALLOC=y" >> "$CONFIG_FILE"
        fi
        sed -i 's/CONFIG_ZRAM=m/CONFIG_ZRAM=y/g' "$CONFIG_FILE"
    fi

    if [ "$KERNEL_VERSION" = "6.6" ]; then
        echo "CONFIG_ZSMALLOC=y" >> "$CONFIG_FILE"
        sed -i 's/CONFIG_ZRAM=m/CONFIG_ZRAM=y/g' "$CONFIG_FILE"
    fi

    if [ "$ANDROID_VERSION" = "android14" ] || [ "$ANDROID_VERSION" = "android15" ]; then
        if [ -e ./common/modules.bzl ]; then
            sed -i 's/"drivers\/block\/zram\/zram\.ko",//g; s/"mm\/zsmalloc\.ko",//g' "./common/modules.bzl"
        fi

        if [ -e ./msm-kernel/modules.bzl ]; then
            sed -i 's/"drivers\/block\/zram\/zram\.ko",//g; s/"mm\/zsmalloc\.ko",//g' "./msm-kernel/modules.bzl"
            echo "CONFIG_ZSMALLOC=y" >> "msm-kernel/arch/arm64/configs/$CPUD-GKI.config"
            echo "CONFIG_ZRAM=y" >> "msm-kernel/arch/arm64/configs/$CPUD-GKI.config"
        fi
        
        echo "CONFIG_MODULE_SIG_FORCE=n" >> "$CONFIG_FILE"
    elif [ "$KERNEL_VERSION" = "5.10" ] || [ "$KERNEL_VERSION" = "5.15" ]; then
        rm "common/android/gki_aarch64_modules"
        touch "common/android/gki_aarch64_modules"
    fi

    if grep -q "CONFIG_ZSMALLOC=y" "$CONFIG_FILE" && grep -q "CONFIG_ZRAM=y" "$CONFIG_FILE"; then
        echo "CONFIG_CRYPTO_LZ4HC=y" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_LZ4K=y" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_LZ4KD=y" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_842=y" >> "$CONFIG_FILE"
        echo "CONFIG_CRYPTO_LZ4K_OPLUS=y" >> "$CONFIG_FILE"
        echo "CONFIG_ZRAM_WRITEBACK=y" >> "$CONFIG_FILE"
    fi
fi

# 步骤15: 构建内核（对应Build kernel和Fallback build kernel步骤）
print_info "构建内核..."
cd $WORKSPACE/kernel_workspace

if [ "$CPU" = "sm8650" ] || [ "$CPU" = "sm7675" ]; then
    ./kernel_platform/build_with_bazel.py -t $CPUD $BUILD_METHOD
else
    LTO=full SYSTEM_DLKM_RE_SIGN=0 BUILD_SYSTEM_DLKM=0 KMI_SYMBOL_LIST_STRICT_MODE=0 ./kernel_platform/oplus/build/oplus_build_kernel.sh $CPUD $BUILD_METHOD
fi

# 步骤16: 制作 AnyKernel3（对应Make AnyKernel3步骤）
print_info "制作 AnyKernel3..."
cd $WORKSPACE
git clone https://github.com/Numbersf/AnyKernel3 --depth=1
rm -rf ./AnyKernel3/.git

dir1="kernel_workspace/kernel_platform/out/msm-kernel-$CPUD-$BUILD_METHOD/dist/"
dir2="kernel_workspace/kernel_platform/bazel-out/k8-fastbuild/bin/msm-kernel/$CPUD"_gki_kbuild_mixed_tree/
dir3="kernel_workspace/kernel_platform/out/msm-$CPUD-$CPUD-$BUILD_METHOD/dist/"
dir4="kernel_workspace/kernel_platform/out/msm-kernel-$CPUD-$BUILD_METHOD/gki_kernel/common/arch/arm64/boot/"
dir5="kernel_workspace/kernel_platform/out/msm-$CPUD-$CPUD-$BUILD_METHOD/gki_kernel/common/arch/arm64/boot/"
target1="./AnyKernel3/"
target2="./kernel_workspace/kernel"

# 查找 Image 文件
if find "$dir1" -name "Image" | grep -q "Image"; then
    image_path="$dir1"Image
elif find "$dir2" -name "Image" | grep -q "Image"; then
    image_path="$dir2"Image
elif find "$dir3" -name "Image" | grep -q "Image"; then
    image_path="$dir3"Image
elif find "$dir4" -name "Image" | grep -q "Image"; then
    image_path="$dir4"Image
elif find "$dir5" -name "Image" | grep -q "Image"; then
    image_path="$dir5"Image
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
    echo "未找到 Image 文件，构建可能失败"
    exit 1
fi

# 可选复制其它新文件（如果存在）
if [ "$CPU" = "sm8750" ]; then
    for file in dtbo.img system_dlkm.erofs.img vendor_dlkm.img vendor_boot.img; do
        if [ -f "$dir1$file" ]; then
            target_name="$file"
            # 特殊处理 system_dlkm.erofs.img 的目标名
            if [ "$file" = "system_dlkm.erofs.img" ]; then
                target_name="system_dlkm.img"
            fi
            cp "$dir1$file" "./AnyKernel3/$target_name"
        else
            echo "$file 不存在，跳过复制"
        fi
    done
fi

# 步骤17: 应用 patch_linux 并替换 Image（对应Apply patch_linux and replace Image步骤）
print_info "应用 patch_linux 并替换 Image..."
cd $WORKSPACE/kernel_workspace/kernel_platform/out/msm-kernel-$CPUD-$BUILD_METHOD/dist
curl -LO --retry 5 --retry-delay 2 --retry-connrefused https://raw.githubusercontent.com/Numbersf/Action-Build/main/patchs/patch_linux
chmod +x patch_linux
./patch_linux
rm -f Image
mv oImage Image
cp Image $WORKSPACE/AnyKernel3/Image

# 步骤18: 下载 SUSFS 模块（对应Download Latest SUSFS Module from CI/Release步骤）
print_info "下载SUSFS模块..."
cd $WORKSPACE

if [ "$SUSFS_CI" = "true" ]; then
    print_info "从CI下载最新的SUSFS模块..."
    
    # 检查是否设置了GITHUB_TOKEN环境变量
    if [ -z "$GITHUB_TOKEN" ]; then
        print_warning "未设置GITHUB_TOKEN环境变量，尝试从Release下载..."
        wget -O ksu_module_susfs_1.5.2+_Release.zip https://github.com/sidex15/ksu_module_susfs/releases/latest/download/ksu_module_susfs_1.5.2+.zip
        cp ksu_module_susfs_1.5.2+_Release.zip ./AnyKernel3/
    else
        LATEST_RUN_ID=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
            "https://api.github.com/repos/sidex15/susfs4ksu-module/actions/runs?status=success" | \
            jq -r '.workflow_runs[] | select(.head_branch == "v1.5.2+") | .id' | head -n 1)

        if [ -z "$LATEST_RUN_ID" ]; then
            echo "No successful run found for branch v1.5.2+"
            exit 1
        fi

        ARTIFACT_URL=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
            "https://api.github.com/repos/sidex15/susfs4ksu-module/actions/runs/$LATEST_RUN_ID/artifacts" | jq -r '.artifacts[0].archive_download_url')

        curl -L -H "Authorization: Bearer $GITHUB_TOKEN" -o ksu_module_susfs_1.5.2+_CI.zip "$ARTIFACT_URL"
        cp ksu_module_susfs_1.5.2+_CI.zip ./AnyKernel3/
    fi
else
    print_info "从Release下载最新的SUSFS模块..."
    wget -O ksu_module_susfs_1.5.2+_Release.zip https://github.com/sidex15/ksu_module_susfs/releases/latest/download/ksu_module_susfs_1.5.2+.zip
    cp ksu_module_susfs_1.5.2+_Release.zip ./AnyKernel3/
fi

# 步骤19: 设置zip后缀（对应Set zip suffix步骤）
print_info "设置zip后缀..."
SUFFIX_VALUE=""
if [ "$VFS" = "true" ]; then
    SUFFIX_VALUE="${SUFFIX_VALUE}_VFS"
fi
if [ "$ZRAM" = "true" ]; then
    SUFFIX_VALUE="${SUFFIX_VALUE}_LZ4KD"
fi

# 步骤20: 自动映射FEIL到Android版本（对应Auto map FEIL to Android version by manifest步骤）
print_info "自动映射FEIL到Android版本..."
cd $WORKSPACE/kernel_workspace
feil="$FEIL"
cpu="$CPU"
xml=".repo/manifests/${feil}.xml"

if [ ! -f "$xml" ]; then
    echo "Manifest $xml not found, attempting to download from branch oneplus/$cpu..."
    mkdir -p .repo/manifests
    git clone --depth=1 --branch oneplus/$cpu https://github.com/OnePlusOSS/kernel_manifest.git repo_tmp || {
        echo "Failed to clone branch oneplus/$cpu"
        feil_clean_value="${feil}_AndroidUnknown"
    }

    if [ -f "repo_tmp/${feil}.xml" ]; then
        mv "repo_tmp/${feil}.xml" "$xml"
    else
        echo "Manifest file ${feil}.xml not found in branch oneplus/$cpu"
        feil_clean_value="${feil}_AndroidUnknown"
        rm -rf repo_tmp
    fi
    rm -rf repo_tmp
fi

if [ -f "$xml" ]; then
    echo "Manifest $xml found."

    # 去掉末尾的 _x（只删一次）
    feil_base=$(echo "$feil" | sed -E 's/_[a-z]$//')

    # 提取 revision 并解析 Android 版本
    revision_full=$(grep -oP '<project[^>]*name="android_kernel[^"]*"[^>]*revision="\K[^"]+' "$xml" | head -n1 || true)

    if [ -n "$revision_full" ]; then
        android_ver=$(echo "$revision_full" | grep -oP '_v?_?\K([0-9]+\.[0-9]+(?:\.[0-9]+)?)' || true)
        if [ -n "$android_ver" ]; then
            feil_clean_value="${feil_base}_Android${android_ver}"
        else
            feil_clean_value="${feil_base}_AndroidUnknown"
        fi
    else
        feil_clean_value="${feil_base}_AndroidUnknown"
    fi
else
    feil_clean_value="${feil}_AndroidUnknown"
fi

# 步骤21: 创建最终ZIP（对应Upload AnyKernel3步骤的命名逻辑）
print_info "创建最终ZIP..."
cd $WORKSPACE/AnyKernel3
zip -r9 ../AnyKernel3_SukiSUUltra_${KSUVER}_${feil_clean_value}_KPM${SUFFIX_VALUE}.zip *

print_success "构建完成！"
print_success "输出文件: $WORKSPACE/AnyKernel3_SukiSUUltra_${KSUVER}_${feil_clean_value}_KPM${SUFFIX_VALUE}.zip"
