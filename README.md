# moza-gatus

[Gatus](https://github.com/TwiN/gatus) healthcheck-dashboard voor MijnOverheidZakelijk, gedeployed op ZAD.

Dit is de ZAD-variant van de Gatus die op het Standaard Platform draait (Helm chart `twin/gatus` 1.5.0, namespace `logius-moz-poc`, infra-files op de Logius GitLab). De config komt overeen met die op het Standaard Platform, met twee verschillen: de Mattermost-webhook komt uit een env-var in plaats van uit de ConfigMap, en de cluster-interne checks (profiel-service dev en acceptatie op poort 9090, Keycloak) ontbreken, want die adressen zijn vanaf ZAD niet bereikbaar. De profiel-service acceptatie wordt via de publieke URL gecontroleerd.

## Hoe het werkt

ZAD deployt uitsluitend een container-image, dus de config zit in de image:

- `Dockerfile`: `twinproduction/gatus:v5.34.0` (de versie van chart 1.5.0) met de map `config/` op `/config` en `GATUS_CONFIG_PATH=/config`. Gatus voegt alle `*.yaml`-bestanden in die map en de submappen samen tot een config.
- `config/config.yaml`: UI en alerting. `webhook-url` is `${MATTERMOST_WEBHOOK_URL}`; Gatus vult env-vars in bij het laden van de config. Het dashboard sorteert standaard op groep (`default-sort-by: group`).
- `config/<domein>/endpoints.yaml`: de endpoints per domein, elk in een eigen map. De mapnaam is ook de `group` van de endpoints, zodat elk domein op het dashboard een eigen blok heeft:
  - `mijnoverheidzakelijk.nl/`: alles op mijnoverheidzakelijk.nl, de endpoints van het Standaard Platform.
  - `proef.moza.rijksapp.dev/`: de MOZa-proefomgeving op <https://proef.moza.rijksapp.dev/moza/>.
- `.github/workflows/deploy.yml`: pull requests draaien de smoke test en krijgen een preview op deployment `pr-<nummer>` (url als PR-comment, alerts naar het testkanaal `alerts-test`, opgeruimd bij sluiten van de PR); een push naar `main` bouwt de image, pusht die naar GHCR en deployt op digest naar de `stable`-deployment via `RijksICTGilde/zad-actions/deploy`.

Een nieuw domein toevoegen: maak `config/<domein>/endpoints.yaml` aan, geef de endpoints `group: <domein>` en zet de namen in `EXPECTED_ENDPOINTS` in `test/smoke.sh`.

## Eenmalige setup

1. ZAD-project aanmaken voor Gatus en de project-id invullen in `ZAD_PROJECT_ID` in `deploy.yml`.
2. In Operations Manager een deployment `stable` met component `gatus` aanmaken.
3. De twee webhooks zetten zoals beschreven onder [Mattermost-webhooks](#mattermost-webhooks).
4. Repo-secret `ZAD_API_KEY` zetten.

## Mattermost-webhooks

Twee incoming webhooks, elk op een eigen laag van `MATTERMOST_WEBHOOK_URL` in Operations Manager:

- **Override op deployment `stable`:** de webhook van het teamkanaal (uit de ConfigMap op het Standaard Platform).
- **Componentbreed op `gatus`:** de webhook van [`alerts-test`](https://digilab.overheid.nl/chat/mijnoverheid-zakelijk/channels/alerts-test). Previews (`pr-<nummer>`) erven die, want een deployment-override reist niet mee naar een preview. Zo zie je een config-wijziging vóór de merge met echte meldingen, buiten het teamkanaal.

Zet de webhook van het teamkanaal dus nooit componentbreed: dan meldt elke PR met een falende controle elk kwartier in het teamkanaal.

Een webhook vraag je aan volgens de [handleiding van Digilab Chat](https://digilab.overheid.nl/docs/mattermost/#bots): een team-admin maakt hem aan via **Integrations** → **Incoming Webhooks** → **Add Incoming Webhook**, en hij post alleen in zijn eigen kanaal. De url is een wachtwoord: alleen in Operations Manager, nooit in een repository, chat of ticket. Uitgelekt? Verwijder hem en maak een nieuwe; het demopaneel van het Federatief Berichtenstelsel gebruikt de webhook van het teamkanaal ook.

De opstartregel `configuredProviders=[mattermost]` in de log bevestigt dat Gatus een webhook heeft; zonder meldt hij niets.

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
