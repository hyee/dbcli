#!/bin/bash
cd "$(dirname "$0")"
chmod +x ./dbcli.sh
./dbcli.sh pgsql "$@"