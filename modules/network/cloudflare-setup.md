# Cloudflare Tunnel Setup

Cloudflare Tunnel routes all web traffic through an encrypted outbound connection.
No inbound ports 80/443 needed. Zero-trust networking.

## Prerequisites

- Cloudflare account (free)
- Domain DNS managed by Cloudflare (nameservers pointing to Cloudflare)

## Setup steps

### 1. Install cloudflared

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
cloudflared --version
```

### 2. Authenticate

```bash
cloudflared tunnel login
```

Opens a URL — visit it in your browser and select your domain.

### 3. Create tunnel

```bash
cloudflared tunnel create actools-YOUR_DOMAIN
```

Note the tunnel ID printed. Credentials written to `~/.cloudflared/TUNNEL_ID.json`.

### 4. Configure

```bash
sudo mkdir -p /etc/cloudflared
sudo cp modules/network/cloudflared-config.yml.example /etc/cloudflared/config.yml
sudo nano /etc/cloudflared/config.yml
# Replace YOUR_TUNNEL_ID and YOUR_DOMAIN
```

### 5. Route DNS

```bash
cloudflared tunnel route dns actools-YOUR_DOMAIN YOUR_DOMAIN
cloudflared tunnel route dns actools-YOUR_DOMAIN www.YOUR_DOMAIN
```

If A records exist, delete them in Cloudflare DNS dashboard first.

### 6. Install systemd service

```bash
sudo cp modules/network/cloudflared.service /etc/systemd/system/cloudflared.service
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
sudo systemctl status cloudflared
```

### 7. Verify then close inbound ports

```bash
# Verify tunnel is working first
actools tunnel status
curl -I https://YOUR_DOMAIN

# Then close inbound ports — SSH stays open
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp
sudo ufw delete allow 443/udp
sudo ufw status numbered
```

## CLI

```bash
actools tunnel status    # tunnel health + connection count
actools tunnel restart   # restart the systemd service
actools tunnel logs      # last 50 lines of tunnel logs
```

## Notes

- Credentials JSON (`TUNNEL_ID.json`) is never committed to git
- `cert.pem` is never committed to git
- The `.cloudflared/` directory is in `.gitignore`

## TLS posture when using Cloudflare Tunnel

The standard install assumes ports 80 and 443 are open and Caddy issues
TLS certificates via Let's Encrypt's HTTP-01 challenge. When you put the
server behind a Cloudflare tunnel and close those ports, the HTTP-01
challenge can no longer reach Caddy — certificates will fail to renew
after ~90 days.

Choose one of these patterns when running under a tunnel:

**Option 1 — DNS-01 challenge via Cloudflare API**

Caddy can prove domain control by setting DNS TXT records via the
Cloudflare API, with no inbound port required.

1. Create a Cloudflare API token with `Zone:DNS:Edit` permission for your
   domain
2. Set `CADDY_CLOUDFLARE_TOKEN` in `actools.env`
3. Caddy will use DNS-01 automatically when this token is set

**Option 2 — Cloudflare Origin Certificate with `tls internal`**

Generate a free 15-year origin certificate from the Cloudflare dashboard
and configure Caddy to use it directly.

1. Cloudflare Dashboard → SSL/TLS → Origin Server → Create Certificate
2. Save the certificate and key to `certs/cloudflare-origin/`
3. Adjust the Caddyfile to use those certs instead of ACME

Both options keep Caddy as the TLS terminator on the inside of the tunnel.
Pick the one that fits your operational comfort.
