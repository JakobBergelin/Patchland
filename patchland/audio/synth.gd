class_name Synth
extends Node
## Tiny runtime synth on an AudioStreamGenerator: oscillators with exponential
## pitch slides and envelopes, plus low-passed noise hits (no audio files).

const RATE := 44100.0
const MAX_VOICES := 48

var muted := false
var master := 0.5
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _voices: Array = []
var _clock := 0  # samples pushed so far
var _silence := PackedVector2Array()


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.08
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback()


func tone(freq: float, dur: float, type := "sine", vol := 0.2, when := 0.0, slide := 0.0) -> void:
	if muted or _voices.size() >= MAX_VOICES:
		return
	var n_att := maxf(1.0, 0.008 * RATE)
	var n_dec := maxf(1.0, (dur - 0.008) * RATE)
	var ratio := (maxf(30.0, freq * slide) / freq) if slide > 0 else 1.0
	_voices.append({
		"kind": type, "start": _clock + int(when * RATE) + 256, "len": int((dur + 0.03) * RATE), "pos": 0,
		"freq": freq, "fmul": pow(ratio, 1.0 / (dur * RATE)), "fend": int(dur * RATE),
		"env": 0.0001, "vol": vol, "n_att": int(n_att), "ka": pow(vol / 0.0001, 1.0 / n_att), "kd": pow(0.0001 / vol, 1.0 / n_dec),
		"ph": 0.0,
	})


func noise_hit(dur: float, vol: float, freq: float, when := 0.0) -> void:
	if muted or _voices.size() >= MAX_VOICES:
		return
	_voices.append({
		"kind": "noise", "start": _clock + int(when * RATE) + 256, "len": int((dur + 0.02) * RATE), "pos": 0,
		"env": vol, "kd": pow(0.0001 / vol, 1.0 / maxf(1.0, dur * RATE)),
		"a": 1.0 - exp(-TAU * freq / RATE), "y1": 0.0, "y2": 0.0,
	})


func stop_all() -> void:
	_voices.clear()


func _process(_dt: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	if _voices.is_empty():
		if _silence.size() != n:
			_silence.resize(n)
			_silence.fill(Vector2.ZERO)
		_pb.push_buffer(_silence)
		_clock += n
		return
	var mix := PackedFloat32Array()
	mix.resize(n)
	mix.fill(0.0)
	for vi in range(_voices.size() - 1, -1, -1):
		var v: Dictionary = _voices[vi]
		var i0: int = maxi(0, v.start - _clock)
		if i0 >= n:
			continue
		var pos: int = v.pos
		var length: int = v.len
		var env: float = v.env
		var kd: float = v.kd
		var count: int = mini(n - i0, length - pos)
		if v.kind == "noise":
			var a: float = v.a
			var y1: float = v.y1
			var y2: float = v.y2
			for i in count:
				var x := randf() * 2.0 - 1.0
				y1 += a * (x - y1)
				y2 += a * (y1 - y2)
				mix[i0 + i] += y2 * env
				env = maxf(0.0001, env * kd)
			v.y1 = y1
			v.y2 = y2
		else:
			var kind: String = v.kind
			var freq: float = v.freq
			var fmul: float = v.fmul
			var fend: int = v.fend
			var ph: float = v.ph
			var n_att: int = v.n_att
			var ka: float = v.ka
			var vol: float = v.vol
			for i in count:
				var p := pos + i
				var smp: float
				if kind == "sine":
					smp = sin(TAU * ph)
				elif kind == "triangle":
					smp = 4.0 * absf(ph - 0.5) - 1.0
				elif kind == "square":
					smp = 1.0 if ph < 0.5 else -1.0
				else:
					smp = 2.0 * ph - 1.0
				mix[i0 + i] += smp * env
				ph = fmod(ph + freq / RATE, 1.0)
				if p < fend:
					freq *= fmul
				if p < n_att:
					env = minf(vol, env * ka)
				else:
					env = maxf(0.0001, env * kd)
			v.freq = freq
			v.ph = ph
		v.env = env
		v.pos = pos + count
		if v.pos >= length:
			_voices.remove_at(vi)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var s := clampf(mix[i] * master, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)
	_clock += n
