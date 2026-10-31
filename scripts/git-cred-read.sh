#!/bin/sh
op="${1:-get}"
[ "$op" = "get" ] || exit 0
proto=""
host=""
want_user=""
while IFS='=' read -r key value; do
  case "$key" in
    protocol) proto="$value" ;;
    host) host="$value" ;;
    username) want_user="$value" ;;
  esac
done
[ -n "$proto" ] && [ -n "$host" ] || exit 0
cred="$HOME/.git-credentials"
[ -f "$cred" ] || exit 0
while IFS= read -r line; do
  case "$line" in
    "$proto://"*"@$host") ;;
    *) continue ;;
  esac
  rest="${line#"$proto://"}"
  rest="${rest%%/*}"
  userpass="${rest%@*}"
  case "$userpass" in *:*) ;; *) continue ;; esac
  user="${userpass%%:*}"
  pass="${userpass#*:}"
  case "$pass" in
    *%*) echo "git-cred-read: percent-encoded password unsupported for $host" >&2; exit 1 ;;
  esac
  if [ -n "$want_user" ] && [ "$user" != "$want_user" ]; then continue; fi
  printf 'protocol=%s\nhost=%s\nusername=%s\npassword=%s\n' "$proto" "$host" "$user" "$pass"
  exit 0
done < "$cred"
exit 0
