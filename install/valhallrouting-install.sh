#!/usr/bin/env bash
# Valhalla + Web-App – LXC-Installer (läuft IM Container)
# Wird vom Host-Script (valhalla.sh / ct-Script) via build_container aufgerufen.
# Kann auch manuell in einem frischen Debian-13-LXC als root ausgeführt werden.
#
# Ergebnis:
#   - Valhalla Routing-Engine (ghcr.io/valhalla/valhalla-scripted) auf Port 8002
#   - Web-App (valhalla/web-app, React-Build) auf Port 80 mit Reverse-Proxy /valhalla -> :8002
#   - Aufruf im LAN: http://<LXC-IP>/  (sofort nutzbar: Route, Isochrone, Matrix)

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
# Fallback, falls das Script manuell (ohne build_container) in einem
# bestehenden Debian-LXC / einer VM als root ausgeführt wird:
if ! command -v setting_up_container >/dev/null 2>&1; then
  STD=""
  TAB="  "
  GN="\e[1;92m"
  CL="\e[0m"
  msg_info() { echo -e "${TAB}$1..."; }
  msg_ok() { echo -e "${TAB}\e[1;92mOK\e[0m $1"; }
  msg_warn() { echo -e "${TAB}\e[1;93mWARN\e[0m $1"; }
  msg_error() { echo -e "${TAB}\e[1;91mFEHLER\e[0m $1"; }
  setting_up_container() { :; }
  network_check() { :; }
  update_os() { apt-get update && apt-get -y upgrade; }
  setup_docker() {
    if ! command -v docker >/dev/null 2>&1; then
      apt-get install -y ca-certificates curl gnupg
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
      chmod a+r /etc/apt/keyrings/docker.asc
      # shellcheck disable=SC1091
      . /etc/os-release
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" >/etc/apt/sources.list.d/docker.list
      apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
  }
  motd_ssh() { :; }
  customize() { :; }
  cleanup_lxc() { apt-get -y autoremove && apt-get -y autoclean; }
  verb_ip6() { :; }
  color() { :; }
  catch_errors() { set -Eeuo pipefail; }
fi
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ---------- 1. Region -> PBF-URLs + Kartenzentrum auflösen ----------
# var_tile_region kommt aus dem Host-Menü (exportiert). Zur Kontrolle steht die
# erhaltene Vorgabe explizit im Log – so sieht man sofort, was gebaut wird.
msg_info "Regions-Vorgabe vom Host-Menü: var_tile_region='${var_tile_region:-<leer>}' var_tile_urls='${var_tile_urls:-<leer>}'"
TILE_REGION="${var_tile_region:-${TILE_REGION:-germany}}"
TILE_URLS_CUSTOM="${var_tile_urls:-${TILE_URLS:-}}"
WEB_PORT="${var_web_port:-80}"
VALHALLA_PORT="${var_valhalla_port:-8002}"

# Regions-Auflösung: region_entry() liefert pro Key EINE URL ("URL|CENTER"),
# resolve_multi() kombiniert mehrere Keys (Leerzeichen-getrennt) zu URL-Listen.
# Es wird NUR geladen, was gewählt wurde – kein stiller Germany-Fallback.
region_entry() {
  case "$1" in
  andorra)                  echo "https://download.geofabrik.de/europe/andorra-latest.osm.pbf|42.55,1.58" ;;
  saarland)                 echo "https://download.geofabrik.de/europe/germany/saarland-latest.osm.pbf|49.38,7.07" ;;
  nrw|nordrhein-westfalen)  echo "https://download.geofabrik.de/europe/germany/nordrhein-westfalen-latest.osm.pbf|51.43,7.66" ;;
  bw|baden-wuerttemberg)    echo "https://download.geofabrik.de/europe/germany/baden-wuerttemberg-latest.osm.pbf|48.50,9.00" ;;
  bayern)                   echo "https://download.geofabrik.de/europe/germany/bayern-latest.osm.pbf|49.00,11.40" ;;
  berlin)                   echo "https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf|52.52,13.40" ;;
  brandenburg)              echo "https://download.geofabrik.de/europe/germany/brandenburg-latest.osm.pbf|52.40,13.00" ;;
  bremen)                   echo "https://download.geofabrik.de/europe/germany/bremen-latest.osm.pbf|53.08,8.80" ;;
  hamburg)                  echo "https://download.geofabrik.de/europe/germany/hamburg-latest.osm.pbf|53.55,10.00" ;;
  hessen)                   echo "https://download.geofabrik.de/europe/germany/hessen-latest.osm.pbf|50.60,8.70" ;;
  mecklenburg-vorpommern|meckpomm|mv) echo "https://download.geofabrik.de/europe/germany/mecklenburg-vorpommern-latest.osm.pbf|53.80,12.40" ;;
  niedersachsen)            echo "https://download.geofabrik.de/europe/germany/niedersachsen-latest.osm.pbf|52.80,9.00" ;;
  rheinland-pfalz|rlp)      echo "https://download.geofabrik.de/europe/germany/rheinland-pfalz-latest.osm.pbf|49.90,7.45" ;;
  sachsen)                  echo "https://download.geofabrik.de/europe/germany/sachsen-latest.osm.pbf|51.10,13.30" ;;
  sachsen-anhalt)           echo "https://download.geofabrik.de/europe/germany/sachsen-anhalt-latest.osm.pbf|51.90,11.60" ;;
  schleswig-holstein|sh)    echo "https://download.geofabrik.de/europe/germany/schleswig-holstein-latest.osm.pbf|54.10,9.70" ;;
  thueringen)               echo "https://download.geofabrik.de/europe/germany/thueringen-latest.osm.pbf|50.90,11.00" ;;
  germany)                  echo "https://download.geofabrik.de/europe/germany-latest.osm.pbf|51.16,10.45" ;;
  austria)                  echo "https://download.geofabrik.de/europe/austria-latest.osm.pbf|47.51,14.55" ;;
  switzerland)              echo "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf|46.82,8.22" ;;
  *) return 1 ;;
  esac
}

resolve_multi() {
  local input="$1" r e u c urls="" center=""
  # Komfort-Kombis auf Einzel-Keys zurückführen
  input="${input//bw-bayern/bw bayern}"
  input="${input//dach/germany austria switzerland}"
  for r in $input; do
    if ! e="$(region_entry "$r")"; then
      msg_error "Unbekannte Region '$r' (TILE_REGION='$TILE_REGION')"
      msg_error "Gültig: germany bw-bayern bw bayern berlin brandenburg bremen hamburg hessen mecklenburg-vorpommern niedersachsen nrw rheinland-pfalz saarland sachsen sachsen-anhalt schleswig-holstein thueringen austria switzerland dach andorra custom"
      exit 1
    fi
    u="${e%%|*}"; c="${e##*|}"
    urls="${urls:+$urls }$u"
    [[ -z "$center" ]] && center="$c"
  done
  echo "URLS=${urls}|CENTER=${center}"
}

if [[ -n "$TILE_URLS_CUSTOM" && -z "$TILE_REGION" ]]; then TILE_REGION="custom"; fi
if [[ "$TILE_REGION" == "custom" && -z "$TILE_URLS_CUSTOM" ]]; then
  msg_error "Region 'custom' gewählt, aber keine URL in var_tile_urls gesetzt!"
  exit 1
fi
# Interaktiv nachfragen, falls im Container noch nichts gesetzt (manueller Lauf)
if [[ -z "${var_tile_region:-}" && -z "${var_tile_urls:-}" && -t 0 ]]; then
  msg_info "Welche Karte soll gebaut werden? [germany | Bundesländer: bw bayern berlin brandenburg bremen hamburg hessen mecklenburg-vorpommern niedersachsen nrw rheinland-pfalz saarland sachsen sachsen-anhalt schleswig-holstein thueringen – mehrere mit Leerzeichen, z. B. 'bw bayern']"
  read -r -p "Region (default: germany): " _r || true
  TILE_REGION="${_r:-germany}"
fi

if [[ "$TILE_REGION" == "custom" ]]; then
  TILE_URLS="$TILE_URLS_CUSTOM"
  CENTER_COORDS="51.16,10.45"
else
  RESOLVED="$(resolve_multi "$TILE_REGION")"
  TILE_URLS="$(echo "$RESOLVED" | cut -d'|' -f1 | cut -d'=' -f2-)"
  CENTER_COORDS="$(echo "$RESOLVED" | cut -d'|' -f2 | cut -d'=' -f2)"
fi

msg_info "Region: $TILE_REGION | Zentrum: $CENTER_COORDS"
msg_info "PBF-Quelle(n): $TILE_URLS"

# ---------- 2. Dependencies + Docker ----------
msg_info "Installing Dependencies"
$STD apt install -y curl git ca-certificates jq xz-utils
msg_ok "Installed Dependencies"

setup_docker

# ---------- 3. Projektverzeichnis /opt/valhalla ----------
msg_info "Lege /opt/valhalla Stack an"
mkdir -p /opt/valhalla/custom_files /opt/valhalla/web
cd /opt/valhalla || exit 1
# Transparenz: welche Region wurde gebaut (hilft bei "falsche Karte gebaut"-Fragen)
echo "TILE_REGION=${TILE_REGION}" >/opt/valhalla/REGION
echo "TILE_URLS=${TILE_URLS}" >>/opt/valhalla/REGION
echo "CENTER_COORDS=${CENTER_COORDS}" >>/opt/valhalla/REGION
echo "# BUILD_START $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>/opt/valhalla/REGION
LOCAL_IP="$(hostname -I | awk '{print $1}')"
# Build-Threads: sicherer Auto-Modus gegen den bekannten enhance-OOM-Segfault.
# Regel: 1 Thread pro ~4 GB RAM (valhalla/docs + Issue #5947: 1:2 Thread:GB als Minimum,
# enhance-Phase spikes darüber). germany/dach auf 8 GB -> 1, sonst max. 2.
# var_server_threads (vom Host exportiert) gewinnt immer, wird aber bei OOM-Risiko gedeckelt.
MEM_MB="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
MEM_MB="${MEM_MB:-8192}"
THREADS_REQ="${var_server_threads:-${SERVER_THREADS:-}}"
if [[ -z "$THREADS_REQ" ]]; then
  if [[ "$TILE_REGION" == *germany* || "$TILE_REGION" == *dach* ]]; then
    THREADS=1
  else
    THREADS=2
  fi
  # Kleine Container (<6 GB RAM) immer auf 1 Thread runter
  if (( MEM_MB < 6144 )); then THREADS=1; fi
else
  THREADS="$THREADS_REQ"
  # Deckel: mehr als MEM/2048 Threads ist OOM-sicherungsrelevant (min. 1, max. 8)
  _MAX_T=$(( MEM_MB / 2048 ))
  (( _MAX_T < 1 )) && _MAX_T=1
  (( _MAX_T > 8 )) && _MAX_T=8
  if (( THREADS > _MAX_T )); then
    msg_warn "var_server_threads=${THREADS} zu hoch für ${MEM_MB} MB RAM (max ${_MAX_T}) – deckele auf ${_MAX_T} (OOM-Segfault-Schutz)"
    THREADS="$_MAX_T"
  fi
  # Germany/DACH-Extra: selbst bei viel RAM max. 2 für den Build (enhance-Spikes)
  if [[ "$TILE_REGION" == *germany* || "$TILE_REGION" == *dach* ]] && (( THREADS > 2 )) && (( MEM_MB < 16384 )); then
    msg_warn "Germany/DACH-Build mit ${THREADS} Threads auf ${MEM_MB} MB RAM riskiert enhance-Segfault – deckele auf 2"
    THREADS=2
  fi
fi
msg_ok "Arbeitsverzeichnis bereit (Build-/Server-Threads: $THREADS, RAM: ${MEM_MB} MB, IP: $LOCAL_IP)"

# Swap als OOM-Airbag: Germany braucht beim Enhancen kurz mehr als 8 GB.
# Falls kein Swap aktiv und RAM < 16 GB -> 8 GB Swapfile anlegen (idempotent).
if (( MEM_MB < 16384 )); then
  if ! swapon --show 2>/dev/null | grep -q .; then
    msg_info "Lege 8 GB Swap an (OOM-Schutz für Tile-Build)"
    fallocate -l 8G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=8192 status=none || true
    chmod 600 /swapfile 2>/dev/null || true
    mkswap /swapfile >/dev/null 2>&1 || true
    swapon /swapfile 2>/dev/null || msg_warn "swapon blockiert (LXC ohne swap-Recht?) – im Proxmox-Host ggf. Swap für den CT erlauben"
    grep -q '/swapfile' /etc/fstab 2>/dev/null || echo '/swapfile none swap sw 0 0' >>/etc/fstab
  fi
fi
# Build ohne Swap + wenig RAM = fast sicherer Kill -> früh abbrechen mit klarer Meldung
if (( MEM_MB < 4096 )) && ! swapon --show 2>/dev/null | grep -q .; then
  msg_error "Nur ${MEM_MB} MB RAM ohne Swap – Tile-Build wird mit Segfault/OOM sterben. Brich ab: mehr RAM geben oder Swap erlauben."
  exit 1
fi

# ---------- 4. docker-compose.yml ----------
cat <<EOF >/opt/valhalla/docker-compose.yml
services:
  valhalla:
    image: ghcr.io/valhalla/valhalla-scripted:latest
    container_name: valhalla
    restart: unless-stopped
    ports:
      - "${VALHALLA_PORT}:8002"
    volumes:
      - ./custom_files:/custom_files
    environment:
      - tile_urls=${TILE_URLS}
      - use_tiles_ignore_pbf=True
      - force_rebuild=False
      - build_elevation=False
      - build_admins=True
      - build_time_zones=True
      - build_transit=False
      - build_tar=True
      - serve_tiles=True
      - server_threads=${THREADS}
      - use_default_speeds_config=True
    stop_grace_period: 30s
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8002/status >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 20
      start_period: 60s

  web:
    build:
      context: .
      dockerfile: ./web/Dockerfile
    container_name: valhalla-web
    restart: unless-stopped
    ports:
      - "${WEB_PORT}:80"
    depends_on:
      - valhalla
EOF
msg_ok "docker-compose.yml geschrieben"

# ---------- 5. Web-App bauen (valhalla/web-app, VITE_VALHALLA_URL=/valhalla) ----------
# Trick: relative API-URL "/valhalla" -> nginx proxyt auf valhalla:8002.
# Damit funktioniert die App unter JEDER LXC-IP ohne Rebuild.
msg_info "Hole valhalla/web-app Quellcode"
if [[ -d /opt/valhalla/web-app-src ]]; then
  cd /opt/valhalla/web-app-src && $STD git pull --ff-only && cd /opt/valhalla || exit 1
else
  $STD git clone --depth 1 https://github.com/valhalla/web-app.git /opt/valhalla/web-app-src
fi

msg_info "Schreibe .env für Offline-LAN-Betrieb (API=/valhalla)"
# WICHTIG: Default NICHT 'auto' – das Settings-Panel von upstream kennt 'auto'
# nicht (profileSettings/generalSettings haben keinen auto-Key) und crasht mit
# "Cannot read properties of undefined (reading 'boolean')". Upstream-Default: bicycle.
cat <<EOF >/opt/valhalla/web-app-src/.env
SKIP_PREFLIGHT_CHECK=true
VITE_VALHALLA_URL=/valhalla
VITE_NOMINATIM_URL=https://nominatim.openstreetmap.org
VITE_TILE_SERVER_URL="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
VITE_CENTER_COORDS="${CENTER_COORDS}"
VITE_DEFAULT_COSTING_MODEL=bicycle
VITE_CLIENT_ID=valhalla-pve-lxc
EOF

msg_info "Patche Settings-Panel für Profil 'auto' (upstream kennt nur car/bicycle/...) "
# Falls der User im UI trotzdem auf 'auto' stellt: auf 'car'-Settings zurückfallen
# statt mit "Cannot read properties of undefined (reading 'boolean')" zu crashen.
PANEL=/opt/valhalla/web-app-src/src/components/settings-panel/settings-panel.tsx
if [[ -f "$PANEL" ]]; then
  # Idempotent: nach git pull ist der Patch weg (neu patchen), bei
  # wiederholtem Lauf ohne pull ist er schon drin (überspringen).
  if grep -q 'profileSettings\[profile as ProfileWithSettings\] ?? profileSettings.car' "$PANEL"; then
    msg_ok "Settings-Panel bereits gepatcht"
  else
    $STD sed -i 's|profileSettings\[profile as ProfileWithSettings\]|(profileSettings[profile as ProfileWithSettings] ?? profileSettings.car)|g' "$PANEL"
    $STD sed -i 's|generalSettings\[profile as ProfileWithSettings\]|(generalSettings[profile as ProfileWithSettings] ?? generalSettings.car)|g' "$PANEL"
    msg_ok "Settings-Panel gepatcht"
  fi
else
  msg_warn "settings-panel.tsx nicht gefunden – Patch übersprungen"
fi

msg_info "Erstelle Web-Dockerfile + nginx Reverse-Proxy"
cat <<'EOF' >/opt/valhalla/web/Dockerfile
FROM node:24-alpine AS builder
WORKDIR /app
COPY ./web-app-src /app
RUN npm i && npm run build

FROM nginx:1.29-alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY ./web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

cat <<'EOF' >/opt/valhalla/web/nginx.conf
server {
  listen 80;
  server_name _;
  root /usr/share/nginx/html;
  index index.html;
  client_max_body_size 10m;

  # Valhalla-API hinter gleichem Origin (kein CORS-Problem, IP-unabhängig)
  # Frontend ruft /valhalla/route, /valhalla/optimized_route, /valhalla/matrix,
  # /valhalla/isochrone, /valhalla/status auf. optimized_route/matrix senden
  # große POST-Bodies -> Timeouts + Buffer großzügig.
  location /valhalla/ {
    rewrite ^/valhalla/(.*) /$1 break;
    proxy_pass http://valhalla:8002;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_http_version 1.1;
    proxy_request_buffering off;
    proxy_buffering off;
    proxy_connect_timeout 60s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
  }
  location = /valhalla { return 301 /valhalla/; }

  location / {
    try_files $uri $uri/ /index.html;
  }
}
EOF
# Build-Kontext ist /opt/valhalla (.) -> custom_files (GBs!) + .git vom Build ausschließen
cat <<'EOF' >/opt/valhalla/.dockerignore
custom_files
web-app-src/.git
EOF
msg_ok "Web-Build-Kontext fertig"

# ---------- 6. Stack starten (Tiles-Bau läuft automatisch) ----------
msg_info "Starte Valhalla + Web-App (erster Tiles-Bau kann lange dauern)"
cd /opt/valhalla || exit 1
$STD docker compose up -d --build
msg_ok "Container laufen: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"

# ---------- 7. Auf Valhalla warten (max ~90 Min, je nach PBF) ----------
msg_info "Warte auf Valhalla-API (Tiles werden ggf. jetzt gebaut – das ist normal)"
echo -e "${TAB}Log live verfolgen in 2. Shell: ${GN}docker logs -f valhalla${CL}"
READY=0
for i in $(seq 1 540); do
  if curl -fsS "http://127.0.0.1:${VALHALLA_PORT}/status" >/dev/null 2>&1; then
    READY=1
    break
  fi
  # Alle 30s Fortschritt loggen
  if (( i % 30 == 0 )); then
    echo -e "${TAB}... noch am Bauen/warten (${i}/540 x 10s) – aktuelle Logs:"
    docker logs --tail 5 valhalla 2>&1 | tail -5 || true
  fi
  sleep 10
done

if [[ "$READY" == "1" ]]; then
  msg_ok "Valhalla-API antwortet auf :${VALHALLA_PORT}/status"
else
  msg_warn "Valhalla antwortet noch nicht – Tiles-Bau läuft evtl. weiter. Prüfe: docker logs -f valhalla"
fi

# Web-Check
if curl -fsS "http://127.0.0.1:${WEB_PORT}/" >/dev/null 2>&1; then
  msg_ok "Web-App antwortet auf :${WEB_PORT}"
else
  msg_warn "Web-App noch nicht erreichbar – prüfe: docker logs valhalla-web"
fi

# ---------- 8. Smoke-Test: Route + Optimized Route IN der gebauten Region ----------
# Häufigste "Fehlermeldung" ist NoSegment: Testpunkt liegt AUSSERHALB der Tiles
# (z. B. München testen, aber nur Saarland gebaut). Deshalb testen wir um CENTER.
if [[ "$READY" == "1" ]]; then
  _CLAT="${CENTER_COORDS%%,*}"; _CLON="${CENTER_COORDS##*,}"
  _LAT2="$(awk "BEGIN{print ${_CLAT}+0.05}")"; _LON2="$(awk "BEGIN{print ${_CLON}+0.07}")"
  _LAT3="$(awk "BEGIN{print ${_CLAT}+0.03}")"; _LON3="$(awk "BEGIN{print ${_CLON}-0.06}")"
  _LAT4="$(awk "BEGIN{print ${_CLAT}-0.04}")"; _LON4="$(awk "BEGIN{print ${_CLON}+0.04}")"
  msg_info "Smoke-Test Route um Zentrum ${CENTER_COORDS} (kostet auto)"
  if curl -fsS "http://127.0.0.1:${VALHALLA_PORT}/route" \
      -d "{\"locations\":[{\"lat\":${_CLAT},\"lon\":${_CLON}},{\"lat\":${_LAT2},\"lon\":${_LON2}}],\"costing\":\"auto\"}" \
      | grep -q '"trip"'; then
    msg_ok "Route-Test OK (Tiles vollständig, auto-Routing geht)"
  else
    msg_warn "Route-Test FEHLGESCHLAGEN – meist: Tiles unvollständig (Segfault-Build?) oder Punkte außerhalb Region."
    msg_warn "Diagnose: docker logs --tail 50 valhalla | grep -iE 'segfault|killed|oom|error|failed'; ./check-route.sh"
  fi
  msg_info "Smoke-Test Optimized Route (braucht >=4 Punkte, costing auto|bicycle|pedestrian)"
  if curl -fsS "http://127.0.0.1:${VALHALLA_PORT}/optimized_route" \
      -d "{\"locations\":[{\"lat\":${_CLAT},\"lon\":${_CLON}},{\"lat\":${_LAT2},\"lon\":${_LON2}},{\"lat\":${_LAT3},\"lon\":${_LON3}},{\"lat\":${_LAT4},\"lon\":${_LON4}}],\"costing\":\"auto\"}" \
      | grep -q '"trip"'; then
    msg_ok "Optimized-Route-Test OK"
  else
    msg_warn "Optimized-Route-Test FEHLGESCHLAGEN – Hinweis: braucht mind. 4 Punkte + costing auto/bicycle/pedestrian (kein truck/bus/multimodal)."
  fi
  unset _CLAT _CLON _LAT2 _LON2 _LAT3 _LON3 _LAT4 _LON4
fi

# ---------- 9. Hilfsskripte + MOTD ----------
cat <<EOF >/opt/valhalla/rebuild.sh
#!/usr/bin/env bash
# Tiles neu bauen (z. B. nach PBF-Tausch in custom_files/)
# Wichtig: gleiche sichere Threads wie beim Erstbuild (${THREADS}, OOM-Schutz).
cd /opt/valhalla
THREADS_FALLBACK="${THREADS}"
THREADS_FROM_COMPOSE="\$(grep -Eo 'server_threads=[0-9]+' docker-compose.yml 2>/dev/null | grep -Eo '[0-9]+' | head -n1)"
THREADS="\${SERVER_THREADS:-\${THREADS_FROM_COMPOSE:-\$THREADS_FALLBACK}}"
docker compose run --rm -e force_rebuild=True -e build_tar=True -e server_threads="\${THREADS:-1}" valhalla || true
docker compose restart valhalla
docker logs -f valhalla
EOF
chmod +x /opt/valhalla/rebuild.sh

# Diagnose-Skript: unterscheidet "Tiles kaputt" vs "Punkt außerhalb Region" vs "falsches Costing"
cat <<'DIAG_EOF' >/opt/valhalla/check-route.sh
#!/usr/bin/env bash
# Diagnose für "optimale route geht nicht / Fehlermeldungen"
# Aufruf: ./check-route.sh [lat lon lat lon ...]  (default: um CENTER aus REGION testen)
set -u
cd /opt/valhalla || exit 1
source ./REGION 2>/dev/null || true
PORT="%%VALHALLA_PORT%%"
PORT_FROM_COMPOSE="$(grep -Eo '[0-9]+:8002' docker-compose.yml 2>/dev/null | cut -d: -f1 | head -n1)"
PORT="${PORT_FROM_COMPOSE:-$PORT}"
CENTER="${CENTER_COORDS:-51.16,10.45}"
CLAT="${CENTER%%,*}"; CLON="${CENTER##*,}"
if (( $# >= 4 )); then LAT1="$1"; LON1="$2"; LAT2="$3"; LON2="$4"
else LAT1="$CLAT"; LON1="$CLON"; LAT2="$(awk "BEGIN{print $CLAT+0.05}")"; LON2="$(awk "BEGIN{print $CLON+0.07}")"; fi
echo "== 1/4 status =="; curl -s "http://127.0.0.1:${PORT}/status" | head -c 500; echo
echo "== 2/4 route (auto) ${LAT1},${LON1} -> ${LAT2},${LON2} =="
curl -s "http://127.0.0.1:${PORT}/route" -d "{\"locations\":[{\"lat\":${LAT1},\"lon\":${LON1}},{\"lat\":${LAT2},\"lon\":${LON2}}],\"costing\":\"auto\"}" | head -c 1000; echo
echo "== 3/4 optimized_route (4 Punkte, auto) =="
curl -s "http://127.0.0.1:${PORT}/optimized_route" -d "{\"locations\":[{\"lat\":${LAT1},\"lon\":${LON1}},{\"lat\":${LAT2},\"lon\":${LON2}},{\"lat\":${LAT1},\"lon\":${LON2}},{\"lat\":${LAT2},\"lon\":${LON1}}],\"costing\":\"auto\"}" | head -c 1000; echo
echo "== 4/4 Build-Log Fehler =="; docker logs --tail 200 valhalla 2>&1 | grep -iE 'segfault|killed|oom|aborted|failed tile|ERROR' | tail -20 || echo "(keine Build-Fehler in den letzten 200 Zeilen)"
echo; echo "Hinweise:"; echo "- NoSegment/could not snap = Punkt AUSSERHALB der gebauten Region (${CENTER}) oder Tiles unvollständig."; echo "- optimized_route braucht >=4 locations + costing auto|bicycle|pedestrian."; echo "- Segfault/Killed im Log = OOM: Threads senken (server_threads=1), Swap prüfen, siehe README."
DIAG_EOF
chmod +x /opt/valhalla/check-route.sh
# Installzeit-Port in das Diagnose-Skript einbacken (Template nutzt quoted heredoc)
sed -i "s/%%VALHALLA_PORT%%/${VALHALLA_PORT}/" /opt/valhalla/check-route.sh

_RLAT="${CENTER_COORDS%%,*}"; _RLON="${CENTER_COORDS##*,}"
_RLAT2="$(awk "BEGIN{print ${_RLAT}+0.05}")"; _RLON2="$(awk "BEGIN{print ${_RLON}+0.07}")"
cat <<EOF >/opt/valhalla/README.txt
Valhalla LXC – Kurzanleitung
============================
Web-App : http://${LOCAL_IP}:${WEB_PORT}/
API     : http://${LOCAL_IP}:${VALHALLA_PORT}/status
Region  : ${TILE_REGION} (Zentrum ${CENTER_COORDS})
Route-Test (Punkte IN der Region!):
  curl -s http://${LOCAL_IP}:${VALHALLA_PORT}/route -d '{"locations":[{"lat":${_RLAT},"lon":${_RLON}},{"lat":${_RLAT2},"lon":${_RLON2}}],"costing":"auto"}'
Optimized Route: mind. 4 Punkte + costing auto|bicycle|pedestrian (kein truck/bus/multimodal!)

PBF tauschen: neue .pbf nach /opt/valhalla/custom_files/ legen, dann ./rebuild.sh
Diagnose bei Fehlermeldung: ./check-route.sh   (Tiles-kaputt vs Punkt-ausserhalb vs Costing)
Logs: docker logs -f valhalla   |   docker logs valhalla-web
Stack: cd /opt/valhalla && docker compose ps / docker compose up -d
OOM/Segfault (enhance-Phase): server_threads=${THREADS} + Swap – siehe REGION + docker-compose.yml
EOF

motd_ssh
customize
cleanup_lxc
