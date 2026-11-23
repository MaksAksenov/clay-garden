extends Node
## All sounds are synthesized at startup — no files.
## Buses (stage 9): Master ← Music, Effects. Effects and world sounds (birds, crickets) go to Effects.

const RATE := 22050
const BUSES := ["Master", "Music", "Effects"]

var streams: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var idx := 0


## The Music and Effects buses: there is one AudioServer per process, while tests create Main many times — find by name, don't duplicate.
static func ensure_buses() -> void:
	for bus in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


## Bus volume 0…1; 0 — mute (linear_to_db(0) would give -inf). Master is also muted by the quick "quiet" (M).
static func set_volume(bus: String, v: float, quiet: bool = false) -> void:
	var i := AudioServer.get_bus_index(bus.capitalize())
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001 or quiet)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _ready() -> void:
	ensure_buses()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		players.append(p)
	streams["plop"] = _wav(_plop())
	streams["pop"] = _wav(_pop())
	streams["dig"] = _wav(_dig())
	streams["splash"] = _wav(_splash())
	streams["chirp"] = _wav(_chirp())
	streams["cricket"] = _wav(_cricket())
	streams["tick"] = _wav(_tick())
	streams["nope"] = _wav(_nope())


func play(sound: String, pitch: float = 1.0, db: float = -6.0) -> void:
	if not streams.has(sound):
		return
	var p := players[idx]
	idx = (idx + 1) % players.size()
	p.stream = streams[sound]
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.volume_db = db
	p.play()


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


## A soft clay "plop": a tone sliding down.
func _plop() -> PackedFloat32Array:
	var s := _buf(0.2)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (130.0 + 520.0 * exp(-t * 18.0)) / RATE
		var env := (1.0 - exp(-t * 500.0)) * exp(-t * 19.0)
		s[i] = (sin(ph) + 0.3 * sin(ph * 2.0)) * env * 0.75
	return s


func _pop() -> PackedFloat32Array:
	var s := _buf(0.16)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (240.0 + 800.0 * (1.0 - exp(-t * 30.0))) / RATE
		var env := (1.0 - exp(-t * 800.0)) * exp(-t * 26.0)
		s[i] = sin(ph) * env * 0.6
	return s


func _dig() -> PackedFloat32Array:
	var s := _buf(0.28)
	var y := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		y += (randf() * 2.0 - 1.0 - y) * 0.07
		ph += TAU * (70.0 + 60.0 * exp(-t * 20.0)) / RATE
		var env := (1.0 - exp(-t * 400.0)) * exp(-t * 13.0)
		s[i] = (y * 1.6 + sin(ph) * 0.7) * env * 0.7
	return s


func _splash() -> PackedFloat32Array:
	var s := _buf(0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b in 6:
		var start := rng.randf_range(0.0, 0.25)
		var f0 := rng.randf_range(350.0, 700.0)
		var ph := 0.0
		var i0 := int(start * RATE)
		for i in range(i0, mini(i0 + int(0.07 * RATE), s.size())):
			var t := float(i - i0) / RATE
			ph += TAU * (f0 + 2500.0 * t) / RATE
			s[i] += sin(ph) * exp(-t * 45.0) * 0.35
	return s


func _chirp() -> PackedFloat32Array:
	var s := _buf(0.32)
	for syl in 3:
		var i0 := int(syl * 0.1 * RATE)
		var ph := 0.0
		var seg_len := int(0.065 * RATE)
		for i in range(i0, mini(i0 + seg_len, s.size())):
			var u := float(i - i0) / seg_len
			ph += TAU * (3000.0 + 1500.0 * sin(u * PI) - syl * 200.0) / RATE
			s[i] = sin(ph) * sin(u * PI) * 0.35
	return s


func _cricket() -> PackedFloat32Array:
	var s := _buf(0.22)
	for pulse in 4:
		var i0 := int(pulse * 0.05 * RATE)
		var seg_len := int(0.028 * RATE)
		for i in range(i0, mini(i0 + seg_len, s.size())):
			var u := float(i - i0) / seg_len
			s[i] = sin(TAU * 4500.0 * float(i) / RATE) * sin(u * PI) * 0.3
	return s


func _tick() -> PackedFloat32Array:
	var s := _buf(0.06)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 1300.0 * t) * exp(-t * 90.0) * 0.4
	return s


func _nope() -> PackedFloat32Array:
	var s := _buf(0.14)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (210.0 - 60.0 * t / 0.14) / RATE
		s[i] = sin(ph) * exp(-t * 25.0) * 0.4
	return s
