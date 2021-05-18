#!/usr/bin/env bash
SCRIPTNAME=$(basename "$0")
log() { l="$1"; shift; printf "%s %4s - %s\n" "$(date -Is)" "$l" "$*"; }
errcho() { >&2 echo "$@"; }
usage() {
    errcho "Usage: $SCRIPTNAME [-h] [-x <exclude>] <-u <user>> <-t <token>>"
    errcho " -h, --help                 display this message and exit"
    errcho " -x, --exclude <slugs>      ignore specified comma-separated goals"
    errcho " -u, --user <username>      your beeminder username"
    errcho " -t, --token <api_token>    your beeminder API token"
    errcho
    errcho "Username and token must be provided or passed as environment"
    errcho "variables BEEMINDER_USER and BEEMINDER_TOKEN. You can set"
    errcho "BEEMINDER_TIME to override the default (date -d'+24hour' '+%s')"
    errcho "time used to determine if there are active true beemergencies."
    exit 1
}

has() { command -v "$1" > /dev/null; }
if ! has curl || ! has jq; then
    log ERR "Fatal: missing required dependency 'curl' or 'jq' from PATH"
fi

declare -a EXCLUDE
if ! options=$(getopt -o 'hx:t:u:' --long 'help,exclude:,token:,user:' -n "$SCRIPTNAME" -- "$@"); then usage; fi
eval set -- "$options"
while [ $# -gt 0 ]; do
    case "$1" in
        -x | --exclude)
            IFS=',' read -ra EXCLUDE <<< "$2"
            shift 2
            ;;
        -t | --token)
            BEEMINDER_TOKEN="$2"
            shift 2
            ;;
        -u | --user)
            BEEMINDER_USER="$2"
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        --) shift; ;;
        *)
            log ERR "unknown option: $1"
            errcho; usage
            ;;
    esac
done

if [ -z "$BEEMINDER_USER" ]; then
    log ERR "Fatal: beeminder user required, via -u or BEEMINDER_USER"
    errcho; usage
elif [ -z "$BEEMINDER_TOKEN" ]; then
    log ERR "Fatal: beeminder API token required, via -t or BEEMINDER_TOKEN"
    log INFO "Visit https://www.beeminder.com/api/v1/auth_token.json while logged in to get it."
    errcho; usage
fi


beeapi() {
    curl -sSL "https://www.beeminder.com/api/v1${1}?auth_token=${BEEMINDER_TOKEN}"
}

: "${BEEMERGENCY_TIME:=$(date -d'+24hour' '+%s')}"
log INFO "beemergency deadline: $(date -d"@$BEEMERGENCY_TIME" -Is)"
mapfile -t beemergencies <<< "$(\
    beeapi "/users/${BEEMINDER_USER}/goals.json" \
    | jq -r '.[] | select(.losedate < '"$BEEMERGENCY_TIME"') | .slug' \
)"

log INFO "beemergencies: ${beemergencies[*]}"
if [ -n "${EXCLUDE[*]}" ]; then
    log INFO "excluding: ${EXCLUDE[*]}"
fi

mapfile -t real_beemergencies <<< "$(\
    echo "${beemergencies[@]}" "${EXCLUDE[@]}" "${EXCLUDE[@]}" \
    | tr ' ' '\n' | sort | uniq -u \
)"

if [ -n "${real_beemergencies[*]}" ]; then
    log INFO "true beemergencies remaining: ${real_beemergencies[*]}"
    # DO WEBHOOK
else
    log INFO "no true beemergencies. whew!"
fi
