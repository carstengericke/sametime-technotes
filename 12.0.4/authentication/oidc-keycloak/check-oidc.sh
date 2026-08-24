#!/usr/bin/env bash

set -u

SAMETIME_DIR="${SAMETIME_DIR:-/opt/hcl/sametime}"
SAMETIME_URL="${SAMETIME_URL:-}"

ERRORS=0
WARNINGS=0

TMP_COMPOSE="/tmp/check-oidc-compose.yml"
TMP_COMPOSE_ERR="/tmp/check-oidc-compose.err"
TMP_DISCOVERY="/tmp/check-oidc-discovery.json"

cleanup() {
    rm -f "$TMP_COMPOSE" "$TMP_COMPOSE_ERR" "$TMP_DISCOVERY"
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

mask_secret() {
    local value="$1"

    if [[ -z "$value" ]]; then
        echo "<leer>"
    else
        echo "<gesetzt>"
    fi
}

echo "============================================================"
echo " HCL Sametime OIDC Configuration Check"
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
    info "saml.env ist noch vorhanden, wird aber nur beanstandet wenn es eingebunden ist"
else
    ok "saml.env ist nicht vorhanden"
fi

if command -v jq >/dev/null 2>&1; then
    ok "jq ist installiert"
else
    error "jq ist nicht installiert"
fi

if command -v curl >/dev/null 2>&1; then
    ok "curl ist installiert"
else
    error "curl ist nicht installiert"
fi

#
# 2. OIDC Parameter
#

echo
echo "2. OIDC Parameter"
echo "------------------------------------------------------------"

STCONF_ISOIDC="$(get_value "$CUSTOM_ENV" "STCONF_ISOIDC")"

OIDC_CLIENT_ID="$(get_value "$CUSTOM_ENV" "OIDC_CLIENT_ID")"
OIDC_CLIENT_SECRET="$(get_value "$CUSTOM_ENV" "OIDC_CLIENT_SECRET")"
OIDC_ISSUER_URI="$(get_value "$CUSTOM_ENV" "OIDC_ISSUER_URI")"
OIDC_AUTHORIZATION_URL="$(get_value "$CUSTOM_ENV" "OIDC_AUTHORIZATION_URL")"
OIDC_TOKEN_URL="$(get_value "$CUSTOM_ENV" "OIDC_TOKEN_URL")"
OIDC_USER_INFO_URL="$(get_value "$CUSTOM_ENV" "OIDC_USER_INFO_URL")"

IDP_URL="$(get_value "$CUSTOM_ENV" "IDP_URL")"
AUTH_TOKEN="$(get_value "$CUSTOM_ENV" "STI__ST_BB_NAMES__ST_AUTH_TOKEN")"

STCONF_IDPURL="$(get_value "$ENV_FILE" "STCONF_IDPURL")"

case "${STCONF_ISOIDC,,}" in
    true|yes|1)
        ok "STCONF_ISOIDC ist aktiviert"
        ;;
    false|no|0)
        error "STCONF_ISOIDC ist deaktiviert: $STCONF_ISOIDC"
        ;;
    "")
        error "STCONF_ISOIDC ist nicht gesetzt"
        ;;
    *)
        error "Unbekannter Wert für STCONF_ISOIDC: $STCONF_ISOIDC"
        ;;
esac

if [[ -n "$OIDC_CLIENT_ID" ]]; then
    ok "OIDC_CLIENT_ID ist gesetzt"
    info "OIDC_CLIENT_ID=$OIDC_CLIENT_ID"
else
    error "OIDC_CLIENT_ID ist nicht gesetzt"
fi

if [[ -n "$OIDC_CLIENT_SECRET" ]]; then
    ok "OIDC_CLIENT_SECRET ist gesetzt"
else
    error "OIDC_CLIENT_SECRET ist nicht gesetzt"
fi

if [[ -n "$OIDC_ISSUER_URI" ]]; then
    ok "OIDC_ISSUER_URI ist gesetzt"
    info "OIDC_ISSUER_URI=$OIDC_ISSUER_URI"

    if [[ "$OIDC_ISSUER_URI" =~ ^https:// ]]; then
        ok "OIDC_ISSUER_URI verwendet HTTPS"
    else
        error "OIDC_ISSUER_URI verwendet kein HTTPS"
    fi

    if echo "$OIDC_ISSUER_URI" | grep -q '/protocol/'; then
        warn "OIDC_ISSUER_URI enthält /protocol/ - normalerweise muss hier nur der Realm-Issuer stehen"
    fi
else
    error "OIDC_ISSUER_URI ist nicht gesetzt"
fi

if [[ -n "$OIDC_AUTHORIZATION_URL" ]]; then
    ok "OIDC_AUTHORIZATION_URL ist gesetzt"
    info "OIDC_AUTHORIZATION_URL=$OIDC_AUTHORIZATION_URL"

    if echo "$OIDC_AUTHORIZATION_URL" | grep -q '/protocol/openid-connect/auth'; then
        ok "OIDC_AUTHORIZATION_URL sieht nach Keycloak OIDC aus"
    else
        warn "OIDC_AUTHORIZATION_URL sieht nicht nach Keycloak /protocol/openid-connect/auth aus"
    fi
else
    error "OIDC_AUTHORIZATION_URL ist nicht gesetzt"
fi

if [[ -n "$OIDC_TOKEN_URL" ]]; then
    ok "OIDC_TOKEN_URL ist gesetzt"
    info "OIDC_TOKEN_URL=$OIDC_TOKEN_URL"

    if echo "$OIDC_TOKEN_URL" | grep -q '/protocol/openid-connect/token'; then
        ok "OIDC_TOKEN_URL sieht nach Keycloak OIDC aus"
    else
        warn "OIDC_TOKEN_URL sieht nicht nach Keycloak /protocol/openid-connect/token aus"
    fi
else
    error "OIDC_TOKEN_URL ist nicht gesetzt"
fi

if [[ -n "$OIDC_USER_INFO_URL" ]]; then
    ok "OIDC_USER_INFO_URL ist gesetzt"
    info "OIDC_USER_INFO_URL=$OIDC_USER_INFO_URL"

    if echo "$OIDC_USER_INFO_URL" | grep -q '/protocol/openid-connect/userinfo'; then
        ok "OIDC_USER_INFO_URL sieht nach Keycloak OIDC aus"
    else
        warn "OIDC_USER_INFO_URL sieht nicht nach Keycloak /protocol/openid-connect/userinfo aus"
    fi
else
    error "OIDC_USER_INFO_URL ist nicht gesetzt"
fi

#
# 3. SAML muss deaktiviert sein
#

echo
echo "3. SAML deaktiviert"
echo "------------------------------------------------------------"

if [[ -z "$IDP_URL" ]]; then
    ok "IDP_URL ist leer"
else
    error "IDP_URL ist noch gesetzt: $IDP_URL"
fi

if [[ -z "$STCONF_IDPURL" ]]; then
    ok "STCONF_IDPURL ist leer"
else
    error "STCONF_IDPURL ist noch gesetzt: $STCONF_IDPURL"
fi

if [[ -n "$AUTH_TOKEN" ]]; then
    info "ST_AUTH_TOKEN=$AUTH_TOKEN"

    if echo "$AUTH_TOKEN" | grep -qi 'saml'; then
        error "SAML ist noch in STI__ST_BB_NAMES__ST_AUTH_TOKEN aktiviert"
    else
        ok "SAML ist nicht mehr in STI__ST_BB_NAMES__ST_AUTH_TOKEN enthalten"
    fi

    if echo "$AUTH_TOKEN" | grep -qi 'jwt'; then
        ok "Jwt ist in STI__ST_BB_NAMES__ST_AUTH_TOKEN enthalten"
    else
        warn "Jwt wurde in STI__ST_BB_NAMES__ST_AUTH_TOKEN nicht gefunden"
    fi
else
    error "STI__ST_BB_NAMES__ST_AUTH_TOKEN ist nicht gesetzt"
fi

#
# 4. OIDC Discovery
#

echo
echo "4. OIDC Discovery"
echo "------------------------------------------------------------"

DISCOVERY_URL=""

if [[ -n "$OIDC_ISSUER_URI" ]]; then
    DISCOVERY_URL="${OIDC_ISSUER_URI%/}/.well-known/openid-configuration"
    info "Discovery URL: $DISCOVERY_URL"

    if curl -fsS \
        --connect-timeout 10 \
        "$DISCOVERY_URL" \
        -o "$TMP_DISCOVERY"
    then
        ok "OIDC Discovery erfolgreich abgerufen"
    else
        error "OIDC Discovery konnte nicht abgerufen werden"
    fi
fi

if [[ -s "$TMP_DISCOVERY" ]] && command -v jq >/dev/null 2>&1; then

    DISC_ISSUER="$(jq -r '.issuer // ""' "$TMP_DISCOVERY")"
    DISC_AUTH="$(jq -r '.authorization_endpoint // ""' "$TMP_DISCOVERY")"
    DISC_TOKEN="$(jq -r '.token_endpoint // ""' "$TMP_DISCOVERY")"
    DISC_USERINFO="$(jq -r '.userinfo_endpoint // ""' "$TMP_DISCOVERY")"
    DISC_JWKS="$(jq -r '.jwks_uri // ""' "$TMP_DISCOVERY")"

    if [[ "$DISC_ISSUER" == "$OIDC_ISSUER_URI" ]]; then
        ok "Discovery issuer entspricht OIDC_ISSUER_URI"
    else
        error "Discovery issuer stimmt nicht mit OIDC_ISSUER_URI überein"
        info "Konfiguriert: $OIDC_ISSUER_URI"
        info "Discovery:    $DISC_ISSUER"
    fi

    if [[ "$DISC_AUTH" == "$OIDC_AUTHORIZATION_URL" ]]; then
        ok "authorization_endpoint entspricht OIDC_AUTHORIZATION_URL"
    else
        error "authorization_endpoint stimmt nicht mit OIDC_AUTHORIZATION_URL überein"
        info "Konfiguriert: $OIDC_AUTHORIZATION_URL"
        info "Discovery:    $DISC_AUTH"
    fi

    if [[ "$DISC_TOKEN" == "$OIDC_TOKEN_URL" ]]; then
        ok "token_endpoint entspricht OIDC_TOKEN_URL"
    else
        error "token_endpoint stimmt nicht mit OIDC_TOKEN_URL überein"
        info "Konfiguriert: $OIDC_TOKEN_URL"
        info "Discovery:    $DISC_TOKEN"
    fi

    if [[ "$DISC_USERINFO" == "$OIDC_USER_INFO_URL" ]]; then
        ok "userinfo_endpoint entspricht OIDC_USER_INFO_URL"
    else
        error "userinfo_endpoint stimmt nicht mit OIDC_USER_INFO_URL überein"
        info "Konfiguriert: $OIDC_USER_INFO_URL"
        info "Discovery:    $DISC_USERINFO"
    fi

    if [[ -n "$DISC_JWKS" ]]; then
        ok "jwks_uri ist vorhanden"
        info "jwks_uri=$DISC_JWKS"

        if curl -fsS \
            --connect-timeout 10 \
            "$DISC_JWKS" \
            >/dev/null
        then
            ok "JWKS Endpoint ist erreichbar"
        else
            error "JWKS Endpoint ist nicht erreichbar"
        fi
    else
        error "Discovery enthält keine jwks_uri"
    fi
fi

#
# 5. Docker Compose
#

echo
echo "5. Docker Compose"
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

    info "Prüfe env_file des Community-Service"

    if echo "$COMMUNITY_RAW" | grep -qE \
        '^[[:space:]]*env_file:[[:space:]]*custom\.env[[:space:]]*$|^[[:space:]]*-[[:space:]]*custom\.env[[:space:]]*$'
    then
        ok "community verwendet custom.env"
    else
        error "community verwendet custom.env nicht"
    fi

    if echo "$COMMUNITY_RAW" | grep -qE \
        '^[[:space:]]*-[[:space:]]*saml\.env[[:space:]]*$|^[[:space:]]*env_file:[[:space:]]*saml\.env[[:space:]]*$'
    then
        error "community verwendet noch saml.env"
    else
        ok "community verwendet saml.env nicht"
    fi

    if echo "$COMMUNITY_RAW" | grep -qi \
        'samltruststore'
    then
        error "Community-Service enthält noch einen SAML Truststore Mount"
    else
        ok "Community-Service enthält keinen SAML Truststore Mount"
    fi

fi

#
# Aufgelöste Compose-Konfiguration auf SAML prüfen
#

if [[ "$COMPOSE_OK" == true ]]; then

    if grep -qi 'samltruststore' "$TMP_COMPOSE"; then
        error "Aufgelöste Compose-Konfiguration enthält noch samltruststore"
    else
        ok "Aufgelöste Compose-Konfiguration enthält keinen SAML Truststore"
    fi

    if grep -qi '/protocol/saml/' "$TMP_COMPOSE"; then
        error "Aufgelöste Compose-Konfiguration enthält noch einen SAML-Endpunkt"
    else
        ok "Aufgelöste Compose-Konfiguration enthält keinen SAML-Endpunkt"
    fi

fi

#
# 6. Laufende Container
#

echo
echo "6. Laufende Container"
echo "------------------------------------------------------------"

if [[ "$COMPOSE_OK" == true ]]; then

    COMMUNITY_CONTAINER="$(docker compose ps -q community 2>/dev/null || true)"

    if [[ -n "$COMMUNITY_CONTAINER" ]]; then

        ok "Community Container läuft"

        CONTAINER_AUTH_TOKEN="$(
            docker exec "$COMMUNITY_CONTAINER" env 2>/dev/null \
              | grep '^STI__ST_BB_NAMES__ST_AUTH_TOKEN=' \
              | cut -d= -f2- \
              | tr -d '\r' \
              | trim
        )"

        if [[ -n "$CONTAINER_AUTH_TOKEN" ]]; then

            info "ST_AUTH_TOKEN=$CONTAINER_AUTH_TOKEN"

            if echo "$CONTAINER_AUTH_TOKEN" | grep -qi 'saml'; then
                error "Community Container hat SAML noch im ST_AUTH_TOKEN aktiviert"
            else
                ok "Community Container hat SAML nicht im ST_AUTH_TOKEN aktiviert"
            fi

        else
            error "ST_AUTH_TOKEN wurde im Community Container nicht gefunden"
        fi

        if docker exec "$COMMUNITY_CONTAINER" \
             test -f /local/notesdata/samltruststore.p12 2>/dev/null
        then
            error "SAML Truststore ist im Community Container noch vorhanden"
        else
            ok "SAML Truststore ist im Community Container nicht vorhanden"
        fi

    else
        error "Community Container läuft nicht oder konnte nicht ermittelt werden"
    fi

else
    warn "Container-Prüfung wegen ungültiger Docker-Compose-Konfiguration übersprungen"
fi

#
# Prüfen, ob mindestens ein laufender Container die OIDC-Variablen sieht
#

echo
info "Suche OIDC-Konfiguration in laufenden Sametime-Containern"

OIDC_CONTAINER_COUNT=0

for container in $(docker compose ps -q 2>/dev/null); do

    CONTAINER_NAME="$(
        docker inspect \
            -f '{{.Name}}' \
            "$container" 2>/dev/null \
            | sed 's#^/##'
    )"

    CONTAINER_OIDC_CLIENT_ID="$(
        docker exec "$container" env 2>/dev/null \
            | grep '^OIDC_CLIENT_ID=' \
            | cut -d= -f2- \
            | tr -d '\r' \
            | trim
    )"

    if [[ -n "$CONTAINER_OIDC_CLIENT_ID" ]]; then
        OIDC_CONTAINER_COUNT=$((OIDC_CONTAINER_COUNT + 1))
        ok "$CONTAINER_NAME verwendet OIDC_CLIENT_ID=$CONTAINER_OIDC_CLIENT_ID"
    fi

done

if [[ "$OIDC_CONTAINER_COUNT" -eq 0 ]]; then
    warn "OIDC_CLIENT_ID wurde in keinem laufenden Container gefunden"
else
    ok "OIDC-Konfiguration ist in $OIDC_CONTAINER_COUNT Container(n) vorhanden"
fi

#
# 7. Sametime URL
#

echo
echo "7. Sametime URL ermitteln"
echo "------------------------------------------------------------"

if [[ -z "$SAMETIME_URL" ]]; then

    #
    # Bei OIDC lässt sich die Sametime URL nicht mehr aus TARGET ableiten.
    # Deshalb REACT_APP_MEETING_SERVER_HOSTNAME aus .env verwenden.
    #

    ST_HOSTNAME="$(get_value "$ENV_FILE" "REACT_APP_MEETING_SERVER_HOSTNAME")"

    if [[ -n "$ST_HOSTNAME" ]]; then

        if [[ "$ST_HOSTNAME" =~ ^https?:// ]]; then
            SAMETIME_URL="${ST_HOSTNAME%/}"
        else
            SAMETIME_URL="https://${ST_HOSTNAME}"
        fi

        info "Sametime URL aus REACT_APP_MEETING_SERVER_HOSTNAME erkannt: $SAMETIME_URL"

    else
        warn "Sametime URL konnte nicht automatisch ermittelt werden"
        info "Bei Bedarf aufrufen mit:"
        info "SAMETIME_URL=https://stlab1.inlakech.de ./check-oidc.sh"
    fi

else
    info "Vorgegebene Sametime URL: $SAMETIME_URL"
fi

#
# 8. /stwebapi/proxyinfo
#

echo
echo "8. /stwebapi/proxyinfo"
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

            IS_SAML="$(printf '%s' "$PROXYINFO" | jq -r '.isSAML | tostring')"
            IS_OIDC="$(printf '%s' "$PROXYINFO" | jq -r '.isOIDC | tostring')"
            OIDC_ISSUER_REMOTE="$(printf '%s' "$PROXYINFO" | jq -r '.oidcIssuer // ""')"
            IDP_REMOTE="$(printf '%s' "$PROXYINFO" | jq -r '.IDPUrl // ""')"
            COMMUNITY_CONNECTED="$(printf '%s' "$PROXYINFO" | jq -r '.communityConnected | tostring')"

            if [[ "$IS_SAML" == "false" ]]; then
                ok "proxyinfo: isSAML=false"
            else
                error "proxyinfo: isSAML=$IS_SAML"
            fi

            if [[ "$IS_OIDC" == "true" ]]; then
                ok "proxyinfo: isOIDC=true"
            else
                error "proxyinfo: isOIDC=$IS_OIDC"
            fi

            if [[ "$OIDC_ISSUER_REMOTE" == "$OIDC_ISSUER_URI" ]]; then
                ok "proxyinfo: oidcIssuer entspricht OIDC_ISSUER_URI"
                info "oidcIssuer=$OIDC_ISSUER_REMOTE"
            else
                error "proxyinfo: oidcIssuer stimmt nicht mit OIDC_ISSUER_URI überein"
                info "Konfiguriert: $OIDC_ISSUER_URI"
                info "proxyinfo:    $OIDC_ISSUER_REMOTE"
            fi

            if [[ "$IDP_REMOTE" == *"/sametime-auth/api/v1/oidc/login"* ]]; then
                ok "proxyinfo: IDPUrl verweist auf Sametime OIDC Login"
                info "IDPUrl=$IDP_REMOTE"
            elif [[ -z "$IDP_REMOTE" ]]; then
		ok "proxyinfo: IDPUrl ist bei OIDC leer"
            elif echo "$IDP_REMOTE" | grep -q '/protocol/saml/'; then
                error "proxyinfo: IDPUrl verweist noch auf SAML: $IDP_REMOTE"
            else
                warn "proxyinfo: Unerwartete IDPUrl: $IDP_REMOTE"
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
    echo "STATUS: OK - OIDC-Konfiguration sieht konsistent aus"
    exit 0
fi
