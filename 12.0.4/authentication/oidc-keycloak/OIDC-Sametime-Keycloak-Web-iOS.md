# OIDC Flow zwischen HCL Sametime, Keycloak, Webbrowser und iOS

Diese Dokumentation beschreibt den
OpenID-Connect-(OIDC)-Authentifizierungsflow zwischen **HCL Sametime**,
**Keycloak**, einem **Webbrowser** und dem **Sametime Mobile Client für
iOS**.

Ziel ist insbesondere, den Ablauf der Anmeldung und die Rolle der
JWT-Claims `iss`, `aud`, `azp`, `sub`, `scope`, `iat` und `exp`
verständlich zu machen.

> **Hinweis:** Die konkreten Hostnamen und Client-Namen stammen aus
> einer Testumgebung. Details des internen Sametime-Verhaltens werden
> anhand der beobachteten Sametime-Auth-Logs beschrieben.

## 1. Beispielumgebung

  Komponente              Wert
  ----------------------- ------------------------------
  Keycloak                `https://kclab1.inlakech.de`
  Realm                   `Renovations`
  Sametime                `https://stlab1.inlakech.de`
  iOS Keycloak Client     `sametime_mobile`
  iOS Redirect URI        `sametime://oauth2redirect`
  zusätzlicher Scope      `Domino.user.all`
  Audience Client Scope   `sametime_mobile_audience`
  Sametime Audience       `https://stlab1.inlakech.de`

## 2. Beteiligte Rollen

Keycloak ist der **OpenID Provider (OP)** bzw. Authorization Server.
Dort authentifiziert sich der Benutzer und dort werden die OIDC-Tokens
ausgestellt.

Der Browser bzw. der Sametime iOS Client startet den OIDC Authorization
Code Flow. Sametime vertraut anschließend den von Keycloak ausgestellten
Tokens, sofern unter anderem Signatur, Issuer, Audience und
Gültigkeitszeitraum stimmen.

``` text
                 +------------------+
                 |     Keycloak     |
                 | Identity Provider|
                 | Token Issuer     |
                 +---------+--------+
                           |
                         OIDC/JWT
                           |
              +------------+------------+
              |                         |
       +------v------+           +------v---------+
       | Webbrowser  |           | Sametime iOS   |
       +------+------+           | sametime_mobile|
              |                  +------+---------+
              |                         |
              +------------+------------+
                           |
                           v
                 +------------------+
                 |     Sametime     |
                 | Auth / Services  |
                 +------------------+
```

## 3. JWT: Header, Payload und Signatur

Ein JSON Web Token besteht aus:

``` text
HEADER.PAYLOAD.SIGNATURE
```

Beispiel für den beobachteten Header:

``` json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "ULqBa57bcwf2sP-iSxQ9bIOd5mRw_JvrZxd4SJE7ShM"
}
```

`alg = RS256` bedeutet RSA/SHA-256. `kid` identifiziert den verwendeten
Keycloak-Schlüssel. Sametime kann über den JWKS-Endpunkt den passenden
**öffentlichen Schlüssel** ermitteln und damit die Signatur prüfen. Der
private Key bleibt bei Keycloak.

Beobachtete Sametime-Logs:

``` text
JWKS key lookup requested for JWT validation
JWKS key lookup using kid ULqBa57bcwf2sP-iSxQ9bIOd5mRw_JvrZxd4SJE7ShM
```

## 4. Wichtige JWT Claims

Ein funktionierender iOS Access Token enthielt:

``` json
{
  "iss": "https://kclab1.inlakech.de/realms/Renovations",
  "aud": [
    "https://stlab1.inlakech.de",
    "account"
  ],
  "azp": "sametime_mobile",
  "sub": "c6a54616-ca51-4fd6-8a16-9687aa1a73fa",
  "scope": "openid email Domino.user.all profile",
  "iat": 1787694510,
  "exp": 1787694810
}
```

  Claim     Bedeutung
  --------- --------------------------------------------------------
  `iss`     Issuer -- wer hat das Token ausgestellt?
  `aud`     Audience -- für welche Ressource(n) ist es bestimmt?
  `azp`     Authorized Party -- welcher Client hat es angefordert?
  `sub`     eindeutige Benutzer-ID bei Keycloak
  `scope`   angeforderte/erteilte Scopes
  `iat`     Issued At
  `exp`     Ablaufzeitpunkt

### `aud` und `azp`

`azp = sametime_mobile` bedeutet: Der Client `sametime_mobile` hat das
Token angefordert.

`aud = https://stlab1.inlakech.de` bedeutet: Das Access Token ist für
Sametime als Ressource bestimmt.

``` text
sametime_mobile  ---> fordert Token an
       |
       | azp
       v
    Keycloak
       |
       | stellt Access Token aus
       v
aud = https://stlab1.inlakech.de
       |
       v
    Sametime
```

## 5. Audience-Konfiguration in Keycloak

Ursprünglich enthielt der iOS Access Token nur:

``` json
{
  "aud": "account",
  "azp": "sametime_mobile"
}
```

Sametime selbst war damit nicht als Audience enthalten.

Temporär konnte Sametime so erweitert werden, dass auch `account`
akzeptiert wurde:

``` text
JWKS_AUDIENCES=sametimeMeetings,https://stlab1.inlakech.de,https://stlab1.inlakech.de/,account
```

Die sauberere Lösung besteht jedoch darin, die korrekte Audience in
Keycloak ausstellen zu lassen.

Dafür wurde der Client Scope angelegt:

``` text
sametime_mobile_audience
```

mit einem Audience Mapper:

``` text
Mapper Type:              Audience
Included Custom Audience: https://stlab1.inlakech.de
Add to access token:      On
```

Der Scope wurde `sametime_mobile` als **Default Client Scope**
zugeordnet.

Danach enthält das Access Token:

``` json
"aud": [
  "https://stlab1.inlakech.de",
  "account"
]
```

Damit konnte der `JWKS_AUDIENCES`-Override wieder aus
`docker-compose.yaml` entfernt werden.

## 6. OIDC Authorization Code Flow im Webbrowser

``` text
Browser                Sametime                 Keycloak
   |                       |                       |
   | Sametime aufrufen     |                       |
   +---------------------->|                       |
   |                       |                       |
   | Redirect zu Keycloak  |                       |
   |<----------------------+                       |
   |                                               |
   | Authorization Request                         |
   +---------------------------------------------->|
   |                                               |
   | Login Page                                    |
   |<----------------------------------------------+
   |                                               |
   | Username / Password / MFA                     |
   +---------------------------------------------->|
   |                                               |
   | Authorization Code                            |
   |<----------------------------------------------+
   |                                               |
   | Redirect zurück                               |
   +---------------------->|                       |
   |                       |                       |
   |                       | Token Exchange        |
   |                       +---------------------->|
   |                       |                       |
   |                       | Tokens                |
   |                       |<----------------------+
   |                       |                       |
   | angemeldet            |                       |
   |<----------------------+                       |
```

Der Authorization Code ist **nicht** der Access Token. Er ist ein
kurzlebiger Zwischenschritt und wird am Token Endpoint gegen Tokens
eingetauscht.

## 7. ID Token, Access Token und Refresh Token

### ID Token

Beantwortet primär: **Wer wurde authentifiziert?**

### Access Token

Beantwortet primär: **Auf welche Ressource darf zugegriffen werden und
mit welchen Berechtigungen?**

Für Sametime ist insbesondere dieser Token relevant. Sametime Auth
protokolliert ihn als **Subject Token**.

### Refresh Token

Erlaubt grundsätzlich, nach Ablauf eines Access Tokens einen neuen
Access Token anzufordern, ohne erneut interaktiv Benutzername und
Passwort abzufragen.

## 8. OIDC Flow des iOS Clients

Verwendete Keycloak-Konfiguration:

``` text
Client ID:              sametime_mobile
Client authentication: OFF
Standard flow:          ON
Redirect URI:           sametime://oauth2redirect
```

`sametime_mobile` ist ein **Public Client**.

``` text
Sametime iOS                Keycloak
     |                          |
     | Authorization Request    |
     +------------------------->|
     |                          |
     | Keycloak Login           |
     |<-------------------------+
     |                          |
     | Credentials / MFA        |
     +------------------------->|
     |                          |
     | Authorization Code       |
     |<-------------------------+
     |                          |
     | Code -> Token Endpoint   |
     +------------------------->|
     |                          |
     | Access / ID / Refresh    |
     |<-------------------------+
     |
     | Redirect:
     | sametime://oauth2redirect
```

## 9. Übergang von Keycloak zu Sametime Auth

Nach dem OIDC-Flow übergibt der iOS Client den von Keycloak
ausgestellten Access Token an Sametime Auth:

``` text
Keycloak
   |
   | Keycloak Access Token
   v
Sametime iOS
   |
   | POST /api/v1/token
   v
Sametime Auth
   |
   +-- Issuer prüfen
   +-- Signatur via JWKS prüfen
   +-- Audience prüfen
   +-- Gültigkeitszeit prüfen
   +-- Rollen/Scopes prüfen
   +-- Benutzer zuordnen
   |
   v
Sametime Authentication
```

## 10. `/api/v1/token`

Sametime sieht zunächst die Claims:

``` text
Subject token payload claims:
{
  "iss":"https://kclab1.inlakech.de/realms/Renovations",
  "aud":["https://stlab1.inlakech.de","account"],
  "azp":"sametime_mobile",
  ...
}
```

Danach erfolgt die Signaturprüfung:

``` text
JWKS key lookup requested for JWT validation
JWKS key lookup using kid ...
```

Anschließend erfolgt das Identity Mapping, beispielsweise:

``` text
Search quickfind for carsten.gericke@inlakech.de
```

bzw.:

``` text
Returning CN=Carsten Gericke,O=Renovations
for carsten.gericke@inlakech.de from cache
```

Damit wird die Keycloak-Identität auf die Sametime/Domino-Identität
abgebildet:

``` text
carsten.gericke@inlakech.de
              |
              v
CN=Carsten Gericke,O=Renovations
```

Weitere Prüfungen:

``` text
Validating roles for user
Checking if JWT is revoked ...
User revocations found: []
```

Bei Erfolg:

``` text
Got user from Sametime
POST /api/v1/token HTTP/1.0" 200
```

## 11. `/api/v1/check`

Bei gültiger Sametime-Authentifizierung:

``` text
GET /api/v1/check HTTP/1.0" 200
```

Ohne vorhandenen Token:

``` text
Token not present in request
GET /api/v1/check HTTP/1.0" 401
```

Vereinfacht:

``` text
/api/v1/token
Keycloak/OIDC identity -> Sametime authentication

/api/v1/check
bestehende Sametime authentication -> noch gültig?
```

Ein beobachteter Ablauf:

``` text
GET  /api/v1/check   -> 401
        |
        v
OIDC / Keycloak
        |
        v
POST /api/v1/token   -> 200
        |
        v
GET  /api/v1/check   -> 200
```

## 12. iOS Background/Foreground-Verhalten

Im Test wurde beobachtet, dass der iOS Client nach dem Wechsel in den
Hintergrund und späteren Wechsel in den Vordergrund den Loginprozess
erneut startet.

Zuvor war die Authentifizierung erfolgreich:

``` text
POST /api/v1/token -> 200
GET  /api/v1/check -> 200
```

Später trat unter anderem auf:

``` text
POST /api/v1/token -> 403
```

gefolgt von:

``` text
Token not present in request
GET /api/v1/check -> 401
```

Danach wurde erneut ein OIDC-Login gegen Keycloak gestartet. Der
Benutzer musste dabei erneut seine Keycloak-Credentials eingeben.

Dieses Verhalten ist vom zuvor behobenen Audience-Problem zu
unterscheiden: Die neu ausgestellten Tokens enthalten inzwischen die
korrekte Sametime-Audience und werden von Sametime erfolgreich
akzeptiert.

Für die weitere Analyse ist der Lifecycle dieser Zustände entscheidend:

``` text
Keycloak SSO Session
        |
        +-- Authorization Code
        +-- Access Token
        +-- ID Token
        +-- Refresh Token
                 |
                 v
          Sametime Auth
                 |
                 +-- Sametime Token / Session
```

Die zentrale Frage lautet:

> Welchen Authentifizierungs- oder Token-Zustand verliert bzw. verwirft
> der iOS Client beim Wechsel zwischen Background und Foreground?
  
## 13. Browser und iOS im Vergleich

| Merkmal | Browser | iOS |
|---|---|---|
| OIDC Provider | Keycloak | Keycloak |
| Verfahren | Authorization Code Flow | Authorization Code Flow |
| Client | Web-Konfiguration | `sametime_mobile` |
| Mobile Client-Typ | -- | Public Client |
| Redirect | HTTPS | `sametime://oauth2redirect` |
| Benutzerlogin | Keycloak | Keycloak über iOS User Agent |
| Access Token | JWT | JWT |
| Issuer | Keycloak | Keycloak |
| `azp` | jeweiliger Web-Client | `sametime_mobile` |
| Audience | Sametime URL | `https://stlab1.inlakech.de` |
| Signaturprüfung | JWKS | JWKS |
| Benutzer-Mapping | Sametime | Sametime |

## 14. Mentales Modell für das Debugging

``` text
1. Authentication
   Benutzer -> Keycloak
             |
             v
2. Authorization Code / Token Issuance
   Keycloak -> Access Token / ID Token / Refresh Token
             |
             v
3. Trust Validation durch Sametime
   - Issuer
   - Signatur über JWKS
   - Audience
   - Ablaufzeit
   - Scopes / Rollen
             |
             v
4. Identity Mapping
   Keycloak identity -> Domino/Sametime identity
             |
             v
5. Sametime Authentication
   /api/v1/token  -> Authentifizierung herstellen
   /api/v1/check  -> Authentifizierung prüfen
   /api/v1/logout -> Authentifizierung beenden
```

Diese Trennung hilft bei der Fehlersuche:

-   Scheitert die Anmeldung bereits bei Keycloak, liegt der Fehler in
    einer frühen OIDC-Phase.
-   Ist das JWT gültig signiert, enthält aber eine falsche `aud`, liegt
    ein Audience-/Resource-Server-Problem vor.
-   Liefert `/api/v1/token` `200`, wurde der Keycloak-Token
    grundsätzlich von Sametime akzeptiert.
-   Folgt später `/api/v1/check -> 401`, muss der nachgelagerte
    Token-/Session-Lifecycle untersucht werden.
-   Wird danach wieder ein interaktiver Keycloak-Login verlangt, sollte
    geprüft werden, warum vorhandene SSO-/Refresh-Mechanismen nicht zu
    einer transparenten erneuten Authentifizierung führen.

## 15. Referenzen

-   Keycloak OIDC Layers:
    <https://www.keycloak.org/securing-apps/oidc-layers>
-   Keycloak Server Administration Guide:
    <https://www.keycloak.org/docs/latest/server_admin/>
-   HCL Sametime Documentation:
    <https://help.hcl-software.com/sametime/welcome/index.html>
