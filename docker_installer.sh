#!/bin/bash
set -e

# ---------- Safety checks ----------
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root"
  exit 1
fi

command -v systemctl >/dev/null || {
  echo "[!] systemd not found"
  exit 1
}

# ---------- Logging ----------
LOG_FILE="/var/log/docker-install.log"
exec > >(tee -i "$LOG_FILE")
exec 2>&1

echo "[+] Docker installation started"

# ---------- Proxy base ----------
DOCKER_BASE="https://download-docker.isssh.ir"
DOCKER_GPG_FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"

echo "[+] Using Docker proxy: $DOCKER_BASE"

# ---------- Detect OS ----------
. /etc/os-release

# ---------- Debian / Ubuntu ----------
install_debian() {
  echo "[+] Detected Debian/Ubuntu"

  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y $pkg >/dev/null 2>&1 || true
  done

  apt-get update
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings

  echo "[+] Downloading Docker GPG key"
  curl -fsSL --retry 5 --retry-delay 2 \
    "$DOCKER_BASE/linux/$ID/gpg" \
    -o /etc/apt/keyrings/docker.asc

  chmod a+r /etc/apt/keyrings/docker.asc

  echo "[+] Verifying Docker GPG key"
  gpg --show-keys /etc/apt/keyrings/docker.asc | \
    grep -q "$DOCKER_GPG_FINGERPRINT" || {
      echo "[!] Invalid Docker GPG key"
      exit 1
    }

  echo "[+] Adding Docker repository"
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    $DOCKER_BASE/linux/$ID \
    $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update

  apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  # Optional: prevent containerd mismatch
  apt-mark hold containerd.io || true
}

# ---------- RHEL / CentOS / Alma / Rocky ----------
install_rhel() {
  echo "[+] Detected RHEL-based system"

  yum remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

  yum install -y yum-utils curl

  yum-config-manager --add-repo \
    "$DOCKER_BASE/linux/centos/docker-ce.repo"

  yum install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
}

# ---------- Amazon Linux ----------
install_amazon() {
  echo "[+] Detected Amazon Linux"

  yum remove -y docker || true
  yum install -y docker
}

# ---------- Install ----------
case "$ID" in
  ubuntu|debian)
    install_debian
    ;;
  centos|rhel|almalinux|rocky)
    install_rhel
    ;;
  amzn)
    install_amazon
    ;;
  *)
    echo "[!] Unsupported distribution: $ID"
    exit 1
    ;;
esac

# ---------- Docker registry mirrors (Iran only) ----------
echo "[+] Configuring Docker registry mirrors"

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.arvancloud.ir",
    "https://focker.ir",
    "https://registry.docker.ir",
    "https://docker.iranserver.com",
    "https://docker.haiocloud.com"
  ]
}
EOF

systemctl enable docker
systemctl restart docker

echo "[✓] Docker installed successfully"
docker --version
echo "[✓] Logs saved to $LOG_FILE"
