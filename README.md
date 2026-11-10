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

Gatus meldt via een incoming webhook in Digilab Chat (Mattermost). Er zijn er twee, elk op een eigen laag van `MATTERMOST_WEBHOOK_URL` in Operations Manager:

| Laag | Webhook | Kanaal |
|---|---|---|
| Override op deployment `stable` | de webhook-url uit de ConfigMap op het Standaard Platform | het teamkanaal waar de meldingen van beide Gatussen landen |
| Componentbreed op `gatus` | de acceptatie-webhook | [`alerts-test`](https://digilab.overheid.nl/chat/mijnoverheid-zakelijk/channels/alerts-test), alleen voor deze bot |

Een override op een deployment wint van de componentbrede waarde, en reist niet mee naar een preview. Zo meldt `stable` in het teamkanaal en een preview (`pr-<nummer>`) in het testkanaal: een config-wijziging is vóór de merge met echte meldingen te zien, zonder het teamkanaal te vervuilen. Een preview draait de volledige config, dus een echte storing staat in het testkanaal ook.

Staat de webhook van het teamkanaal componentbreed, dan erft elke preview hem, en meldt een PR met een falende controle elk kwartier in het teamkanaal.

**Een webhook aanvragen** gaat volgens de [handleiding van Digilab Chat](https://digilab.overheid.nl/docs/mattermost/#bots):

1. Een team-admin maakt hem aan via **Integrations** → **Incoming Webhooks** → **Add Incoming Webhook**. Weet niemand wie team-admin is, vraag het dan in het kanaal `mattermost-perikelen` van Digilab.
2. Digilab Chat zet elke webhook vast op zijn kanaal; hij kan nergens anders posten.
3. Een kanaal voor een bot krijgt een naam waaraan je ziet dat er alleen automatische berichten staan, zoals `alerts-test`, met de naam van de tool in de kanaalheader. Geen gesprekken in zo'n kanaal.
4. De url is een wachtwoord: wie hem heeft, kan onder elke naam in het kanaal posten. Hij hoort alleen in Operations Manager, nooit in een repository, chat of ticket. Is hij uitgelekt, verwijder hem dan onder **Incoming Webhooks** en maak een nieuwe aan; zet de nieuwe url ook bij elke andere afnemer (het demopaneel van het Federatief Berichtenstelsel gebruikt de webhook van het teamkanaal ook).

Zonder `MATTERMOST_WEBHOOK_URL` start Gatus wel, maar negeert hij de Mattermost-provider en verstuurt hij geen alerts; de opstartregel `configuredProviders=[mattermost]` in de log bevestigt dat hij er wel is.

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
