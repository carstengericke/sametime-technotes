# HCL Sametime 12.0.4 – SAML-Integration mit Keycloak unter Docker

## 1. Ziel

Diese Dokumentation beschreibt die Einrichtung einer SAML-basierten Single-Sign-on-Anmeldung zwischen:

- HCL Sametime 12.0.4
- Docker / Docker Compose
- Keycloak als SAML Identity Provider (IdP)

Die Konfiguration soll sowohl für den Sametime Web Client als auch für unterstützte Sametime Mobile Clients verwendet werden.

> **Wichtig:** SAML und OIDC dürfen nicht vermischt werden. Für diese Konfiguration wird ausschließlich **SAML** verwendet. Eventuell vorhandene OIDC-Konfigurationen müssen deaktiviert bzw. entfernt werden.

**HCL-Dokumentation:**

[HCL Sametime 12.0.4 – Configuring SAML on Docker and Podman](https://help.hcl-software.com/sametime/v1204/admin/enabling_saml_docker.html?h=saml)

---

## 2. Voraussetzungen

Folgende Voraussetzungen müssen erfüllt sein:

- HCL Sametime 12.0.4 ist unter Docker installiert.
- Sametime ist über HTTPS erreichbar.
- Keycloak ist über HTTPS erreichbar.
- Die Sametime-Benutzer können den entsprechenden Keycloak-Benutzern eindeutig zugeordnet werden.
- Ein SAML-Client für Sametime ist bzw. wird in Keycloak eingerichtet.
- Das Zertifikat des Identity Providers steht für die Erstellung des Sametime-SAML-Truststores zur Verfügung.
- Zugriff mit `root` oder `sudo` auf den Sametime-Server ist vorhanden.

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

Falls bereits eine `saml.env` existiert:

```bash
cp saml.env saml.env.backup
```

---

## 4. Vorhandene OIDC-Konfiguration prüfen

Da ausschließlich SAML verwendet werden soll, muss zunächst geprüft werden, ob noch OIDC-Parameter vorhanden sind.

```bash
cd /opt/hcl/sametime
grep -Ei 'OIDC|STCONF|IDP_URL|SAML|AUTH_TOKEN' \
  .env custom.env saml.env 2>/dev/null
```

Bei einer reinen SAML-Konfiguration dürfen insbesondere keine aktiven OIDC-Einstellungen wie die folgenden vorhanden sein:

```ini
OIDC_CLIENT_ID=
OIDC_CLIENT_SECRET=
OIDC_ISSUER_URI=
OIDC_SCOPES=
STCONF_ISOIDC=true
```

Diese Einstellungen gehören zum OIDC-Authentifizierungsverfahren und werden für SAML nicht benötigt.

> **Wichtig:** Insbesondere `STCONF_ISOIDC=true` darf bei einer reinen SAML-Konfiguration nicht aktiv sein.

---

## 5. SAML Truststore erstellen

Sametime benötigt einen Truststore, um SAML-Tokens zu verarbeiten.

Die Datei muss gemäß HCL den Namen

```text
samltruststore.p12
```

haben.

Der Truststore muss das für die SAML-Kommunikation benötigte Zertifikat des Identity Providers enthalten.

Die fertige Datei wird anschließend in das Sametime-Installationsverzeichnis kopiert:

```bash
cd /opt/hcl/sametime
ls -l samltruststore.p12
```

Das Ergebnis sollte beispielsweise folgendermaßen aussehen:

```text
/opt/hcl/sametime/samltruststore.p12
```

> **Hinweis:** Der konkrete Host-Pfad darf abweichen. Entscheidend ist, dass der in `docker-compose.yml` konfigurierte Host-Pfad auf die tatsächliche Datei zeigt und diese im Community-Container als `/local/notesdata/samltruststore.p12` verfügbar ist.

---

## 6. `saml.env` erstellen

Im Sametime-Installationsverzeichnis wird eine zusätzliche Environment-Datei angelegt.

```bash
cd /opt/hcl/sametime
vi saml.env
```

Folgende Parameter eintragen:

```ini
STI__Config__STSAML_TRUST_STORE_TYPE=p12
STI__Config__STSAML_TRUST_STORE_FILE=/local/notesdata/samltruststore.p12
STI__Config__STSAML_TRUST_STORE_PASSWORD=<TRUSTSTORE-PASSWORT>
```

Beispiel:

```ini
STI__Config__STSAML_TRUST_STORE_TYPE=p12
STI__Config__STSAML_TRUST_STORE_FILE=/local/notesdata/samltruststore.p12
STI__Config__STSAML_TRUST_STORE_PASSWORD=MeinSicheresPasswort
```

Das Passwort muss dem Passwort entsprechen, mit dem der PKCS#12-Truststore erstellt wurde.

---

## 7. `docker-compose.yml` anpassen

Die Datei öffnen:

```bash
cd /opt/hcl/sametime
vi docker-compose.yml
```

Im Service

```yaml
services:
  community:
```

muss der Bereich `env_file` angepasst werden.

Aus beispielsweise:

```yaml
env_file: custom.env
```

wird:

```yaml
env_file:
  - custom.env
  - saml.env
```

Damit erhält der Community-Container zusätzlich die SAML-spezifischen Einstellungen.

---

## 8. Truststore in den Community-Container einbinden

Im `community`-Service muss zusätzlich die Datei `samltruststore.p12` als Volume eingebunden werden.

Unter `volumes:` ergänzen:

```yaml
volumes:
  - ./samltruststore.p12:/local/notesdata/samltruststore.p12
```

Ein vereinfachtes Beispiel sieht damit folgendermaßen aus:

```yaml
services:
  community:
    env_file:
      - custom.env
      - saml.env

    volumes:
      - ./samltruststore.p12:/local/notesdata/samltruststore.p12
```

> **Hinweis:** Die vorhandenen Volumes dürfen dabei nicht entfernt werden. Der SAML-Truststore wird lediglich zusätzlich ergänzt.

Falls der Truststore beispielsweise unter `./saml/samltruststore.p12` liegt, kann der Mount entsprechend lauten:

```yaml
- ./saml/samltruststore.p12:/local/notesdata/samltruststore.p12
```

---

## 9. SAML als Authentifizierungsmethode aktivieren

Die Datei `custom.env` öffnen:

```bash
vi /opt/hcl/sametime/custom.env
```

Folgender Parameter muss vorhanden sein:

```ini
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt,Ltpa,Saml
```

Damit akzeptiert der Sametime Community Server die von HCL vorgesehenen Authentifizierungsverfahren einschließlich SAML.

Wenn LTPA in der Umgebung nicht benötigt wird, kann die Konfiguration je nach Umgebung auch beispielsweise so aussehen:

```ini
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt,Saml
```

Zusätzlich wird die URL des SAML Identity Providers angegeben:

```ini
IDP_URL=<KEYCLOAK-SAML-URL>
```

Beispiel:

```ini
IDP_URL=https://keycloak.example.com/realms/example/protocol/saml/clients/sametime
```

Die tatsächliche URL hängt von der Konfiguration des SAML-Clients in Keycloak ab.

---

## 10. `TARGET` für die Rückleitung beachten

HCL weist ausdrücklich darauf hin, dass der `TARGET`-Parameter für die Weiterleitung verwendet wird, nachdem die SAML Assertion an Sametime zurückgesendet und erfolgreich validiert wurde.

Die IDP-URL kann deshalb beispielsweise folgendermaßen aufgebaut sein:

```ini
IDP_URL=<KEYCLOAK-SAML-URL>?TARGET=https://sametime.example.com/chat
```

Der `TARGET` muss auf den verwendeten Sametime Chat Hostnamen zeigen.

Die genaue URL muss an die vorhandene Keycloak- und Sametime-Konfiguration angepasst werden.

---

## 11. `STCONF_IDPURL` in `.env` konfigurieren

Für Sametime 12.0.4 muss die IdP-URL zusätzlich in der Datei `.env` hinterlegt werden.

```bash
vi /opt/hcl/sametime/.env
```

Folgenden Parameter hinzufügen bzw. korrigieren:

```ini
STCONF_IDPURL=<KEYCLOAK-SAML-URL>
```

Beispiel:

```ini
STCONF_IDPURL=https://keycloak.example.com/realms/example/protocol/saml/clients/sametime
```

Falls ein `TARGET` verwendet wird:

```ini
STCONF_IDPURL=<KEYCLOAK-SAML-URL>?TARGET=https://sametime.example.com/chat
```

> **Wichtig für Mobile Clients:** `STCONF_IDPURL` muss bei Sametime 12.0.4 korrekt gesetzt sein. Der Mobile Client verwendet diese Information, um den SAML Identity Provider aufzurufen.

---

## 12. SAML-Konfiguration zusammengefasst

Nach Abschluss der Konfiguration sollten die relevanten Dateien ungefähr folgenden Inhalt besitzen.

### `custom.env`

```ini
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt,Ltpa,Saml
IDP_URL=<KEYCLOAK-SAML-URL>?TARGET=https://<SAMETIME-FQDN>/chat
```

### `.env`

```ini
STCONF_IDPURL=<KEYCLOAK-SAML-URL>?TARGET=https://<SAMETIME-FQDN>/chat
```

Es darf für diese Konfiguration insbesondere kein

```ini
STCONF_ISOIDC=true
```

aktiv sein.

### `saml.env`

```ini
STI__Config__STSAML_TRUST_STORE_TYPE=p12
STI__Config__STSAML_TRUST_STORE_FILE=/local/notesdata/samltruststore.p12
STI__Config__STSAML_TRUST_STORE_PASSWORD=<TRUSTSTORE-PASSWORT>
```

### `docker-compose.yml`

Im Community-Service:

```yaml
community:
  env_file:
    - custom.env
    - saml.env

  volumes:
    - ./samltruststore.p12:/local/notesdata/samltruststore.p12
```

Vorhandene Einträge bleiben zusätzlich bestehen.

---

## 13. Docker-Konfiguration überprüfen

Vor dem Start sollte die Docker-Compose-Datei validiert werden:

```bash
cd /opt/hcl/sametime
sudo docker compose config >/dev/null
```

Bei korrekter Konfiguration sollte der Befehl keinen Fehler melden.

Optional kann die aufgelöste Konfiguration angezeigt werden:

```bash
sudo docker compose config
```

---

## 14. Sametime neu starten

Die Änderungen werden durch einen Neustart der Sametime-Container aktiviert.

```bash
cd /opt/hcl/sametime
sudo docker compose down
sudo docker compose up -d
```

Anschließend den Status kontrollieren:

```bash
sudo docker compose ps
```

Falls nur der Community-Container neu erstellt werden soll:

```bash
sudo docker compose up -d --force-recreate community
```

---

## 15. Community-Container überprüfen

Prüfen, ob der Community-Container gestartet wurde:

```bash
sudo docker compose ps community
```

Logs kontrollieren:

```bash
sudo docker compose logs --tail=200 community
```

Bei Problemen kann gezielt nach SAML-bezogenen Meldungen gesucht werden:

```bash
sudo docker compose logs community 2>&1 | \
grep -Ei 'saml|trust|certificate|auth|error|exception'
```

---

## 16. Truststore im Container überprüfen

Prüfen, ob der Truststore tatsächlich in den Community-Container eingebunden wurde:

```bash
sudo docker compose exec community \
  ls -l /local/notesdata/samltruststore.p12
```

Die Datei muss vorhanden sein.

Zusätzlich können die SAML-Environment-Variablen überprüft werden:

```bash
sudo docker compose exec community env | grep -i SAML
```

Dabei sollte unter anderem Folgendes erscheinen:

```text
STI__Config__STSAML_TRUST_STORE_TYPE=p12
STI__Config__STSAML_TRUST_STORE_FILE=/local/notesdata/samltruststore.p12
```

Zusätzlich sollte der Authentifizierungs-Token SAML enthalten:

```bash
sudo docker compose exec community env | grep 'STI__ST_BB_NAMES__ST_AUTH_TOKEN'
```

Beispiel:

```text
STI__ST_BB_NAMES__ST_AUTH_TOKEN=Fork:Jwt,Saml
```

---

## 17. Sametime Proxy-Konfiguration prüfen

Nach dem Start muss kontrolliert werden, welche Authentifizierungskonfiguration Sametime an seine Clients ausliefert.

Aufruf:

```bash
curl -s https://<SAMETIME-FQDN>/stwebapi/proxyinfo
```

Falls `jq` installiert ist:

```bash
curl -s https://<SAMETIME-FQDN>/stwebapi/proxyinfo | jq
```

Bei einer reinen SAML-Konfiguration sollte der relevante Zustand folgendermaßen aussehen:

```json
{
  "isSAML": true,
  "isOIDC": false,
  "oidcIssuer": "",
  "communityConnected": true,
  "IDPUrl": "https://<KEYCLOAK>/realms/<REALM>/protocol/saml/clients/<CLIENT>?TARGET=https://<SAMETIME-FQDN>/chat"
}
```

Besonders wichtig:

```text
isSAML     = true
isOIDC     = false
oidcIssuer = ""
```

Falls `oidcIssuer` gesetzt ist, obwohl ausschließlich SAML verwendet werden soll, müssen `.env`, `custom.env` und weitere Environment-Dateien erneut auf OIDC-Einstellungen untersucht werden.

---

## 18. Web Client testen

Zunächst sollte die Anmeldung über den Browser getestet werden.

1. Browser im privaten bzw. Inkognito-Modus öffnen.
2. Sametime aufrufen:

   ```text
   https://<SAMETIME-FQDN>
   ```

3. Anmeldung starten.
4. Sametime muss zum Keycloak Identity Provider weiterleiten.
5. Benutzer in Keycloak authentifizieren.
6. Keycloak sendet die SAML Assertion an Sametime zurück.
7. Sametime validiert die Assertion.
8. Der Benutzer wird am Sametime Web Client angemeldet.

---

## 19. Mobile Client testen

Nachdem die Web-Anmeldung erfolgreich funktioniert, wird der Mobile Client getestet.

Der Mobile Client erhält die benötigte IdP-Konfiguration vom Sametime Server.

Deshalb ist für Sametime 12.0.4 insbesondere dieser Parameter wichtig:

```ini
STCONF_IDPURL=<KEYCLOAK-SAML-URL>
```

Der erwartete Ablauf lautet:

```text
Sametime Mobile Client
        |
        v
Sametime Server
        |
        | STCONF_IDPURL
        v
Keycloak
        |
        | SAML Login
        v
SAML Assertion
        |
        v
Sametime
        |
        v
Mobile Client angemeldet
```

Wenn der Browser-Login funktioniert, der Mobile Client aber beispielsweise von Keycloak

```text
Client not found
```

erhält, sollte als Erstes `/stwebapi/proxyinfo` kontrolliert werden.

Insbesondere muss ausgeschlossen werden, dass gleichzeitig SAML- und OIDC-Einstellungen an den Client geliefert werden.

---

## 20. Fehlersuche

### Konfiguration anzeigen

```bash
grep -Ei 'OIDC|STCONF|IDP_URL|SAML|AUTH_TOKEN' \
  /opt/hcl/sametime/.env \
  /opt/hcl/sametime/custom.env \
  /opt/hcl/sametime/saml.env 2>/dev/null
```

### Proxyinformationen abrufen

```bash
curl -s https://<SAMETIME-FQDN>/stwebapi/proxyinfo | jq
```

### Community Logs

```bash
cd /opt/hcl/sametime
sudo docker compose logs --tail=500 community
```

### Nach SAML-Fehlern suchen

```bash
sudo docker compose logs community 2>&1 | \
grep -Ei 'saml|idp|assertion|trust|certificate|auth|error|exception'
```

### Container-Konfiguration überprüfen

```bash
sudo docker compose config
```

### Environment des Community-Containers

```bash
sudo docker compose exec community env | \
grep -Ei 'SAML|IDP|AUTH'
```

### Truststore-Mount des laufenden Containers überprüfen

```bash
docker inspect "$(docker compose ps -q community)" \
  --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}'
```

---

## 21. SAML-Konfiguration mit `check-saml.sh` prüfen

Für die technische Prüfung kann zusätzlich das erstellte Check-Script verwendet werden.

Standardaufruf:

```bash
cd /opt/hcl/sametime
./check-saml.sh
```

Falls `SAMETIME_URL` nicht angegeben wird, versucht das Script die Sametime-URL automatisch aus dem `TARGET` von `STCONF_IDPURL` bzw. `IDP_URL` zu ermitteln.

Optional kann die URL explizit angegeben werden:

```bash
SAMETIME_URL=https://<SAMETIME-FQDN> ./check-saml.sh
```

Bei einer sauberen SAML-Konfiguration sollte das Ergebnis lauten:

```text
Fehler   : 0
Warnungen: 0

STATUS: OK - SAML-Konfiguration sieht konsistent aus
```

---

## 22. Besonders wichtig bei Sametime 12.0.4

Für eine reine SAML-Konfiguration sind insbesondere folgende Punkte zu beachten:

1. `samltruststore.p12` muss vorhanden sein.
2. `saml.env` muss die Truststore-Konfiguration enthalten.
3. `saml.env` muss beim `community`-Service als `env_file` eingebunden sein.
4. Der Truststore muss als Volume in den Community-Container eingebunden sein.
5. `STI__ST_BB_NAMES__ST_AUTH_TOKEN` muss `Saml` enthalten.
6. `IDP_URL` muss in `custom.env` gesetzt sein.
7. `STCONF_IDPURL` muss in `.env` gesetzt sein.
8. Der `TARGET` muss zurück zum Sametime Chat Host zeigen.
9. Bei reiner SAML-Konfiguration darf `STCONF_ISOIDC=true` nicht aktiv sein.
10. SAML- und OIDC-Einstellungen dürfen nicht miteinander vermischt werden.
11. Nach Änderungen müssen die betroffenen Container neu erstellt bzw. Sametime neu gestartet werden.
12. Anschließend sollte `/stwebapi/proxyinfo` kontrolliert werden.
13. Bei reinem SAML sollte `oidcIssuer` leer sein.

---

## 23. Referenz

Grundlage der Docker-Konfiguration ist die offizielle Dokumentation für HCL Sametime 12.0.4:

[Configuring SAML on Docker and Podman – HCL Sametime 12.0.4](https://help.hcl-software.com/sametime/v1204/admin/enabling_saml_docker.html?h=saml)
