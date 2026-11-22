extends Node
## Autoload "Sfx": sound effects synthesised in code at start-up (no audio files).
## Mono, 22.05 kHz, 16-bit. Respects the master volume and the "sfx" setting.

const RATE := 22050
const MIN_GAP_MS := 45  # the same sound is not retriggered faster than this

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last_ms: Dictionary = {}


func _ready() -> void:
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build()


func enabled() -> bool:
	return bool(SaveManager.get_setting("sfx")) if SaveManager.data.has("settings") else true


func names() -> Array:
	return _streams.keys()


func stream(name: String) -> AudioStreamWAV:
	return _streams.get(name)


## Plays a sound; returns false when it was skipped (disabled / unknown / too soon).
func play(name: String) -> bool:
	if not _streams.has(name) or not enabled():
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(name, -1000)) < MIN_GAP_MS:
		return false
	_last_ms[name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.play()
	return true


func click() -> void:
	play("click")


# ------------------------------------------------------------------ synthesis

func _build() -> void:
	_streams["click"] = _make(0.05, func(t: float, d: float) -> float: return sin(TAU * 720.0 * t) * exp(-t * 70.0) * 0.5)
	_streams["step"] = _make(0.045, func(t: float, d: float) -> float: return sin(TAU * 320.0 * t) * exp(-t * 80.0) * 0.4)
	_streams["coin"] = _make(0.28, func(t: float, d: float) -> float:
		var f := 988.0 if t < 0.07 else 1319.0
		return sin(TAU * f * t) * exp(-t * 11.0) * 0.45)
	_streams["dice"] = _make(0.55, func(t: float, d: float) -> float:
		var burst := fmod(t * 14.0, 1.0)  # rattle: short noise bursts
		return (_noise(t) * exp(-burst * 9.0)) * (1.0 - t / d) * 0.55)
	_streams["hit"] = _make(0.14, func(t: float, d: float) -> float:
		return (_noise(t) * 0.6 + sin(TAU * 140.0 * t) * 0.7) * exp(-t * 30.0) * 0.7)
	_streams["death"] = _make(0.34, func(t: float, d: float) -> float:
		var f := lerpf(320.0, 70.0, t / d)
		return sin(TAU * f * t) * (1.0 - t / d) * 0.5)
	_streams["magic"] = _make(0.42, func(t: float, d: float) -> float:
		var f := lerpf(500.0, 1500.0, t / d)
		return (sin(TAU * f * t) * 0.35 + sin(TAU * f * 1.5 * t) * 0.15) * sin(PI * t / d) * 0.8)
	_streams["portal"] = _make(0.45, func(t: float, d: float) -> float:
		var f := 300.0 + 700.0 * sin(PI * t / d)
		return sin(TAU * f * t) * sin(PI * t / d) * 0.5)
	_streams["error"] = _make(0.16, func(t: float, d: float) -> float:
		return sign(sin(TAU * 150.0 * t)) * exp(-t * 14.0) * 0.28)
	_streams["victory"] = _make_notes([523.25, 659.25, 783.99, 1046.5], 0.13, 0.4)
	_streams["defeat"] = _make_notes([392.0, 329.63, 261.63, 196.0], 0.16, 0.4)


func _noise(t: float) -> float:
	# deterministic pseudo-noise: the same sound every time
	return fposmod(sin(t * 12989.0 + 78.233) * 43758.5453, 1.0) * 2.0 - 1.0


func _make(duration: float, fn: Callable) -> AudioStreamWAV:
	var n := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / RATE
		var v := clampf(float(fn.call(t, duration)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _make_notes(freqs: Array, note_len: float, vol: float) -> AudioStreamWAV:
	var total := note_len * freqs.size() + 0.15
	return _make(total, func(t: float, d: float) -> float:
		var idx := mini(int(t / note_len), freqs.size() - 1)
		var lt := t - idx * note_len
		return sin(TAU * float(freqs[idx]) * t) * exp(-lt * 6.0) * vol)


func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
