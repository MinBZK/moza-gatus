# Same Gatus version as Helm chart twin/gatus 1.5.0 on the Standaard Platform.
FROM twinproduction/gatus:v5.34.0

COPY config/config.yaml /config/config.yaml

# ZAD only runs rootless images; Gatus needs no privileges (port 8080, read-only config).
USER 65534:65534
