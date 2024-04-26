#!/usr/bin/env bash

set -ue

DATAGEN=$1

THIS_DIR="$(cd "$(dirname "$0")"; pwd -P)"

DATA_DIR=$THIS_DIR/tmp
echo "Data will be stored in $DATA_DIR"
rm -rf $DATA_DIR/*
mkdir -p $DATA_DIR/{config,logs}

check_port_is_available() {
    local name="$1"
    local port="$2"
    true &>/dev/null </dev/tcp/127.0.0.1/$port && echo "Something (probably $name) is already running on port $port. Please kill it and try again." && exit 1 || echo "$port is available for $name"
}

wait_for_port() {
    local name="$1"
    local port="$2"
    echo "Waiting for $name (check $DATA_DIR/logs/$name)"
    while ! $(true &>/dev/null </dev/tcp/127.0.0.1/$port)
    do
        echo -n "."
        sleep 0.1
    done
    echo
}

wait_for_sql_conn() {
    local name="$1"
    local port="$2"
    local user="$3"
    echo "Waiting for SQL connection to $name (check $DATA_DIR/logs/$name)"
    while true; do
        if psql "postgres://$user@localhost:$port/$user" -c "SELECT 1" &>/dev/null; then
            break;
        else
            echo -n "."
            sleep 0.1
        fi
    done
    echo
}

echo "Cleaning up environment"
docker-compose down

echo "Checking ports"
check_port_is_available "Materialize" 6875
check_port_is_available "PostgreSQL" 5433

echo "Starting PostgreSQL and Materialize"
docker pull postgres
docker pull materialize/materialized
docker-compose up -d
wait_for_port "postgres" 5433
wait_for_sql_conn "postgres" 5433 "postgres"
wait_for_port "materialized" 6875
wait_for_sql_conn "materialized" 6875 "materialize"

echo "Creating pg tables"
psql postgres://postgres@localhost:5433/postgres -f ./pg_tables.sql

echo "Creating views"
psql postgres://materialize@localhost:6875/materialize -c "ALTER ROLE materialize SET client_min_messages TO error" &>/dev/null
psql postgres://materialize@localhost:6875/materialize -f ./views.sql

echo "Watching outputs"
watch_view() { 
     unbuffer psql postgres://materialize@localhost:6875/materialize -c "COPY (SUBSCRIBE $1 WITH (snapshot) AS OF AT LEAST 0) TO STDOUT" > $DATA_DIR/$1 &
}
watch_view accepted_transactions
watch_view outer_join
watch_view credits
watch_view debits
watch_view balance
watch_view total

echo "Feeding inputs"
python3 $DATAGEN | cut -d'|' -f2 | jq -r '"INSERT INTO transactions (id, from_account, to_account, amount, ts) VALUES (\(.id), \(.from_account), \(.to_account), \(.amount), '\''\(.ts)'\'');"' >> $DATA_DIR/transactions.sql
psql postgres://postgres@localhost:5433/postgres -f $DATA_DIR/transactions.sql

echo "All systems go. Hit ctrl-c when you're ready to shut everything down."
read -r -d '' _