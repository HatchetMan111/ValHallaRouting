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

APP="ValhallRouting"
var_hostname="${var_hostname:-ValhallRouting}"
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

# Kartenregion: germany | bw-bayern | bw | bayern | berlin | brandenburg | ... (alle 16 Bundesländer)
# | nrw | austria | switzerland | dach | andorra | custom – mehrere mit Leerzeichen trennen,
# z. B. var_tile_region="bw bayern". Nur exakt diese Region(en) werden von Geofabrik geladen.
# Hinweis: Default ganz Deutschland (~4 GB PBF, ~25 GB Tiles, braucht 50 GB Disk + 8 GB RAM).
var_tile_region="${var_tile_region:-}"
var_tile_urls="${var_tile_urls:-}"
var_web_port="${var_web_port:-80}"
var_valhalla_port="${var_valhalla_port:-8002}"
# Build-/Server-Threads: leer = auto (1 bei germany/dach, sonst 2).
# Hinweis: server_threads steuert BEIDES: valhalla_build_tiles-Concurrency UND
# Service-Threads. Germany/dach crasht in der enhance-Phase mit 4 Threads auf
# 8 GB RAM (Segfault/OOM) – deshalb dort max. 2, empfohlen 1. Mehr nur mit mehr RAM.
var_server_threads="${var_server_threads:-}"

header_info "$APP"
variables
color
catch_errors

# --- Kartenregion interaktiv wählen (nur wenn nichts vorgegeben) ---
# Eigenes Menü statt msg_menu: msg_menu hat nur 10s Timeout und akzeptiert nur
# exakte Tags (eine getippte Zahl fällt still auf Default zurück – das hat schon
# ungewollt ganz Deutschland gebaut). Hier gehen Nummer ODER Name, ohne Timeout,
# mehrere Bundesländer Komma-getrennt (z. B. "3,4" oder "bw,bayern").
if [[ -z "${var_tile_region:-}" && -z "${var_tile_urls:-}" ]]; then
  if command -v pveversion >/dev/null 2>&1 && [[ -t 0 ]]; then
    echo ""
    msg_custom "📋" "${BL}" "Welche Karte soll Valhalla bauen? (Default: ganz Deutschland – 50GB Disk / 8GB RAM, Bau 60-180 Min)"
    msg_custom "📋" "${BL}" "Mehrere Bundesländer mit Komma trennen, z. B. 4,5 oder bw,bayern"
    echo ""
    _REGIONS=(germany bw-bayern bw bayern berlin brandenburg bremen hamburg hessen mecklenburg-vorpommern niedersachsen nrw rheinland-pfalz saarland sachsen sachsen-anhalt schleswig-holstein thueringen austria switzerland dach andorra)
    _REGDESC=("Deutschland komplett (~4 GB PBF, 60-180 Min) [Default]" "Baden-Württemberg + Bayern (~2 GB PBF, 15-40 Min)" "Baden-Württemberg (~650 MB)" "Bayern (~1,3 GB)" "Berlin (~120 MB)" "Brandenburg (~350 MB)" "Bremen (~35 MB)" "Hamburg (~90 MB)" "Hessen (~550 MB)" "Mecklenburg-Vorpommern (~250 MB)" "Niedersachsen (~550 MB)" "Nordrhein-Westfalen (~700 MB)" "Rheinland-Pfalz (~400 MB)" "Saarland (~50 MB)" "Sachsen (~300 MB)" "Sachsen-Anhalt (~250 MB)" "Schleswig-Holstein (~350 MB)" "Thüringen (~250 MB)" "Österreich (~600 MB)" "Schweiz (~500 MB)" "D-A-CH (3 Länder, groß!)" "Andorra (~8 MB, Test)")
    for _i in "${!_REGIONS[@]}"; do
      _mark="  "; [[ $_i -eq 0 ]] && _mark="* "
      printf "${TAB3}${_mark}%d) %s – %s\n" "$((_i + 1))" "${_REGIONS[$_i]}" "${_REGDESC[$_i]}"
    done
    echo ""
    _sel=""
    read -r -p "${TAB3}Auswahl [Nummern/Namen, Komma-getrennt, default=germany]: " _sel || true
    _sel="$(echo "${_sel:-}" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"
    var_tile_region="germany"
    if [[ -n "${_sel// /}" ]]; then
      _picked=()
      _ok=1
      for _t in $_sel; do
        if [[ "$_t" =~ ^[0-9]+$ ]] && (( _t >= 1 && _t <= ${#_REGIONS[@]} )); then
          _picked+=("${_REGIONS[$((_t - 1))]}")
        else
          _found=0
          for _r in "${_REGIONS[@]}"; do
            if [[ "$_t" == "$_r" ]]; then _picked+=("$_r"); _found=1; break; fi
          done
          (( _found )) || _ok=0
        fi
      done
      # germany sticht alles andere (Mix mit Gesamt-DE wäre sinnlos)
      for _p in "${_picked[@]:-}"; do
        if [[ "$_p" == "germany" ]]; then _picked=(germany); break; fi
      done
      if (( _ok )) && (( ${#_picked[@]} > 0 )); then
        var_tile_region="${_picked[*]}"
      else
        msg_warn "Ungültige Auswahl – nehme Default: germany"
      fi
    fi
    unset _REGIONS _REGDESC _sel _t _r _p _i _mark _picked _found _ok
    msg_ok "Gewählte Region(en): ${var_tile_region}"
  else
    var_tile_region="germany"
  fi
fi
export var_tile_region var_tile_urls var_web_port var_valhalla_port var_server_threads

# --- Ressourcen-Guard: Germany/DACH braucht 8 GB RAM + 50 GB Disk ---
# Der bekannte enhance-Segfault ist fast immer OOM (4 Threads auf 8 GB).
# Hier warnen wir FRÜH (Host-Seite), statt nach 2h Bauzeit zu crashen.
if [[ "${var_tile_region,,}" == *germany* || "${var_tile_region,,}" == *dach* ]]; then
  if (( var_ram < 8192 )); then
    msg_warn "Region '${var_tile_region}' + ${var_ram} MB RAM = OOM-Risiko (enhance-Segfault)!"
    msg_warn "Empfohlen: 8192+ MB RAM und var_server_threads=1. Baue trotzdem mit Threads=1."
    var_server_threads="${var_server_threads:-1}"
    export var_server_threads
  fi
  if (( var_disk < 50 )); then
    msg_warn "Region '${var_tile_region}' braucht ~25 GB Tiles + ~4 GB PBF – var_disk=${var_disk} GB ist knapp!"
    msg_warn "Empfohlen: var_disk=50 oder mehr."
  fi
fi

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
