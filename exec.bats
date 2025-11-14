#!/usr/bin/env bats

setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Create test proxy files
    cat > proxy1.txt << 'EOF'
name;login;password;address
proxy1;user1;pass1;http://1.2.3.4:8080
proxy2;user2;pass2;http://5.6.7.8:8080
proxy3;user3;pass3;http://9.10.11.12:8080
EOF

    cat > proxy2.txt << 'EOF'
name;login;password;address
test1;;;http://10.20.30.40:8080
test2;user2;;http://50.60.70.80:8080
test3;user3;pass3;https://90.100.110.120:8080
EOF

    cat > invalid_duplicate.txt << 'EOF'
name;login;password;address
proxy1;user1;pass1;http://1.2.3.4:8080
proxy1;user2;pass2;http://5.6.7.8:8080
EOF

    cat > invalid_address.txt << 'EOF'
name;login;password;address
proxy1;user1;pass1;invalid-address
proxy2;user2;pass2;http://5.6.7.8
EOF

    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    EXEC_SCRIPT="$SCRIPT_DIR/exec.sh"
    chmod +x "$EXEC_SCRIPT"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "help flag shows usage" {
    run "$EXEC_SCRIPT" --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Execute a command with proxy environment variables set from a proxy list file." ]
}

@test "help flag -h shows usage" {
    run "$EXEC_SCRIPT" -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Execute a command with proxy environment variables set from a proxy list file." ]
}

@test "usage shown when no arguments" {
    run "$EXEC_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"Usage:"* ]]
}

@test "usage shown when no command provided" {
    run "$EXEC_SCRIPT" proxy1.txt
    [ "$status" -eq 1 ]
    [[ "${output}" == *"command"* ]]
}

@test "error when file not found" {
    run "$EXEC_SCRIPT" nonexistent.txt echo "test"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"not found"* ]]
}

@test "default mode is cycle" {
    run "$EXEC_SCRIPT" proxy1.txt --silent env
    [ "$status" -eq 0 ]
    [[ "${output}" == *"HTTP_PROXY="* ]]
}

@test "cycle mode cycles through proxies" {
    rm -f .state
    run "$EXEC_SCRIPT" proxy1.txt --silent --cycle env
    [ "$status" -eq 0 ]
    proxy1=$(echo "$output" | grep HTTP_PROXY | head -1)
    
    run "$EXEC_SCRIPT" proxy1.txt --silent --cycle env
    [ "$status" -eq 0 ]
    proxy2=$(echo "$output" | grep HTTP_PROXY | head -1)
    
    [ "$proxy1" != "$proxy2" ]
}

@test "rand mode selects random proxy" {
    run "$EXEC_SCRIPT" proxy1.txt --silent --rand env
    [ "$status" -eq 0 ]
    [[ "$output" == *"HTTP_PROXY="* ]]
}

@test "name mode selects specific proxy" {
    run "$EXEC_SCRIPT" proxy1.txt --silent --name proxy2 env
    [ "$status" -eq 0 ]
    [[ "$output" == *"5.6.7.8:8080"* ]]
}

@test "name mode errors on non-existent proxy" {
    run "$EXEC_SCRIPT" proxy1.txt --silent --name nonexistent env
    [ "$status" -eq 1 ]
    [[ "${output}" == *"not found"* ]]
}

@test "silent flag suppresses output" {
    run "$EXEC_SCRIPT" proxy1.txt --silent echo "test"
    [ "$status" -eq 0 ]
    [ "${output}" = "test" ]
}

@test "proxy name printed without silent flag" {
    run "$EXEC_SCRIPT" proxy1.txt echo "test"
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Using proxy:"* ]]
}

@test "all proxy environment variables are set" {
    run "$EXEC_SCRIPT" proxy1.txt --silent env
    [ "$status" -eq 0 ]
    [[ "${output}" == *"HTTP_PROXY="* ]]
    [[ "${output}" == *"HTTPS_PROXY="* ]]
    [[ "${output}" == *"ALL_PROXY="* ]]
    [[ "${output}" == *"http_proxy="* ]]
    [[ "${output}" == *"https_proxy="* ]]
    [[ "${output}" == *"all_proxy="* ]]
}

@test "proxy URL includes credentials when provided" {
    run "$EXEC_SCRIPT" proxy1.txt --silent --name proxy1 env
    [ "$status" -eq 0 ]
    [[ "$output" == *"user1:pass1@"* ]]
}

@test "proxy URL without credentials" {
    run "$EXEC_SCRIPT" proxy2.txt --silent --name test1 env
    [ "$status" -eq 0 ]
    [[ "$output" == *"HTTP_PROXY=http://10.20.30.40:8080"* ]]
}

@test "proxy URL with only username" {
    run "$EXEC_SCRIPT" proxy2.txt --silent --name test2 env
    [ "$status" -eq 0 ]
    [[ "$output" == *"HTTP_PROXY=http://user2@50.60.70.80:8080"* ]]
}

@test "https protocol preserved" {
    run "$EXEC_SCRIPT" proxy2.txt --silent --name test3 env
    [ "$status" -eq 0 ]
    [[ "$output" == *"HTTPS_PROXY=https://user3:pass3@90.100.110.120:8080"* ]]
}

@test "state file created in current directory" {
    rm -f .state
    run "$EXEC_SCRIPT" proxy1.txt --silent echo "test"
    [ "$status" -eq 0 ]
    [ -f .state ]
    state_content=$(cat .state)
    [[ "$state_content" == *"proxy1.txt:"* ]]
}

@test "state file stores per-file state" {
    rm -f .state
    run "$EXEC_SCRIPT" proxy1.txt --silent echo "test"
    [ "$status" -eq 0 ]
    run "$EXEC_SCRIPT" proxy2.txt --silent echo "test"
    [ "$status" -eq 0 ]
    
    state_content=$(cat .state)
    [[ "$state_content" == *"proxy1.txt:"* ]]
    [[ "$state_content" == *"proxy2.txt:"* ]]
}

@test "custom state file location" {
    custom_state="$TEST_DIR/custom-state"
    run "$EXEC_SCRIPT" proxy1.txt --state "$custom_state" --silent echo "test"
    [ "$status" -eq 0 ]
    [ -f "$custom_state" ]
}

@test "state file in directory uses .proxy-state" {
    state_dir="$TEST_DIR/state-dir"
    mkdir -p "$state_dir"
    run "$EXEC_SCRIPT" proxy1.txt --state "$state_dir" --silent echo "test"
    [ "$status" -eq 0 ]
    [ -f "$state_dir/.proxy-state" ]
}

@test "--dir flag finds file in directory" {
    proxy_dir="$TEST_DIR/proxy-dir"
    mkdir -p "$proxy_dir"
    cp proxy1.txt "$proxy_dir/"
    
    run "$EXEC_SCRIPT" proxy1.txt --dir "$proxy_dir" --silent echo "test"
    [ "$status" -eq 0 ]
}

@test "--dir flag sets state file in directory" {
    proxy_dir="$TEST_DIR/proxy-dir"
    mkdir -p "$proxy_dir"
    cp proxy1.txt "$proxy_dir/"
    
    run "$EXEC_SCRIPT" proxy1.txt --dir "$proxy_dir" --silent echo "test"
    [ "$status" -eq 0 ]
    [ -f "$proxy_dir/.state" ]
}

@test "validation fails on duplicate names" {
    run "$EXEC_SCRIPT" invalid_duplicate.txt echo "test"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"Duplicate proxy name"* ]]
}

@test "validation fails on invalid address format" {
    run "$EXEC_SCRIPT" invalid_address.txt echo "test"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"Invalid proxy address format"* ]]
}

@test "--no-valid skips validation" {
    run "$EXEC_SCRIPT" invalid_duplicate.txt --no-valid --silent echo "test"
    [ "$status" -eq 0 ]
    [ "${output}" = "test" ]
}

@test "command receives proxy environment variables" {
    run "$EXEC_SCRIPT" proxy1.txt --silent --name proxy1 sh -c 'echo "$HTTP_PROXY"'
    [ "$status" -eq 0 ]
    [[ "${output}" == *"user1:pass1@1.2.3.4:8080"* ]]
}

@test "cycle mode wraps around" {
    rm -f .state
    # Run cycle 4 times (3 proxies + 1 wrap)
    for i in {1..4}; do
        run "$EXEC_SCRIPT" proxy1.txt --silent --cycle env
        [ "$status" -eq 0 ]
    done
}

@test "state persists between runs" {
    rm -f .state
    run "$EXEC_SCRIPT" proxy1.txt --silent --cycle env
    first_proxy=$(echo "$output" | grep HTTP_PROXY | head -1)
    
    run "$EXEC_SCRIPT" proxy1.txt --silent --cycle env
    second_proxy=$(echo "$output" | grep HTTP_PROXY | head -1)
    
    [ "$first_proxy" != "$second_proxy" ]
}

@test "error on invalid option" {
    run "$EXEC_SCRIPT" proxy1.txt --invalid-option echo "test"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"Invalid option"* ]]
}

@test "error when --name missing proxy name" {
    run "$EXEC_SCRIPT" proxy1.txt --name
    [ "$status" -eq 1 ]
    [[ "${output}" == *"requires a proxy name"* ]]
}

@test "error when --dir missing directory" {
    run "$EXEC_SCRIPT" proxy1.txt --dir
    [ "$status" -eq 1 ]
    [[ "${output}" == *"requires a directory path"* ]]
}

@test "error when --state missing path" {
    run "$EXEC_SCRIPT" proxy1.txt --state
    [ "$status" -eq 1 ]
    [[ "${output}" == *"requires a file or directory path"* ]]
}

@test "help works after filename" {
    run "$EXEC_SCRIPT" proxy1.txt --help
    [ "$status" -eq 0 ]
    [[ "${output}" == *"USAGE:"* ]]
}

@test "multiple flags work together" {
    proxy_dir="$TEST_DIR/proxy-dir"
    mkdir -p "$proxy_dir"
    cp proxy1.txt "$proxy_dir/"
    
    run "$EXEC_SCRIPT" proxy1.txt --dir "$proxy_dir" --state "$TEST_DIR/custom-state" --silent --name proxy2 echo "test"
    [ "$status" -eq 0 ]
    [ "${output}" = "test" ]
    [ -f "$TEST_DIR/custom-state" ]
}

