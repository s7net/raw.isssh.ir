#!/bin/bash
set -e

echo "[+] Installing Docker using proxy"

DOCKER_BASE="https://download-docker.isssh.ir"

echo "[+] Using Docker base URL: $DOCKER_BASE"

for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y $pkg >/dev/null 2>&1 || true
done

apt-get update
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings

curl -fsSL "$DOCKER_BASE/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  $DOCKER_BASE/linux/$ID \
  $VERSION_CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update

apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

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

systemctl restart docker

echo "[✓] Docker installed successfully"
docker --version
