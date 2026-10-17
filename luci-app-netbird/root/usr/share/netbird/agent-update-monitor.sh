#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Independent of rpcd, LuCI sessions, the download worker and its connection.
export NB_AGENT_WORKER=1
worker=/usr/share/netbird/agent-update-worker.uc
child=
waiter=
finish() {
    [ -z "$child" ] || kill "$child" 2>/dev/null
    [ -z "$waiter" ] || kill "$waiter" 2>/dev/null
    exit 0
}
trap finish TERM INT
while :; do
    ucode "$worker" recover >/dev/null 2>&1 &
    child=$!
    wait "$child"
    child=
    ucode "$worker" tick >/dev/null 2>&1 &
    child=$!
    wait "$child"
    child=
    if [ -f /etc/netbird-update/settings.pending ] && ucode "$worker" guard; then
        /etc/init.d/netbird-settings reload && rm -f /etc/netbird-update/settings.pending
    fi
    sleep 20 &
    waiter=$!
    wait "$waiter"
    waiter=
done
