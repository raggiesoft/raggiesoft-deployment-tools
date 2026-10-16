#cloud-config

# ==============================================================================
# ARCHITECTURAL BLOCK: CLAIRE - INFRASTRUCTURE ARCHITECT
# ==============================================================================
# This cloud-config YAML file provisions the foundational infrastructure for 
# the RaggieSoft environment. It is processed by cloud-init upon initial 
# instance boot. 
# 
# Key Responsibilities:
# 1. User Provisioning (Creating the `michael` admin user with SSH keys).
# 2. System Housekeeping (Package updates).
# 3. File Injection (Deploying Nginx configs, Deployment scripts, Systemd units).
# 4. Execution Sequence (Installing software, configuring firewall, setting up 
#    the web directory, and bootstrapping the `sarah` deployment service).
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. THE GUEST LIST
# ------------------------------------------------------------------------------
# Defines the system users, their access levels, and authentication methods.
users:
  - name: michael
    # Grant sudo privileges
    groups: sudo
    # Define default shell as bash
    shell: /bin/bash
    # Allow passwordless sudo for automation ease
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    # Inject authorized SSH keys for remote access from multiple devices
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbI2in/zZldj7MeeCqnYItZzGX8AEEi6FAvmTWbJnF0 michael@windows-desktop-tower
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBTirNBbMwmqi6bnlz0PCQMYBb0NRDH/rqMVvjuCEqG M2 MacBook Air
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHUAlAKsdD9d1tT4dmYt8gSqyErOYiEMpbM3zDVTjSZg michael@hp-laptop

# Disable root login over SSH to enforce using the specific admin user ('michael')
disable_root: true

# ------------------------------------------------------------------------------
# 2. HOUSEKEEPING
# ------------------------------------------------------------------------------
# Ensure package lists are up to date before installing any software.
package_update: true
# We skip package upgrades to avoid unexpected behavioral changes or downtime
# during initial provisioning.
package_upgrade: false

# ------------------------------------------------------------------------------
# 3. FILE INJECTION (The Blueprints)
# ------------------------------------------------------------------------------
# The `write_files` directive creates files on the filesystem prior to the 
# execution of commands. We use it to lay down configuration and scripts.
write_files:
  # --------------------------------------------------------------------------
  # -> NGINX GATEWAY
  # --------------------------------------------------------------------------
  # Creates the primary Nginx server block configuration for raggiesoft.com.
  - path: /etc/nginx/sites-available/raggiesoft.com.conf
    owner: root:root
    permissions: '0644'
    content: |
      # Primary HTTPS server block
      server {
          server_name raggiesoft.com www.raggiesoft.com;
          root /var/www/raggiesoft.com;

          # Access and error logging configuration
          access_log /var/log/nginx/raggiesoft_access.log;
          error_log /var/log/nginx/raggiesoft_error.log;

          # Default index routed through Elara (the gateway)
          index amanda/elara.php;

          # Security: Deny access to hidden files (e.g., .git, .env)
          location ~ /\. {
              deny all;
          }

          # Internal apps routing logic
          location ^~ /includes/components/apps/ {
              try_files $uri $uri/ =404;
              location ~ \.php$ {
                  include snippets/fastcgi-php.conf;
                  fastcgi_pass unix:/var/run/php/php8.5-fpm.sock;
                  fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                  include fastcgi_params;
              }
          }

          # Security: Block direct access to internal includes
          location ^~ /includes/ {
              deny all;
              return 404;
          }

          # Asset caching and hotlink protection
          location ~* \.(gif|png|jpe?g|svg|webp|ico)$ {
              valid_referers none blocked server_names 
                             *.raggiesoft.com raggiesoft.com 
                             *.engineroom-records.com engineroom-records.com
                             ~*\.google\. ~*\.bing\. ~*\.yahoo\. ~*\.duckduckgo\. ~*\.yandex\.
                             ~*\.ask\. ~*\.lycos\. ~*\.altavista\.;
              if ($invalid_referer) {
                  return 302 https://assets.raggiesoft.com/common/images/no-hotlink.jpg;
              }
              expires 30d;
              add_header Cache-Control "public, no-transform";
              try_files $uri $uri/ =404;
          }

          # Primary fallback routing: Send everything to Elara router if file not found
          location / {
              try_files $uri $uri/ /amanda/elara.php?$query_string;
          }

          # Global PHP execution logic
          location ~ \.php$ {
              include snippets/fastcgi-php.conf;
              fastcgi_pass unix:/var/run/php/php8.5-fpm.sock;
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              include fastcgi_params;
          }

          # Custom error pages mapped to Amanda's error handlers
          error_page 403 /amanda/errors/403.php;
          error_page 404 /amanda/errors/404.php;
          error_page 500 /amanda/errors/500.php;
          error_page 502 /amanda/errors/502.php;
          error_page 503 /amanda/errors/503.php;
          error_page 504 /amanda/errors/504.php;

          # Make error pages internal so they can't be accessed directly
          location ^~ /amanda/errors/ {
              internal; 
          }

          # SSL Configuration
          listen 443 ssl; 
          ssl_certificate /etc/nginx/ssl/raggiesoft.pem; 
          ssl_certificate_key /etc/nginx/ssl/raggiesoft.key; 
          ssl_protocols TLSv1.2 TLSv1.3;
          ssl_ciphers HIGH:!aNULL:!MD5;
      }

      # HTTP to HTTPS redirect server block
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
  # -> SARAH'S DEPLOYMENT SCRIPT (Staging Area)
  # --------------------------------------------------------------------------
  # A bash script representing "Sarah", an autonomous deployment agent.
  # It checks for updates in the central repository and rsyncs them to the webroot.
  - path: /opt/sarah-deploy.sh
    owner: root:root
    # Needs to be executable
    permissions: '0755'
    content: |
      #!/bin/bash
      
      # --- SARAH: AUTONOMOUS DEPLOYMENT (v4.1 - Systemd Edition) ---
      
      # 0. ROOT PRIVILEGE CHECK
      # Sarah operates in user space; root execution is blocked to enforce security boundaries.
      if [ "$EUID" -eq 0 ]; then
          echo "[!] SARAH: WHAT ARE YOU DOING?! I explicitly told you I do not need root!"
          echo "    ABORTING: Drop the sudo and let me do my job."
          exit 1
      fi
      
      # 1. CONFIGURATION
      # Define source repository and destination web root
      REPO_DIR="/home/michael/raggiesoft-hub"
      WEB_ROOT="/var/www/raggiesoft.com"
      
      # 2. THE INTELLIGENCE CHECK (Detect Changes)
      # Move to repository and fetch latest state from remote origin
      cd "$REPO_DIR" || exit
      git fetch origin main
      
      # Compare local HEAD with remote branch to detect updates
      LOCAL=$(git rev-parse HEAD)
      REMOTE=$(git rev-parse origin/main)
      
      # If no changes, exit gracefully without deploying
      if [ "$LOCAL" == "$REMOTE" ]; then
          exit 0
      fi
      
      # 3. CHANGES DETECTED
      echo "[i] SARAH: Change detected! Jenna pushed updates."
      echo "    Previous: $LOCAL"
      echo "    New:      $REMOTE"
      # Hard reset local to match remote state
      git reset --hard origin/main
      
      # 4. DEPLOY (Standard User Mode - No Sudo)
      # Synchronize repository contents to web root, excluding metadata and repo-only files
      echo "[i] SARAH: Syncing files to Showroom..."
      rsync -av --delete --no-o --no-g \
          --exclude '.git' \
          --exclude '.gitignore' \
          --exclude 'deploy.sh' \
          --exclude 'README.md' \
          "$REPO_DIR/" "$WEB_ROOT/"
      
      # 5. PERMISSIONS (Self-Correction)
      # Enforce standard web directory (755) and file (644) permissions
      echo "[i] SARAH: Standardizing file permissions..."
      find "$WEB_ROOT" -type d -exec chmod 755 {} +
      find "$WEB_ROOT" -type f -exec chmod 644 {} +
      
      echo "[*] SARAH: Deployment Complete at $(date)"

  # --------------------------------------------------------------------------
  # -> SARAH'S SYSTEMD SERVICE
  # --------------------------------------------------------------------------
  # Defines the Systemd service wrapper for the Sarah deployment script.
  - path: /etc/systemd/system/sarah.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Sarah Autonomous Deployment Service
      After=network.target

      [Service]
      Type=oneshot
      # Execute as the standard user, matching the script's root check
      User=michael
      Group=michael
      ExecStart=/home/michael/sarah-deploy.sh

  # --------------------------------------------------------------------------
  # -> SARAH'S SYSTEMD TIMER
  # --------------------------------------------------------------------------
  # Schedules the Sarah deployment service to run periodically (every 5 mins).
  - path: /etc/systemd/system/sarah.timer
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Run Sarah Deployment Script every 5 minutes

      [Timer]
      # Start timer 5 minutes after boot
      OnBootSec=5min
      # Trigger every 5 minutes thereafter
      OnUnitActiveSec=5min
      # Ensure high accuracy for scheduled execution
      AccuracySec=1s

      [Install]
      WantedBy=timers.target

# ------------------------------------------------------------------------------
# 4. EXECUTION SEQUENCE
# ------------------------------------------------------------------------------
# The runcmd block specifies arbitrary shell commands to run after write_files
# are created. This sets up dependencies, directories, and starts services.
runcmd:
  # 1. Install Core Software 
  # Note: Ubuntu 26.04 natively ships PHP 8.5. Install Nginx, PHP-FPM, Git, UFW, etc.
  - apt-get update -y
  - apt-get install -y nginx php-fpm php-cli php-common php-xml php-curl php-mbstring php-zip unzip curl git jq ufw
  
  # 2. Configure the UFW Firewall
  # Block incoming by default, allow outgoing. Whitelist SSH and Nginx traffic.
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow OpenSSH
  - ufw allow "Nginx Full"
  - ufw --force enable
  
  # 3. Set up the Web Directory Structure & Gateway File
  # Prepare webroot for deployment script and set permissions
  - mkdir -p /var/www/raggiesoft.com/amanda/errors
  - chown -R michael:michael /var/www/raggiesoft.com
  - chmod -R 755 /var/www/raggiesoft.com
  # Inject an initial placeholder gateway file so Nginx doesn't crash on start
  - echo "<?php echo 'Elara Gateway 5.7 Initialized. Awaiting Sarah deployment.'; ?>" > /var/www/raggiesoft.com/amanda/elara.php
  
  # 4. Create SSL Directory and Temporary Certs
  # Generate self-signed certs to allow Nginx to bind to port 443 during initialization
  - mkdir -p /etc/nginx/ssl
  - openssl req -x509 -nodes -days 30 -newkey rsa:2048 -keyout /etc/nginx/ssl/raggiesoft.key -out /etc/nginx/ssl/raggiesoft.pem -subj "/CN=raggiesoft.com"
  
  # 5. Activate the Nginx Configuration
  # Remove the default Ubuntu Nginx page and symlink our raggiesoft block
  - rm -f /etc/nginx/sites-enabled/default
  - ln -s /etc/nginx/sites-available/raggiesoft.com.conf /etc/nginx/sites-enabled/
  
  # 6. Activate Sarah's Systemd Timer
  # Reload systemd manager to pick up new timer/service units, then enable and start the timer
  - systemctl daemon-reload
  - systemctl enable sarah.timer
  - systemctl start sarah.timer
  
  # 7. Optimize and Restart Services
  # Restart and enable PHP-FPM and Nginx to ensure they apply the new configurations
  - systemctl restart php8.5-fpm
  - systemctl enable php8.5-fpm
  - systemctl restart nginx
  - systemctl enable nginx

  # 8. CLONE THE REPOSITORY (The Hand-off)
  # Clone the web application source code as the user 'michael'
  - sudo -u michael git clone https://github.com/raggiesoft/raggiesoft-hub.git /home/michael/raggiesoft-hub

  # 9. WAKE SARAH UP 
  # Manually trigger the first deployment run immediately rather than waiting 5 minutes
  - systemctl start sarah.service