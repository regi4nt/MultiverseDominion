extends Node
## Sound effects: synthesis sanity, settings and playback without crashes.
## Run: godot --headless --path . res://tests/audio_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	var names := Sfx.names()
	check(names.size() >= 11, "%d sound effects synthesised: %s" % [names.size(), str(names)])
	var ok := true
	var total := 0.0
	for n in names:
		var s: AudioStreamWAV = Sfx.stream(n)
		var peak := 0
		var energy := 0.0
		for i in range(0, s.data.size() - 1, 2):
			var v := absi(s.data.decode_s16(i))
			peak = maxi(peak, v)
			energy += float(v)
		var dur := float(s.data.size() / 2) / Sfx.RATE
		total += dur
		var good := dur > 0.03 and dur < 1.2 and peak > 3000 and peak <= 32767 and energy > 0.0
		if not good:
			ok = false
			push_error("bad sound %s: %.2fs peak %d" % [n, dur, peak])
		print("   %-8s %.2f s  peak %5d" % [n, dur, peak])
	check(ok, "every sound has a sensible length, is audible and does not clip (total %.1f s)" % total)
	var a: AudioStreamWAV = Sfx.stream("dice")
	var b: AudioStreamWAV = Sfx.stream("dice")
	check(a.data == b.data, "sounds are deterministic")
	SaveManager.set_setting("sfx", true)
	check(Sfx.play("coin"), "play() works when enabled")
	check(not Sfx.play("coin"), "the same sound is not retriggered within %d ms" % Sfx.MIN_GAP_MS)
	check(not Sfx.play("does_not_exist"), "unknown sound is ignored")
	SaveManager.set_setting("sfx", false)
	check(not Sfx.play("hit"), "nothing plays when sound effects are switched off")
	SaveManager.set_setting("sfx", true)
	var btn := UiTheme.make_button("x")
	check(btn.pressed.is_connected(Sfx.click), "every UiTheme button clicks")
	btn.free()
	print("AUDIO TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
