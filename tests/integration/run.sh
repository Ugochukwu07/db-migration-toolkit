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
run_tool() { # run_tool <script> [args]  (always --yes; output in $P/out.log, status returned)
    local script="$1"; shift
    bash "$P/scripts/$script" --yes "$@" > "$P/out.log" 2>&1
}
run_raw() { # run_raw <script> [args]  -- exactly the given flags, no CI env, no stdin
    local script="$1"; shift
    env -u CI -u GITHUB_ACTIONS bash "$P/scripts/$script" "$@" > "$P/out.log" 2>&1 < /dev/null
}
log_has() { grep -q -- "$1" "$P/out.log"; }

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
# SAFETY GUARDS
# =============================================================================
CURRENT="guard: system schemas (source)"; echo; echo "== $CURRENT =="
reset_local
USERS_BEFORE="$(lq 'SELECT COUNT(*) FROM mysql.user')"
for name in mysql sys information_schema performance_schema MySQL; do
    new_project "SYNC_DATABASES=\"$name\""
    run_tool sync_databases.sh; rc=$?
    check "'$name' refused (non-zero exit)" test "$rc" -ne 0
    check "'$name' reports protected schema" log_has "protected system schema"
    check "'$name' was never dumped" bash -c "! ls '$P'/data/backups/*.sql >/dev/null 2>&1"
    eq "'$name': no local_$name database created" 0 "$(lq "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='local_${name,,}'")"
done
new_project 'SYNC_DATABASES="app_db,mysql"' 'MAX_THREADS=2'
run_tool multi_thread_sync.sh; rc=$?
check "multi-thread: one bad database refuses the whole run" test "$rc" -ne 0
eq "multi-thread: the good database was not synced either" 0 "$(lq "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='local_app_db'")"
eq "mysql.user untouched" "$USERS_BEFORE" "$(lq 'SELECT COUNT(*) FROM mysql.user')"

CURRENT="guard: system schemas (target)"; echo; echo "== $CURRENT =="
for target in mysql sys information_schema performance_schema; do
    new_project "TABLE_SYNC_CONFIG=\"app_db:$target:customers\""
    run_tool multi_thread_table_sync.sh; rc=$?
    check "table sync into '$target' refused" test "$rc" -ne 0
    check "'$target' reports protected schema" log_has "protected system schema"
    eq "no customers table written into '$target'" 0 "$(lq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$target' AND table_name='customers'")"
done
eq "mysql.user untouched" "$USERS_BEFORE" "$(lq 'SELECT COUNT(*) FROM mysql.user')"

CURRENT="guard: custom PROTECTED_DATABASES"; echo; echo "== $CURRENT =="
reset_local
new_project 'SYNC_DATABASES="other_db"' 'PROTECTED_DATABASES="foo, Local_Other_DB"'
run_tool sync_databases.sh; rc=$?
check "custom protected target refused" test "$rc" -ne 0
eq "local_other_db not created" 0 "$(lq "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='local_other_db'")"

# =============================================================================
CURRENT="guard: same server"; echo; echo "== $CURRENT =="
reset_local
OTHER_ROWS="$(rq 'SELECT COUNT(*) FROM other_db.t1')"
# local pointed at the *remote* server, empty prefix => would replace the source with itself
new_project 'SYNC_DATABASES="other_db"' "LOCAL_PORT=$RPORT" 'LOCAL_DB_PREFIX='
run_tool sync_databases.sh; rc=$?
check "same host+port, empty prefix refused" test "$rc" -ne 0
check "message explains same server" log_has "SAME server"
eq "source database intact" "$OTHER_ROWS" "$(rq 'SELECT COUNT(*) FROM other_db.t1')"
check "source was never dumped" bash -c "! ls '$P'/data/backups/*.sql >/dev/null 2>&1"

# same server reached through a different address (127.0.0.2 is loopback on Linux)
new_project 'SYNC_DATABASES="other_db"' "LOCAL_PORT=$RPORT" 'LOCAL_HOST=127.0.0.2' 'LOCAL_DB_PREFIX='
run_tool multi_thread_sync.sh; rc=$?
check "same server via another address refused" test "$rc" -ne 0
check "message explains same server" log_has "SAME server"
eq "source database intact" "$OTHER_ROWS" "$(rq 'SELECT COUNT(*) FROM other_db.t1')"

new_project 'TABLE_SYNC_CONFIG="other_db:other_db:t1"' "LOCAL_PORT=$RPORT"
run_tool multi_thread_table_sync.sh; rc=$?
check "table sync onto itself refused" test "$rc" -ne 0
eq "source table intact" "$OTHER_ROWS" "$(rq 'SELECT COUNT(*) FROM other_db.t1')"

# a prefixed target that is also a source of the same run
new_project 'SYNC_DATABASES="other_db,x_other_db"' "LOCAL_PORT=$RPORT" 'LOCAL_DB_PREFIX=x_'
run_tool sync_databases.sh; rc=$?
check "target that is also a source refused" test "$rc" -ne 0
check "message mentions SOURCE" log_has "also a SOURCE"

# control: same server is fine when the names differ (no false positive)
new_project 'SYNC_DATABASES="other_db"' "LOCAL_PORT=$RPORT" 'LOCAL_DB_PREFIX=copy_'
run_tool sync_databases.sh; rc=$?
eq "same server with a prefix is allowed" 0 "$rc"
eq "copy created on the same server" "$OTHER_ROWS" "$(rq 'SELECT COUNT(*) FROM copy_other_db.t1')"
rq 'DROP DATABASE IF EXISTS copy_other_db' >/dev/null 2>&1

# control: different servers with an identical name need no prefix
reset_local
new_project 'SYNC_DATABASES="other_db"' 'LOCAL_DB_PREFIX='
run_tool sync_databases.sh; rc=$?
eq "different servers, same name, empty prefix is allowed" 0 "$rc"
eq "synced" "$OTHER_ROWS" "$(lq 'SELECT COUNT(*) FROM other_db.t1')"
lq 'DROP DATABASE IF EXISTS other_db' >/dev/null 2>&1

# =============================================================================
CURRENT="guard: confirmation"; echo; echo "== $CURRENT =="
reset_local
new_project 'SYNC_DATABASES="other_db"'
run_tool sync_databases.sh >/dev/null; tamper() { lq "UPDATE local_other_db.t1 SET v='SENTINEL' WHERE id=1" >/dev/null; }
sentinel_is() { lq "SELECT v FROM local_other_db.t1 WHERE id=1"; }

tamper
run_raw sync_databases.sh --dry-run; rc=$?
eq "--dry-run exits 0" 0 "$rc"
check "--dry-run prints the plan" log_has "PLANNED CHANGES"
check "--dry-run flags the existing database" log_has "EXISTS"
check "--dry-run says nothing was changed" log_has "DRY RUN"
eq "--dry-run left local data alone" "SENTINEL" "$(sentinel_is)"
rm -rf -- "${P:?}/data"; run_raw sync_databases.sh --dry-run
check "--dry-run dumped nothing" bash -c "! ls '$P'/data/backups/*.sql >/dev/null 2>&1"

run_raw sync_databases.sh; rc=$?
check "no terminal and no --yes: refused" test "$rc" -ne 0
check "message tells you to use --yes" log_has "Re-run with --yes"
eq "refusal left local data alone" "SENTINEL" "$(sentinel_is)"

run_raw sync_databases.sh --bogus; rc=$?
check "unknown option rejected" test "$rc" -ne 0
eq "unknown option left local data alone" "SENTINEL" "$(sentinel_is)"

env CI=true bash "$P/scripts/sync_databases.sh" > "$P/out.log" 2>&1 < /dev/null; rc=$?
eq "CI=true skips the prompt" 0 "$rc"
eq "CI=true replaced the data" "a" "$(sentinel_is)"

tamper
run_raw sync_databases.sh --yes; rc=$?
eq "--yes skips the prompt" 0 "$rc"
eq "--yes replaced the data" "a" "$(sentinel_is)"

if command -v script >/dev/null 2>&1; then
    tamper
    { printf 'no\n'; sleep 5; } | timeout 120 script -qec "env -u CI -u GITHUB_ACTIONS bash '$P/scripts/sync_databases.sh'" /dev/null > "$P/out.log" 2>&1; rc=$?
    check "answering 'no' aborts" test "$rc" -ne 0
    check "prompt was shown" log_has "Type 'yes'"
    eq "answering 'no' left local data alone" "SENTINEL" "$(sentinel_is)"
    { printf 'yes\n'; sleep 5; } | timeout 120 script -qec "env -u CI -u GITHUB_ACTIONS bash '$P/scripts/sync_databases.sh'" /dev/null > "$P/out.log" 2>&1; rc=$?
    eq "answering 'yes' proceeds" 0 "$rc"
    eq "answering 'yes' replaced the data" "a" "$(sentinel_is)"
else
    echo "  (skipped interactive prompt tests: 'script' not installed)"
fi

# the other entry points honour --dry-run too
tamper
run_raw multi_thread_sync.sh --dry-run; rc=$?
eq "multi-thread --dry-run exits 0" 0 "$rc"
eq "multi-thread --dry-run left data alone" "SENTINEL" "$(sentinel_is)"
new_project 'TABLE_SYNC_CONFIG="other_db:local_other_db:t1"'
run_raw multi_thread_table_sync.sh --dry-run; rc=$?
eq "table sync --dry-run exits 0" 0 "$rc"
check "table sync plan lists the table" log_has "t1 -> local_other_db.t1"
eq "table sync --dry-run left data alone" "SENTINEL" "$(sentinel_is)"
run_raw multi_thread_table_sync.sh; rc=$?
check "table sync without --yes refused" test "$rc" -ne 0
eq "table sync refusal left data alone" "SENTINEL" "$(sentinel_is)"

# import_from_backups: plan, dry-run, protection
new_project 'IMPORT_BACKUP_DIR=backups' 'PROTECTED_DATABASES="imported_secret"'
mkdir -p "$P/backups"
printf 'CREATE TABLE t (id INT);\nINSERT INTO t VALUES (1);\n' > "$P/backups/imp1.sql"
run_raw import_from_backups.sh --dry-run; rc=$?
eq "import --dry-run exits 0" 0 "$rc"
check "import plan shows the target" log_has "imp1.sql -> imported_imp1"
eq "import --dry-run created nothing" 0 "$(lq "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='imported_imp1'")"
printf 'CREATE TABLE t (id INT);\n' > "$P/backups/secret.sql"
run_tool import_from_backups.sh; rc=$?
check "import into a protected name refused" test "$rc" -ne 0
eq "refused import created nothing (secret)" 0 "$(lq "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='imported_secret'")"
eq "refused import created nothing (imp1)" 0 "$(lq "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='imported_imp1'")"
lq 'DROP DATABASE IF EXISTS imported_imp1' >/dev/null 2>&1

# =============================================================================
echo; echo "================ SUMMARY ================"
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf ' - %s\n' "${FAILED_TESTS[@]}"
    echo; echo "--- last tool output ($P/out.log) ---"; tail -n 40 "$P/out.log" 2>/dev/null
    exit 1
fi
