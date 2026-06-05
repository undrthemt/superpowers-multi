#!/usr/bin/env bash
# Test: documentation-dispatch skill
# Verifies dispatcher behavior: provider config, fallback, session state
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: documentation-dispatch ==="
echo ""

# Test 1: Dispatcher file exists and has correct structure
echo "Test 1: Dispatcher file structure..."

output=$(run_claude "Read skills/subagent-driven-development/documentation-dispatch.md and list its step numbers (Step 1 through Step 7)." 30 "Read")

if assert_contains "$output" "Step 1\|Step1" "Has Step 1"; then : ; else exit 1; fi
if assert_contains "$output" "Step 7\|Step7" "Has Step 7"; then : ; else exit 1; fi
echo ""

# Test 2: Fallback behavior when documentation_provider is not configured
echo "Test 2: Unconfigured provider falls back silently to root AI..."

output=$(run_claude "According to documentation-dispatch.md, what happens when documentation_provider is not set in the config (undefined or empty)? Does it warn the user?" 30 "Read")

if assert_contains "$output" "silent\|silently\|no.*warn\|without.*warn\|root.*AI\|fallback" "Falls back silently"; then : ; else exit 1; fi
if assert_not_contains "$output" "prompt.*user\|ask.*user\|setup.*UX" "Does not prompt user"; then : ; else exit 1; fi
echo ""

# Test 3: User-declined sets session_documentation_decline
echo "Test 3: User-declined sets session_documentation_decline flag..."

output=$(run_claude "In documentation-dispatch.md, when config-loading returns source='user-declined', what session state variable is set and to what value?" 30 "Read")

if assert_contains "$output" "session_documentation_decline" "Sets session_documentation_decline"; then : ; else exit 1; fi
if assert_contains "$output" "true" "Sets to true"; then : ; else exit 1; fi
echo ""

# Test 4: session_documentation_decline suppresses re-prompting
echo "Test 4: session_documentation_decline prevents Setup UX on second dispatch..."

output=$(run_claude "In documentation-dispatch.md Step 1, when session_documentation_decline is true AND no config files exist on disk, what does the dispatcher do?" 30 "Read")

if assert_contains "$output" "Step 7\|fallback\|skip" "Skips to fallback"; then : ; else exit 1; fi
if assert_not_contains "$output" "config-loading\|Setup UX\|prompt" "Does not call config-loading"; then : ; else exit 1; fi
echo ""

# Test 5: Provider-not-found warns and falls back
echo "Test 5: Unknown provider name warns and falls back..."

output=$(run_claude "In documentation-dispatch.md Step 3, what happens when the provider JSON file does not exist?" 30 "Read")

if assert_contains "$output" "warn\|⚠\|warning\|not found" "Emits warning"; then : ; else exit 1; fi
if assert_contains "$output" "Step 7\|fallback\|root.*AI" "Falls back to root AI"; then : ; else exit 1; fi
echo ""

# Test 6: Empty output triggers Step 6 warning and fallback
echo "Test 6: Empty CLI output triggers Step 6 warning and fallback..."

output=$(run_claude "In documentation-dispatch.md, if the CLI exits 0 but stdout is empty, which step catches this and what happens?" 30 "Read")

if assert_contains "$output" "Step 6\|validation\|empty" "Step 6 catches empty output"; then : ; else exit 1; fi
if assert_contains "$output" "warn\|⚠\|warning" "Emits warning"; then : ; else exit 1; fi
echo ""

# Test 7: session-only provider is cached for next dispatch
echo "Test 7: session-only path caches provider in session_documentation_provider..."

output=$(run_claude "In documentation-dispatch.md Step 1, when config-loading returns source='session-only' and documentation_provider is a non-empty string, what session variable is set?" 30 "Read")

if assert_contains "$output" "session_documentation_provider" "Sets session_documentation_provider"; then : ; else exit 1; fi
echo ""

# Test 8: Plugin override uses plugin_override field
echo "Test 8: Plugin override priority chain uses plugin_override (not plugin_override_coding)..."

output=$(run_claude "In documentation-dispatch.md Step 4, what is the plugin override priority chain? Which field is checked first, and what is the fallback?" 30 "Read")

if assert_contains "$output" "plugin_override_documentation" "Checks plugin_override_documentation first"; then : ; else exit 1; fi
if assert_contains "$output" "plugin_override[^_].*fallback\|fallback.*plugin_override[^_]\|else.*plugin_override[^_c]" "Falls back to plugin_override"; then : ; else exit 1; fi
if assert_not_contains "$output" "plugin_override_coding" "Does not use plugin_override_coding"; then : ; else exit 1; fi
echo ""

# Test 9: Plugin override failure falls through to CLI (Step 5), not Step 7
echo "Test 9: Plugin override failure falls through to CLI dispatch..."

output=$(run_claude "In documentation-dispatch.md Step 4, when plugin override dispatch fails, does it go to Step 5 (CLI) or Step 7 (fallback)?" 30 "Read")

if assert_contains "$output" "Step 5\|CLI" "Falls through to Step 5 / CLI"; then : ; else exit 1; fi
if assert_not_contains "$output" "directly.*Step 7\|Step 7.*directly" "Not directly to Step 7"; then : ; else exit 1; fi
echo ""

echo "=== All documentation-dispatch tests passed ==="
