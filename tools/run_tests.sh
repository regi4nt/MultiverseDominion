#!/usr/bin/env bash
# Runs the automated tests headless. Usage: tools/run_tests.sh [logic|ui|all]   (GODOT=path/to/godot to override)
# Exit code is non-zero if any test fails. Tests that need a real renderer (layout_test, ui_tutorial_smoke)
# are not included: see BUILD_ANDROID.md section 4.
GODOT="${GODOT:-godot}"
SET="${1:-all}"
LOGIC="sim_test card_test battle_test duel_test content_test save_test tutorial_test audio_test rules_test"
UI="ui_cards_smoke ui_battle_smoke ui_duel_smoke ui_content_smoke ui_resume_smoke"
case "$SET" in logic) LIST="$LOGIC";; ui) LIST="$UI";; *) LIST="$LOGIC $UI";; esac
"$GODOT" --headless --path . --import >/dev/null 2>&1
fail=0
for t in $LIST; do
  out=$(timeout 280 "$GODOT" --headless --path . "res://tests/$t.tscn" 2>&1); code=$?
  if [ $code -eq 0 ] && ! echo "$out" | grep -qE "SCRIPT ERROR|FAIL"; then echo "PASS  $t"; else echo "FAIL  $t (exit $code)"; echo "$out" | grep -E "FAIL|ERROR" | head -5; fail=1; fi
done
exit $fail
