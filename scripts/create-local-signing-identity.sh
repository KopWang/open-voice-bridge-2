#!/bin/zsh
set -euo pipefail

IDENTITY="Remote Shortcut Bridge Local Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null |
  rg -Fq "\"$IDENTITY\""; then
  print "codesign identity already available: $IDENTITY"
  exit 0
fi

TEMP_DIR="$(mktemp -d /private/tmp/remote-shortcut-signing.XXXXXX)"
chmod 700 "$TEMP_DIR"

cleanup() {
  case "$TEMP_DIR" in
    /private/tmp/remote-shortcut-signing.*) rm -rf -- "$TEMP_DIR" ;;
    *) print -u2 "refusing to clean unexpected path: $TEMP_DIR" ;;
  esac
}
trap cleanup EXIT

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -nodes \
  -days 3650 \
  -subj "/CN=$IDENTITY/O=KopWang/" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$TEMP_DIR/identity-key.pem" \
  -out "$TEMP_DIR/identity.pem"

P12_PASSWORD="$(openssl rand -hex 24)"
export P12_PASSWORD
openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$TEMP_DIR/identity-key.pem" \
  -in "$TEMP_DIR/identity.pem" \
  -out "$TEMP_DIR/identity.p12" \
  -passout env:P12_PASSWORD

security import "$TEMP_DIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$TEMP_DIR/identity.pem"

if ! security find-identity -v -p codesigning 2>/dev/null |
  rg -Fq "\"$IDENTITY\""; then
  print -u2 "created certificate is not a valid code-signing identity"
  exit 1
fi

print "created codesign identity: $IDENTITY"
