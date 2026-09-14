#!/usr/bin/env bash
# Valhalla + Web-App – Proxmox VE Helper-Script (LXC)
# Läuft auf dem Proxmox-Host (pve-Shell). Erstellt einen LXC-Container,
# in dem Valhalla-Routing-Engine + Web-App (valhalla/web-app) per Docker laufen.
#
# Verwendung (Proxmox-Host als root):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ValHallaRouting/main/ct/valhalla.sh)"
# Optional mit Vorgaben:
#   var_cpu=4 var_ram=8192 var_disk=40 var_tile_region=germany bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ValHallaRouting/main/ct/valhalla.sh)"
#
# Am Ende: Web-UI auf http://<LXC-IP>/  (API: http://<LXC-IP>:8002/status)

_CS_DEFAULT_URL="https://raw.githubusercontent.com/HatchetMan111/ValHallaRouting/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
# shellcheck disable=SC1091
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 tteck
# License: MIT
# Source Valhalla: https://github.com/valhalla/valhalla
# Source Web-App:  https://github.com/valhalla/web-app

APP="Valhalla"
var_tags="${var_tags:-routing;maps;valhalla}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arch="${var_arch:-amd64}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
# Docker in LXC braucht nesting + keyctl
var_features="${var_features:-nesting=1,keyctl=1}"

# Kartenregion: germany | bw-bayern | bw | bayern | nrw | saarland | andorra | austria | switzerland | dach | custom
# Kann per Umgebungsvariable vorgegeben werden, z. B. var_tile_region=germany
# Hinweis: Default ganz Deutschland (~4 GB PBF, ~25 GB Tiles, braucht 50 GB Disk + 8 GB RAM).
var_tile_region="${var_tile_region:-}"
var_tile_urls="${var_tile_urls:-}"
var_web_port="${var_web_port:-80}"
var_valhalla_port="${var_valhalla_port:-8002}"

header_info "$APP"
variables
color
catch_errors

# --- Kartenregion interaktiv wählen (nur wenn nichts vorgegeben) ---
if [[ -z "${var_tile_region:-}" && -z "${var_tile_urls:-}" ]]; then
  if command -v pveversion >/dev/null 2>&1; then
    var_tile_region=$(msg_menu "Welche Karte soll Valhalla bauen? (Default: ganz Deutschland – braucht 50GB Disk / 8GB RAM, Bau 30-60 Min)" \
      "germany" "Deutschland (~4 GB PBF, ~25 GB Tiles, 30-60 Min) [Default]" \
      "bw-bayern" "Baden-Württemberg + Bayern (~2 GB PBF, 15-30 Min)" \
      "bw" "Baden-Württemberg (~600 MB, ca. 10 Min)" \
      "bayern" "Bayern (~1,2 GB, ca. 15-20 Min)" \
      "nrw" "NRW (~500 MB, ca. 10-20 Min)" \
      "saarland" "Saarland (~50 MB, wenige Minuten)" \
      "andorra" "Andorra (~8 MB, Test in 2-3 Min)" \
      "austria" "Österreich (~600 MB)" \
      "switzerland" "Schweiz (~500 MB)" \
      "dach" "D-A-CH (3 Dateien, groß!)") || var_tile_region="germany"
  else
    var_tile_region="germany"
  fi
fi
export var_tile_region var_tile_urls var_web_port var_valhalla_port

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/valhalla ]]; then
    msg_error "Keine Valhalla-Installation in /opt/valhalla gefunden!"
    exit 1
  fi
  msg_info "Aktualisiere Valhalla-Images + Web-App"
  cd /opt/valhalla || exit 1
  $STD docker compose pull
  $STD docker compose up -d --build
  msg_ok "Update angestoßen – Tiles werden nur bei geänderter PBF neu gebaut."
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Web-App (sofort nutzbar, wie valhalla.openstreetmap.de):${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:${var_web_port}${CL}"
echo -e "${INFO}${YW}Valhalla-API direkt (Status/Route):${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:${var_valhalla_port}/status${CL}"
echo -e "${INFO}Hinweis: Der erste Tiles-Bau läuft im Container im Hintergrund (docker logs -f valhalla).${CL}"
