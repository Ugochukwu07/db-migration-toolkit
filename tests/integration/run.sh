#!/bin/bash
# Integration tests: run the toolkit against two real MySQL servers
# ("remote" and "local") and verify the data really arrives intact.
#
# Required env (CI sets these):
#   REMOTE_PORT (default 3306)   LOCAL_PORT (default 3307)
#   MYSQL_ROOT_PASSWORD          root password of BOTH servers
# Servers are reached on 127.0.0.1. The tests drop and create databases on
# them, so only point this at disposable servers.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$REPO_ROOT/tests/integration"
RPORT="${REMOTE_PORT:-3306}"
LPORT="${LOCAL_PORT:-3307}"
ROOT_PW="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD must be set}"
# A deliberately hostile password: quotes, $(...), backticks, backslash, '#', space
SYNC_PW="Pa\"ss\$(touch \"\$PWNED_MARKER\")\\w\`id\`'x #y;z"

WORK="$(mktemp -d)"
export PWNED_MARKER="$WORK/PWNED"
PASS=0; FAIL=0; FAILED_TESTS=()
trap 'rm -rf "$WORK"' EXIT

# --- helpers ---------------------------------------------------------------
rmysql() { MYSQL_PWD="$ROOT_PW" mysql -h127.0.0.1 -P"$RPORT" -uroot "$@"; }
lmysql() { MYSQL_PWD="$ROOT_PW" mysql -h127.0.0.1 -P"$LPORT" -uroot "$@"; }
rq() { rmysql -N -B -e "$1"; }
lq() { lmysql -N -B -e "$1"; }

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); FAILED_TESTS+=("$CURRENT: $1"); }
check(){ # check <description> <command...>
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
eq()   { # eq <description> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

# Fresh copy of the scripts + config for each test so nothing leaks between tests
new_project() { # new_project <extra config lines...>
    P="$WORK/proj-$RANDOM"
    mkdir -p "$P/config"
    cp -r "$REPO_ROOT/scripts" "$P/scripts"
    {
        echo 'REMOTE_HOST=127.0.0.1'
        echo "REMOTE_PORT=$RPORT"
        echo 'REMOTE_USER=root'
        printf 'REMOTE_PASS=%q\n' "$ROOT_PW"
        echo 'LOCAL_HOST=127.0.0.1'
        echo "LOCAL_PORT=$LPORT"
        echo 'LOCAL_USER=root'
        printf 'LOCAL_PASS=%q\n' "$ROOT_PW"
        echo 'LOCAL_DB_PREFIX=local_'
        echo 'MAX_RETRY_ATTEMPTS=1'
        echo 'RETRY_DELAY=1'
        echo 'MYSQL_CONNECT_TIMEOUT=10'
        echo 'TEST_CONNECTIONS=true'
        for l in "$@"; do echo "$l"; done
    } > "$P/config/config.env"
}
run_tool() { # run_tool <script>  (output in $P/out.log, status returned)
    bash "$P/scripts/$1" > "$P/out.log" 2>&1
}

table_checksum() { # table_checksum <q-fn> <db> <table>
    "$1" "CHECKSUM TABLE \`$2\`.\`$3\`" | awk '{print $2}'
}
assert_same_tables() { # assert_same_tables <src_db> <dst_db> [tables...]
    local src="$1" dst="$2"; shift 2
    local tables=("$@")
    if [ ${#tables[@]} -eq 0 ]; then
        mapfile -t tables < <(rq "SELECT table_name FROM information_schema.tables WHERE table_schema='$src' AND table_type='BASE TABLE' ORDER BY 1")
    fi
    [ ${#tables[@]} -gt 0 ] || bad "no tables found in $src"
    local t
    for t in "${tables[@]}"; do
        eq "$src.$t row count" "$(rq "SELECT COUNT(*) FROM \`$src\`.\`$t\`")" "$(lq "SELECT COUNT(*) FROM \`$dst\`.\`$t\`")"
        eq "$src.$t checksum"  "$(table_checksum rq "$src" "$t")"             "$(table_checksum lq "$dst" "$t")"
    done
}
reset_local() { # drop every local_*/rb_* db we may have created
    local d
    for d in local_app_db local_other_db "local_weird-db" local_rb_src rb_target; do
        lq "DROP DATABASE IF EXISTS \`$d\`" >/dev/null 2>&1
    done
}

# --- wait for servers + seed -------------------------------------------------
echo "Waiting for MySQL servers..."
for i in $(seq 1 60); do
    rmysql -e 'SELECT 1' >/dev/null 2>&1 && lmysql -e 'SELECT 1' >/dev/null 2>&1 && break
    sleep 2
done
rmysql -e 'SELECT 1' >/dev/null 2>&1 || { echo "remote server not reachable"; exit 2; }
lmysql -e 'SELECT 1' >/dev/null 2>&1 || { echo "local server not reachable"; exit 2; }
echo "remote: $(rq 'SELECT VERSION()')   local: $(lq 'SELECT VERSION()')"
echo "client: $(mysql --version)"
echo "dump:   $(mysqldump --version)"
rmysql < "$HERE/seed.sql" || { echo "seeding failed"; exit 2; }

# =============================================================================
CURRENT="simple sync"; echo; echo "== $CURRENT (sync_databases.sh) =="
reset_local
new_project 'SYNC_DATABASES="app_db"'
run_tool sync_databases.sh; rc=$?
eq "exit code 0" 0 "$rc"
assert_same_tables app_db local_app_db
eq "view exists"        1 "$(lq "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='local_app_db' AND table_name='v_order_totals'")"
eq "routine exists"     1 "$(lq "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='local_app_db' AND routine_name='fn_double'")"
eq "trigger exists"     1 "$(lq "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='local_app_db' AND trigger_name='trg_orders_audit'")"
eq "routine works"      "42" "$(lq "SELECT \`local_app_db\`.fn_double(21)")"
eq "view data matches"  "$(rq "SELECT SUM(total) FROM app_db.v_order_totals")" "$(lq "SELECT SUM(total) FROM local_app_db.v_order_totals")"
eq "utf8mb4 + quotes preserved" "$(rq "SELECT HEX(name), HEX(notes) FROM app_db.customers WHERE id=2")" "$(lq "SELECT HEX(name), HEX(notes) FROM local_app_db.customers WHERE id=2")"
check "no credential directory left behind" bash -c '! ls "${TMPDIR:-/tmp}"/dbmig-cred.* >/dev/null 2>&1'

# =============================================================================
CURRENT="re-sync replaces data"; echo; echo "== $CURRENT =="
lq "UPDATE local_app_db.customers SET name='tampered' WHERE id=1; INSERT INTO local_app_db.order_audit (order_id) VALUES (999999); CREATE TABLE local_app_db.stray (id INT)" >/dev/null
eq "tampering applied" "tampered" "$(lq 'SELECT name FROM local_app_db.customers WHERE id=1')"
run_tool sync_databases.sh; rc=$?
eq "exit code 0" 0 "$rc"
assert_same_tables app_db local_app_db customers order_audit
eq "stray local table removed" 0 "$(lq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='local_app_db' AND table_name='stray'")"
check "pre-sync snapshot removed after success" bash -c "! ls '$P'/data/backups/pre-sync_* >/dev/null 2>&1"

# =============================================================================
CURRENT="multi-thread sync"; echo; echo "== $CURRENT (multi_thread_sync.sh) =="
reset_local
new_project 'SYNC_DATABASES="app_db,other_db,weird-db"' 'MAX_THREADS=3'
run_tool multi_thread_sync.sh; rc=$?
eq "exit code 0" 0 "$rc"
assert_same_tables app_db local_app_db
assert_same_tables other_db local_other_db
assert_same_tables weird-db local_weird-db
eq "awkward table name" "ok" "$(lq 'SELECT v FROM `local_weird-db`.`odd table` WHERE id=1')"

# =============================================================================
CURRENT="table sync"; echo; echo "== $CURRENT (multi_thread_table_sync.sh) =="
reset_local
new_project 'TABLE_SYNC_CONFIG="app_db:rb_target:customers,orders,select|other_db:local_other_db:*"' 'MAX_THREADS=3'
run_tool multi_thread_table_sync.sh; rc=$?
eq "exit code 0" 0 "$rc"
assert_same_tables app_db rb_target customers orders select
assert_same_tables other_db local_other_db t1 t2
eq "only requested tables copied" 3 "$(lq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='rb_target'")"

# =============================================================================
CURRENT="hostile credentials"; echo; echo "== $CURRENT =="
# Create a remote user whose password tries to break out of shell/option-file quoting
esc="${SYNC_PW//\\/\\\\}"; esc="${esc//\'/\'\'}"
rmysql -e "DROP USER IF EXISTS 'sync_user'@'%'; CREATE USER 'sync_user'@'%' IDENTIFIED BY '$esc'; GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES, EVENT, PROCESS, RELOAD ON *.* TO 'sync_user'@'%'; FLUSH PRIVILEGES;" \
    || bad "could not create sync_user"
reset_local
new_project 'SYNC_DATABASES="other_db"' 'REMOTE_USER=sync_user'
printf 'REMOTE_PASS=%q\n' "$SYNC_PW" >> "$P/config/config.env"   # later assignment wins
run_tool sync_databases.sh; rc=$?
eq "exit code 0" 0 "$rc"
assert_same_tables other_db local_other_db
check "no command was injected via the password" test ! -e "$PWNED_MARKER"
check "password is not written to the log" bash -c "! grep -qF 'Pa\"ss' '$P/out.log'"
rmysql -e "DROP USER IF EXISTS 'sync_user'@'%'" >/dev/null 2>&1

# =============================================================================
CURRENT="database sync failure rolls back"; echo; echo "== $CURRENT =="
reset_local
lq "CREATE DATABASE local_rb_src; CREATE TABLE local_rb_src.sentinel (id INT PRIMARY KEY, v VARCHAR(20)); INSERT INTO local_rb_src.sentinel VALUES (1,'precious');" >/dev/null
OLD_PACKET="$(lq 'SELECT @@global.max_allowed_packet')"
lq "SET GLOBAL max_allowed_packet=1048576" >/dev/null     # 1 MiB: the 2 MiB row cannot be imported
new_project 'SYNC_DATABASES="rb_src"'
run_tool sync_databases.sh; rc=$?
lq "SET GLOBAL max_allowed_packet=$OLD_PACKET" >/dev/null
check "exit code is non-zero" test "$rc" -ne 0
check "log reports rollback" grep -q "Rolled back" "$P/out.log"
eq "original data restored" "precious" "$(lq 'SELECT v FROM local_rb_src.sentinel WHERE id=1')"
eq "failed import left no new tables" 1 "$(lq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='local_rb_src'")"

CURRENT="multi-thread failure rolls back"; echo; echo "== $CURRENT =="
lq "SET GLOBAL max_allowed_packet=1048576" >/dev/null
new_project 'SYNC_DATABASES="rb_src"'
run_tool multi_thread_sync.sh; rc=$?
lq "SET GLOBAL max_allowed_packet=$OLD_PACKET" >/dev/null
check "exit code is non-zero" test "$rc" -ne 0
eq "original data restored" "precious" "$(lq 'SELECT v FROM local_rb_src.sentinel WHERE id=1')"

# =============================================================================
CURRENT="table sync failure rolls back"; echo; echo "== $CURRENT =="
lq "DROP DATABASE IF EXISTS rb_target; CREATE DATABASE rb_target; CREATE TABLE rb_target.big (id INT PRIMARY KEY, data LONGBLOB); INSERT INTO rb_target.big VALUES (7, 'keep-me'); CREATE TABLE rb_target.small (id INT PRIMARY KEY, v VARCHAR(20)); INSERT INTO rb_target.small VALUES (7,'old');" >/dev/null
lq "SET GLOBAL max_allowed_packet=1048576" >/dev/null
new_project 'TABLE_SYNC_CONFIG="rb_src:rb_target:big,small"' 'MAX_THREADS=2'
run_tool multi_thread_table_sync.sh; rc=$?
lq "SET GLOBAL max_allowed_packet=$OLD_PACKET" >/dev/null
check "exit code is non-zero" test "$rc" -ne 0
eq "failed table keeps its old row" "keep-me" "$(lq 'SELECT CAST(data AS CHAR) FROM rb_target.big WHERE id=7')"
eq "other table still synced"       "new"     "$(lq 'SELECT v FROM rb_target.small WHERE id=1')"

# =============================================================================
echo; echo "================ SUMMARY ================"
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf ' - %s\n' "${FAILED_TESTS[@]}"
    echo; echo "--- last tool output ($P/out.log) ---"; tail -n 40 "$P/out.log" 2>/dev/null
    exit 1
fi
