# haproxy-unraid: offizielles HAProxy-Image + Vorlage, Prüfung mit Rücksprung,
# Zertifikate aus Cert Warden und JSON-Logs für Home Assistant (access_monitor).
# Neu gebaut, sobald das offizielle Image (z. B. haproxy:3.4-alpine) sich ändert.
ARG HAPROXY_TAG=3.4-alpine
FROM haproxy:${HAPROXY_TAG}

ARG HAPROXY_TAG
ARG BASE_DIGEST=unbekannt
ARG QUELLE=https://github.com/
LABEL org.opencontainers.image.title="haproxy-unraid" \
      org.opencontainers.image.description="HAProxy mit TLS-Ende, Sperrgründen, Prüfung mit Rücksprung und Cert-Warden-Zertifikaten für Unraid" \
      org.opencontainers.image.source="${QUELLE}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="docker.io/library/haproxy:${HAPROXY_TAG}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}"

USER root
RUN apk add --no-cache bash tini curl openssl socat diffutils
COPY vorlage/ /opt/haproxy-vorlage/
COPY bin/hap-lib.sh /usr/local/lib/hap-lib.sh
COPY bin/start.sh bin/hap-uebernehmen bin/hap-zertifikate bin/hap-waechter /usr/local/bin/
# Zeilenenden absichern (Bearbeitung unter Windows) und Selbsttest der Skripte
RUN sed -i 's/\r$//' /usr/local/bin/start.sh /usr/local/bin/hap-* /usr/local/lib/hap-lib.sh \
 && chmod 755 /usr/local/bin/start.sh /usr/local/bin/hap-* \
 && for f in /usr/local/bin/start.sh /usr/local/bin/hap-* /usr/local/lib/hap-lib.sh; do bash -n "$f"; done

ENV HAPROXY_DIR=/usr/local/etc/haproxy \
    CERT_INTERVALL=3600 \
    TZ=Europe/Berlin
VOLUME /usr/local/etc/haproxy
EXPOSE 80 443 8404
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -q -T 4 -O /dev/null http://127.0.0.1:8404/metrics || exit 1
# tini als PID 1: reicht Signale weiter (docker stop = sanftes Beenden) und räumt Prozesse auf
STOPSIGNAL SIGUSR1
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/start.sh"]
CMD []
