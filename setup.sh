sudo apt update && sudo apt upgrade -y

# Basic development tools and compile suits
sudo apt install -y build-essential gcc g++ gdb make cmake git \
    flex bison bc libelf-dev libssl-dev libncurses-dev dwarves \
    pkg-config ccache zstd

# Kernel Performance profiling and eBPF related dependency
sudo apt install -y linux-headers-$(uname -r) \
    clang llvm libbpf-dev bpftool bpfcc-tools \
    linux-tools-common linux-tools-$(uname -r)

# Git config
git config --global user.name "Yulong Tang"
git config --global user.email "yulongtang077@gmail.com"
git config --global core.editor vim
git config --global init.defaultBranch main

# Config ssh keys
ssh-keygen -t ed25519 -C "yulongtang077@gmail.com"
cat ~/.ssh/id_ed25519.pub

# Install and config Miniconda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
bash ~/miniconda.sh -b -p $HOME/.miniconda3
rm ~/miniconda.sh
~/.miniconda3/bin/conda init bash
source ~/.bashrc
conda config --set auto_activate_base false

# Extend disk storage size
sudo fdisk /dev/sda <<EOF
n



w
EOF

sudo partprobe /dev/sda
sleep 2

sudo mkfs.ext4 -F /dev/sda4
sudo tune2fs -m 0 /dev/sda4

mkdir -p ~/sda
sudo mount /dev/sda4 ~/sda
sudo chown -R $USER:$(id -gn) ~/sda

UUID=$(sudo blkid -s UUID -o value /dev/sda4)
if ! grep -q "$UUID" /etc/fstab; then
  echo "UUID=$UUID $HOME/sda ext4 defaults 0 2" | sudo tee -a /etc/fstab
fi

df -h ~/sda

