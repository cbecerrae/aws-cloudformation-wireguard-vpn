#!/bin/bash
set -xe

# Generate server keys
[ ! -f /etc/wireguard/private.key ] && wg genkey | tee /etc/wireguard/private.key
chmod 600 /etc/wireguard/private.key
[ ! -f /etc/wireguard/public.key ] && cat /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key

# Determine primary network interface for NAT
PRIMARY_IF=$(ip r | grep '^default' | awk '{print $5}')

# Create base wg0.conf configuration with inline comments
echo "[Interface]" > /etc/wireguard/wg0.conf
echo "# Private key generated on the EC2 instance" >> /etc/wireguard/wg0.conf
echo "PrivateKey = $(cat /etc/wireguard/private.key)" >> /etc/wireguard/wg0.conf
echo "# IP address assigned to the EC2 instance within the VPN" >> /etc/wireguard/wg0.conf
echo "Address = ${VPN_CIDR%.*}.254/32" >> /etc/wireguard/wg0.conf
echo "# Port WireGuard will listen on" >> /etc/wireguard/wg0.conf
echo "ListenPort = ${PORT}" >> /etc/wireguard/wg0.conf
echo "# Traffic masquerading rules for PostUp and PostDown" >> /etc/wireguard/wg0.conf
echo "PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE" >> /etc/wireguard/wg0.conf
echo "PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $PRIMARY_IF -j MASQUERADE" >> /etc/wireguard/wg0.conf

# Process client configurations
IFS=',' read -ra CLIENTS <<< "$CLIENT_CONFIG"

for entry in "${CLIENTS[@]}"; do
  number=$(echo "$entry" | cut -d':' -f1)
  alias=$(echo "$entry" | cut -d':' -f2)
  pubkey=$(echo "$entry" | cut -d':' -f3)

  # Assign IP address to client
  client_ip="${VPN_CIDR%.*}.${number}/32"

  # Append client peer configuration to wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "[Peer]" >> /etc/wireguard/wg0.conf
  echo "# Public key generated for Client ${number} ${alias}" >> /etc/wireguard/wg0.conf
  echo "PublicKey = ${pubkey}" >> /etc/wireguard/wg0.conf
  echo "# IP address assigned to Client ${number} ${alias} within VPN" >> /etc/wireguard/wg0.conf
  echo "AllowedIPs = ${client_ip}" >> /etc/wireguard/wg0.conf

done

# Secure wg0.conf file
sudo chmod 600 /etc/wireguard/wg0.conf

# Enable IPv4 forwarding
sudo sed -i 's/^#\(net.ipv4.ip_forward=1\)/\1/' /etc/sysctl.conf
sudo sysctl -p

# Restart WireGuard service
sudo systemctl restart wg-quick@wg0

# Extract public key for signaling
PUBKEY=$(cat /etc/wireguard/public.key)

# Send success signal to WaitConditionHandle
curl -X PUT -H 'Content-Type:' \
  --data-binary "{\"Status\":\"SUCCESS\",\"Reason\":\"WireGuard ready\",\"UniqueId\":\"WireGuardConfig\",\"Data\":\"$PUBKEY\"}" \
  "${WAIT_HANDLE}"
