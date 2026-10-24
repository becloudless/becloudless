#!/bin/sh
# Sidecar of the Syncthing instance: keeps the sync protocol listen address of the instance on the relay of the cluster, so that the
# instance is reachable through it without any manual step in the UI. It also sets `gui.insecureAdminAccess`, which only turns off the
# warning of the UI about the missing password (the access is restricted by authelia and the Gateway).
#
# The relay ID is the device ID of its certificate (sha256 of the DER, base32, a luhn32 check character every 13 characters, groups of 7),
# computed here from the public certificate of the relay so that nothing has to be copied by hand.
#
# Environment: RELAY_HOST, RELAY_PORT, RELAY_TOKEN
# Files: /relay/tls.crt (certificate of the relay), /var/syncthing/config/config.xml (read only: the API key of the instance is in it)
set -eu

relay_id() {
  awk '/BEGIN CERTIFICATE/ {f = 1; next} /END CERTIFICATE/ {exit} f' "$1" | base64 -d | sha256sum | awk '{
    alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"; hex = "0123456789abcdef"; bits = ""
    for (i = 1; i <= length($1); i++) {
      d = index(hex, substr($1, i, 1)) - 1
      bits = bits (d >= 8 ? 1 : 0) (int(d / 4) % 2) (int(d / 2) % 2) (d % 2)
    }
    bits = bits "0000"
    s = ""
    for (i = 0; i < 52; i++) {
      v = 0
      for (j = 1; j <= 5; j++) v = v * 2 + substr(bits, i * 5 + j, 1)
      s = s substr(alpha, v + 1, 1)
    }
    out = ""
    for (b = 0; b < 4; b++) {
      p = substr(s, b * 13 + 1, 13); factor = 1; sum = 0
      for (k = 1; k <= 13; k++) {
        add = factor * (index(alpha, substr(p, k, 1)) - 1); factor = (factor == 2 ? 1 : 2)
        sum += int(add / 32) + add % 32
      }
      out = out p substr(alpha, (32 - sum % 32) % 32 + 1, 1)
    }
    res = ""
    for (i = 1; i <= 56; i += 7) res = res (i > 1 ? "-" : "") substr(out, i, 7)
    print res
  }'
}

id=$(relay_id /relay/tls.crt)
if [ "${#id}" != 63 ]; then
  echo "cannot compute the ID of the relay from /relay/tls.crt" >&2
  exit 1
fi
want="relay://${RELAY_HOST}:${RELAY_PORT}/?id=${id}&token=${RELAY_TOKEN}"
echo "the instance listens on the relay relay://${RELAY_HOST}:${RELAY_PORT}/?id=${id}"

# The addresses are reset at each check: a change made in the UI is reverted. The first checks are quick, the instance is starting.
wait=2
while true; do
  key=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' /var/syncthing/config/config.xml 2>/dev/null || true)
  if [ -n "$key" ]; then
    # the UI has no authentication of its own (authelia is in front of it): without this flag it warns about the remote access
    if ! curl -sf -H "X-API-Key: $key" http://localhost:8384/rest/config/gui 2>/dev/null | tr -d ' \n' | grep -q '"insecureAdminAccess":true'; then
      if curl -sf -X PATCH -H "X-API-Key: $key" -d '{"insecureAdminAccess":true}' http://localhost:8384/rest/config/gui >/dev/null; then
        echo "the insecure admin access warning of the UI is disabled"
      fi
    fi
    # the API escapes the `&` of the address
    current=$(curl -sf -H "X-API-Key: $key" http://localhost:8384/rest/config/options 2>/dev/null | tr -d ' \n' | sed 's/\\u0026/\&/g' || true)
    case "$current" in
      *"\"listenAddresses\":[\"$want\"]"*)
        wait=30
        ;;
      "")
        ;;
      *)
        if curl -sf -X PATCH -H "X-API-Key: $key" -d "{\"listenAddresses\":[\"$want\"]}" http://localhost:8384/rest/config/options >/dev/null; then
          echo "the listen address of the instance is set to the relay"
        else
          echo "cannot set the listen address of the instance" >&2
        fi
        ;;
    esac
  fi
  sleep "$wait"
done
