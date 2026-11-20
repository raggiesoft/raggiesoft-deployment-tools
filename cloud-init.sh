#cloud-config
# ==============================================================================
# ARCHITECTURAL BLOCK: CLAIRE - INFRASTRUCTURE ARCHITECT (cloud-init.sh)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Despite the `.sh` filename, this file is actually a **Cloud-Init YAML
#   blueprint**! When you spin up a brand-new Ubuntu Linux server ("Droplet") on
#   DigitalOcean, you paste this file into the "User Data" box. On the server's
#   very first boot, Ubuntu's built-in `cloud-init` daemon sees `#cloud-config`
#   on Line 1, Column 1 (just like a `#!/bin/bash` shebang!) and automatically:
#     1. Creates the non-root admin user `michael` with Ed25519 SSH keys and
#        locks out direct `root` SSH logins (`disable_root: true`).
#     2. Writes initial Nginx virtual-host configs, an initial Sarah deployment
#        script, and Linux `systemd` background timer units (`sarah.service` +
#        `sarah.timer`) onto disk using YAML `write_files:` literal blocks (`|`).
#     3. Runs `runcmd:` shell commands in order: installs Nginx + PHP 8.5-FPM +
#        Git + UFW firewall, opens ports 22 (SSH) & 80/443 (HTTP/HTTPS), generates
#        temporary bootstrap TLS certs, clones `raggiesoft-hub`, and starts
#        `sarah.timer` so the server updates itself every 5 minutes!
#
# HOW YAML `content: |` WORKS:
#   In YAML, a vertical bar `|` starts a **literal block scalar**—every indented
#   line underneath is written verbatim (newlines preserved) into the target file
#   specified by `path:`.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. THE GUEST LIST (`users:` & SSH Hardening)
# ------------------------------------------------------------------------------
# Defines the Linux user accounts provisioned on first boot.
users:
  - name: michael
    # Add `michael` to the `sudo` group for administrative tasks
    groups: sudo
    # Set default interactive login shell to GNU Bash
    shell: /bin/bash
    # `NOPASSWD:ALL` allows non-interactive automation (`install-subdomains.sh`,
    # `sarah-deploy.sh` `sudo -n nginx -t`) to validate/reload Nginx without hanging on a password prompt
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    # Public Ed25519 SSH keys (`~/.ssh/authorized_keys`)—only holders of the matching
    # private keys on these 3 workstations can SSH into the Droplet!
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbI2in/zZldj7MeeCqnYItZzGX8AEEi6FAvmTWbJnF0 michael@windows-desktop-tower
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBTirNBbMwmqi6bnlz0PCQMYBb0NRDH/rqMVvjuCEqG M2 MacBook Air
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHUAlAKsdD9d1tT4dmYt8gSqyErOYiEMpbM3zDVTjSZg michael@hp-laptop

# Security best practice: block brute-force bots from logging in as `root` over SSH
disable_root: true

# ------------------------------------------------------------------------------
# 2. HOUSEKEEPING (`apt` Package Index Refresh)
# ------------------------------------------------------------------------------
# Refresh Ubuntu's package catalog (`apt-get update`) before `runcmd` runs.
package_update: true
# Skip full kernel/OS `apt-get upgrade` on first boot so initial provisioning stays fast and deterministic.
package_upgrade: false

# ------------------------------------------------------------------------------
# 3. FILE INJECTION (`write_files:` — Written BEFORE `runcmd:` Executes)
# ------------------------------------------------------------------------------
# Cloud-init writes each item in `write_files` to `path` with exact Unix `owner`
# and octal `permissions` (`0644` = rw-r--r--, `0755` = rwxr-xr-x executable).
write_files:
  # --------------------------------------------------------------------------
  # -> NGINX GATEWAY (`/etc/nginx/sites-available/raggiesoft.com.conf`)
  # --------------------------------------------------------------------------
  # Reverse-proxy & FastCGI gateway routing dynamic requests through PHP-FPM 8.5 (`amanda/elara.php`).
  - path: /etc/nginx/sites-available/raggiesoft.com.conf
    owner: root:root
    permissions: '0644'
    content: |
      # Primary HTTPS server block (Port 443 TLS)
      server {
          server_name raggiesoft.com www.raggiesoft.com;
          root /var/www/raggiesoft.com;

          # Access and error logging configuration
          access_log /var/log/nginx/raggiesoft_access.log;
          error_log /var/log/nginx/raggiesoft_error.log;

          # Default index routed through Elara (the PHP front-controller gateway; no public index.php)
          index amanda/elara.php;

          # Security: Deny HTTP access to hidden dotfiles (`.git`, `.env`, `.htaccess`)
          location ~ /\. {
              deny all;
          }

          # Internal apps routing logic: allow specific PHP endpoints under `/includes/components/apps/`
          location ^~ /includes/components/apps/ {
              try_files $uri $uri/ =404;
              location ~ \.php$ {
                  include snippets/fastcgi-php.conf;
                  fastcgi_pass unix:/var/run/php/php8.5-fpm.sock;
                  fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                  include fastcgi_params;
              }
          }

          # Security: Block direct browser access to internal PHP partial templates (`/includes/`)
          location ^~ /includes/ {
              deny all;
              return 404;
          }

          # Static image 30-day browser caching (`expires 30d`) + Referer hotlink protection
          # across all 9 verified Michael P. Ragsdale domains and major search engines
          location ~* \.(gif|png|jpe?g|svg|webp|ico)$ {
              valid_referers none blocked server_names 
                             *.raggiesoft.com
                             *.michaelpragsdale.com michaelpragsdale.com
                             *.engineroom-records.com engineroom-records.com
                             *.thestardustengine.com thestardustengine.com
                             *.fracturedprisms.com fracturedprisms.com
                             *.aethelsaga.com aethelsaga.com
                             *.raggiesoftknox.com raggiesoftknox.com
                             *.raggiesoftmedia.com raggiesoftmedia.com
                             *.stardustenginecms.com stardustenginecms.com
                             ~*\.google\. ~*\.bing\. ~*\.yahoo\. ~*\.duckduckgo\. ~*\.yandex\.
                             ~*\.ask\. ~*\.lycos\. ~*\.altavista\.;
              if ($invalid_referer) {
                  return 302 https://assets.raggiesoft.com/common/images/no-hotlink.jpg;
              }
              expires 30d;
              add_header Cache-Control "public, no-transform";
              try_files $uri $uri/ =404;
          }

          # Primary front-controller fallback: serve static file if present, else route URL to `elara.php`
          location / {
              try_files $uri $uri/ /amanda/elara.php?$query_string;
          }

          # Global PHP execution via Unix domain socket (`php8.5-fpm.sock`)
          location ~ \.php$ {
              include snippets/fastcgi-php.conf;
              fastcgi_pass unix:/var/run/php/php8.5-fpm.sock;
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              include fastcgi_params;
          }

          # Custom error pages mapped to Amanda's branded PHP error views
          error_page 403 /amanda/errors/403.php;
          error_page 404 /amanda/errors/404.php;
          error_page 500 /amanda/errors/500.php;
          error_page 502 /amanda/errors/502.php;
          error_page 503 /amanda/errors/503.php;
          error_page 504 /amanda/errors/504.php;

          # `internal;` ensures users cannot visit `/amanda/errors/500.php` directly in a browser
          location ^~ /amanda/errors/ {
              internal; 
          }

          # TLS 1.2 / 1.3 Configuration (Port 443)
          listen 443 ssl; 
          ssl_certificate /etc/nginx/ssl/raggiesoft.pem; 
          ssl_certificate_key /etc/nginx/ssl/raggiesoft.key; 
          ssl_protocols TLSv1.2 TLSv1.3;
          ssl_ciphers HIGH:!aNULL:!MD5;
      }

      # HTTP (Port 80) -> Permanent `301` Redirect to HTTPS (Port 443)
      server {
          if ($host = www.raggiesoft.com) {
              return 301 https://$host$request_uri;
          } 
          if ($host = raggiesoft.com) {
              return 301 https://$host$request_uri;
          } 
          listen 80;
          server_name raggiesoft.com www.raggiesoft.com;
          return 404; 
      }

  # --------------------------------------------------------------------------
  # -> SARAH'S INITIAL BOOTSTRAP DEPLOYMENT SCRIPT (`/opt/sarah-deploy.sh`)
  # --------------------------------------------------------------------------
  # Initial single-hub bootstrap edition laid down before `raggiesoft-deployment-tools`
  # is cloned into `/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh` (v5.0).
  - path: /opt/sarah-deploy.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/bin/bash
      
      # --- SARAH: AUTONOMOUS DEPLOYMENT (v4.1 - Systemd Edition) ---
      
      # 0. ROOT PRIVILEGE CHECK (`$EUID -eq 0` detects `root` / `sudo`)
      # Sarah operates strictly as unprivileged user `michael` so web files are never root-owned.
      if [ "$EUID" -eq 0 ]; then
          echo "[!] SARAH: WHAT ARE YOU DOING?! I explicitly told you I do not need root!"
          echo "    ABORTING: Drop the sudo and let me do my job."
          exit 1
      fi
      
      # 1. CONFIGURATION
      REPO_DIR="/home/michael/raggiesoft-hub"
      WEB_ROOT="/var/www/raggiesoft.com"
      
      # 2. THE INTELLIGENCE CHECK (Compare Git Commit Hashes)
      cd "$REPO_DIR" || exit
      git fetch origin main
      
      LOCAL=$(git rev-parse HEAD)
      REMOTE=$(git rev-parse origin/main)
      
      # Fast no-op exit when GitHub hasn't received any new commits since last check
      if [ "$LOCAL" == "$REMOTE" ]; then
          exit 0
      fi
      
      # 3. CHANGES DETECTED
      echo "[i] SARAH: Change detected! Jenna pushed updates."
      echo "    Previous: $LOCAL"
      echo "    New:      $REMOTE"
      git reset --hard origin/main
      
      # 4. DEPLOY (Standard User Mode - No Sudo)
      echo "[i] SARAH: Syncing files to Showroom..."
      rsync -av --delete --no-o --no-g \
          --exclude '.git' \
          --exclude '.gitignore' \
          --exclude 'deploy.sh' \
          --exclude 'README.md' \
          "$REPO_DIR/" "$WEB_ROOT/"
      
      # 5. PERMISSIONS (755 for traversable directories, 644 for readable files)
      echo "[i] SARAH: Standardizing file permissions..."
      find "$WEB_ROOT" -type d -exec chmod 755 {} +
      find "$WEB_ROOT" -type f -exec chmod 644 {} +
      
      echo "[*] SARAH: Deployment Complete at $(date)"

  # --------------------------------------------------------------------------
  # -> SARAH'S SYSTEMD SERVICE (`/etc/systemd/system/sarah.service`)
  # --------------------------------------------------------------------------
  # Modern Linux alternative to legacy `crontab`: a `Type=oneshot` systemd unit
  # that runs `/home/michael/sarah-deploy.sh` strictly as `User=michael` and logs
  # every run automatically to `journalctl -u sarah.service`!
  - path: /etc/systemd/system/sarah.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Sarah Autonomous Deployment Service
      After=network.target

      [Service]
      Type=oneshot
      # Execute as standard user `michael`, satisfying Sarah's `$EUID -eq 0` non-root guard
      User=michael
      Group=michael
      ExecStart=/home/michael/sarah-deploy.sh

  # --------------------------------------------------------------------------
  # -> SARAH'S SYSTEMD TIMER (`/etc/systemd/system/sarah.timer`)
  # --------------------------------------------------------------------------
  # Companion systemd timer that triggers `sarah.service` 5 minutes after boot
  # and every 5 minutes thereafter (`OnUnitActiveSec=5min`).
  - path: /etc/systemd/system/sarah.timer
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Run Sarah Deployment Script every 5 minutes

      [Timer]
      # First run 5 minutes after server boot
      OnBootSec=5min
      # Repeat 5 minutes after each previous run finishes
      OnUnitActiveSec=5min
      # Prevent systemd from coalescing/delaying the 5-minute tick by up to 1 minute
      AccuracySec=1s

      [Install]
      WantedBy=timers.target

# ------------------------------------------------------------------------------
# 4. EXECUTION SEQUENCE (`runcmd:` — Runs Once on Initial Droplet Boot)
# ------------------------------------------------------------------------------
# Each `- ...` item runs sequentially as `root` after `write_files:` completes.
runcmd:
  # 1. Install Core Web Stack (Nginx, PHP 8.5 FPM + CLI extensions, Python 3 for Sarah's minifier & IndexNow, Git, jq, UFW firewall)
  - apt-get update -y
  - apt-get install -y nginx php-fpm php-cli php-common php-xml php-curl php-mbstring php-zip python3 unzip curl git jq ufw
  
  # 2. Harden UFW (Uncomplicated Firewall): deny all inbound ports except SSH (22) and HTTP/HTTPS (80/443)
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow OpenSSH
  - ufw allow "Nginx Full"
  - ufw --force enable
  
  # 3. Provision initial `/var/www/raggiesoft.com` directory owned by `michael` and a temporary health-check gateway
  - mkdir -p /var/www/raggiesoft.com/amanda/errors
  - chown -R michael:michael /var/www/raggiesoft.com
  - chmod -R 755 /var/www/raggiesoft.com
  - echo "<?php echo 'Elara Gateway 5.7 Initialized. Awaiting Sarah deployment.'; ?>" > /var/www/raggiesoft.com/amanda/elara.php
  
  # 4. Generate temporary self-signed X.509 SSL certificate so `nginx` can start on Port 443 immediately
  #    before Cloudflare Origin / Let's Encrypt certificates are installed
  - mkdir -p /etc/nginx/ssl
  - openssl req -x509 -nodes -days 30 -newkey rsa:2048 -keyout /etc/nginx/ssl/raggiesoft.key -out /etc/nginx/ssl/raggiesoft.pem -subj "/CN=raggiesoft.com"
  
  # 5. Enable our Nginx virtual host by symlinking `sites-available` -> `sites-enabled` and removing `default`
  - rm -f /etc/nginx/sites-enabled/default
  - ln -s /etc/nginx/sites-available/raggiesoft.com.conf /etc/nginx/sites-enabled/
  
  # 6. Register and start `sarah.timer` in systemd (`daemon-reload` reads our newly injected unit files)
  - systemctl daemon-reload
  - systemctl enable sarah.timer
  - systemctl start sarah.timer
  
  # 7. Restart and enable PHP 8.5-FPM and Nginx across reboots
  - systemctl restart php8.5-fpm
  - systemctl enable php8.5-fpm
  - systemctl restart nginx
  - systemctl enable nginx

  # 8. Clone `raggiesoft-hub` as user `michael` (`sudo -u michael` avoids creating root-owned `.git` files)
  - sudo -u michael git clone https://github.com/raggiesoft/raggiesoft-hub.git /home/michael/raggiesoft-hub

  # 9. Trigger the very first deployment immediately instead of waiting 5 minutes for `sarah.timer`
  - systemctl start sarah.service