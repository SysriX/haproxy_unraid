# haproxy-unraid

HAProxy 3.4 LTS (offizielles Image `haproxy:3.4-alpine`) als zentraler Eingang für außen und innen – vorbereitet für Unraid.

`ghcr.io/sysrix/haproxy-unraid:latest`

## Was es kann

- **TLS-Ende** mit eigenen Zertifikaten oder **verschlüsselt durchreichen** – je Dienst über den Namen (SNI)
- **intern / alle**: Dienste nur aus internen Netzen oder auch von außen erreichbar
- **Schutzregeln** mit benannten Ablehnungsgründen: Scanner-Pfade, Passwort-Raten, unbekannte Namen, Sperrliste, automatische Sperre für 15 Minuten
- **Sicheres Übernehmen**: jede Änderung wird geprüft, ohne Verbindungsabbruch neu geladen und springt bei Fehlern automatisch zurück
- **Zertifikate aus Cert Warden** (optional), stündlich abgeholt, neu geladen nur bei Änderung
- **Statistik und Prometheus** an Port 8404 (nur interne Netze)
- **JSON-Zugriffslogs** per Syslog, z. B. an einen Home-Assistant-Zugriffsmonitor
- Weboberfläche dazu: [haproxy-ui](../haproxy-ui/README.md) (optional)

Läuft **allein**; Cert Warden und haproxy-ui sind optional.

## Installation in Unraid

1. Vorlage holen (einmal in der Unraid-Konsole), danach in **Apps › Private** `haproxy-unraid` installieren:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/SysriX/unraid-images/main/unraid/private-vorlagen.sh | bash
   ```
2. Netzwerk `br0` (bzw. das VLAN der Firewall) und eine **feste IP** wählen. Keine Portfreigaben nötig; die Firewall leitet WAN 80/443 auf diese IP.
3. Variablen ausfüllen (siehe unten) und starten. Beim ersten Start wird die Vorlage nach `appdata/haproxy/` kopiert.

## Einstellungen

| Feld | Variable / Pfad | Pflicht | Bedeutung |
| --- | --- | --- | --- |
| Konfiguration | `/usr/local/etc/haproxy` | ja | appdata-Ordner. Unraid ohne Cache: Plattenpfad wie `/mnt/disk1/appdata/haproxy` |
| Statistik-Passwort | `STATS_PASS` | ja | Benutzer `admin`, Port 8404 |
| Cert Warden IP | `CW_IP` | nein | feste IP von certwarden-unraid; leer = ohne Cert Warden |
| Cert Warden Name | `CW_HOST` | nein | Adresse von Cert Warden **selbst** (z. B. `certwarden.example.de`), nicht die Zertifikate der Dienste – die stehen in `certs.conf` |
| Home Assistant Syslog | `HA_SYSLOG` | nein | `IP:Port` (UDP) für JSON-Logs; `127.0.0.1:5514` = aus |
| Zertifikats-Intervall | `CERT_INTERVALL` | nein | Sekunden zwischen zwei Abrufen (Standard 3600) |
| Cert Warden ohne Prüfung | `CW_UNSICHER` | nein | `1` = Zertifikat von Cert Warden nicht prüfen (nur am Anfang) |
| Weboberfläche zulassen | `UI_WAECHTER` | nein | `1` = Aufträge aus haproxy-ui ausführen, `0` = aus |

## Ordner im appdata

| Ordner / Datei | Inhalt |
| --- | --- |
| `bearbeiten/` | hier ändern: `haproxy.cfg`, `dienste.cfg` (Backends), `listen/dienste.map`, `listen/*.lst` |
| `aktiv/` | läuft gerade – nicht von Hand ändern |
| `vorher/` | vorige Fassung für den Rücksprung |
| `certs/` | Zertifikate (`<name>.pem` = Schlüssel + Zertifikat + Kette) |
| `certs.conf` | welche Zertifikate aus Cert Warden geholt werden |

### Dienste eintragen

`bearbeiten/listen/dienste.map`, je Zeile:

```
<name>   <backend>:<zugang>:<modus>
nextcloud.example.de   be_nextcloud:alle:tls
unraid.example.de      be_unraid:intern:tls
mail.example.de        be_mail:alle:durch
```

- **Zugang** `alle` = außen und innen, `intern` = nur aus `listen/intern-netze.lst`
- **Modus** `tls` = HAProxy beendet TLS (Backend `mode http`), `durch` = verschlüsselt durchreichen (Backend `mode tcp`)

Das Backend dazu kommt in `bearbeiten/dienste.cfg`.

### Zertifikate

- **Mit Cert Warden:** in `certs.conf` je Zeile `<name-in-cert-warden> <zertifikat-api-key>.<schluessel-api-key>`.
- **Ohne Cert Warden:** eigene `.pem` (Schlüssel + Zertifikat + Kette) nach `certs/` legen, dann `hap-uebernehmen`.

**Beliebig viele Zertifikate und Domains:** je Zertifikat eine Zeile in `certs.conf`, z. B.

```
mail   <key>.<key>     # mail.deinedomain.de
cloud  <key>.<key>     # cloud.andere-domain.de
web    <key>.<key>     # deinedomain.de + www.deinedomain.de
```

Daraus werden `certs/mail.pem`, `certs/cloud.pem`, `certs/web.pem`. HAProxy lädt den ganzen Ordner und wählt je Anfrage das Zertifikat, das zum angefragten Namen (SNI) passt – egal zu welcher Domain. Wildcards wie `*.deinedomain.de` (nur per DNS-01) decken alle Subdomains mit einer Zeile ab. Passt kein Zertifikat, liefert HAProxy das Ersatz-Zertifikat `000-ersatz.pem`.

## Bedienung (Unraid-Konsole)

| Befehl | Wirkung |
| --- | --- |
| `docker exec haproxy-unraid hap-uebernehmen` | `bearbeiten/` prüfen, übernehmen, ohne Abbruch neu laden, bei Fehler zurück |
| `docker exec haproxy-unraid hap-uebernehmen --pruefen` | nur prüfen |
| `docker exec haproxy-unraid hap-uebernehmen --zurueck` | vorige Konfiguration |
| `docker exec haproxy-unraid hap-zertifikate` | Zertifikate jetzt aus Cert Warden holen |

Bequemer geht es mit der Weboberfläche [haproxy-ui](../haproxy-ui/README.md).

## Ports

| Port | Zweck |
| --- | --- |
| 80 | HTTP: Let's-Encrypt-Prüfung an Cert Warden, sonst Umleitung auf https |
| 443 | HTTPS: Dienste nach Name |
| 8404 | Statistik (`/`) und Prometheus (`/metrics`), nur interne Netze |

## Updates

Das Image wird automatisch neu gebaut, sobald das offizielle HAProxy-Image aktualisiert wird. Unraid zeigt dann „Update verfügbar“. Tags: `latest`, die HAProxy-Version (z. B. `3.4.1`) und `Version-Datum`.
