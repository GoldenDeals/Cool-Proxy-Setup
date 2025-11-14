#!/usr/bin/env bats

setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    cat > proxy1.txt << 'EOF'
name;login;password;address
proxy1;user1;pass1;http://1.2.3.4:8080
proxy2;user2;pass2;http://5.6.7.8:8080
EOF

    cat > proxy2.txt << 'EOF'
name;login;password;address
test1;user1;pass1;http://10.20.30.40:8080
test2;user2;pass2;http://50.60.70.80:8080
EOF

    cat > kz << 'EOF'
name;login;password;address
kz-1;auto;pass;http://1.1.1.1:8080
EOF

    cat > nl << 'EOF'
name;login;password;address
nl-1;auto;pass;http://2.2.2.2:8080
EOF

    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    TEST_SCRIPT="$SCRIPT_DIR/test.sh"
    chmod +x "$TEST_SCRIPT"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "usage shown when no arguments" {
    run "$TEST_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"Usage:"* ]]
}

@test "error when no files found" {
    run "$TEST_SCRIPT" nonexistent*
    [ "$status" -eq 1 ]
    [[ "${output}" == *"No valid files found"* ]]
}

@test "warning when pattern matches no files" {
    run "$TEST_SCRIPT" nonexistent* proxy1.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Warning: No files found matching pattern"* ]]
}

@test "single file argument works" {
    run "$TEST_SCRIPT" proxy1.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Testing proxies from: proxy1.txt"* ]]
}

@test "multiple file arguments work" {
    run "$TEST_SCRIPT" proxy1.txt proxy2.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Testing proxies from: proxy1.txt"* ]]
    [[ "${output}" == *"Testing proxies from: proxy2.txt"* ]]
}

@test "wildcard pattern matches files" {
    run "$TEST_SCRIPT" proxy*.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Testing proxies from: proxy1.txt"* ]]
    [[ "${output}" == *"Testing proxies from: proxy2.txt"* ]]
}

@test "wildcard pattern with single match works" {
    run "$TEST_SCRIPT" k*
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Testing proxies from: kz"* ]]
}

@test "mixed files and wildcards work" {
    run "$TEST_SCRIPT" proxy1.txt n*
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Testing proxies from: proxy1.txt"* ]]
    [[ "${output}" == *"Testing proxies from: nl"* ]]
}

@test "duplicate files are processed only once" {
    run "$TEST_SCRIPT" proxy1.txt proxy*.txt
    output_lines=$(echo "$output" | grep -c "Testing proxies from: proxy1.txt" || true)
    [ "$output_lines" -eq 1 ]
}

@test "file not found warning for non-existent file" {
    run "$TEST_SCRIPT" nonexistent.txt
    [ "$status" -eq 1 ]
    [[ "${output}" == *"No valid files found"* ]]
}

@test "export flag exports to stdout" {
    run "$TEST_SCRIPT" --export proxy1.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"[SmartProxy Servers]"* ]]
}

@test "export suppresses normal output" {
    run "$TEST_SCRIPT" --export proxy1.txt
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Testing proxies from:"* ]]
}

@test "export format is correct" {
    run "$TEST_SCRIPT" --export proxy1.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"[SmartProxy Servers]"* ]]
    [[ "${output}" == *"[HTTP]"* ]]
}

@test "export to file works" {
    run "$TEST_SCRIPT" --export output.txt proxy1.txt
    [ "$status" -eq 0 ]
    [ -f "output.txt" ]
    content=$(cat output.txt)
    [[ "$content" == *"[SmartProxy Servers]"* ]]
}

@test "export with multiple files works" {
    run "$TEST_SCRIPT" --export proxy1.txt proxy2.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"[SmartProxy Servers]"* ]]
}

@test "export with wildcard works" {
    run "$TEST_SCRIPT" --export proxy*.txt
    [ "$status" -eq 0 ]
    [[ "${output}" == *"[SmartProxy Servers]"* ]]
}

@test "export file argument is recognized" {
    run "$TEST_SCRIPT" --export result.txt proxy1.txt
    [ "$status" -eq 0 ]
    [ -f "result.txt" ]
    [ ! -f "proxy1.txt.export" ]
}

