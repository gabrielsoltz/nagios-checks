#!/bin/bash
# Script: Check Bitcoin (high/low) values with Nagios xD
# Autor: Gabriel Soltz
# Site: www.3ops.com

# CHECK JQ
command -v jq >/dev/null 2>&1 || { echo >&2 "UNKNOWN: I require jq but it's not installed. Aborting."; exit 3; }

# ARGUMENTOS
ASK="$1"
VALUE="$2"
API="https://www.bitstamp.net/api/ticker/"

if [ "$#" -ne 2 ]; then
    echo "UNKNOWN: Wrong Parameters. USE: ./check-btc.sh <high/low> <vaue>"
    exit 3
fi

if [[ "$ASK" != "high" && "$ASK" != "low" ]]; then
    echo "UNKNOWN: Wrong Parameters. USE: ./check-btc.sh <high/low> <vaue>"
    exit 3
fi

# HIGH
if [[ "$ASK" == "high" ]]; then
    HIGH=$(curl -s $API | jq '.'$ASK'' | sed -e 's/^"//'  -e 's/"$//' | cut -d "." -f 1)
    if [[ $HIGH -gt $VALUE ]]; then
		echo "CRITICAL: $HIGH | high=$HIGH"
        exit 2
    else
        echo "OK: $HIGH | high=$HIGH"
        exit 0
    fi
fi

# LOW
if [[ "$ASK" == "low" ]]; then
    LOW=$(curl -s $API | jq '.'$ASK'' | sed -e 's/^"//'  -e 's/"$//' | cut -d "." -f 1 )
    if [[ $LOW -lt $VALUE ]]; then
		echo "CRITICAL: $LOW | low=$LOW"
        exit 2
    else
        echo "OK: $LOW | low=$LOW"
        exit 0
    fi
fi