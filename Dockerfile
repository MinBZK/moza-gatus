# Same Gatus version as Helm chart twin/gatus 1.5.0 on the Standaard Platform.
FROM twinproduction/gatus:v5.34.0

# Gatus merges every *.yaml in GATUS_CONFIG_PATH and its subdirectories, so each
# project gets its own folder under config/.
COPY config/ /config/
ENV GATUS_CONFIG_PATH=/config

# ZAD only runs rootless images; Gatus needs no privileges (port 8080, read-only config).
USER 65534:65534
