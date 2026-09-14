# ValHallaRouting – Valhalla + Web-App für Proxmox VE (LXC)

Installiert [Valhalla](https://github.com/valhalla/valhalla) (Routing-Engine) +
[Web-App](https://github.com/valhalla/web-app) als LXC auf Proxmox VE –
im Stil der Proxmox Community-Scripts.

Am Ende: `http://<LXC-IP>/` sofort nutzbar wie `valhalla.openstreetmap.de`
(Route, Isochrone, Matrix), API direkt unter `http://<LXC-IP>:8002/status`.

## Install (Proxmox-Host als root)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ValHallaRouting/main/ct/valhalla.sh)"
```

Mit Vorgaben (ohne Menü):

```bash
var_cpu=4 var_ram=8192 var_disk=40 var_tile_region=germany \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ValHallaRouting/main/ct/valhalla.sh)"
```

Regionen (`var_tile_region`):
`andorra` (Test, ~2 Min) · `saarland` · `nrw` · `germany` (Default, 30–60 Min)
· `austria` · `switzerland` · `dach` · `custom` (+ `var_tile_urls="https://..."`)

## Struktur

```
ct/valhalla.sh            # Host-Script: erstellt LXC (Debian 13, Docker, nesting)
install/valhalla-install.sh  # läuft IM Container: Docker-Stack /opt/valhalla
```

Stack in `/opt/valhalla`:
- `valhalla` (`ghcr.io/valhalla/valhalla-scripted`, PBF→Tiles auto, `:8002`)
- `valhalla-web` (`valhalla/web-app` Build + nginx Proxy `/valhalla` → `:8002`, `:80`)

Frontend nutzt `VITE_VALHALLA_URL=/valhalla` → IP-unabhängig, kein CORS.
Suche/Tiles: public Nominatim + OSM-Tiles (Routing selbst 100% lokal).

## Nützliches im LXC

```bash
docker logs -f valhalla        # Tiles-Bau live
docker logs valhalla-web
curl http://127.0.0.1:8002/status
cd /opt/valhalla && docker compose ps
./rebuild.sh                   # nach PBF-Tausch in custom_files/
```

## Ressourcen

- Germany: ~4 GB PBF, ~25 GB Tiles → 4 CPU / 8 GB RAM / 40 GB Disk
- Update: Host-Script erneut laufen lassen (`docker compose pull + up --build`)
