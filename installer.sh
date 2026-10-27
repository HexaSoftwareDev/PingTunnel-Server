#!/bin/bash

set -e

# Fixed PingTunnel version
VERSION="2.8"

# Detect OS
get_os() {
    os=$(uname | tr '[:upper:]' '[:lower:]')
    case "$os" in
        linux|darwin|freebsd|dragonfly|illumos|aix) echo "$os" ;;
        *) echo "Unsupported OS: $os" >&2; exit 1 ;;
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
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
    esac
}

# Ensure unzip is available
ensure_unzip() {
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Installing unzip..."

        if command -v apt-get >/dev/null 2>&1; then
            apt-get update
            apt-get install -y unzip
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y unzip
        elif command -v yum >/dev/null 2>&1; then
            yum install -y unzip
        else
            echo "❌ Please install unzip manually."
            exit 1
        fi
    fi
}

# Install PingTunnel v2.8
install_pingtunnel() {
    OS=$(get_os)
    ARCH=$(get_arch)

    FILE="pingtunnel_${OS}_${ARCH}.zip"
    URL="https://github.com/esrrhs/pingtunnel/releases/download/${VERSION}/${FILE}"

    echo "--------------------------------"
    echo "Installing PingTunnel v${VERSION}"
    echo "Detected OS: $OS"
    echo "Detected Architecture: $ARCH"
    echo "--------------------------------"

    ensure_unzip

    mkdir -p /opt/pingtunnel
    cd /opt/pingtunnel

    echo "Downloading: $URL"

    if ! curl -fL --retry 3 -o "$FILE" "$URL"; then
        echo "❌ Failed to download PingTunnel v${VERSION}"
        exit 1
    fi

    echo "Extracting PingTunnel..."

    if ! unzip -o "$FILE"; then
        echo "❌ Failed to extract $FILE"
        exit 1
    fi

    if [ ! -f pingtunnel ]; then
        echo "❌ PingTunnel binary not found after extraction."
        exit 1
    fi

    chmod +x pingtunnel
    rm -f "$FILE"

    echo "✅ PingTunnel v${VERSION} installed successfully."
}

# Create systemd service
create_service() {
    echo "Creating systemd service..."

    cat <<EOF > /etc/systemd/system/pingtunnel.service
[Unit]
Description=PingTunnel Server v${VERSION}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/pingtunnel
ExecStart=/opt/pingtunnel/pingtunnel -type server -key ${PINGTUNNEL_KEY}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable pingtunnel
    systemctl restart pingtunnel

    if systemctl is-active --quiet pingtunnel; then
        echo "✅ PingTunnel service is running."
    else
        echo "❌ PingTunnel service failed to start."
        systemctl status pingtunnel --no-pager || true
        exit 1
    fi
}

# Show installation information
show_final_info() {
    SERVER_IP=$(curl -fsS --max-time 10 https://api.ipify.org || echo "Unknown")

    echo ""
    echo "================================"
    echo "✅ PingTunnel Installation Complete"
    echo "================================"
    echo "Version   : ${VERSION}"
    echo "Server IP : ${SERVER_IP}"
    echo "Password  : ${PINGTUNNEL_KEY}"
    echo "Service   : pingtunnel"
    echo "Status    : $(systemctl is-active pingtunnel)"
    echo "================================"
    echo ""
    echo "Useful commands:"
    echo "  systemctl status pingtunnel"
    echo "  systemctl restart pingtunnel"
    echo "  systemctl stop pingtunnel"
    echo "  journalctl -u pingtunnel -f"
    echo ""
}

# Main function
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ Please run this script as root (use sudo)."
        exit 1
    fi

    # systemd is required
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "❌ This installer requires systemd."
        exit 1
    fi

    # Check curl
    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ curl is required. Please install curl first."
        exit 1
    fi

    # Prompt user for PingTunnel key
    while true; do
        read -r -p "Enter a Password (Key) for PingTunnel (-key, numbers only): " PINGTUNNEL_KEY

        if [[ "$PINGTUNNEL_KEY" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "❌ Please enter numbers only."
        fi
    done

    install_pingtunnel
    create_service
    show_final_info
}

main
