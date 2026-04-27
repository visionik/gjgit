#!/usr/bin/env bats
# fly-secrets.bats — unit tests for scripts/fly-secrets.sh
#
# Stubs the `fly` CLI and uses a temp .env file.
# Run: bats tests/unit/  OR  task test:unit

setup() {
    TEST_DIR="$(mktemp -d)"
    export PATH="${TEST_DIR}/stubs:${PATH}"
    mkdir -p "${TEST_DIR}/stubs"

    export FLY_APP="test-gjgit"
    export FLY_SECRETS_IMPORTED="${TEST_DIR}/imported.txt"

    SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/fly-secrets.sh"

    # fly stub: captures secrets import input to a file
    cat > "${TEST_DIR}/stubs/fly" <<'FLYEOF'
#!/bin/sh
if [ "$1 $2" = "auth whoami" ]; then
    echo "test@example.com"; exit 0
fi
if [ "$1 $2" = "secrets import" ]; then
    # Read stdin and record what was piped in
    cat > "${FLY_SECRETS_IMPORTED}"
    echo "Secrets have been staged"
    exit 0
fi
exit 0
FLYEOF
    chmod +x "${TEST_DIR}/stubs/fly"

    # Default: no .env (tests create their own)
    TEST_ENV="${TEST_DIR}/.env"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# ── Auth check ─────────────────────────────────────────────────────────────────

@test "exits non-zero when not authenticated" {
    cat > "${TEST_DIR}/stubs/fly" <<'STUB'
#!/bin/sh
if [ "$1 $2" = "auth whoami" ]; then exit 1; fi
exit 0
STUB
    chmod +x "${TEST_DIR}/stubs/fly"
    # Create .env so we get past the file-exists check
    printf 'FOO=bar\n' > "${TEST_ENV}"
    run sh "${SCRIPT}" --app test-gjgit
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not logged in"* ]]
}

# ── Missing .env ───────────────────────────────────────────────────────────────

@test "exits non-zero when .env is missing" {
    # Run from TEST_DIR where no .env exists
    run sh "${SCRIPT}" --app test-gjgit
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# ── Comment and blank line filtering ──────────────────────────────────────────

@test "strips comment lines before importing" {
    printf '# This is a comment\nFOO=bar\n# Another comment\nBAZ=qux\n' > "${TEST_ENV}"
    run sh -c "cd '${TEST_DIR}' && sh '${SCRIPT}' --app test-gjgit"
    [ "$status" -eq 0 ]
    # Imported content must not contain comment lines
    run grep "^#" "${FLY_SECRETS_IMPORTED}"
    [ "$status" -ne 0 ]
}

@test "strips blank lines before importing" {
    printf 'FOO=bar\n\n\nBAZ=qux\n' > "${TEST_ENV}"
    run sh -c "cd '${TEST_DIR}' && sh '${SCRIPT}' --app test-gjgit"
    [ "$status" -eq 0 ]
    # Imported content must not contain blank lines
    run grep "^$" "${FLY_SECRETS_IMPORTED}"
    [ "$status" -ne 0 ]
}

@test "real key=value pairs are passed to fly secrets import" {
    printf '# comment\nFOO=bar\n\nBAZ=qux\n' > "${TEST_ENV}"
    run sh -c "cd '${TEST_DIR}' && sh '${SCRIPT}' --app test-gjgit"
    [ "$status" -eq 0 ]
    run grep "FOO=bar" "${FLY_SECRETS_IMPORTED}"
    [ "$status" -eq 0 ]
    run grep "BAZ=qux" "${FLY_SECRETS_IMPORTED}"
    [ "$status" -eq 0 ]
}

# ── Success path ───────────────────────────────────────────────────────────────

@test "prints staged confirmation on success" {
    printf 'FOO=bar\n' > "${TEST_ENV}"
    run sh -c "cd '${TEST_DIR}' && sh '${SCRIPT}' --app test-gjgit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Secrets staged"* ]]
}
