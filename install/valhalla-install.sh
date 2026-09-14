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
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ---------- 1. Region -> PBF-URLs + Kartenzentrum auflösen ----------
TILE_REGION="${var_tile_region:-${TILE_REGION:-saarland}}"
TILE_URLS_CUSTOM="${var_tile_urls:-${TILE_URLS:-}}"
WEB_PORT="${var_web_port:-80}"
VALHALLA_PORT="${var_valhalla_port:-8002}"

resolve_region() {
  case "$1" in
  andorra)     echo "URLS=https://download.geofabrik.de/europe/andorra-latest.osm.pbf|CENTER=42.55,1.58" ;;
  saarland)    echo "URLS=https://download.geofabrik.de/europe/germany/saarland-latest.osm.pbf|CENTER=49.38,7.07" ;;
  nrw)         echo "URLS=https://download.geofabrik.de/europe/germany/nordrhein-westfalen-latest.osm.pbf|CENTER=51.43,7.66" ;;
  germany)     echo "URLS=https://download.geofabrik.de/europe/germany-latest.osm.pbf|CENTER=51.16,10.45" ;;
  austria)     echo "URLS=https://download.geofabrik.de/europe/austria-latest.osm.pbf|CENTER=47.51,14.55" ;;
  switzerland) echo "URLS=https://download.geofabrik.de/europe/switzerland-latest.osm.pbf|CENTER=46.82,8.22" ;;
  dach)        echo "URLS=https://download.geofabrik.de/europe/germany-latest.osm.pbf https://download.geofabrik.de/europe/austria-latest.osm.pbf https://download.geofabrik.de/europe/switzerland-latest.osm.pbf|CENTER=48.14,11.58" ;;
  custom)      echo "URLS=${TILE_URLS_CUSTOM}|CENTER=51.16,10.45" ;;
  *)           echo "URLS=https://download.geofabrik.de/europe/germany-latest.osm.pbf|CENTER=51.16,10.45" ;;
  esac
}

if [[ -n "$TILE_URLS_CUSTOM" && -z "$TILE_REGION" ]]; then TILE_REGION="custom"; fi
if [[ "$TILE_REGION" == "custom" && -z "$TILE_URLS_CUSTOM" ]]; then
  msg_error "Region 'custom' gewählt, aber keine URL in var_tile_urls gesetzt!"
  exit 1
fi
# Interaktiv nachfragen, falls im Container noch nichts gesetzt (manueller Lauf)
if [[ -z "${var_tile_region:-}" && -z "${var_tile_urls:-}" && -t 0 ]]; then
  msg_info "Welche Karte soll gebaut werden? [saarland/andorra/nrw/germany/austria/switzerland/dach]"
  read -r -p "Region (default: saarland): " _r || true
  TILE_REGION="${_r:-saarland}"
fi

RESOLVED="$(resolve_region "$TILE_REGION")"
TILE_URLS="$(echo "$RESOLVED" | cut -d'|' -f1 | cut -d'=' -f2-)"
CENTER_COORDS="$(echo "$RESOLVED" | cut -d'|' -f2 | cut -d'=' -f2)"
if [[ "$TILE_REGION" == "custom" ]]; then TILE_URLS="$TILE_URLS_CUSTOM"; fi

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
LOCAL_IP="$(hostname -I | awk '{print $1}')"
THREADS="$(nproc)"
msg_ok "Arbeitsverzeichnis bereit (CPU-Threads: $THREADS, IP: $LOCAL_IP)"

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
cat <<EOF >/opt/valhalla/web-app-src/.env
SKIP_PREFLIGHT_CHECK=true
VITE_VALHALLA_URL=/valhalla
VITE_NOMINATIM_URL=https://nominatim.openstreetmap.org
VITE_TILE_SERVER_URL="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
VITE_CENTER_COORDS="${CENTER_COORDS}"
VITE_DEFAULT_COSTING_MODEL=auto
VITE_CLIENT_ID=valhalla-pve-lxc
EOF

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

  # Valhalla-API hinter gleichem Origin (kein CORS-Problem, IP-unabhängig)
  # Frontend ruft /valhalla/route, /valhalla/isochrone, ... auf
  location /valhalla/ {
    rewrite ^/valhalla/(.*) /$1 break;
    proxy_pass http://valhalla:8002;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
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

# ---------- 8. Hilfsskripte + MOTD ----------
cat <<EOF >/opt/valhalla/rebuild.sh
#!/usr/bin/env bash
# Tiles neu bauen (z. B. nach PBF-Tausch in custom_files/)
cd /opt/valhalla
docker compose run --rm -e force_rebuild=True -e build_tar=True valhalla || true
docker compose restart valhalla
docker logs -f valhalla
EOF
chmod +x /opt/valhalla/rebuild.sh

cat <<EOF >/opt/valhalla/README.txt
Valhalla LXC – Kurzanleitung
============================
Web-App : http://${LOCAL_IP}:${WEB_PORT}/
API     : http://${LOCAL_IP}:${VALHALLA_PORT}/status
Test    : curl http://${LOCAL_IP}:${VALHALLA_PORT}/status
Route   : curl -s http://${LOCAL_IP}:${VALHALLA_PORT}/route -d '{"locations":[{"lat":48.14,"lon":11.58},{"lat":48.20,"lon":11.65}],"costing":"auto"}'

PBF tauschen: neue .pbf nach /opt/valhalla/custom_files/ legen, dann ./rebuild.sh
Logs: docker logs -f valhalla   |   docker logs valhalla-web
Stack: cd /opt/valhalla && docker compose ps / docker compose up -d
EOF

motd_ssh
customize
cleanup_lxc
