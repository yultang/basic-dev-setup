#!/usr/bin/env bash
set -e

# 1. 系统更新与核心工具包安装
sudo apt update && sudo apt upgrade -y

# 基础编译与内核构建工具链
sudo apt install -y build-essential gcc g++ gdb make cmake git \
    flex bison bc libelf-dev libssl-dev libncurses-dev dwarves \
    pkg-config ccache zstd parted

# 内核性能分析与 eBPF 开发依赖
sudo apt install -y linux-headers-$(uname -r) \
    clang llvm libbpf-dev bpftool bpfcc-tools \
    linux-tools-common linux-tools-$(uname -r)

# 2. Git 配置
git config --global user.name "Yulong Tang"
git config --global user.email "yulongtang077@gmail.com"
git config --global core.editor vim
git config --global init.defaultBranch main

# 3. SSH 密钥配置（-N "" 免密回车，-f 指定路径，避免自动化脚本挂起）
if [ ! -f ~/.ssh/id_ed25519 ]; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -N "" -C "yulongtang077@gmail.com" -f ~/.ssh/id_ed25519
fi
echo "=== SSH Public Key ==="
cat ~/.ssh/id_ed25519.pub

# 4. Miniconda 自适应 CPU 架构安装
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  CONDA_ARCH="x86_64" ;;
    aarch64) CONDA_ARCH="aarch64" ;;
    arm64)   CONDA_ARCH="aarch64" ;;
    *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "Detected architecture: $ARCH, downloading Miniconda for $CONDA_ARCH..."
wget "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${CONDA_ARCH}.sh" -O ~/miniconda.sh
bash ~/miniconda.sh -b -p "$HOME/.miniconda3"
rm ~/miniconda.sh

"$HOME/.miniconda3/bin/conda" init bash
eval "$("$HOME/.miniconda3/bin/conda" shell.bash hook)"
conda config --set auto_activate_base false

# 5. 动态检测并自动挂载未分配磁盘空间
TARGET_DISK="/dev/sda"
MOUNT_POINT="$HOME/sda"

if [ -b "$TARGET_DISK" ]; then
    echo "Processing storage expansion on $TARGET_DISK..."

    # 记录分区前的最新分区号
    EXISTING_PARTS=$(lsblk -lnpo NAME "$TARGET_DISK" | grep -v "^${TARGET_DISK}$" || true)

    # 尝试新建分区占用剩余全部空间（适用于 MBR/GPT，使用默认分配范围）
    sudo fdisk "$TARGET_DISK" <<EOF
n



w
EOF

    # 刷新内核分区表
    sudo partprobe "$TARGET_DISK" || true
    sleep 2

    # 动态抓取刚创建的分区设备名（比较分区变动，取最新创建的分区）
    NEW_PART=$(lsblk -lnpo NAME "$TARGET_DISK" | grep -v "^${TARGET_DISK}$" | tail -n 1)

    if [ -n "$NEW_PART" ] && [ "$NEW_PART" != "$TARGET_DISK" ]; then
        echo "Found newly created partition: $NEW_PART"

        # 格式化并解除保留空间限制
        sudo mkfs.ext4 -F "$NEW_PART"
        sudo tune2fs -m 0 "$NEW_PART"

        # 挂载并赋予当前用户权限
        mkdir -p "$MOUNT_POINT"
        sudo mount "$NEW_PART" "$MOUNT_POINT"
        sudo chown -R "$USER:$(id -gn)" "$MOUNT_POINT"

        # 持久化到 /etc/fstab（基于 UUID）
        PART_UUID=$(sudo blkid -s UUID -o value "$NEW_PART")
        if [ -n "$PART_UUID" ] && ! grep -q "$PART_UUID" /etc/fstab; then
            echo "UUID=$PART_UUID $MOUNT_POINT ext4 defaults 0 2" | sudo tee -a /etc/fstab
        fi

        df -h "$MOUNT_POINT"
    else
        echo "Warning: No new partition detected on $TARGET_DISK."
    fi
else
    echo "Notice: Disk $TARGET_DISK not found, skipping disk partition extension."
fi
