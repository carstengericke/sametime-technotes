#!/usr/bin/env bash

set -u

SAMETIME_DIR="${SAMETIME_DIR:-/opt/hcl/sametime}"
SAMETIME_URL="${SAMETIME_URL:-}"

ERRORS=0
WARNINGS=0

TMP_COMPOSE="/tmp/check-saml-compose.yml"
TMP_COMPOSE_ERR="/tmp/check-saml-compose.err"

cleanup() {
    rm -f "$TMP_COMPOSE" "$TMP_COMPOSE_ERR"
}

trap cleanup EXIT

ok() {
    echo "[OK]    $*"
}

warn() {
    echo "[WARN]  $*"
    WARNINGS=$((WARNINGS + 1))
}

error() {
    echo "[ERROR] $*"
    ERRORS=$((ERRORS + 1))
}

info() {
    echo "[INFO]  $*"
}

trim() {
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

get_value() {
    local file="$1"
    local key="$2"

    [[ -f "$file" ]] || return 0

    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null \
        | tail -1 \
        | cut -d= -f2- \
        | tr -d '\r' \
        | trim
}

echo "============================================================"
echo " HCL Sametime SAML Configuration Check"
echo "============================================================"
echo

if [[ ! -d "$SAMETIME_DIR" ]]; then
    error "Sametime-Verzeichnis nicht gefunden: $SAMETIME_DIR"
    exit 2
fi

cd "$SAMETIME_DIR" || exit 2

ENV_FILE="$SAMETIME_DIR/.env"
CUSTOM_ENV="$SAMETIME_DIR/custom.env"
SAML_ENV="$SAMETIME_DIR/saml.env"
COMPOSE_FILE="$SAMETIME_DIR/docker-compose.yml"

#
# 1. Dateien
#

echo "1. Konfigurationsdateien"
echo "------------------------------------------------------------"

for file in "$ENV_FILE" "$CUSTOM_ENV" "$COMPOSE_FILE"; do
    if [[ -f "$file" ]]; then
        ok "Gefunden: $file"
    else
        error "Fehlt: $file"
    fi
done

if [[ -f "$SAML_ENV" ]]; then
    ok "Gefunden: $SAML_ENV"
else
    error "saml.env wurde nicht gefunden"
fi

if command -v jq >/dev/null 2>&1; then
    ok "jq ist installiert"
else
    warn "jq ist nicht installiert; proxyinfo kann nur eingeschränkt geprüft werden"
fi

if command -v curl >/dev/null 2>&1; then
    ok "curl ist installiert"
else
    error "curl ist nicht installiert"
fi

#
# 2. SAML / OIDC
#

echo
echo "2. SAML / OIDC Parameter"
echo "------------------------------------------------------------"

AUTH_TOKEN="$(get_value "$CUSTOM_ENV" "STI__ST_BB_NAMES__ST_AUTH_TOKEN")"
IDP_URL="$(get_value "$CUSTOM_ENV" "IDP_URL")"
STCONF_IDPURL="$(get_value "$ENV_FILE" "STCONF_IDPURL")"
STCONF_ISOIDC="$(get_value "$ENV_FILE" "STCONF_ISOIDC")"
OIDC_ISSUER="$(get_value "$ENV_FILE" "OIDC_ISSUER_URI")"

if [[ -n "$AUTH_TOKEN" ]]; then
    if echo "$AUTH_TOKEN" | grep -qi 'saml'; then
        ok "SAML ist in STI__ST_BB_NAMES__ST_AUTH_TOKEN aktiviert"
        info "ST_AUTH_TOKEN=$AUTH_TOKEN"
    else
        error "SAML fehlt in STI__ST_BB_NAMES__ST_AUTH_TOKEN: $AUTH_TOKEN"
    fi
else
    error "STI__ST_BB_NAMES__ST_AUTH_TOKEN wurde in custom.env nicht gefunden"
fi

if [[ -n "$IDP_URL" ]]; then
    ok "IDP_URL ist gesetzt"
    info "IDP_URL=$IDP_URL"

    if echo "$IDP_URL" | grep -q '/protocol/saml/'; then
        ok "IDP_URL verweist auf einen SAML-Endpunkt"
    else
        warn "IDP_URL enthält nicht /protocol/saml/"
    fi

    if echo "$IDP_URL" | grep -q 'TARGET=https://'; then
        ok "IDP_URL enthält einen HTTPS TARGET"
    else
        warn "IDP_URL enthält keinen TARGET=https://..."
    fi
else
    error "IDP_URL ist nicht gesetzt"
fi

if [[ -n "$STCONF_IDPURL" ]]; then
    ok "STCONF_IDPURL ist gesetzt"
    info "STCONF_IDPURL=$STCONF_IDPURL"
else
    error "STCONF_IDPURL ist in .env nicht gesetzt"
fi

if [[ -n "$IDP_URL" && -n "$STCONF_IDPURL" ]]; then
    if [[ "$IDP_URL" == "$STCONF_IDPURL" ]]; then
        ok "IDP_URL und STCONF_IDPURL sind identisch"
    else
        warn "IDP_URL und STCONF_IDPURL unterscheiden sich"
    fi
fi

case "${STCONF_ISOIDC,,}" in
    true|yes|1)
        error "STCONF_ISOIDC ist aktiviert: $STCONF_ISOIDC"
        ;;
    false|no|0)
        ok "STCONF_ISOIDC ist explizit deaktiviert"
        ;;
    "")
        ok "STCONF_ISOIDC ist nicht gesetzt"
        ;;
    *)
        warn "Unbekannter Wert für STCONF_ISOIDC: $STCONF_ISOIDC"
        ;;
esac

if [[ -n "$OIDC_ISSUER" ]]; then
    error "OIDC_ISSUER_URI ist gesetzt: $OIDC_ISSUER"
else
    ok "OIDC_ISSUER_URI ist nicht gesetzt"
fi

#
# Aktive OIDC-Konfiguration prüfen
#

OIDC_HITS="$(
    grep -HnEi \
      '^[[:space:]]*(OIDC_CLIENT_ID|OIDC_CLIENT_SECRET|OIDC_ISSUER_URI|OIDC_SCOPES)[[:space:]]*=[[:space:]]*[^#[:space:]]' \
      "$ENV_FILE" "$CUSTOM_ENV" "$SAML_ENV" 2>/dev/null || true
)"

if [[ -n "$OIDC_HITS" ]]; then
    warn "Aktive OIDC-bezogene Einstellungen gefunden:"
    echo "$OIDC_HITS"
else
    ok "Keine aktiven OIDC-Parameter gefunden"
fi

echo
echo "3. SAML Truststore"
echo "------------------------------------------------------------"

TRUST_TYPE="$(get_value "$SAML_ENV" "STI__Config__STSAML_TRUST_STORE_TYPE")"
TRUST_FILE="$(get_value "$SAML_ENV" "STI__Config__STSAML_TRUST_STORE_FILE")"
TRUST_PASSWORD="$(get_value "$SAML_ENV" "STI__Config__STSAML_TRUST_STORE_PASSWORD")"

if [[ "${TRUST_TYPE,,}" == "p12" ]]; then
    ok "Truststore-Typ ist p12"
else
    error "Truststore-Typ ist nicht p12: ${TRUST_TYPE:-<leer>}"
fi

if [[ "$TRUST_FILE" == "/local/notesdata/samltruststore.p12" ]]; then
    ok "Truststore-Pfad im Container ist korrekt"
else
    error "Unerwarteter Truststore-Pfad: ${TRUST_FILE:-<leer>}"
fi

if [[ -n "$TRUST_PASSWORD" ]]; then
    ok "Truststore-Passwort ist gesetzt"
else
    error "Truststore-Passwort ist nicht gesetzt"
fi

#
# 4. Docker Compose
#

echo
echo "4. Docker Compose"
echo "------------------------------------------------------------"

COMPOSE_OK=false

if command -v docker >/dev/null 2>&1; then

    if docker compose config >"$TMP_COMPOSE" 2>"$TMP_COMPOSE_ERR"; then
        ok "docker compose config ist syntaktisch gültig"
        COMPOSE_OK=true
    else
        error "docker compose config meldet einen Fehler"
        cat "$TMP_COMPOSE_ERR"
    fi

else
    error "docker wurde nicht gefunden"
fi

#
# Community-Block direkt aus docker-compose.yml lesen
#

COMMUNITY_RAW=""

if [[ -f "$COMPOSE_FILE" ]]; then
    COMMUNITY_RAW="$(
        awk '
            /^[[:space:]]*community:[[:space:]]*$/ {
                in_community=1
                indent=match($0,/[^ ]/)-1
                print
                next
            }

            in_community {
                current_indent=match($0,/[^ ]/)-1

                if ($0 ~ /^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$/ &&
                    current_indent == indent) {
                    exit
                }

                print
            }
        ' "$COMPOSE_FILE"
    )"
fi

if [[ -z "$COMMUNITY_RAW" ]]; then
    error "Community-Service wurde in docker-compose.yml nicht gefunden"
else

    echo
    info "Prüfe env_file des Community-Service"

    #
    # custom.env darf entweder als Kurzform
    #
    #   env_file: custom.env
    #
    # oder als Liste konfiguriert sein:
    #
    #   env_file:
    #     - custom.env
    #     - saml.env
    #

    if echo "$COMMUNITY_RAW" | grep -qE \
        '^[[:space:]]*env_file:[[:space:]]*custom\.env[[:space:]]*$|^[[:space:]]*-[[:space:]]*custom\.env[[:space:]]*$'
    then
        ok "community verwendet custom.env"
    else
        error "community verwendet custom.env nicht"
    fi

    #
    # Für SAML erwarten wir saml.env zusätzlich als env_file.
    #

    if echo "$COMMUNITY_RAW" | grep -qE \
        '^[[:space:]]*-[[:space:]]*saml\.env[[:space:]]*$'
    then
        ok "community verwendet saml.env"
    else
        error "community verwendet saml.env nicht"

        info "Erwartete Konfiguration:"
        echo
        echo "    env_file:"
        echo "      - custom.env"
        echo "      - saml.env"
    fi

fi

#
# Truststore-Mount aus der aufgelösten Compose-Konfiguration prüfen
#

if [[ "$COMPOSE_OK" == true ]]; then

    COMMUNITY_CONFIG="$(
        awk '
            /^  community:$/ {
                in_community=1
                print
                next
            }

            in_community && /^  [a-zA-Z0-9_-]+:$/ {
                exit
            }

            in_community {
                print
            }
        ' "$TMP_COMPOSE"
    )"

    echo
    info "Prüfe Truststore-Mount des Community-Service"

    TRUSTSTORE_SOURCE="$(
        echo "$COMMUNITY_CONFIG" | awk '
            /source:/ {
                source=$2
            }

            /target:[[:space:]]*\/local\/notesdata\/samltruststore\.p12/ {
                print source
                exit
            }
        '
    )"

    if [[ -n "$TRUSTSTORE_SOURCE" ]]; then
        ok "Truststore-Mount im Community-Service gefunden"
        info "Host:      $TRUSTSTORE_SOURCE"
        info "Container: /local/notesdata/samltruststore.p12"

        if [[ -f "$TRUSTSTORE_SOURCE" ]]; then
            ok "Truststore-Datei auf dem Host vorhanden"
        else
            error "Truststore-Datei auf dem Host fehlt: $TRUSTSTORE_SOURCE"
        fi
    else
        error "Community-Service mountet keinen Truststore nach /local/notesdata/samltruststore.p12"
    fi

else
    warn "Truststore-Mount-Prüfung wegen ungültiger Compose-Konfiguration übersprungen"
fi

#
# 5. Laufender Community Container
#

echo
echo "5. Laufender Community Container"
echo "------------------------------------------------------------"

if [[ "$COMPOSE_OK" == true ]]; then

    COMMUNITY_CONTAINER="$(docker compose ps -q community 2>/dev/null || true)"

    if [[ -n "$COMMUNITY_CONTAINER" ]]; then

        ok "Community Container läuft"

        if docker exec "$COMMUNITY_CONTAINER" \
             test -f /local/notesdata/samltruststore.p12 2>/dev/null; then

            ok "Truststore ist im Community Container vorhanden"

        else
            error "Truststore fehlt im Community Container"
        fi

        CONTAINER_TRUST_TYPE="$(
            docker exec "$COMMUNITY_CONTAINER" env 2>/dev/null \
              | grep '^STI__Config__STSAML_TRUST_STORE_TYPE=' \
              | cut -d= -f2- \
              | tr -d '\r' \
              | trim
        )"

        if [[ "${CONTAINER_TRUST_TYPE,,}" == "p12" ]]; then
            ok "Community Container verwendet Truststore-Typ p12"
        else
            error "Truststore-Typ im laufenden Community Container nicht gefunden"
        fi

        CONTAINER_AUTH_TOKEN="$(
            docker exec "$COMMUNITY_CONTAINER" env 2>/dev/null \
              | grep '^STI__ST_BB_NAMES__ST_AUTH_TOKEN=' \
              | cut -d= -f2- \
              | tr -d '\r' \
              | trim
        )"

        if echo "$CONTAINER_AUTH_TOKEN" | grep -qi 'saml'; then
            ok "Community Container hat SAML im ST_AUTH_TOKEN aktiviert"
            info "ST_AUTH_TOKEN=$CONTAINER_AUTH_TOKEN"
        else
            error "Community Container hat SAML nicht im ST_AUTH_TOKEN aktiviert"
        fi

    else
        error "Community Container läuft nicht oder konnte nicht ermittelt werden"
    fi

else
    warn "Container-Prüfung wegen ungültiger Docker-Compose-Konfiguration übersprungen"
fi

#
# 6. Sametime URL
#

echo
echo "6. Sametime URL ermitteln"
echo "------------------------------------------------------------"

if [[ -z "$SAMETIME_URL" ]]; then

    if [[ "$STCONF_IDPURL" =~ TARGET=https://([^/]+)/chat ]]; then

        SAMETIME_URL="https://${BASH_REMATCH[1]}"
        info "Sametime URL aus TARGET erkannt: $SAMETIME_URL"

    elif [[ "$IDP_URL" =~ TARGET=https://([^/]+)/chat ]]; then

        SAMETIME_URL="https://${BASH_REMATCH[1]}"
        info "Sametime URL aus IDP_URL erkannt: $SAMETIME_URL"

    else
        warn "Sametime URL konnte nicht automatisch erkannt werden"
    fi
else
    info "Vorgegebene Sametime URL: $SAMETIME_URL"
fi

#
# 7. proxyinfo
#

echo
echo "7. /stwebapi/proxyinfo"
echo "------------------------------------------------------------"

if [[ -n "$SAMETIME_URL" ]]; then

    PROXYINFO="$(
        curl -fsS \
          --connect-timeout 10 \
          "${SAMETIME_URL}/stwebapi/proxyinfo" \
          2>/dev/null || true
    )"

    if [[ -z "$PROXYINFO" ]]; then

        error "proxyinfo konnte nicht abgerufen werden"

    else

        ok "proxyinfo erfolgreich abgerufen"

        if command -v jq >/dev/null 2>&1; then

            #
            # WICHTIG:
            # Nicht ".isOIDC // empty" benutzen.
            # jq interpretiert FALSE dabei ebenfalls als leer.
            #

            IS_SAML="$(printf '%s' "$PROXYINFO" | jq -r '.isSAML | tostring')"
            IS_OIDC="$(printf '%s' "$PROXYINFO" | jq -r '.isOIDC | tostring')"
            OIDC_ISSUER_REMOTE="$(printf '%s' "$PROXYINFO" | jq -r '.oidcIssuer // ""')"
            IDP_REMOTE="$(printf '%s' "$PROXYINFO" | jq -r '.IDPUrl // ""')"
            COMMUNITY_CONNECTED="$(printf '%s' "$PROXYINFO" | jq -r '.communityConnected | tostring')"

            if [[ "$IS_SAML" == "true" ]]; then
                ok "proxyinfo: isSAML=true"
            else
                error "proxyinfo: isSAML=$IS_SAML"
            fi

            if [[ "$IS_OIDC" == "false" ]]; then
                ok "proxyinfo: isOIDC=false"
            else
                error "proxyinfo: isOIDC=$IS_OIDC"
            fi

            if [[ -z "$OIDC_ISSUER_REMOTE" ]]; then
                ok "proxyinfo: oidcIssuer ist leer"
            else
                error "proxyinfo: oidcIssuer ist gesetzt: $OIDC_ISSUER_REMOTE"
            fi

            if [[ -n "$IDP_REMOTE" ]]; then

                ok "proxyinfo: IDPUrl ist gesetzt"
                info "IDPUrl=$IDP_REMOTE"

                if echo "$IDP_REMOTE" | grep -q '/protocol/saml/'; then
                    ok "proxyinfo: IDPUrl ist ein SAML-Endpunkt"
                else
                    error "proxyinfo: IDPUrl sieht nicht nach SAML aus"
                fi

            else
                error "proxyinfo: IDPUrl ist leer"
            fi

            if [[ "$COMMUNITY_CONNECTED" == "true" ]]; then
                ok "proxyinfo: Community ist verbunden"
            else
                error "proxyinfo: Community ist nicht verbunden"
            fi

            echo
            info "Komplette proxyinfo:"
            printf '%s\n' "$PROXYINFO" | jq .

        else
            warn "jq ist nicht installiert"
            echo "$PROXYINFO"
        fi
    fi

else
    warn "Remote-Prüfung wurde übersprungen"
fi

#
# Ergebnis
#

echo
echo "============================================================"
echo " Ergebnis"
echo "============================================================"
echo "Fehler   : $ERRORS"
echo "Warnungen: $WARNINGS"

if [[ "$ERRORS" -gt 0 ]]; then

    echo
    echo "STATUS: FEHLER"
    exit 2

elif [[ "$WARNINGS" -gt 0 ]]; then

    echo
    echo "STATUS: OK MIT WARNUNGEN"
    exit 1

else

    echo
    echo "STATUS: OK - SAML-Konfiguration sieht konsistent aus"
    exit 0
fi
