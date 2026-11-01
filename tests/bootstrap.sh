#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="$REPOSITORY_ROOT/scripts/bootstrap.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-fedora-bootstrap-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

TEST_FAILURES=0

assert_equal() {
    local expected="$1" actual="$2" description="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $description" >&2
        echo "  ожидалось: [$expected]" >&2
        echo "  фактически: [$actual]" >&2
        TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
}

assert_symlink_resolves_to() {
    local expected_target="$1" link_path="$2" description="$3"
    if [[ ! -L "$link_path" ]]; then
        echo "FAIL: $description: $link_path не является симлинком" >&2
        TEST_FAILURES=$((TEST_FAILURES + 1))
        return
    fi
    assert_equal "$expected_target" "$(readlink -f "$link_path")" "$description"
}

assert_path_absent() {
    local path_value="$1" description="$2"
    if [[ -e "$path_value" || -L "$path_value" ]]; then
        echo "FAIL: $description: $path_value существует" >&2
        TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
}

assert_regular_file_content() {
    local expected_content="$1" path_value="$2" description="$3"
    if [[ ! -f "$path_value" || -L "$path_value" ]]; then
        echo "FAIL: $description: $path_value не регулярный файл" >&2
        TEST_FAILURES=$((TEST_FAILURES + 1))
        return
    fi
    assert_equal "$expected_content" "$(cat "$path_value")" "$description"
}

assert_status_not_zero() {
    local actual_status="$1" description="$2"
    if [[ "$actual_status" == "0" ]]; then
        echo "FAIL: $description: команда неожиданно завершилась успешно" >&2
        TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
}

make_sandbox() {
    local sandbox_name="$1" sandbox_path
    sandbox_path="$TEST_ROOT/$sandbox_name"
    mkdir -p "$sandbox_path/home" "$sandbox_path/xdg-config" "$sandbox_path/bin"
    printf '%s' "$sandbox_path"
}

write_firefox_stub() {
    local stub_path="$1"
    cat > "$stub_path" <<'FIREFOX_STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-CreateProfile" ]]; then
    firefox_profile_root="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
    firefox_profile_directory="$firefox_profile_root/stub-created.default"
    mkdir -p "$firefox_profile_directory"
    printf '{}' > "$firefox_profile_directory/times.json"
fi
FIREFOX_STUB
    chmod +x "$stub_path"
}

populate_sandbox_bin() {
    local bin_directory="$1" include_firefox_stub="$2" tool
    for tool in bash dirname readlink mkdir ln env; do
        ln -s "$(command -v "$tool")" "$bin_directory/$tool"
    done
    if [[ "$include_firefox_stub" == true ]]; then
        write_firefox_stub "$bin_directory/firefox"
    fi
}

create_firefox_profile() {
    local profile_directory="$1"
    mkdir -p "$profile_directory"
    printf '{}' > "$profile_directory/times.json"
}

invoke_bootstrap_function() {
    local home_directory="$1" xdg_config_directory="$2" path_value="$3" bootstrap_function="$4"
    shift 4
    HOME="$home_directory" XDG_CONFIG_HOME="$xdg_config_directory" PATH="$path_value" \
        "$BASH" -c '
            set -euo pipefail
            source "$1"
            shift
            "$@"
        ' dotfiles-fedora-bootstrap-test "$BOOTSTRAP_SCRIPT" "$bootstrap_function" "$@"
}

scenario_find_firefox_profiles_returns_only_directories_with_times_json() {
    local sandbox home_directory xdg_config_directory found_profiles
    sandbox="$(make_sandbox find-profiles)"
    home_directory="$sandbox/home"
    xdg_config_directory="$sandbox/xdg-config"
    populate_sandbox_bin "$sandbox/bin" false
    create_firefox_profile "$xdg_config_directory/mozilla/firefox/abc123.default-release"
    create_firefox_profile "$home_directory/.mozilla/firefox/legacy42.default"
    mkdir -p "$xdg_config_directory/mozilla/firefox/Crash Reports" \
        "$xdg_config_directory/mozilla/firefox/Pending Pings"
    found_profiles="$(invoke_bootstrap_function "$home_directory" "$xdg_config_directory" \
        "$sandbox/bin" find_firefox_profiles)"
    assert_equal "$(printf '%s\n%s' \
        "$xdg_config_directory/mozilla/firefox/abc123.default-release" \
        "$home_directory/.mozilla/firefox/legacy42.default")" \
        "$found_profiles" \
        "находятся профили обоих корней, служебные каталоги пропущены"
}

scenario_install_firefox_prefs_links_user_js_into_every_profile() {
    local sandbox home_directory xdg_config_directory user_js_target status
    sandbox="$(make_sandbox link-profiles)"
    home_directory="$sandbox/home"
    xdg_config_directory="$sandbox/xdg-config"
    populate_sandbox_bin "$sandbox/bin" true
    create_firefox_profile "$xdg_config_directory/mozilla/firefox/xdg.default-release"
    create_firefox_profile "$home_directory/.mozilla/firefox/legacy.default"
    user_js_target="$(readlink -f "$REPOSITORY_ROOT/firefox/user.js")"
    status=0
    invoke_bootstrap_function "$home_directory" "$xdg_config_directory" \
        "$sandbox/bin" install_firefox_prefs || status=$?
    assert_equal "0" "$status" "установка в существующие профили успешна"
    assert_symlink_resolves_to "$user_js_target" \
        "$xdg_config_directory/mozilla/firefox/xdg.default-release/user.js" \
        "симлинк user.js в XDG-профиле"
    assert_symlink_resolves_to "$user_js_target" \
        "$home_directory/.mozilla/firefox/legacy.default/user.js" \
        "симлинк user.js в легаси-профиле"
}

scenario_repeated_install_firefox_prefs_is_idempotent() {
    local sandbox home_directory xdg_config_directory profile_directory user_js_target
    local first_status second_status
    sandbox="$(make_sandbox idempotent-install)"
    home_directory="$sandbox/home"
    xdg_config_directory="$sandbox/xdg-config"
    populate_sandbox_bin "$sandbox/bin" true
    profile_directory="$xdg_config_directory/mozilla/firefox/solo.default-release"
    create_firefox_profile "$profile_directory"
    user_js_target="$(readlink -f "$REPOSITORY_ROOT/firefox/user.js")"
    first_status=0
    invoke_bootstrap_function "$home_directory" "$xdg_config_directory" \
        "$sandbox/bin" install_firefox_prefs || first_status=$?
    second_status=0
    invoke_bootstrap_function "$home_directory" "$xdg_config_directory" \
        "$sandbox/bin" install_firefox_prefs || second_status=$?
    assert_equal "0" "$first_status" "первая установка успешна"
    assert_equal "0" "$second_status" "повторная установка успешна"
    assert_symlink_resolves_to "$user_js_target" "$profile_directory/user.js" \
        "повторная установка сохраняет симлинк user.js"
}

scenario_install_firefox_prefs_skips_when_firefox_missing() {
    local sandbox home_directory xdg_config_directory status
    sandbox="$(make_sandbox firefox-missing)"
    home_directory="$sandbox/home"
    xdg_config_directory="$sandbox/xdg-config"
    populate_sandbox_bin "$sandbox/bin" false
    create_firefox_profile "$xdg_config_directory/mozilla/firefox/alone.default"
    status=0
    invoke_bootstrap_function "$home_directory" "$xdg_config_directory" \
        "$sandbox/bin" install_firefox_prefs || status=$?
    assert_equal "0" "$status" "без firefox установка пропускается успешно"
    assert_path_absent "$xdg_config_directory/mozilla/firefox/alone.default/user.js" \
        "без firefox user.js в профиле не появляется"
}

scenario_install_firefox_prefs_creates_default_profile_when_none_exists() {
    local sandbox home_directory xdg_config_directory created_profile_directory user_js_target status
    sandbox="$(make_sandbox create-profile)"
    home_directory="$sandbox/home"
    xdg_config_directory="$sandbox/xdg-config"
    populate_sandbox_bin "$sandbox/bin" true
    mkdir -p "$xdg_config_directory/mozilla/firefox" "$home_directory/.mozilla/firefox"
    user_js_target="$(readlink -f "$REPOSITORY_ROOT/firefox/user.js")"
    status=0
    invoke_bootstrap_function "$home_directory" "$xdg_config_directory" \
        "$sandbox/bin" install_firefox_prefs || status=$?
    assert_equal "0" "$status" "создание профиля и установка успешны"
    created_profile_directory="$xdg_config_directory/mozilla/firefox/stub-created.default"
    assert_regular_file_content '{}' "$created_profile_directory/times.json" \
        "firefox -CreateProfile создаёт профиль с times.json"
    assert_symlink_resolves_to "$user_js_target" "$created_profile_directory/user.js" \
        "после создания профиля user.js устанавливается симлинком"
}

scenario_install_firefox_prefs_fails_loudly_on_foreign_user_js() {
    local sandbox home_directory xdg_config_directory profile_directory foreign_content status
    sandbox="$(make_sandbox foreign-user-js)"
    home_directory="$sandbox/home"
    xdg_config_directory="$sandbox/xdg-config"
    populate_sandbox_bin "$sandbox/bin" true
    profile_directory="$xdg_config_directory/mozilla/firefox/occupied.default"
    create_firefox_profile "$profile_directory"
    foreign_content='user_pref("browser.sessionhistory.max_entries", 3);'
    printf '%s\n' "$foreign_content" > "$profile_directory/user.js"
    status=0
    invoke_bootstrap_function "$home_directory" "$xdg_config_directory" \
        "$sandbox/bin" install_firefox_prefs || status=$?
    assert_status_not_zero "$status" "чужой регулярный user.js даёт громкий отказ"
    assert_regular_file_content "$foreign_content" "$profile_directory/user.js" \
        "чужой user.js остаётся регулярным файлом без изменений"
}

run_all_scenarios() {
    scenario_find_firefox_profiles_returns_only_directories_with_times_json
    scenario_install_firefox_prefs_links_user_js_into_every_profile
    scenario_repeated_install_firefox_prefs_is_idempotent
    scenario_install_firefox_prefs_skips_when_firefox_missing
    scenario_install_firefox_prefs_creates_default_profile_when_none_exists
    scenario_install_firefox_prefs_fails_loudly_on_foreign_user_js
}

main() {
    run_all_scenarios
    if (( TEST_FAILURES > 0 )); then
        echo "bootstrap-tests: провалено проверок: $TEST_FAILURES" >&2
        exit 1
    fi
    echo "bootstrap-tests: все сценарии прошли"
}

main "$@"
