#!/usr/bin/env bash
# Idempotently ensure a stable self-signed codesigning identity exists so
# every rebuild has the same designated requirement. Ad-hoc signatures
# (`codesign --sign -`) pin TCC to the binary cdhash, so Files and Folders
# grants die on every rebuild.
#
# Lives in a dedicated keychain so this does not need the login password
# and does not touch unrelated credentials. Same pattern as Deal / Cockpit.
set -euo pipefail

IDENTITY_NAME="${SHARK_SIGN_IDENTITY:-Shark Self-Signed}"
KEYCHAIN_BASENAME="${SHARK_SIGN_KEYCHAIN:-shark-signing.keychain-db}"
KEYCHAIN_PASSWORD="${SHARK_SIGN_KEYCHAIN_PASSWORD:-shark-signing}"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN_BASENAME"

ensure_in_search_list() {
    local kc="$1"
    local list
    list=$(security list-keychains -d user | tr -d '"' | xargs)
    case " $list " in
        *" $kc "*) return 0 ;;
    esac
    # shellcheck disable=SC2086
    security list-keychains -d user -s $list "$kc" >/dev/null
}

has_identity() {
    # Self-signed identities are usable by codesign even when `find-identity -v`
    # reports 0 valid identities.
    security find-identity -p codesigning "$1" 2>/dev/null |
        grep -F "\"$IDENTITY_NAME\"" >/dev/null
}

if [ -f "$KEYCHAIN_PATH" ] && has_identity "$KEYCHAIN_PATH"; then
    ensure_in_search_list "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
    security set-keychain-settings "$KEYCHAIN_PATH" >/dev/null
    echo "$IDENTITY_NAME"
    exit 0
fi

echo "Creating codesigning identity '$IDENTITY_NAME'" >&2

if [ ! -f "$KEYCHAIN_PATH" ]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
fi
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security set-keychain-settings "$KEYCHAIN_PATH" >/dev/null

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

conf="$workdir/cert.cnf"
key="$workdir/key.pem"
cert="$workdir/cert.pem"
p12="$workdir/bundle.p12"

cat >"$conf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = v3
[ dn ]
CN = $IDENTITY_NAME
[ v3 ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$key" -out "$cert" \
    -days 3650 -config "$conf" >/dev/null 2>&1

p12_pass="shark-import"
openssl pkcs12 -export -legacy \
    -inkey "$key" -in "$cert" \
    -name "$IDENTITY_NAME" \
    -out "$p12" -passout "pass:$p12_pass"

security import "$p12" \
    -k "$KEYCHAIN_PATH" \
    -P "$p12_pass" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null 2>&1 || true

ensure_in_search_list "$KEYCHAIN_PATH"

if ! has_identity "$KEYCHAIN_PATH"; then
    echo "Failed to register identity '$IDENTITY_NAME' in $KEYCHAIN_PATH" >&2
    exit 1
fi

echo "$IDENTITY_NAME"
