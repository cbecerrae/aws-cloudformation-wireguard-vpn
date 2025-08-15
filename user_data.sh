#!/bin/bash
set -xe

# Update package lists and install required packages
apt update
apt install -y wireguard awscli jq

# Generate server keys
wg genkey | tee /etc/wireguard/private.key
chmod 600 /etc/wireguard/private.key
cat /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key

# Determine primary network interface for NAT
PRIMARY_IF=$(ip r | grep '^default' | awk '{print $5}')

# Create base wg0.conf configuration with inline comments
echo "[Interface]" > /etc/wireguard/wg0.conf
echo "# Private key generated on the EC2 instance" >> /etc/wireguard/wg0.conf
echo "PrivateKey = $(cat /etc/wireguard/private.key)" >> /etc/wireguard/wg0.conf
echo "# IP address assigned to the EC2 instance within the VPN" >> /etc/wireguard/wg0.conf
echo "Address = ${VPN_CIDR%.*}.1/32" >> /etc/wireguard/wg0.conf
echo "# Port WireGuard will listen on" >> /etc/wireguard/wg0.conf
echo "ListenPort = ${PORT}" >> /etc/wireguard/wg0.conf
echo "# Traffic masquerading rules for PostUp and PostDown" >> /etc/wireguard/wg0.conf
echo "PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE" >> /etc/wireguard/wg0.conf
echo "PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $PRIMARY_IF -j MASQUERADE" >> /etc/wireguard/wg0.conf

# Process client configurations
IFS=',' read -ra CLIENTS <<< "$CLIENT_CONFIG"
declare -A CLIENTS_MAP
CLIENTS_JSON="{}"   # Initialize as empty JSON object
ip_index=2

for entry in "${CLIENTS[@]}"; do
  alias=$(echo "$entry" | cut -d':' -f1)
  pubkey=$(echo "$entry" | cut -d':' -f2)

  # Assign IP address to client
  client_ip="${VPN_CIDR%.*}.${ip_index}/32"
  CLIENTS_MAP["$alias"]="$client_ip"

  # Append client peer configuration to wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "[Peer]" >> /etc/wireguard/wg0.conf
  echo "# Public key generated for Client ${alias}" >> /etc/wireguard/wg0.conf
  echo "PublicKey = ${pubkey}" >> /etc/wireguard/wg0.conf
  echo "# IP address assigned to Client ${alias} within VPN" >> /etc/wireguard/wg0.conf
  echo "AllowedIPs = ${client_ip}" >> /etc/wireguard/wg0.conf

  # Add client to JSON object
  CLIENTS_JSON=$(echo "$CLIENTS_JSON" | jq --arg a "$alias" --arg ip "$client_ip" '. + {($a): $ip}')

  ((ip_index++))
done

# Secure wg0.conf file
sudo chmod 600 /etc/wireguard/wg0.conf
# Enable IPv4 forwarding
sudo sed -i 's/^#\(net.ipv4.ip_forward=1\)/\1/' /etc/sysctl.conf
sudo sysctl -p
# Enable and start WireGuard service
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0

# Extract public key for signaling
PUBKEY=$(cat /etc/wireguard/public.key)

# Prepare final JSON with server public key and client addresses
JSON=$(jq -n --arg pk "$PUBKEY" --argjson ca "$CLIENTS_JSON" \
          '{publicKey:$pk, clientsAddresses:$ca}')

# Encode JSON to base64
ENCODED_JSON=$(echo "$JSON" | base64 -w0)

# Send success signal to WaitConditionHandle
curl -X PUT -H 'Content-Type:' \
  --data-binary "{\"Status\":\"SUCCESS\",\"Reason\":\"WireGuard ready\",\"UniqueId\":\"WireGuardConfig\",\"Data\":\"$ENCODED_JSON\"}" \
  "${WAIT_HANDLE}"
