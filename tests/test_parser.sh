#!/bin/sh
# Unit and integration test suite for kvas-hysteria parser, URL extraction and YAML generator
set -e

PASSED=0
FAILED=0

assert_eq() {
    expected="$1"
    actual="$2"
    test_name="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    haystack="$1"
    needle="$2"
    test_name="$3"
    if echo "$haystack" | grep -F -q -- "$needle"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Pattern not found: '$needle'"
        FAILED=$((FAILED + 1))
    fi
}

assert_not_contains() {
    haystack="$1"
    needle="$2"
    test_name="$3"
    if ! echo "$haystack" | grep -F -q -- "$needle"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Pattern unexpectedly found: '$needle'"
        FAILED=$((FAILED + 1))
    fi
}

assert_true() {
    cmd="$1"
    test_name="$2"
    if eval "$cmd"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        FAILED=$((FAILED + 1))
    fi
}

assert_false() {
    cmd="$1"
    test_name="$2"
    if ! eval "$cmd"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== Running kvas-hysteria test suite ==="

TMP_DIR=$(mktemp -d /tmp/kvas-hysteria-tests.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# --------------------------------------------------------------------------
# Test 1: Hysteria 2 URL Parser
# --------------------------------------------------------------------------
echo "Test Group 1: Hysteria 2 URL Parser"

parse_hysteria_url() {
    URL="$1"
    URL=$(echo "$URL" | tr -d '[:space:]')
    MAIN_PART=$(echo "$URL" | sed -E 's|h2://||;s|hysteria2://||;s|\?.*||;s|#.*||')
    if ! echo "$MAIN_PART" | grep -q '@'; then
        return 1
    fi
    AUTH=$(echo "$MAIN_PART" | cut -d'@' -f1)
    SERVER=$(echo "$MAIN_PART" | cut -d'@' -f2 | sed 's|/*$||')
    SNI=$(echo "$URL" | sed -n -E 's/.*([?&])sni=([^&#]*).*/\2/p')
    FP=$(echo "$URL" | sed -n -E 's/.*([?&])fp=([^&#]*).*/\2/p')
    OBFS_TYPE=$(echo "$URL" | sed -n -E 's/.*([?&])obfs=([^&#]*).*/\2/p')
    OBFS_PASS=$(echo "$URL" | sed -n -E 's/.*([?&])obfs-password=([^&#]*).*/\2/p')
    [ -z "$SNI" ] && SNI=$(echo "$SERVER" | cut -d':' -f1)
    [ -z "$FP" ] && FP="chrome"

    if [ -z "$AUTH" ] || [ -z "$SERVER" ]; then
        return 1
    fi
    echo "AUTH=$AUTH;SERVER=$SERVER;SNI=$SNI;FP=$FP;OBFS_TYPE=$OBFS_TYPE;OBFS_PASS=$OBFS_PASS"
    return 0
}

# Full URL with all parameters
FULL_URL="hysteria2://my_auth_token@vpn.example.com:8443/?sni=custom.sni.com&obfs=salamander&obfs-password=secretpass&fp=firefox#MyNode"
eval "$(parse_hysteria_url "$FULL_URL")"
assert_eq "my_auth_token" "$AUTH" "Extracts auth token"
assert_eq "vpn.example.com:8443" "$SERVER" "Extracts server host and port"
assert_eq "custom.sni.com" "$SNI" "Extracts explicit SNI"
assert_eq "firefox" "$FP" "Extracts fingerprint"
assert_eq "salamander" "$OBFS_TYPE" "Extracts obfs type"
assert_eq "secretpass" "$OBFS_PASS" "Extracts obfs password"

# Minimal URL with h2:// scheme and without query params but with fragment
MIN_URL="h2://secret@198.51.100.1:443#PrimaryServer"
eval "$(parse_hysteria_url "$MIN_URL")"
assert_eq "secret" "$AUTH" "Minimal URL extracts auth"
assert_eq "198.51.100.1:443" "$SERVER" "Minimal URL extracts server (fragment stripped)"
assert_eq "198.51.100.1" "$SNI" "SNI defaults to server host"
assert_eq "chrome" "$FP" "Fingerprint defaults to chrome"
assert_eq "" "$OBFS_TYPE" "Obfs type is empty"
assert_eq "" "$OBFS_PASS" "Obfs password is empty"

# Invalid URL (no auth / server)
assert_false "parse_hysteria_url 'not_a_valid_url'" "Rejects invalid URL format"

# --------------------------------------------------------------------------
# Test 2: YAML Config Generation and Placeholder Substitution
# --------------------------------------------------------------------------
echo "Test Group 2: YAML Generation and Template Substitution"

generate_yaml_config() {
    SERVER="$1"
    AUTH="$2"
    SNI="$3"
    FP="${4:-chrome}"
    OBFS_TYPE="$5"
    OBFS_PASS="$6"
    OUT_FILE="$7"
    TEMPLATE="$8"

    PROXY_LOCAL_IP="127.0.0.1"
    PROXY_LOCAL_PORT_SOCKS=10808
    PROXY_LOCAL_PORT_HTTP=10809

    cat << EOC > "$OUT_FILE"
server: $SERVER
auth: $AUTH
tls:
  sni: ${SNI}
  fingerprint: ${FP}
EOC

    if [ "$OBFS_TYPE" = "salamander" ] && [ -n "$OBFS_PASS" ]; then
        cat << EOC >> "$OUT_FILE"
obfs:
  type: salamander
  salamander:
    password: $OBFS_PASS
EOC
    fi

    echo "" >> "$OUT_FILE"

    sed -e "s|@PROXY_LOCAL_IP|${PROXY_LOCAL_IP}|g" \
        -e "s|@PROXY_LOCAL_PORT_SOCKS|${PROXY_LOCAL_PORT_SOCKS}|g" \
        -e "s|@PROXY_LOCAL_PORT_HTTP|${PROXY_LOCAL_PORT_HTTP}|g" \
        "$TEMPLATE" >> "$OUT_FILE"
}

TEST_TEMPLATE="$TMP_DIR/config.yaml"
cat << 'EOF' > "$TEST_TEMPLATE"
socks5:
  listen: @PROXY_LOCAL_IP:@PROXY_LOCAL_PORT_SOCKS
http:
  listen: @PROXY_LOCAL_IP:@PROXY_LOCAL_PORT_HTTP
quic:
  init_to: 10s
fast_open: true
EOF

YAML_OUT_1="$TMP_DIR/out_full.yaml"
generate_yaml_config "vpn.server.com:443" "pass123" "sni.server.com" "chrome" "salamander" "obfspass" "$YAML_OUT_1" "$TEST_TEMPLATE"
CONTENT_1=$(cat "$YAML_OUT_1")

assert_contains "$CONTENT_1" "server: vpn.server.com:443" "YAML has server"
assert_contains "$CONTENT_1" "auth: pass123" "YAML has auth"
assert_contains "$CONTENT_1" "sni: sni.server.com" "YAML has sni"
assert_contains "$CONTENT_1" "type: salamander" "YAML has salamander obfs"
assert_contains "$CONTENT_1" "password: obfspass" "YAML has obfs password"
assert_contains "$CONTENT_1" "listen: 127.0.0.1:10808" "SOCKS5 placeholder replaced"
assert_contains "$CONTENT_1" "listen: 127.0.0.1:10809" "HTTP placeholder replaced"

YAML_OUT_2="$TMP_DIR/out_no_obfs.yaml"
generate_yaml_config "1.2.3.4:8443" "auth999" "1.2.3.4" "chrome" "" "" "$YAML_OUT_2" "$TEST_TEMPLATE"
CONTENT_2=$(cat "$YAML_OUT_2")
assert_not_contains "$CONTENT_2" "obfs:" "YAML has no obfs block when unconfigured"

# --------------------------------------------------------------------------
# Test 3: IP validation helper from test_connection.sh
# --------------------------------------------------------------------------
echo "Test Group 3: IP validation helper"

is_valid_ip() {
    echo "$1" | grep -q -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
}

assert_true "is_valid_ip '1.1.1.1'" "IPv4 1.1.1.1 is valid"
assert_true "is_valid_ip '130.49.161.82'" "IPv4 130.49.161.82 is valid"
assert_true "is_valid_ip '127.0.0.1'" "IPv4 127.0.0.1 is valid"
assert_true "is_valid_ip '2001:db8::1'" "IPv6 2001:db8::1 is valid"
assert_false "is_valid_ip ''" "Empty IP is invalid"
assert_false "is_valid_ip 'abc'" "Hostname is invalid"
assert_false "is_valid_ip '502 Bad Gateway'" "HTTP error body is invalid"
assert_false "is_valid_ip '1.2.3.4.5'" "5 octet IP is invalid"

# --------------------------------------------------------------------------
# Test 4: MIPS Endianness detection via ELF header
# --------------------------------------------------------------------------
echo "Test Group 4: MIPS Endianness detection via ELF header"

detect_mips_endian() {
    file="$1"
    ENDIAN_BYTE=$(dd if="$file" bs=1 count=1 skip=5 2>/dev/null | od -b 2>/dev/null | awk 'NR==1 {print $2}')
    if [ "$ENDIAN_BYTE" = "002" ] || [ "$ENDIAN_BYTE" = "2" ]; then
        echo "mips"
    else
        echo "mipsle"
    fi
}

MIPSLE_BIN="$TMP_DIR/dummy_mipsle"
MIPS_BIN="$TMP_DIR/dummy_mips"

printf '\177ELF\001\001\000\000\000\000\000\000\000\000\000\000' > "$MIPSLE_BIN"
printf '\177ELF\001\002\000\000\000\000\000\000\000\000\000\000' > "$MIPS_BIN"

assert_eq "mipsle" "$(detect_mips_endian "$MIPSLE_BIN")" "Byte 5 = 1 detected as mipsle (little-endian)"
assert_eq "mips" "$(detect_mips_endian "$MIPS_BIN")" "Byte 5 = 2 detected as mips (big-endian)"

# --------------------------------------------------------------------------
# Test 5: Smart env.sh preservation in install.sh
# --------------------------------------------------------------------------
echo "Test Group 5: Smart env.sh sync in install.sh"

OLD_USER_ENV="$TMP_DIR/old_user_env.sh"
cat << 'EOF' > "$OLD_USER_ENV"
PROXY_LOCAL_IP="192.168.1.1"
PROXY_LOCAL_PORT_SOCKS=10999
CUSTOM_USER_SETTING="keep_me"
EOF

NEW_RELEASE_ENV="$TMP_DIR/new_release_env.sh"
cat << 'EOF' > "$NEW_RELEASE_ENV"
PROXY_LOCAL_IP="127.0.0.1"
PROXY_LOCAL_PORT_SOCKS=10808
PROXY_LOCAL_PORT_HTTP=10809
NEW_RELEASE_FEATURE="enabled"
EOF

sync_env() {
    user_env="$1"
    target_env="$2"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \#*|"") continue ;;
            [A-Za-z_][A-Za-z0-9_]*=*)
                key="${line%%=*}"
                key=$(echo "$key" | tr -d " \t")
                val="${line#*=}"
                if grep -q "^[[:space:]]*${key}=" "$target_env"; then
                    sed -i "s|^[[:space:]]*${key}=.*|${key}=${val}|" "$target_env"
                else
                    echo "${key}=${val}" >> "$target_env"
                fi
                ;;
        esac
    done < "$user_env"
}

sync_env "$OLD_USER_ENV" "$NEW_RELEASE_ENV"
RESULT_ENV=$(cat "$NEW_RELEASE_ENV")

assert_contains "$RESULT_ENV" 'PROXY_LOCAL_IP="192.168.1.1"' "User custom IP preserved"
assert_contains "$RESULT_ENV" 'PROXY_LOCAL_PORT_SOCKS=10999' "User custom port preserved"
assert_contains "$RESULT_ENV" 'PROXY_LOCAL_PORT_HTTP=10809' "New release default variable kept"
assert_contains "$RESULT_ENV" 'NEW_RELEASE_FEATURE="enabled"' "New release feature variable added"
assert_contains "$RESULT_ENV" 'CUSTOM_USER_SETTING="keep_me"' "Extra user setting carried over"

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "=== Test Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ "$FAILED" -eq 0 ]; then
    echo "ALL TESTS PASSED!"
    exit 0
else
    echo "SOME TESTS FAILED!"
    exit 1
fi
