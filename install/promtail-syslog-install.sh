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

msg_info "Creating Promtail user"
useradd --no-create-home --system --shell /usr/sbin/nologin promtail
msg_ok "Created Promtail user"

msg_info "Downloading Promtail and extracting"
$STD curl -LO https://github.com/grafana/loki/releases/latest/download/promtail-linux-amd64.zip
$STD unzip promtail-linux-amd64.zip
$STD chmod +x promtail-linux-amd64
$STD mv promtail-linux-amd64 /usr/local/bin/promtail
$STD rm promtail-linux-amd64.zip

msg_ok "Downloaded and extracted Promtail"

read -p "Enter the Loki server URL: " LOKI_SERVER_URL
if [ -z "$LOKI_SERVER_URL" ]; then
  LOKI_SERVER_URL="https://loki.homelab.local"
fi

msg_info "Creating Promtail configuration"
$STD mkdir -p /etc/promtail /var/lib/promtail
$STD touch /etc/promtail/promtail-config.yaml

$STD cat <<EOF >/etc/promtail/promtail-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /etc/promtail/positions.yaml

clients:
  - url: ${LOKI_SERVER_URL}/loki/api/v1/push
    tls_config:
      insecure_skip_verify: true

scrape_configs:
  - job_name: opnsense-syslog
    syslog:
      listen_address: 0.0.0.0:1514
      label_structured_data: yes
    relabel_configs:
      - source_labels: ['__syslog_message_hostname']
        target_label: 'host'
    pipeline_stages:
      - regex:
          expression: 'level=(?P<level>\w+)'
      - labels:
          level:
EOF
$STD chown -R promtail:promtail /var/lib/promtail
$STD chown -R promtail:promtail /etc/promtail

msg_ok "Created Promtail configuration"

msg_info "Creating Promtail service"
$STD cat <<EOF >/etc/systemd/system/promtail.service
[Unit]
Description=Grafana Promtail Syslog Log Forwarder
After=network.target

[Service]
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Promtail service"

msg_info "Starting Promtail"
$STD systemctl daemon-reexec
$STD systemctl daemon-reload
$STD systemctl enable promtail
$STD systemctl start promtail
msg_ok "Started Promtail"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
