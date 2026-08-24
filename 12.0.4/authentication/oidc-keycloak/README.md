# HCL Sametime 12.0.4 – OIDC-Integration mit Keycloak unter Docker

## 1. Ziel

Diese Dokumentation beschreibt die Einrichtung einer OIDC-basierten Single-Sign-on-Anmeldung zwischen:

- HCL Sametime 12.0.4
- Docker / Docker Compose
- Keycloak als OpenID Connect Identity Provider

Die Konfiguration ermöglicht die Authentifizierung von Sametime-Benutzern über einen Keycloak-Realm mittels OpenID Connect (OIDC).

> **Wichtig:** SAML und OIDC sollten nicht miteinander vermischt werden. Für die hier beschriebene Konfiguration wird ausschließlich **OIDC** verwendet. Eventuell vorhandene SAML-Konfigurationen müssen deaktiviert werden.

Für Mobile Clients ist zusätzlich wichtig, dass `STCONF_IDPURL` auf den Sametime-internen OIDC-Login-Endpunkt zeigt. Der Mobile Client wird also nicht direkt auf den Keycloak-OIDC-Endpunkt gelenkt, sondern zunächst auf den Sametime-Auth-Service.

---

## 2. Voraussetzungen

Folgende Voraussetzungen müssen erfüllt sein:

- HCL Sametime 12.0.4 ist unter Docker installiert.
- Sametime ist über HTTPS erreichbar.
- Keycloak ist über HTTPS erreichbar.
- Die Sametime-Benutzer können den entsprechenden Keycloak-Benutzern eindeutig zugeordnet werden.
- In Keycloak existiert ein OpenID-Connect-Client für Sametime.
- Client-ID und Client-Secret des Keycloak-Clients sind bekannt.
- Zugriff mit `root` oder `sudo` auf den Sametime-Server ist vorhanden.
- Die OIDC Discovery URL des Keycloak-Realm ist vom Sametime-Server erreichbar.

Im Folgenden wird angenommen, dass sich die Sametime-Installation unter folgendem Verzeichnis befindet:

```text
/opt/hcl/sametime
```

In diesem Verzeichnis befinden sich unter anderem:

```text
docker-compose.yml
.env
custom.env
```

---

## 3. Bestehende Konfiguration sichern

Vor Änderungen an der Sametime-Konfiguration sollte eine Sicherung erstellt werden.

```bash
cd /opt/hcl/sametime

cp .env .env.backup
cp custom.env custom.env.backup
cp docker-compose.yml docker-compose.yml.backup
```

Falls bereits eine SAML-Konfiguration vorhanden ist, sollten auch die entsprechenden Dateien gesichert werden:

```bash
cp saml.env saml.env.backup
cp samltruststore.p12 samltruststore.p12.backup
```

sofern diese Dateien vorhanden sind.

---

## 4. Vorhandene SAML-Konfiguration prüfen

Da ausschließlich OIDC verwendet werden soll, muss zunächst geprüft werden, ob noch aktive SAML-Parameter vorhanden sind.

```bash
cd /opt/hcl/sametime

grep -Ei 'OIDC|STCONF|IDP_URL|SAML|AUTH_TOKEN' \
  .env custom.env saml.env 2>/dev/null
```

Bei einer reinen OIDC-Konfiguration dürfen insbesondere keine aktiven SAML-Einstellungen mehr verwendet werden.

Insbesondere darf `IDP_URL` nicht mehr auf einen SAML-Endpunkt zeigen.

Nicht geeignet wäre beispielsweise:

```ini
IDP_URL=https://keycloak.example.com/realms/example/protocol/saml/clients/sametime
```

Für OIDC sollte `IDP_URL` leer sein:

```ini
IDP_URL=
```

Außerdem darf `Saml` nicht mehr im Authentifizierungs-Token enthalten sein.

Nicht geeignet:

```ini
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt,Saml
```

Für OIDC wird stattdessen verwendet:

```ini
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt
```

> **Wichtig:** Eine eventuell vorhandene `saml.env` kann auf dem Dateisystem verbleiben. Sie darf jedoch nicht mehr über `docker-compose.yml` eingebunden werden.

---

## 5. Keycloak OIDC Client

In Keycloak muss ein Client für Sametime als OpenID-Connect-Client eingerichtet werden.

Beispiel:

```text
Client ID: sametime
Protocol:  OpenID Connect
```

Der Client benötigt ein Client Secret.

Dieses Secret wird später in Sametime als

```ini
OIDC_CLIENT_SECRET=
```

hinterlegt.

> **Sicherheit:** Das Client Secret darf nicht in öffentliche Git-Repositories, Dokumentationen oder Support-Ausgaben übernommen werden.

Der Sametime OIDC Callback lautet typischerweise:

```text
https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/cb
```

Dieser Endpunkt muss in Keycloak als gültige Redirect URI erlaubt sein.

Beispiel:

```text
https://sametime.example.com/sametime-auth/api/v1/oidc/cb
```

Als Web Origin wird üblicherweise der Sametime-Host verwendet:

```text
https://sametime.example.com
```

---

## 6. OIDC Discovery prüfen

Keycloak stellt die OIDC-Konfiguration über den standardisierten Discovery Endpoint zur Verfügung.

Das Schema lautet:

```text
https://<KEYCLOAK>/realms/<REALM>/.well-known/openid-configuration
```

Beispiel:

```text
https://keycloak.example.com/realms/example/.well-known/openid-configuration
```

Der Endpoint kann vom Sametime-Server getestet werden:

```bash
curl -s \
  https://keycloak.example.com/realms/example/.well-known/openid-configuration | jq
```

Die Antwort enthält unter anderem:

```json
{
  "issuer": "https://keycloak.example.com/realms/example",
  "authorization_endpoint": "https://keycloak.example.com/realms/example/protocol/openid-connect/auth",
  "token_endpoint": "https://keycloak.example.com/realms/example/protocol/openid-connect/token",
  "userinfo_endpoint": "https://keycloak.example.com/realms/example/protocol/openid-connect/userinfo",
  "jwks_uri": "https://keycloak.example.com/realms/example/protocol/openid-connect/certs"
}
```

Diese Werte können direkt zur Kontrolle der Sametime-Konfiguration verwendet werden.

---

## 7. OIDC in `custom.env` konfigurieren

Die Datei öffnen:

```bash
vi /opt/hcl/sametime/custom.env
```

Die OIDC-Konfiguration enthält mindestens folgende Parameter:

```ini
STCONF_ISOIDC=true

OIDC_CLIENT_ID=<CLIENT-ID>
OIDC_CLIENT_SECRET=<CLIENT-SECRET>

OIDC_ISSUER_URI=https://<KEYCLOAK>/realms/<REALM>
OIDC_AUTHORIZATION_URL=https://<KEYCLOAK>/realms/<REALM>/protocol/openid-connect/auth
OIDC_TOKEN_URL=https://<KEYCLOAK>/realms/<REALM>/protocol/openid-connect/token
OIDC_USER_INFO_URL=https://<KEYCLOAK>/realms/<REALM>/protocol/openid-connect/userinfo

OIDC_SCOPES=openid email profile
```

Beispiel:

```ini
STCONF_ISOIDC=true

OIDC_CLIENT_ID=sametime
OIDC_CLIENT_SECRET=<CLIENT-SECRET>

OIDC_ISSUER_URI=https://keycloak.example.com/realms/example
OIDC_AUTHORIZATION_URL=https://keycloak.example.com/realms/example/protocol/openid-connect/auth
OIDC_TOKEN_URL=https://keycloak.example.com/realms/example/protocol/openid-connect/token
OIDC_USER_INFO_URL=https://keycloak.example.com/realms/example/protocol/openid-connect/userinfo

OIDC_SCOPES=openid email profile
```

> **Wichtig:** `OIDC_ISSUER_URI` ist der Realm-Issuer. Dort darf nicht versehentlich der Authorization- oder Token-Endpoint eingetragen werden.

Der korrekte Wert hat bei Keycloak typischerweise die Form:

```text
https://<KEYCLOAK>/realms/<REALM>
```

`OIDC_SCOPES` sollte mindestens `openid` enthalten. Für Sametime Mobile ist die folgende Konfiguration sinnvoll:

```ini
OIDC_SCOPES=openid email profile
```

---

## 8. JWT-Authentifizierung für Community konfigurieren

Für die OIDC-Konfiguration wird im Community Server JWT verwendet.

In `custom.env`:

```ini
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt
```

Eine vorherige SAML-Konfiguration wie

```ini
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt,Saml
```

muss entsprechend geändert werden.

Kontrolle:

```bash
grep '^STI__ST_BB_NAMES__ST_AUTH_TOKEN=' \
  /opt/hcl/sametime/custom.env
```

Erwartetes Ergebnis:

```text
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt
```

---

## 9. IdP-URLs für OIDC und Mobile konfigurieren

Bei OIDC müssen SAML-IdP-URLs entfernt werden.

In `custom.env`:

```ini
IDP_URL=
```

Für Mobile Clients muss jedoch `STCONF_IDPURL` gesetzt sein.

In `.env`:

```ini
STCONF_IDPURL=https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
```

Beispiel:

```ini
STCONF_IDPURL=https://sametime.example.com/sametime-auth/api/v1/oidc/login
```

Kontrolle:

```bash
grep '^IDP_URL=' /opt/hcl/sametime/custom.env
grep '^STCONF_IDPURL=' /opt/hcl/sametime/.env
```

Erwartetes Ergebnis:

```text
IDP_URL=
STCONF_IDPURL=https://sametime.example.com/sametime-auth/api/v1/oidc/login
```

> **Wichtig für Mobile Clients:** Bei OIDC darf `STCONF_IDPURL` nicht auf Keycloak direkt zeigen. Der Wert muss auf den Sametime OIDC Login zeigen:

```text
https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
```

Der Ablauf ist damit:

```text
Sametime Mobile Client
        |
        v
Sametime /stwebapi/proxyinfo
        |
        | IDPUrl
        v
Sametime Auth Service
        |
        | OIDC
        v
Keycloak
        |
        v
Sametime
```

---

## 10. `saml.env` aus Docker Compose entfernen

Falls zuvor SAML verwendet wurde, kann im `community`-Service beispielsweise folgende Konfiguration vorhanden sein:

```yaml
env_file:
  - custom.env
  - saml.env
```

Für die reine OIDC-Konfiguration muss `saml.env` entfernt werden:

```yaml
env_file:
  - custom.env
```

Die Datei `saml.env` selbst kann auf dem Host bestehen bleiben.

Entscheidend ist, dass sie nicht mehr vom Community-Service geladen wird.

---

## 11. SAML Truststore Mount entfernen

Falls zuvor SAML konfiguriert war, kann sich im Community-Service noch ein Mount für den SAML Truststore befinden:

```yaml
volumes:
  - ./samltruststore.p12:/local/notesdata/samltruststore.p12
```

oder beispielsweise:

```yaml
volumes:
  - ./saml/samltruststore.p12:/local/notesdata/samltruststore.p12
```

Dieser Mount wird für OIDC nicht benötigt und sollte aus der OIDC-Konfiguration entfernt werden.

Die Datei selbst kann für eine spätere Rückkehr zur SAML-Konfiguration auf dem Host aufbewahrt werden.

---

## 12. OIDC-Konfiguration zusammengefasst

Nach Abschluss der Konfiguration sollten die relevanten Einstellungen ungefähr folgendermaßen aussehen.

### `custom.env`

```ini
STCONF_ISOIDC=true

OIDC_CLIENT_ID=sametime
OIDC_CLIENT_SECRET=<CLIENT-SECRET>

OIDC_ISSUER_URI=https://<KEYCLOAK>/realms/<REALM>
OIDC_AUTHORIZATION_URL=https://<KEYCLOAK>/realms/<REALM>/protocol/openid-connect/auth
OIDC_TOKEN_URL=https://<KEYCLOAK>/realms/<REALM>/protocol/openid-connect/token
OIDC_USER_INFO_URL=https://<KEYCLOAK>/realms/<REALM>/protocol/openid-connect/userinfo
OIDC_SCOPES=openid email profile

STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt

IDP_URL=
```

### `.env`

```ini
STCONF_IDPURL=https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
```

### `docker-compose.yml`

Im Community-Service darf nur die normale Sametime Environment-Datei eingebunden sein:

```yaml
community:
  env_file:
    - custom.env
```

Insbesondere dürfen nicht mehr vorhanden sein:

```yaml
- saml.env
```

und kein SAML-Truststore-Mount:

```yaml
- ./samltruststore.p12:/local/notesdata/samltruststore.p12
```

---

## 13. Docker-Konfiguration überprüfen

Vor dem Neustart sollte die aufgelöste Docker-Compose-Konfiguration kontrolliert werden.

```bash
cd /opt/hcl/sametime

docker compose config >/tmp/oidc-compose.yml
```

Anschließend gezielt nach Authentifizierungseinstellungen suchen:

```bash
grep -nEi \
'saml|samltruststore|OIDC_CLIENT_ID|OIDC_ISSUER_URI|OIDC_SCOPES|STCONF_ISOIDC|STCONF_IDPURL|ST_AUTH_TOKEN|IDP_URL' \
/tmp/oidc-compose.yml
```

Bei einer reinen OIDC-Konfiguration sollten unter anderem Werte wie diese erscheinen:

```text
IDP_URL: ""
OIDC_CLIENT_ID: sametime
OIDC_ISSUER_URI: https://<KEYCLOAK>/realms/<REALM>
OIDC_SCOPES: openid email profile
STCONF_ISOIDC: "true"
STI__ST_BB_NAMES__ST_AUTH_TOKEN: Fork:Jwt
```

Es dürfen keine aktiven SAML-Endpunkte und kein `samltruststore` mehr auftauchen.

---

## 14. Sametime neu starten

Damit die geänderten Environment-Variablen in die Container übernommen werden, müssen die betroffenen Container neu erstellt werden.

Für einen vollständigen Neustart:

```bash
cd /opt/hcl/sametime

sudo docker compose down
sudo docker compose up -d
```

Anschließend:

```bash
sudo docker compose ps
```

> **Wichtig:** Ein einfacher Neustart bestehender Container reicht bei Änderungen an Environment-Variablen nicht immer aus. Die Container sollten mit der neuen Compose-Konfiguration neu erstellt werden.

---

## 15. Community-Container überprüfen

Status kontrollieren:

```bash
docker compose ps community mux auth
```

Anschließend die Community Logs überprüfen:

```bash
docker compose logs --tail=200 community
```

Gezielte Suche nach Authentifizierungsproblemen:

```bash
docker compose logs community 2>&1 | \
grep -iE 'error|fail|fatal|exception|ldap|domino|connect|auth|jwt' | tail -100
```

Beim Start sollte unter anderem die JWT-Authentifizierungsbibliothek geladen werden.

Typische Meldungen sind beispielsweise:

```text
Loading delegate [0] [libStAuthTokenJwt]
Initializing delegate [0] [libStAuthTokenJwt]
Sametime token authentication JWT library
```

Direkt nach dem Start können einzelne Sametime Services noch nicht vollständig verfügbar sein. Entscheidend ist, dass sich der Community Server anschließend vollständig initialisiert.

---

## 16. Mux-Verbindung überprüfen

Der Mux muss sich erfolgreich mit dem Community Server verbinden.

```bash
docker compose logs --tail=150 mux
```

Ein erfolgreicher Zustand enthält beispielsweise Meldungen wie:

```text
Connection to server ... established
Logged in to server ...
server ip:... provides all the essential services
```

Direkt nach dem Start können kurzzeitig Verbindungsfehler auftreten, während der Community Server seine Dienste initialisiert.

Entscheidend ist, dass der Mux anschließend erfolgreich verbunden ist.

---

## 17. OIDC-Environment im Container überprüfen

Prüfen, ob die OIDC-Konfiguration tatsächlich in den laufenden Containern angekommen ist.

Für den Community-Container:

```bash
docker compose exec community env | \
grep -E '^(OIDC_|STCONF_ISOIDC|STI__ST_BB_NAMES__ST_AUTH_TOKEN|IDP_URL)'
```

Erwartet werden beispielsweise:

```text
OIDC_CLIENT_ID=sametime
OIDC_ISSUER_URI=https://<KEYCLOAK>/realms/<REALM>
OIDC_SCOPES=openid email profile
STCONF_ISOIDC=true
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt
IDP_URL=
```

Das Client Secret sollte bei Diagnoseausgaben nicht unnötig ausgegeben oder dokumentiert werden.

---

## 18. Sametime Proxy-Konfiguration prüfen

Nach dem Start muss kontrolliert werden, welche Authentifizierungskonfiguration Sametime an seine Clients ausliefert.

Aufruf:

```bash
curl -s https://<SAMETIME-FQDN>/stwebapi/proxyinfo
```

Mit `jq`:

```bash
curl -s https://<SAMETIME-FQDN>/stwebapi/proxyinfo | jq
```

Bei einer funktionierenden reinen OIDC-Konfiguration mit Mobile-Support sollte der relevante Zustand beispielsweise so aussehen:

```json
{
  "isSAML": false,
  "isOIDC": true,
  "oidcIssuer": "https://<KEYCLOAK>/realms/<REALM>",
  "communityConnected": true,
  "IDPUrl": "https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login"
}
```

Besonders wichtig:

```text
isSAML             = false
isOIDC             = true
oidcIssuer          = OIDC_ISSUER_URI
communityConnected = true
IDPUrl              = https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
```

> **Wichtig:** Für OIDC mit Mobile Clients sollte `IDPUrl` nicht leer sein.

Ist `IDPUrl` leer, obwohl OIDC verwendet wird, sollte `STCONF_IDPURL` in `.env` geprüft werden.

---

## 19. Web Client testen

Für den ersten Funktionstest empfiehlt sich ein privates bzw. Inkognito-Browserfenster.

Sametime aufrufen:

```text
https://<SAMETIME-FQDN>
```

Der erwartete Ablauf lautet:

```text
Sametime Web Client
        |
        v
Sametime OIDC Authentication
        |
        v
Keycloak Authorization Endpoint
        |
        v
Keycloak Login
        |
        v
OIDC Authorization Response
        |
        v
Sametime
        |
        v
Benutzer angemeldet
```

Nach erfolgreicher Anmeldung sollten zusätzlich Chat, Präsenzstatus und Benutzerauflösung getestet werden.

---

## 20. Mobile Client testen

Nach erfolgreichem Web-Login sollte der Mobile Client separat getestet werden.

Für Mobile Clients sind insbesondere diese Einstellungen relevant:

```ini
STCONF_ISOIDC=true
STCONF_IDPURL=https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
OIDC_SCOPES=openid email profile
```

Der erwartete Ablauf ist:

```text
Sametime Mobile Client
        |
        v
Sametime Server
        |
        | /stwebapi/proxyinfo
        |
        | isOIDC=true
        | oidcIssuer=<KEYCLOAK ISSUER>
        | IDPUrl=<SAMETIME OIDC LOGIN>
        v
Sametime Auth Service
        |
        v
Keycloak
        |
        | OIDC Login
        v
Sametime
        |
        v
Mobile Client angemeldet
```

Wenn Web-OIDC funktioniert, der Mobile Client jedoch nicht, sollte als Erstes geprüft werden:

```bash
curl -s https://<SAMETIME-FQDN>/stwebapi/proxyinfo | jq
```

Insbesondere müssen folgende Werte korrekt sein:

```text
isSAML=false
isOIDC=true
oidcIssuer=<KEYCLOAK-ISSUER>
IDPUrl=https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
```

Eine gemischte SAML-/OIDC-Konfiguration kann zu unerwartetem Verhalten des Mobile Clients führen.

---

## 21. Fehlersuche

### Aktive Konfiguration anzeigen

```bash
grep -Ei 'OIDC|STCONF|IDP_URL|SAML|AUTH_TOKEN' \
  /opt/hcl/sametime/.env \
  /opt/hcl/sametime/custom.env \
  /opt/hcl/sametime/saml.env 2>/dev/null
```

### OIDC Discovery testen

```bash
curl -s \
  https://<KEYCLOAK>/realms/<REALM>/.well-known/openid-configuration | jq
```

### JWKS Endpoint testen

Die `jwks_uri` zunächst aus der Discovery-Konfiguration ermitteln.

Anschließend:

```bash
curl -s \
  https://<KEYCLOAK>/realms/<REALM>/protocol/openid-connect/certs | jq
```

### Proxyinformationen abrufen

```bash
curl -s https://<SAMETIME-FQDN>/stwebapi/proxyinfo | jq
```

### OIDC Login URL testen

```bash
curl -I \
  https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
```

Der Endpunkt sollte den OIDC-Anmeldeprozess starten bzw. auf den Keycloak Authorization Endpoint weiterleiten.

### Community Logs

```bash
cd /opt/hcl/sametime

docker compose logs --tail=500 community
```

### Nach Authentifizierungsfehlern suchen

```bash
docker compose logs community 2>&1 | \
grep -Ei 'oidc|jwt|token|auth|error|exception|fail'
```

### Auth-Service Logs

Bei OIDC-Problemen ist zusätzlich der Auth-Service wichtig:

```bash
docker compose logs --tail=500 auth
```

Gezielte Suche:

```bash
docker compose logs auth 2>&1 | \
grep -Ei 'oidc|openid|passport|token|callback|auth|error|exception|fail'
```

### Mux überprüfen

```bash
docker compose logs mux 2>&1 | \
grep -iE 'error|fail|fatal|exception|connect|community' | tail -100
```

### Container-Konfiguration überprüfen

```bash
docker compose config
```

### Environment des Community-Containers

```bash
docker compose exec community env | \
grep -Ei 'OIDC|STCONF|IDP|AUTH'
```

---

## 22. OIDC-Konfiguration mit `check-oidc.sh` prüfen

Für eine vollständige technische Prüfung kann das zusätzliche Check-Script verwendet werden.

Standardaufruf:

```bash
cd /opt/hcl/sametime

./check-oidc.sh
```

Das Script überprüft unter anderem:

- Vorhandensein der benötigten Konfigurationsdateien
- `STCONF_ISOIDC`
- OIDC Client ID
- OIDC Client Secret
- OIDC Issuer URI
- OIDC Scopes
- `openid`, `email` und `profile`
- Authorization Endpoint
- Token Endpoint
- UserInfo Endpoint
- OIDC Discovery
- JWKS Endpoint
- `STCONF_IDPURL`
- Sametime OIDC Login URL
- deaktivierte SAML-Konfiguration
- Docker-Compose-Konfiguration
- laufende Container
- OIDC-Environment der Container
- `/stwebapi/proxyinfo`
- `IDPUrl`
- Verbindung zum Community Server

Optional kann die Sametime-URL explizit angegeben werden:

```bash
SAMETIME_URL=https://<SAMETIME-FQDN> ./check-oidc.sh
```

Bei einer sauberen Konfiguration sollte das Ergebnis lauten:

```text
Fehler   : 0
Warnungen: 0

STATUS: OK - OIDC-Konfiguration sieht konsistent aus
```

---

## 23. Zwischen SAML und OIDC wechseln

Für Test- und Migrationsumgebungen kann es sinnvoll sein, vollständige Konfigurationssätze für SAML und OIDC getrennt aufzubewahren.

Beispielsweise:

```text
/opt/hcl/sametime/auth-config/
├── saml/
│   ├── .env
│   ├── custom.env
│   └── docker-compose.yml
└── oidc/
    ├── .env
    ├── custom.env
    └── docker-compose.yml
```

Damit können jeweils vollständige und getestete Konfigurationsstände verwendet werden.

Ein separates `switch-auth.sh` kann die drei Dateien des gewünschten Authentifizierungsverfahrens in das aktive Sametime-Verzeichnis kopieren.

Beispiel:

```bash
./switch-auth.sh oidc
```

bzw.

```bash
./switch-auth.sh saml
```

Das Umschalten sollte lediglich die Konfigurationsdateien austauschen.

Der eigentliche Neustart des Sametime-Stacks erfolgt anschließend bewusst separat:

```bash
docker compose down
docker compose up -d
```

Nach dem Wechsel sollte die jeweilige Konfiguration geprüft werden:

```bash
./check-oidc.sh
```

oder:

```bash
./check-saml.sh
```

> **Wichtig:** Nach Änderungen an der funktionierenden OIDC-Konfiguration sollte auch der gespeicherte OIDC-Konfigurationssatz unter `auth-config/oidc/` aktualisiert werden.

---

## 24. Besonders wichtig bei Sametime 12.0.4

Für eine reine OIDC-Konfiguration sind insbesondere folgende Punkte zu beachten:

1. `STCONF_ISOIDC=true` muss gesetzt sein.
2. `OIDC_CLIENT_ID` muss der Keycloak Client ID entsprechen.
3. `OIDC_CLIENT_SECRET` muss dem tatsächlichen Keycloak Client Secret entsprechen.
4. `OIDC_ISSUER_URI` muss exakt dem von Keycloak veröffentlichten `issuer` entsprechen.
5. Authorization-, Token- und UserInfo-Endpoint sollten mit der OIDC Discovery übereinstimmen.
6. `OIDC_SCOPES=openid email profile` sollte gesetzt sein.
7. Der JWKS Endpoint muss vom Sametime-Server erreichbar sein.
8. `STI__ST_BB_NAMES__ST_AUTH_TOKEN` muss `Jwt` enthalten.
9. Bei reiner OIDC-Konfiguration darf `Saml` nicht mehr in `ST_AUTH_TOKEN` enthalten sein.
10. `IDP_URL` sollte für die reine OIDC-Konfiguration leer sein.
11. `STCONF_IDPURL` muss für OIDC mit Mobile Clients auf den Sametime OIDC Login zeigen.
12. Der korrekte Wert lautet:

    ```text
    https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
    ```

13. `STCONF_IDPURL` darf für OIDC nicht auf den Keycloak-SAML- oder Keycloak-OIDC-Endpunkt zeigen.
14. `saml.env` darf nicht mehr vom Community-Service eingebunden werden.
15. Der SAML Truststore darf nicht mehr in den Community-Container gemountet werden.
16. Nach Änderungen müssen die Container mit der neuen Environment-Konfiguration neu erstellt werden.
17. `/stwebapi/proxyinfo` sollte `isOIDC=true` und `isSAML=false` melden.
18. `oidcIssuer` muss dem konfigurierten `OIDC_ISSUER_URI` entsprechen.
19. `IDPUrl` sollte dem konfigurierten `STCONF_IDPURL` entsprechen.
20. `communityConnected` sollte nach vollständigem Start `true` sein.
21. SAML und OIDC dürfen nicht gleichzeitig aktiv konfiguriert sein.

---

## 25. Erwarteter Endzustand

Eine erfolgreich konfigurierte Installation kann mit `check-oidc.sh` beispielsweise folgenden Zustand liefern:

```text
OIDC Parameter
--------------
STCONF_ISOIDC=true
OIDC_CLIENT_ID=sametime
OIDC_CLIENT_SECRET=<gesetzt>
OIDC_ISSUER_URI=https://<KEYCLOAK>/realms/<REALM>
OIDC_SCOPES=openid email profile

Authentifizierungsmodus / Mobile OIDC
-------------------------------------
IDP_URL=
STCONF_IDPURL=https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
ST_AUTH_TOKEN=Fork:Jwt
saml.env nicht eingebunden
SAML Truststore nicht eingebunden

OIDC Discovery
--------------
issuer korrekt
authorization_endpoint korrekt
token_endpoint korrekt
userinfo_endpoint korrekt
jwks_uri erreichbar

proxyinfo
---------
isSAML=false
isOIDC=true
oidcIssuer=https://<KEYCLOAK>/realms/<REALM>
IDPUrl=https://<SAMETIME-FQDN>/sametime-auth/api/v1/oidc/login
communityConnected=true

Ergebnis
--------
Fehler   : 0
Warnungen: 0

STATUS: OK - OIDC-Konfiguration sieht konsistent aus
```

Damit sind sowohl die statische OIDC-Konfiguration als auch die von Sametime zur Laufzeit veröffentlichte Konfiguration für Web- und Mobile-Clients konsistent.
