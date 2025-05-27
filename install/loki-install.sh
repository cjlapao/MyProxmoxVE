#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: Carlos Lapao (cjlapao)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://grafana.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl unzip
msg_ok "Installed Dependencies"

msg_info "Creating Loki user"
useradd --no-create-home --system --shell /usr/sbin/nologin loki
msg_ok "Created Loki user"

msg_info "Downloading Loki and extracting"
LATEST_VERSION=$(curl -s https://api.github.com/repos/grafana/loki/releases/latest | grep -oP '"tag_name": "\K[^"]+')
$STD curl -LO https://github.com/grafana/loki/releases/latest/download/loki-linux-amd64.zip
$STD unzip loki-linux-amd64.zip
$STD chmod +x loki-linux-amd64
$STD mv loki-linux-amd64 /usr/local/bin/loki
$STD rm loki-linux-amd64.zip

msg_ok "Downloaded and extracted Loki"

read -p "Do you want to use Azure Blob Storage? (y/n): " USE_AZURE
if [ "$USE_AZURE" == "y" ]; then
  read -p "Enter your Azure Blob Storage Account Key: " AZURE_ACCOUNT_KEY
  read -p "Enter your Azure Blob Storage Account Name: " AZURE_ACCOUNT_NAME
  read -p "Enter your Azure Blob Storage Container Name: " AZURE_CONTAINER_NAME
fi
read -p "How many days of data do you want to keep (in hours)? (default: 0): " RETENTION_HOURS
if [ -z "$RETENTION_HOURS" ]; then
  RETENTION_HOURS=0
fi

msg_info "Creating Loki configuration"
$STD mkdir -p /etc/loki /var/lib/loki
$STD touch /etc/loki/loki-config.yaml

if [ "$USE_AZURE" == "y" ]; then
  STORAGE_TYPE="azure"
else
  STORAGE_TYPE="filesystem"
fi
if [ "$RETENTION_HOURS" == "0" ]; then
  RETENTION_HOURS="0s"
else
  RETENTION_HOURS="${RETENTION_HOURS}h"
fi

$STD cat <<EOF >/etc/loki/loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  log_level: info

ingester:
  wal:
    dir: /var/lib/loki/wal
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2023-01-01
      store: tsdb
      object_store: ${STORAGE_TYPE}
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  azure:
    account_name: ${AZURE_ACCOUNT_NAME}
    account_key: ${AZURE_ACCOUNT_KEY}
    container_name: ${AZURE_CONTAINER_NAME}
  filesystem:
    directory: /var/lib/loki/chunks  
  tsdb_shipper:
    active_index_directory: /var/lib/loki/index
    cache_location: /var/lib/loki/cache

compactor:
  working_directory: /data/retention
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
  delete_request_store: ${STORAGE_TYPE}

query_scheduler:
  max_outstanding_requests_per_tenant: 32768
querier:
  max_concurrent: 16
limits_config:
  retention_period: ${RETENTION_HOURS}
  max_query_lookback: ${RETENTION_HOURS}
  reject_old_samples: true
  reject_old_samples_max_age: 168h
EOF
$STD chown -R loki:loki /var/lib/loki
$STD chown -R loki:loki /etc/loki

msg_ok "Created Loki configuration"

msg_info "Creating Loki service"
$STD cat <<EOF >/etc/systemd/system/loki.service
[Unit]
Description=Loki Log Aggregator
After=network.target

[Service]
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Loki service"

msg_info "Starting Loki"
$STD systemctl daemon-reexec
$STD systemctl daemon-reload
$STD systemctl enable loki
$STD systemctl start loki
msg_ok "Started Loki"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
