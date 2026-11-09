#!/usr/bin/env bash


echo "==> 1. Updating APT repositories..."
sudo apt update || echo "Warning: apt update encountered minor issues, continuing..."

echo "==> 2. Installing basic build tools..."
sudo apt install -y build-essential gcc g++ gdb make cmake git \
    flex bison bc libelf-dev libssl-dev libncurses-dev dwarves \
    pkg-config ccache zstd parted clangd || { echo "Failed to install some build tools, continuing..."; }

echo "==> 3. Installing kernel profiling & BPF dependencies..."
sudo apt install -y \
    linux-headers-$(uname -r) \
    linux-tools-common \
    linux-tools-$(uname -r) \
    clang llvm libbpf-dev bpfcc-tools || { echo "Warning: Some kernel tools failed to install, continuing..."; }

if ! command -v bpftool &> /dev/null; then
    echo "Notice: bpftool not in PATH directly, usually located in /usr/lib/linux-tools/$(uname -r)/bpftool"
fi

echo "==> 4. Configuring Git..."
git config --global user.name "Yulong Tang"
git config --global user.email "yulongtang077@gmail.com"
git config --global core.editor vim
git config --global init.defaultBranch main

echo "==> 5. Checking SSH keys..."
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -C "yulongtang077@gmail.com" -f "$HOME/.ssh/id_ed25519"
fi
echo "=== SSH Public Key ==="
cat "$HOME/.ssh/id_ed25519.pub"

echo "==> 6. Setting up Miniconda..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  CONDA_ARCH="x86_64" ;;
    aarch64) CONDA_ARCH="aarch64" ;;
    arm64)   CONDA_ARCH="aarch64" ;;
    *)       echo "Warning: Unsupported architecture $ARCH, skipping Conda."; CONDA_ARCH="" ;;
esac

if [ -n "$CONDA_ARCH" ] && [ ! -d "$HOME/.miniconda3" ]; then
    echo "Detected architecture: $ARCH, downloading Miniconda for $CONDA_ARCH..."
    wget -q "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${CONDA_ARCH}.sh" -O ~/miniconda.sh || true
    if [ -f ~/miniconda.sh ]; then
        bash ~/miniconda.sh -b -p "$HOME/.miniconda3"
        rm -f ~/miniconda.sh
        "$HOME/.miniconda3/bin/conda" init bash || true
        eval "$("$HOME/.miniconda3/bin/conda" shell.bash hook)" || true
        conda config --set auto_activate_base false || true
    fi
else
    echo "Miniconda already installed or skipped."
fi

TARGET_DISK="/dev/sda"
MOUNT_POINT="$HOME/sda"

if [ -b "$TARGET_DISK" ]; then
    echo "==> 7. Checking disk expansion on $TARGET_DISK..."

    sudo fdisk "$TARGET_DISK" <<EOF >/dev/null 2>&1 || true
n



w
EOF

    sudo partprobe "$TARGET_DISK" 2>/dev/null || true
    sleep 2

    NEW_PART=$(lsblk -lnpo NAME,TYPE,FSTYPE,MOUNTPOINTS "$TARGET_DISK" | awk '$2=="part" && $3=="" && $4=="" {print $1}' | head -n 1)

    if [ -n "$NEW_PART" ] && [ "$NEW_PART" != "$TARGET_DISK" ]; then
        echo "Found target unformatted partition: $NEW_PART"

        if ! mountpoint -q "$MOUNT_POINT"; then
            echo "Formatting and mounting $NEW_PART to $MOUNT_POINT..."
            sudo mkfs.ext4 -F "$NEW_PART"
            sudo tune2fs -m 0 "$NEW_PART"

            mkdir -p "$MOUNT_POINT"
            sudo mount "$NEW_PART" "$MOUNT_POINT"
            sudo chown -R "$USER:$(id -gn)" "$MOUNT_POINT"

            PART_UUID=$(sudo blkid -s UUID -o value "$NEW_PART")
            if [ -n "$PART_UUID" ] && ! grep -q "$PART_UUID" /etc/fstab; then
                echo "UUID=$PART_UUID $MOUNT_POINT ext4 defaults 0 2" | sudo tee -a /etc/fstab
            fi
        else
            echo "$MOUNT_POINT is already mounted."
        fi
        df -h "$MOUNT_POINT"
    else
        echo "Notice: No new unpartitioned space or unformatted partition detected on $TARGET_DISK."
    fi
fi

echo "==> Initialization script completed successfully."
