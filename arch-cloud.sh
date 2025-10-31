#!/bin/bash
# arch-cloud.sh - Setup script for Arch Linux VM
# Downloads Arch cloud image, sets up cloud-init with user account,
# and creates a helper script ~/start.sh to launch the VM quickly.

# Ask user for VM parameters
read -p "Enter VM RAM in GB (e.g., 2 for 2GB): " RAM_GB
read -p "Enter number of CPUs: " CPUS
read -p "Enter disk size in GB (e.g., 10 for 10GB): " DISK_GB
read -p "Enter name for VM image file (e.g., arch-cloud.qcow2): " IMAGE_NAME
read -p "Enter desired username for the VM: " NEW_USER
read -sp "Enter password for user $NEW_USER: " NEW_PASS
echo
read -p "Do you want to allocate additional disk space? (y/n): " ALLOCATE_DISK

# Convert GB to MB for RAM
RAM_MB=$((RAM_GB * 1024))

# Set default image path
IMAGE="$HOME/$IMAGE_NAME"

# Download Arch cloud image if not exists
if [ ! -f "$IMAGE" ]; then
    echo "Downloading latest Arch Linux cloud image..."
    curl -L -o "$IMAGE" https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
    if [ $? -ne 0 ]; then
        echo "Download failed. Exiting."
        exit 1
    fi
else
    echo "Arch cloud image already exists at $IMAGE"
fi

# Optional: create additional qcow2 overlay for user-defined disk size
if [ "$ALLOCATE_DISK" = "y" ] || [ "$ALLOCATE_DISK" = "Y" ]; then
    echo "Creating additional disk space ($DISK_GB GB)..."
    QEMU_DISK="$HOME/${IMAGE_NAME%.qcow2}-disk.qcow2"
    qemu-img create -f qcow2 "$QEMU_DISK" "${DISK_GB}G"
else
    QEMU_DISK="$IMAGE"
fi

# Create cloud-init user-data for automatic user creation
CLOUD_INIT_DIR="$HOME/arch-cloud-init"
mkdir -p "$CLOUD_INIT_DIR"

cat > "$CLOUD_INIT_DIR/user-data" <<EOL
#cloud-config
users:
  - name: $NEW_USER
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: users,wheel
    lock_passwd: false
    passwd: $(openssl passwd -6 "$NEW_PASS")
ssh_pwauth: true
chpasswd:
  list: |
    $NEW_USER:$NEW_PASS
  expire: False
EOL

# Create meta-data for cloud-init
cat > "$CLOUD_INIT_DIR/meta-data" <<EOL
instance-id: arch-vm
local-hostname: arch-vm
EOL

# Check for genisoimage or mkisofs command
if command -v genisoimage >/dev/null 2>&1; then
    ISO_CMD="genisoimage"
elif command -v mkisofs >/dev/null 2>&1; then
    ISO_CMD="mkisofs"
else
    echo "Error: Neither genisoimage nor mkisofs is installed. Please install one of them."
    exit 1
fi

# Create cloud-init ISO seed
SEED_ISO="$HOME/arch-cloud-seed.iso"
$ISO_CMD -output "$SEED_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"

# Create start.sh in home directory
START_SCRIPT="$HOME/start.sh"
cat > "$START_SCRIPT" <<EOL
#!/bin/bash
# start.sh - Launch Arch Linux VM in terminal

qemu-system-x86_64 -enable-kvm -m $RAM_MB -smp $CPUS -cpu host \\
  -drive file="$QEMU_DISK",if=virtio,format=qcow2 \\
  -drive file="$SEED_ISO",if=virtio,format=raw \\
  -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net,netdev=net0 \\
  -nographic
EOL

chmod +x "$START_SCRIPT"

echo "Setup complete! You can start your Arch VM at any time by running:"
echo "  $START_SCRIPT"
