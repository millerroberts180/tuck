#!/bin/zsh
# Creates "Tuck Local Signing", a self-signed code-signing identity kept in
# its own keychain, once per Mac. scripts/build-app.sh signs with it when it
# exists, and so does scripts/release.sh --unsigned.
#
# macOS ties the Accessibility grant to the app's signature. An ad-hoc
# signature changes with every build, so each rebuild needs the permission
# granted again; a signature from one stable certificate keeps the grant.
#
# Until there is a Developer ID, this identity also signs the test DMG that
# people download, so their grant survives each update too. Back up its
# private key (docs/release.md): a new certificate is a new signature, and
# everyone would grant Accessibility once more.
#
# The certificate is trusted by nothing and signs nothing anyone else would
# accept, so its keychain password is not a secret: it only lets builds use
# the key without a prompt. For a signed release, use a Developer ID instead
# (DEVELOPER_ID in scripts/release.sh).
set -euo pipefail

name="Tuck Local Signing"
keychain="$HOME/Library/Keychains/tuck-signing.keychain-db"
password="tuck-local-signing"

# codesign finds private keys only in keychains on the search list; keep the
# ones already there.
add_to_search_list() {
  local existing=("${(@f)$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')}")
  if (( ! ${existing[(Ie)$keychain]} )); then
    security list-keychains -d user -s "${existing[@]}" "$keychain"
  fi
}

if [[ -f $keychain ]] && security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  add_to_search_list
  echo "$name already exists in $keychain"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Tuck Local Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem 2>/dev/null
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$name" -out identity.p12 -passout "pass:$password"

[[ -f $keychain ]] || security create-keychain -p "$password" "$keychain"
security set-keychain-settings "$keychain" # Never locks on a timer.
security unlock-keychain -p "$password" "$keychain"
security import identity.p12 -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
# Lets codesign use the key without asking.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
add_to_search_list

echo "Created $name in $keychain"
