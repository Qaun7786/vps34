{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      if [ ! -f /home/user/.cleanup_done ]; then
        echo "Cleaning up..."
        rm -rf /home/user/.gradle/* || true
        rm -rf /home/user/.emu/* || true
        rm -rf /home/user/.android/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'vps' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
        echo "Cleanup done."
      else
        echo "Cleanup already done, skipping."
      fi

      VM_DIR="$HOME/qemu"
      DISK="$VM_DIR/ubuntu.qcow2"
      SEED_ISO="$VM_DIR/seed.iso"
      NOVNC_DIR="$HOME/noVNC"

      mkdir -p "$VM_DIR"

      if [ ! -f "$DISK" ]; then
        echo "Downloading Ubuntu 24.04 cloud image..."
        wget -O "$DISK" \
          https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
        echo "Resizing disk to 64G..."
        qemu-img resize "$DISK" 64G
      else
        echo "Ubuntu disk exists, skipping."
      fi

      if [ ! -f "$SEED_ISO" ] || [ ! -s "$SEED_ISO" ]; then
        echo "Creating seed ISO..."
        python3 /home/user/vps/main.py
        if [ -s "$SEED_ISO" ]; then
          echo "Seed ISO OK"
        else
          echo "Seed ISO failed!"
          exit 1
        fi
      else
        echo "Seed ISO exists, skipping."
      fi

      if [ ! -d "$NOVNC_DIR/.git" ]; then
        echo "Cloning noVNC..."
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      else
        echo "noVNC exists, skipping."
      fi

      echo "Starting QEMU..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -smp 8,cores=128 \
        -m 64589 \
        -M q35 \
        -device qemu-xhci \
        -device usb-tablet \
        -vga virtio \
        -netdev user,id=n0,hostfwd=tcp::2222-:22 \
        -net nic,netdev=n0,model=virtio-net-pci \
        -drive file="$DISK",format=qcow2,if=virtio \
        -drive file="$SEED_ISO",format=raw,if=virtio,readonly=on \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      echo "QEMU started. Waiting for VM to boot..."
      sleep 10

      echo "Starting noVNC..."
      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      echo "Starting Cloudflared..."
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 15

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " Ubuntu Server + XFCE ready:"
        echo "     $URL/vnc.html"
        echo "     VNC Password: ubuntu"
        echo "     SSH: ssh -p 2222 ubuntu@localhost"
        echo "========================================="
        mkdir -p /home/user/vps
        echo "$URL/vnc.html" > /home/user/vps/noVNC-URL.txt
        echo "URL saved to ~/vps/noVNC-URL.txt"
      else
        echo "Cloudflared failed. Check /tmp/cloudflared.log"
      fi
      echo "========================================="
      echo "Setting up Python venv for bot..."
      echo "========================================="

      BOT_DIR="$HOME/bot"

      mkdir -p "$BOT_DIR"
      cd "$BOT_DIR"

      # Tạo venv nếu chưa có
      if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
      fi

      # Activate venv
      source venv/bin/activate

      # Upgrade pip + cài thư viện
      pip install --upgrade pip
      pip install discord.py python-dotenv

      # Download bot file nếu chưa có
      if [ ! -f "bot.py" ]; then
        echo "Downloading bot..."
        wget -O bot.py "https://download1472.mediafire.com/8e0axx6fdargn03Ol27mY8yism3ee1Yknj6GGJdQfk1T98xbhqYCiyvRVTLX3FTjCUOyDkibY9w5lZ1OQ2AdhcB-CIfhvkmVABIc079srNZZeMMkh5W3EV8jjgISyIa-Zkn8Z_7uHguqmfaGwRWZHxkRAnIPJ94V3sL7Tse_pVnd/y5hdv9nwsr054aj/bot+%281%29.py"
      fi

      # Chạy bot (background)
      echo "Starting Discord bot..."
      nohup python bot.py > /tmp/bot.log 2>&1 &

      echo "Bot started. Log: /tmp/bot.log"

      elapsed=0
      while true; do
        echo "Time elapsed: $elapsed min | QEMU: $(pgrep qemu-system > /dev/null && echo running || echo STOPPED)"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [
          "bash" "-lc"
          "echo 'noVNC running on port 8888'"
        ];
      };
      terminal = {
        manager = "web";
        command = [ "bash" ];
      };
    };
  };
}
