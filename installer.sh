#!/bin/bash

set -e

# Detect OS
get_os() {
    os=$(uname | tr '[:upper:]' '[:lower:]')
    case "$os" in
        linux|darwin|freebsd|dragonfly|illumos|aix) echo "$os" ;;
        *) echo "Unsupported OS: $os"; exit 1 ;;
    esac
}

# Detect architecture
get_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        i386|i686) echo "386" ;;
        armv7l|armv6l) echo "arm" ;;
        aarch64|arm64) echo "arm64" ;;
        riscv64) echo "riscv64" ;;
        ppc64) echo "ppc64" ;;
        *) echo "Unsupported architecture: $arch"; exit 1 ;;
    esac
}

# Get latest version from GitHub
get_latest_version() {
    curl -s https://api.github.com/repos/esrrhs/pingtunnel/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/'
}

# Ensure unzip is available
ensure_unzip() {
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Installing unzip..."
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y unzip
        elif command -v yum >/dev/null 2>&1; then
            yum install -y unzip
        else
            echo "Please install unzip manually."; exit 1
        fi
    fi
}

install_pingtunnel() {
    OS=$(get_os)
    ARCH=$(get_arch)
    VERSION=$(get_latest_version)
    FILE="pingtunnel_${OS}_${ARCH}.zip"
    URL="https://github.com/esrrhs/pingtunnel/releases/download/${VERSION}/${FILE}"

    echo "Detected: OS=$OS ARCH=$ARCH"
    echo "Downloading: $URL"

    mkdir -p /opt/pingtunnel
    cd /opt/pingtunnel

    curl -fLO "$URL" || { echo "❌ Failed to download $FILE"; exit 1; }

    ensure_unzip
    unzip -o "$FILE" || { echo "❌ Failed to unzip $FILE"; exit 1; }

    chmod +x pingtunnel
    rm -f "$FILE"
}

create_service() {
    echo "Creating systemd service..."

    cat <<EOF > /etc/systemd/system/pingtunnel.service
[Unit]
Description=PingTunnel Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/pingtunnel
ExecStart=/opt/pingtunnel/pingtunnel -type server -key ${PINGTUNNEL_KEY}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable pingtunnel
    systemctl restart pingtunnel

    echo "✅ pingtunnel service is running."
}

show_final_info() {
    SERVER_IP=$(curl -s https://api.ipify.org)
    echo ""
    echo "✅ Installation complete."
    echo "---------------------------"
    echo "Server IP : $SERVER_IP"
    echo "Password  : $PINGTUNNEL_KEY"
    echo "---------------------------"
}

main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ Please run this script as root (use sudo)"
        exit 1
    fi
    
    # Prompt user for PingTunnel key
    read -p "Enter a shared key for PingTunnel (-key): " PINGTUNNEL_KEY

    install_pingtunnel
    create_service
    show_final_info
}

main
