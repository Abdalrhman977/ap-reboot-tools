#!/usr/bin/env bash
#
# hnap-reboot.sh - Reboot D-Link (and other HNAP1-based) routers / access points
#
# Logs in through the HNAP1 web API (challenge / HMAC-MD5 handshake) and
# sends the Reboot action.
#
# Usage:
#   ./hnap-reboot.sh [-u user] [-s] HOST [HOST ...]
#   ./hnap-reboot.sh [-u user] -f devices.txt
#
#   -u USER   Login username (default: admin)
#   -f FILE   File with one host per line (# comments allowed)
#   -s        Use plain http instead of https
#   -h        Show this help
#
# The password is read from the HNAP_PASSWORD environment variable, or you
# are prompted for it (it is never passed on the command line).
#
# Requires: bash, curl, openssl, sed, awk  (Linux, macOS, WSL or Git Bash)

set -euo pipefail

USERNAME="admin"
SCHEME="https"
HOSTS=()

usage() { sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":u:f:sh" opt; do
  case "$opt" in
    u) USERNAME="$OPTARG" ;;
    f) while IFS= read -r line || [[ -n "$line" ]]; do
         line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"
         [[ -n "$line" ]] && HOSTS+=("$line")
       done < "$OPTARG" ;;
    s) SCHEME="http" ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND - 1))
HOSTS+=("$@")

[[ ${#HOSTS[@]} -eq 0 ]] && { echo "Error: no host given." >&2; usage 1; }

for bin in curl openssl sed awk; do
  command -v "$bin" >/dev/null || { echo "Error: '$bin' is required." >&2; exit 1; }
done

PASSWORD="${HNAP_PASSWORD:-}"
if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "Password for $USERNAME: " PASSWORD; echo
fi

# Extract the text of an XML tag: xml_tag <Tag> <<< "$xml"
xml_tag() { sed -n "s:.*<$1>\([^<]*\)</$1>.*:\1:p" | head -n1; }

# HMAC-MD5, uppercase hex: hmac_md5 <key> <message>
hmac_md5() { printf '%s' "$2" | openssl dgst -md5 -hmac "$1" | awk '{print toupper($NF)}'; }

# HNAP timestamp (last 6 digits of epoch milliseconds)
hnap_timestamp() {
  local ms
  ms="$(date +%s%3N 2>/dev/null)"
  [[ "$ms" == *N ]] && ms="$(( $(date +%s) * 1000 ))"   # macOS fallback
  echo "${ms: -6}"
}

soap_login() {
  cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Body>
<Login xmlns="http://purenetworks.com/HNAP1/">
<Action>$1</Action>
<Username>$USERNAME</Username>
<LoginPassword>$2</LoginPassword>
<Captcha></Captcha>
</Login>
</soap:Body>
</soap:Envelope>
EOF
}

SOAP_REBOOT='<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Body>
<Reboot xmlns="http://purenetworks.com/HNAP1/"/>
</soap:Body>
</soap:Envelope>'

reboot_host() {
  local host="$1"
  local url="$SCHEME://$host/HNAP1/"
  local curl_opts=(-k -s --max-time 10 -H "Content-Type: text/xml; charset=utf-8")

  # 1. Ask for a login challenge
  local resp challenge cookie pubkey
  resp="$(curl "${curl_opts[@]}" -H 'SOAPAction: "http://purenetworks.com/HNAP1/Login"' \
            -d "$(soap_login request '')" "$url")" || { echo "[FAIL] $host - not reachable"; return 1; }

  challenge="$(xml_tag Challenge <<< "$resp")"
  cookie="$(xml_tag Cookie <<< "$resp")"
  pubkey="$(xml_tag PublicKey <<< "$resp")"
  if [[ -z "$challenge" || -z "$cookie" || -z "$pubkey" ]]; then
    echo "[FAIL] $host - no HNAP challenge (not an HNAP1 device?)"; return 1
  fi

  # 2. Compute keys and log in
  local private_key login_pass result
  private_key="$(hmac_md5 "${pubkey}${PASSWORD}" "$challenge")"
  login_pass="$(hmac_md5 "$private_key" "$challenge")"

  resp="$(curl "${curl_opts[@]}" -H 'SOAPAction: "http://purenetworks.com/HNAP1/Login"' \
            -H "Cookie: uid=$cookie" -d "$(soap_login login "$login_pass")" "$url")"
  result="$(xml_tag LoginResult <<< "$resp")"
  if [[ -n "$result" && "$result" != "success" ]]; then
    echo "[FAIL] $host - login rejected ($result)"; return 1
  fi

  # 3. Send the reboot
  local ts auth
  ts="$(hnap_timestamp)"
  auth="$(hmac_md5 "$private_key" "${ts}http://purenetworks.com/HNAP1/Reboot")"

  curl "${curl_opts[@]}" -H 'SOAPAction: "http://purenetworks.com/HNAP1/Reboot"' \
       -H "Cookie: uid=$cookie" -H "HNAP_AUTH: $auth $ts" \
       -d "$SOAP_REBOOT" "$url" >/dev/null || true

  echo "[OK]   $host - reboot sent"
}

failed=0
for host in "${HOSTS[@]}"; do
  reboot_host "$host" || failed=$((failed + 1))
done

unset PASSWORD
exit "$failed"
