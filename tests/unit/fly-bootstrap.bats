#!/usr/bin/env bats
# fly-bootstrap.bats — unit tests for scripts/fly-bootstrap.sh
#
# Stubs the `fly` CLI so no live Fly.io account is needed.
# Run: bats tests/unit/  OR  task test:unit

setup() {
    TEST_DIR="$(mktemp -d)"
    export PATH="${TEST_DIR}/stubs:${PATH}"
    mkdir -p "${TEST_DIR}/stubs"

    # Default env — can be overridden per-test
    export FLY_APP="test-gjgit"
    export FLY_REGION="nrt"

    # Track which fly commands were called
    export FLY_CALLS_LOG="${TEST_DIR}/fly-calls.log"

    SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/fly-bootstrap.sh"

    # ── Default fly stub (all operations succeed, app does NOT exist) ─────────
    _write_fly_stub "0" "no-app" "no-volumes" "no-ip"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# Helper: write the fly stub with configurable behaviour
_write_fly_stub() {
    AUTH_EXIT="$1"    # 0=authenticated, 1=not authenticated
    APP_STATE="$2"    # "exists" or "no-app"
    VOL_STATE="$3"    # "has-forgejo_data" or "no-volumes" or "has-both"
    IP_STATE="$4"     # "has-v4" or "no-ip"

    cat > "${TEST_DIR}/stubs/fly" <<FLYEOF
#!/bin/sh
echo "\$*" >> "${FLY_CALLS_LOG}"
case "\$1 \$2" in
    "auth whoami")
        if [ "${AUTH_EXIT}" = "1" ]; then exit 1; fi
        echo "test@example.com"; exit 0 ;;
    "status --app")
        if [ "${APP_STATE}" = "exists" ]; then exit 0; else exit 1; fi ;;
    "apps create")
        echo "New app created: \$3"; exit 0 ;;
    "volumes list")
        case "${VOL_STATE}" in
            "has-forgejo_data")
                printf " vol_aaa | created | forgejo_data | 15GB\n" ;;
            "has-both")
                printf " vol_aaa | created | forgejo_data | 15GB\n vol_bbb | created | ghproxy_cache | 20GB\n" ;;
            *) printf "" ;;
        esac
        exit 0 ;;
    "volumes create")
        echo "Volume created: \$3"; exit 0 ;;
    "ips list")
        if [ "${IP_STATE}" = "has-v4" ]; then
            printf " v4 | 1.2.3.4 | public\n"
        fi
        exit 0 ;;
    "ips allocate-v4")
        echo "IPv4 allocated: 1.2.3.4"; exit 0 ;;
    *) exit 0 ;;
esac
FLYEOF
    chmod +x "${TEST_DIR}/stubs/fly"
}

# ── Auth ──────────────────────────────────────────────────────────────────────

@test "exits non-zero when not authenticated" {
    _write_fly_stub "1" "no-app" "no-volumes" "no-ip"
    run sh "${SCRIPT}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not logged in"* ]]
}

@test "proceeds when authenticated" {
    _write_fly_stub "0" "exists" "has-forgejo_data" "has-v4"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Authenticated as"* ]]
}

# ── App creation (idempotency) ─────────────────────────────────────────────────

@test "skips app creation when app already exists" {
    _write_fly_stub "0" "exists" "has-forgejo_data" "has-v4"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
    # fly apps create must NOT have been called
    run grep "apps create" "${FLY_CALLS_LOG}"
    [ "$status" -ne 0 ]
}

@test "creates app when it does not exist" {
    _write_fly_stub "0" "no-app" "no-volumes" "no-ip"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    run grep "apps create" "${FLY_CALLS_LOG}"
    [ "$status" -eq 0 ]
}

# ── Volume creation (idempotency) ─────────────────────────────────────────────

@test "skips forgejo_data volume when it already exists" {
    _write_fly_stub "0" "exists" "has-forgejo_data" "has-v4"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    # volumes create must NOT have been called for forgejo_data
    run grep "volumes create forgejo_data" "${FLY_CALLS_LOG}"
    [ "$status" -ne 0 ]
}

@test "creates forgejo_data volume when it does not exist" {
    _write_fly_stub "0" "exists" "no-volumes" "has-v4"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    run grep "volumes create forgejo_data" "${FLY_CALLS_LOG}"
    [ "$status" -eq 0 ]
}

# ── IPv4 allocation (idempotency) ─────────────────────────────────────────────

@test "skips IPv4 allocation when already allocated" {
    _write_fly_stub "0" "exists" "has-forgejo_data" "has-v4"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    run grep "ips allocate-v4" "${FLY_CALLS_LOG}"
    [ "$status" -ne 0 ]
}

@test "allocates IPv4 when not yet allocated" {
    _write_fly_stub "0" "exists" "has-forgejo_data" "no-ip"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    run grep "ips allocate-v4" "${FLY_CALLS_LOG}"
    [ "$status" -eq 0 ]
}

# ── --proxy flag ──────────────────────────────────────────────────────────────

@test "--proxy flag creates ghproxy_cache volume" {
    _write_fly_stub "0" "exists" "has-forgejo_data" "has-v4"
    run sh "${SCRIPT}" --proxy
    [ "$status" -eq 0 ]
    run grep "volumes create ghproxy_cache" "${FLY_CALLS_LOG}"
    [ "$status" -eq 0 ]
}

@test "--proxy flag skips ghproxy_cache when already exists" {
    _write_fly_stub "0" "exists" "has-both" "has-v4"
    run sh "${SCRIPT}" --proxy
    [ "$status" -eq 0 ]
    run grep "volumes create ghproxy_cache" "${FLY_CALLS_LOG}"
    [ "$status" -ne 0 ]
}

@test "without --proxy flag does not create ghproxy_cache" {
    _write_fly_stub "0" "no-app" "no-volumes" "no-ip"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    run grep "volumes create ghproxy_cache" "${FLY_CALLS_LOG}"
    [ "$status" -ne 0 ]
}

# ── Completion message ─────────────────────────────────────────────────────────

@test "prints bootstrap complete on success" {
    _write_fly_stub "0" "no-app" "no-volumes" "no-ip"
    run sh "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bootstrap complete"* ]]
}
