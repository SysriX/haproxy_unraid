#!/bin/bash
# Start des Containers: Vorlage beim ersten Start anlegen, Ersatz-Zertifikat, Prüfung,
# Zertifikate regelmäßig aus Cert Warden holen, dann HAProxy (master-worker) starten.
set -euo pipefail
. /usr/local/lib/hap-lib.sh

for v in CW_IP CW_HOST STATS_PASS; do
  val="${!v:-}"
  case "$val" in ""|*"<"*) fehler "Variable $v in der Unraid-Vorlage setzen";; esac
done
export HA_SYSLOG="${HA_SYSLOG:-127.0.0.1:5514}"

mkdir -p "$D/certs"
for z in bearbeiten aktiv; do
  if [ ! -f "$D/$z/haproxy.cfg" ]; then
    mkdir -p "$D/$z"; cp -r /opt/haproxy-vorlage/. "$D/$z/"
    sed -i "/^#/! s|<Name_CertWarden>|$CW_HOST|" "$D/$z/listen/dienste.map"
    log "$z/ aus der Vorlage angelegt"
  fi
done
[ -f "$D/certs.conf" ] || cat > "$D/certs.conf" <<'EOF'
# Zertifikate aus Cert Warden für Dienste im Modus "tls", je Zeile:
#   <name-in-cert-warden> <zertifikat-api-key>.<schluessel-api-key>
EOF
chmod 600 "$D/certs.conf"

if [ ! -f "$D/certs/000-ersatz.pem" ]; then
  T="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=haproxy-ersatz" \
    -keyout "$T/k.pem" -out "$T/c.pem" 2>/dev/null
  cat "$T/c.pem" "$T/k.pem" > "$D/certs/000-ersatz.pem"; rm -rf "$T"
  log "Ersatz-Zertifikat erzeugt"
fi
chmod 700 "$D/certs"; chmod 600 "$D/certs/"*.pem

# Ist aktiv/ ungültig (z. B. von Hand geändert), mit vorher/ starten statt gar nicht
if ! pruefe_cfg aktiv; then
  if [ -f "$D/vorher/haproxy.cfg" ] && pruefe_cfg vorher; then
    log "aktiv/ ist ungültig – starte mit vorher/"; nach_aktiv vorher
  else
    fehler "aktiv/ ist ungültig und es gibt kein gültiges vorher/ – siehe Meldung oben"
  fi
fi

# Zertifikate holen: kurz nach dem Start, danach alle CERT_INTERVALL Sekunden
( sleep 30; while true; do hap-zertifikate || true; sleep "${CERT_INTERVALL:-3600}"; done ) &

# Aufträge der Weboberfläche (haproxy-ui) – läuft nur mit, wenn UI_WAECHTER nicht 0 ist
[ "${UI_WAECHTER:-1}" = 0 ] || hap-waechter &

log "starte HAProxy $(haproxy -v | head -1 | awk '{print $3}')"
exec haproxy -W -db -S "$MASTER_SOCK" -f "$D/aktiv/haproxy.cfg" -f "$D/aktiv/dienste.cfg"
