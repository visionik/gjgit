#!/usr/bin/env bats
# bootstrap.bats — unit tests for scripts/bootstrap.sh
#
# Uses bats-core. Install: https://bats-core.readthedocs.io/en/stable/installation.html
# Run: bats tests/unit/  OR  task test:unit

setup() {
    # Create a temp dir for each test
    TEST_DIR="$(mktemp -d)"
    SHARED_DIR="${TEST_DIR}/shared"
    mkdir -p "${SHARED_DIR}"

    # Default required env vars
    export GITEA_URL="http://localhost:13000"
    export GITEA_ADMIN_USERNAME="testadmin"
    export GITEA_ADMIN_PASSWORD="testpass123"
    export GITEA_ADMIN_EMAIL="test@example.com"

    # Point bootstrap to test shared dir by overriding TOKEN_FILE via env
    # bootstrap.sh hardcodes /shared/forgejo-token — we stub forgejo binary instead
    export PATH="${TEST_DIR}/stubs:${PATH}"
    mkdir -p "${TEST_DIR}/stubs"

    # Create a stub `forgejo` binary
    cat > "${TEST_DIR}/stubs/forgejo" <<'EOF'
#!/bin/sh
# Stub forgejo CLI — records invocation args
echo "$@" >> "${TEST_DIR}/forgejo-calls.txt"
exit 0
EOF
    chmod +x "${TEST_DIR}/stubs/forgejo"

    # Create a URL-aware curl stub.
    # Control via env vars:
    #   CURL_STUB_HEALTH_OK=1   (default) — /api/v1/version returns 200; set 0 to simulate down
    #   CURL_STUB_USER_EXISTS=0 (default) — /api/v1/user returns 401; set 1 for 200
    #   CURL_STUB_TOKEN_BODY    (default: '{"sha1":"fake-token-value"}') — token create response
    cat > "${TEST_DIR}/stubs/curl" <<'CURLEOF'
#!/bin/sh
HAS_F=0; METHOD="GET"
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; OUTPUT_FILE="$1" ;;
        -w) shift; FORMAT="$1" ;;
        -sf|-f) HAS_F=1 ;;
        -s) ;;
        -X) shift; METHOD="$1" ;;
        -H) shift ;; -u) shift ;; -d) shift ;;
        *) URL="$1" ;;
    esac; shift
done
STATUS=200; BODY=""
case "${URL:-}" in
    */api/v1/version*)
        if [ "${CURL_STUB_HEALTH_OK:-1}" = "0" ]; then STATUS=503; else STATUS=200; fi
        BODY='{"version":"test"}' ;;
    */api/v1/users/*/tokens*)
        if [ "$METHOD" = "DELETE" ]; then STATUS=204
        else STATUS=200; BODY="${CURL_STUB_TOKEN_BODY:-{\"sha1\":\"fake-token-value\"}}"; fi ;;
    */api/v1/user*)
        if [ "${CURL_STUB_USER_EXISTS:-0}" = "1" ]; then STATUS=200; BODY='{"login":"ok"}'
        else STATUS=401; BODY='{"message":"unauthorized"}'; fi ;;
    *) STATUS="${CURL_STUB_STATUS:-200}"; BODY="${CURL_STUB_BODY:-}" ;;
esac
[ -n "$OUTPUT_FILE" ] && [ "$OUTPUT_FILE" != "/dev/null" ] && printf '%s' "$BODY" > "$OUTPUT_FILE"
if [ -n "$FORMAT" ] && [ "$FORMAT" = "%{http_code}" ]; then printf '%s' "$STATUS"
else printf '%s' "$BODY"; fi
[ "$HAS_F" = "1" ] && [ "$STATUS" -ge 400 ] 2>/dev/null && exit 22
exit 0
CURLEOF
    chmod +x "${TEST_DIR}/stubs/curl"

    # No-op sleep stub — eliminates wait time in unit tests
    printf '#!/bin/sh\nexit 0\n' > "${TEST_DIR}/stubs/sleep"
    chmod +x "${TEST_DIR}/stubs/sleep"

    SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/bootstrap.sh"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# ── Test: exits non-zero when required env vars are missing ──────────────────

@test "exits non-zero when GITEA_ADMIN_USERNAME is empty" {
    unset GITEA_ADMIN_USERNAME
    # The :? expansion should cause an error
    run sh -c "GITEA_ADMIN_USERNAME='' sh '${SCRIPT}'"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when GITEA_ADMIN_PASSWORD is empty" {
    unset GITEA_ADMIN_PASSWORD
    run sh -c "GITEA_ADMIN_PASSWORD='' sh '${SCRIPT}'"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when GITEA_ADMIN_EMAIL is empty" {
    unset GITEA_ADMIN_EMAIL
    run sh -c "GITEA_ADMIN_EMAIL='' sh '${SCRIPT}'"
    [ "$status" -ne 0 ]
}

# ── Test: wait loop gives up after MAX_ATTEMPTS ───────────────────────────────

@test "exits non-zero when Forgejo never becomes healthy" {
    export CURL_STUB_HEALTH_OK=0   # health check returns 503
    # Override MAX_ATTEMPTS to keep test fast (2 attempts)
    run sh -c "MAX_ATTEMPTS=2 sh '${SCRIPT}'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Forgejo did not become healthy"* ]]
}

# ── Test: skips admin creation when user already exists ──────────────────────

@test "skips admin user creation when API returns 200 for existing user" {
    export CURL_STUB_USER_EXISTS=1   # user check returns 200
    export CURL_STUB_TOKEN_BODY='{"sha1":"some-token"}'
    TOKEN_FILE="${SHARED_DIR}/forgejo-token"
    # Patch TOKEN_FILE by overriding via env (sed the path)
    PATCHED_SCRIPT="${TEST_DIR}/bootstrap-patched.sh"
    sed "s|/shared/forgejo-token|${TOKEN_FILE}|g" "${SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"

    run sh "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
    # forgejo admin user create must NOT have been called
    if [ -f "${TEST_DIR}/forgejo-calls.txt" ]; then
        run grep "admin user create" "${TEST_DIR}/forgejo-calls.txt"
        [ "$status" -ne 0 ]
    fi
}

# ── Test: token file is written correctly ─────────────────────────────────────

@test "token file is created with the token value" {
    export CURL_STUB_USER_EXISTS=0   # user does not exist — triggers admin creation
    export CURL_STUB_TOKEN_BODY='{"sha1":"my-secret-token"}'
    TOKEN_FILE="${SHARED_DIR}/forgejo-token"
    PATCHED_SCRIPT="${TEST_DIR}/bootstrap-patched.sh"
    sed "s|/shared/forgejo-token|${TOKEN_FILE}|g" "${SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"

    run sh "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TOKEN_FILE}" ]
    TOKEN_CONTENT="$(cat "${TOKEN_FILE}")"
    [ -n "$TOKEN_CONTENT" ]
}

# ── Test: idempotent — skips token generation if token file already exists ───

@test "skips token generation if token file already non-empty" {
    TOKEN_FILE="${SHARED_DIR}/forgejo-token"
    printf 'existing-token' > "${TOKEN_FILE}"
    export CURL_STUB_USER_EXISTS=1   # user exists, health passes
    PATCHED_SCRIPT="${TEST_DIR}/bootstrap-patched.sh"
    sed "s|/shared/forgejo-token|${TOKEN_FILE}|g" "${SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"

    run sh "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"idempotent run"* ]]
    # Token file content must be unchanged
    [ "$(cat "${TOKEN_FILE}")" = "existing-token" ]
}
