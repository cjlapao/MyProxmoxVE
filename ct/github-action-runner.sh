#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/cjlapao/MyProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 carlos lapao
# Author: carlos lapao
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/bastienwirtz/homer

APP="gitHub-action-runner"
var_tags="${var_tags:-dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-40}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  exit
}

start
build_container
description

echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
