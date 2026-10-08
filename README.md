# moza-gatus

[Gatus](https://github.com/TwiN/gatus) healthcheck-dashboard voor MijnOverheidZakelijk, gedeployed op ZAD.

Dit is de ZAD-variant van de Gatus die op het Standaard Platform draait (Helm chart `twin/gatus` 1.5.0, namespace `logius-moz-poc`, infra-files op de Logius GitLab). De config komt overeen met die op het Standaard Platform, met twee verschillen: de Mattermost-webhook komt uit een env-var in plaats van uit de ConfigMap, en de cluster-interne checks (profiel-service dev en acceptatie op poort 9090, Keycloak) ontbreken, want die adressen zijn vanaf ZAD niet bereikbaar. De profiel-service acceptatie wordt via de publieke URL gecontroleerd.

## Hoe het werkt

ZAD deployt uitsluitend een container-image, dus de config zit in de image:

- `Dockerfile`: `twinproduction/gatus:v5.34.0` (de versie van chart 1.5.0) met de map `config/` op `/config` en `GATUS_CONFIG_PATH=/config`. Gatus voegt alle `*.yaml`-bestanden in die map en de submappen samen tot een config.
- `config/config.yaml`: UI en alerting. `webhook-url` is `${MATTERMOST_WEBHOOK_URL}`; Gatus vult env-vars in bij het laden van de config.
- `config/<project>/endpoints.yaml`: de endpoints per project, elk in een eigen map:
  - `mijnoverheidzakelijk/`: de endpoints van het Standaard Platform.
  - `moza-proef/`: de MOZa-proefomgeving op <https://proef.moza.rijksapp.dev/moza/>, in het dashboard gebundeld onder de groep `moza proef`.

Een nieuw project toevoegen: maak `config/<project>/endpoints.yaml` aan, geef de endpoints een eigen `group` en zet de namen in `EXPECTED_ENDPOINTS` in `test/smoke.sh`.
- `.github/workflows/deploy.yml`: pull requests draaien de smoke test; een push naar `main` bouwt de image, pusht die naar GHCR en deployt op digest naar de `stable`-deployment via `RijksICTGilde/zad-actions/deploy`.

## Eenmalige setup

1. ZAD-project aanmaken voor Gatus en de project-id invullen in `ZAD_PROJECT_ID` in `deploy.yml`.
2. In Operations Manager een deployment `stable` met component `gatus` aanmaken.
3. Op die deployment de env-var `MATTERMOST_WEBHOOK_URL` zetten (de webhook-url uit de ConfigMap op het Standaard Platform). Zonder die env-var start Gatus wel, maar negeert hij de Mattermost-provider en verstuurt hij geen alerts.
4. Repo-secret `ZAD_API_KEY` zetten.

## Lokaal testen

```sh
sh test/smoke.sh                       # podman, of docker als podman ontbreekt
CONTAINER_CLI=docker sh test/smoke.sh
```

De smoke test bouwt de image, start hem, wacht op `/health`, controleert dat de Mattermost-provider geconfigureerd is en dat alle endpoints uit `config/` in `/api/v1/endpoints/statuses` verschijnen. De verwachte endpoint-namen staan in `EXPECTED_ENDPOINTS` in `test/smoke.sh`; voeg je een endpoint toe aan de config, voeg die naam daar dan ook toe.

Handmatig draaien:

```sh
podman build -t moza-gatus .
podman run --rm -p 8080:8080 -e MATTERMOST_WEBHOOK_URL=... moza-gatus
```

Dashboard op <http://localhost:8080>.
