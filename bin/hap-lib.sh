# Gemeinsame Funktionen für start.sh, hap-uebernehmen, hap-zertifikate (wird per "." geladen)
D="${HAPROXY_DIR:-/usr/local/etc/haproxy}"
MASTER_SOCK=/tmp/master.sock

log()    { echo "[$(basename "$0")] $*"; }
fehler() { echo "[$(basename "$0")] FEHLER: $*" >&2; exit 1; }

# haproxy -c für einen Unterordner (bearbeiten | aktiv | vorher)
pruefe_cfg() { haproxy -c -q -f "$D/$1/haproxy.cfg" -f "$D/$1/dienste.cfg"; }

# Läuft HAProxy und antwortet die Statistik?
antwortet() { wget -q -T 5 -O /dev/null http://127.0.0.1:8404/metrics; }

# Neu laden ohne Verbindungsabbruch. Der Master meldet seit HAProxy 2.7 "Success=1|0".
neu_laden() {
  local out
  out="$(echo reload | socat -t 60 "$MASTER_SOCK" - 2>&1)" || { log "Master-Socket nicht erreichbar"; return 1; }
  case "$out" in *"Success=0"*) echo "$out" | tail -20 >&2; return 1;; esac
  sleep 2; antwortet
}

# jedes Backend aus dienste.map existiert und hat den passenden Modus
pruefe_map() {   # $1 = Unterordner
  local dir="$D/$1" ok=0 name wert be zugang modus mode want
  while read -r name wert _; do
    [ -z "${name:-}" ] && continue; [ "${name:0:1}" = "#" ] && continue
    case "$name$wert" in *"<"*) echo "  $name: Platzhalter <...> noch nicht ersetzt"; ok=1; continue;; esac
    IFS=: read -r be zugang modus <<<"$wert"
    case "$zugang" in alle|intern) ;; *) echo "  $name: Zugang '$zugang' (erlaubt: alle|intern)"; ok=1; continue;; esac
    case "$modus" in tls) want=http;; durch) want=tcp;; *) echo "  $name: Modus '$modus' (erlaubt: tls|durch)"; ok=1; continue;; esac
    mode="$(awk -v b="$be" '
      $1=="backend" && $2==b {inb=1; found=1; next}
      inb && ($1=="backend"||$1=="frontend"||$1=="listen"||$1=="defaults") {inb=0}
      inb && $1=="mode" {m=$2}
      END {if (found) print (m==""?"tcp":m); else print "FEHLT"}' "$dir"/*.cfg)"
    if [ "$mode" = FEHLT ]; then echo "  $name: Backend '$be' fehlt"; ok=1
    elif [ "$mode" != "$want" ]; then echo "  $name: Backend '$be' hat mode $mode, Modus $modus braucht mode $want"; ok=1; fi
  done < "$dir/listen/dienste.map"
  return $ok
}

# Ordner $1 wird zu aktiv/ (Inhalt ersetzt, Ordnername bleibt)
nach_aktiv() {
  rm -rf "$D/aktiv.neu" && cp -r "$D/$1" "$D/aktiv.neu" || fehler "Kopieren fehlgeschlagen"
  rm -rf "$D/aktiv.alt"; mv "$D/aktiv" "$D/aktiv.alt" && mv "$D/aktiv.neu" "$D/aktiv" && rm -rf "$D/aktiv.alt"
}
