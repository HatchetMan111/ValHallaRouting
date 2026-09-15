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

Mit Vorgaben (ohne Menü) – Default ganz Deutschland:

```bash
var_cpu=4 var_ram=8192 var_disk=50 var_tile_region=germany \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ValHallaRouting/main/ct/valhalla.sh)"
```

Regionen (`var_tile_region`):
`germany` (Default, ~4 GB PBF, 60–180 Min) · alle 16 Bundesländer einzeln
(`bw` `bayern` `berlin` `brandenburg` `bremen` `hamburg` `hessen`
`mecklenburg-vorpommern` `niedersachsen` `nrw` `rheinland-pfalz` `saarland`
`sachsen` `sachsen-anhalt` `schleswig-holstein` `thueringen`)
· Kombis (`bw-bayern`, oder Leerzeichen-getrennt wie `"bw bayern hessen"`)
· `austria` · `switzerland` · `dach` · `andorra` (Test, ~2 Min)
· `custom` (+ `var_tile_urls="https://..."`)

Es wird **nur** die gewählte Region von Geofabrik geladen (kein stiller
Germany-Fallback; unbekannte Namen brechen mit Fehler ab). Im Menü mehrere
Länder Komma-getrennt wählen, z. B. `4,5` — oder per Variable:

```bash
var_tile_region="bw bayern" bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ValHallaRouting/main/ct/valhalla.sh)"
```

## Struktur

```
ct/valhalla.sh                  # Host-Script: erstellt LXC (Debian 13, Docker, nesting)
install/valhallrouting-install.sh  # läuft IM Container: Docker-Stack /opt/valhalla
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
./check-route.sh               # Diagnose: Route + Optimized Route + Build-Fehler
cat REGION                     # welche Region/Zentrum wurde gebaut?
```

## Wenn die Route fehlschlägt („optimale Route" / Fehlermeldung)

1. **Punkt außerhalb der Region** (häufigster Fall, Fehler `NoSegment` /
   `could not snap`): Es wird nur geroutet, was in den Tiles ist.
   Wer z. B. nur `saarland` gebaut hat, kann nicht München–Berlin testen.
   Lösung: Punkte **innerhalb** der gebauten Region wählen
   (Zentrum steht in `/opt/valhalla/REGION` → `CENTER_COORDS`) oder
   Diagnose laufen lassen: `./check-route.sh`.
2. **Optimized Route braucht mind. 4 Punkte** + Costing
   `auto`/`bicycle`/`pedestrian` (kein `truck`/`bus`/`multimodal`).
   Mit 2–3 Punkten oder falschem Costing antwortet `/optimized_route`
   immer mit 400 – das ist Valhalla-Verhalten, kein Proxy-Fehler.
3. **Tiles unvollständig (Segfault-Build):** Valhalla serviert auch kaputte
   Tiles weiter (`serve_tiles=True`), Routen schlagen dann flächendeckend
   fehl. Prüfen: `docker logs valhalla | grep -iE 'segfault|killed|oom|aborted'`.
   Falls ja → neu bauen mit `server_threads=1` (siehe unten), nicht einfach
   Container neu starten (`use_tiles_ignore_pbf=True` würde die kaputten
   Tiles wiederverwenden!).

## Ressourcen / Vergrößern

- Default (Deutschland): ~4 GB PBF, ~25 GB Tiles → 4 CPU / 8 GB RAM / 50 GB Disk
- **Germany-Crash (`valhalla_build_tiles` Segfault in `enhance`, „Tile-Build
  in 101 ist abgestürzt"):** Das ist OOM – `server_threads` steuert beim
  Scripted-Image Build-Concurrency *und* Service-Threads. Faustregel
  1 Thread pro ~4 GB RAM. Deshalb Auto-Modus: `germany`/`dach` → **1 Thread**,
  sonst max. 2; zusätzlich wird 8 GB Swap angelegt (wenn möglich) und bei
  zu hohem `var_server_threads` automatisch gedeckelt. Explizit setzen nur
  mit mehr RAM: `var_server_threads=1` (8 GB, Germany, sicher) bzw.
  `var_server_threads=2` (ab 16 GB).
- Später vergrößern: in Proxmox-GUI RAM/CPU hoch + `pct resize <CTID> rootfs +20G`
  (oder neue PBF nach `/opt/valhalla/custom_files/` + `./rebuild.sh`)
- Update: Host-Script erneut laufen lassen (`docker compose pull + up --build`)
