extends Node
## Music (stage 9): a quiet generative music box — not a single sound file.
## The pentatonic notes are synthesized once per process (static cache); every 1.4–3 s the sequencer picks the next one
## by a random walk over the scale, sometimes rests, and returns to the tonic about every 40 s. No loop — nothing to tire of.
## Bus Music; the settings set the volume, here — only a gentle fade-in and ducking on levels.

const RATE := 22050
const NOTE_LEN := 2.4
## C major pentatonic, two octaves: C4 D4 E4 G4 A4 C5 D5 E5 G5 A5.
const FREQS := [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25, 783.99, 880.0]
const TONICS := [0, 5]
const GAP_MIN := 1.4
const GAP_MAX := 3.0
const REST_CHANCE := 0.22
const HOME_EVERY := 40.0
const FADE_IN := 2.0
const BASE_DB := -12.0

static var notes: Array[AudioStreamWAV] = []

var players: Array[AudioStreamPlayer] = []
var idx := 0
var pos := 5             # current degree (index in FREQS)
var wait := 1.5          # until the next note
var since_home := 0.0
var gain := 0.0          # gentle fade-in 0 → 1
var duck := 1.0          # quieter on levels (×0.6) so it doesn't get in the way of thinking
var duck_target := 1.0


func _ready() -> void:
	if notes.is_empty():
		for f in FREQS:
			notes.append(_wav(_tine(f)))
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		players.append(p)


func set_duck(on: bool) -> void:
	duck_target = 0.6 if on else 1.0


func _process(dt: float) -> void:
	dt = minf(dt, 1.0 / 15.0)
	gain = minf(1.0, gain + dt / FADE_IN)
	duck = move_toward(duck, duck_target, dt * 0.5)
	since_home += dt
	wait -= dt
	if wait > 0.0:
		return
	wait = randf_range(GAP_MIN, GAP_MAX)
	if randf() < REST_CHANCE:
		return
	if since_home >= HOME_EVERY:
		since_home = 0.0
		pos = TONICS[0] if pos < 5 else TONICS[1]
	else:
		var step: int = [-2, -1, -1, 1, 1, 2].pick_random()
		pos = clampi(pos + step, 0, FREQS.size() - 1)
	_play(pos)


func _play(n: int) -> void:
	var p := players[idx]
	idx = (idx + 1) % players.size()
	p.stream = notes[n]
	p.volume_db = BASE_DB + linear_to_db(maxf(gain * duck, 0.001)) + randf_range(-2.0, 0.0)
	p.play()


## A music box "tine" note: the fundamental, a quiet octave and a quickly fading uneven overtone (ring).
func _tine(f: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(NOTE_LEN * RATE))
	for i in s.size():
		var t := float(i) / RATE
		var env := (1.0 - exp(-t * 300.0)) * exp(-t * 1.9)
		var v := sin(TAU * f * t) + 0.22 * sin(TAU * 2.0 * f * t) * exp(-t * 3.0) \
			+ 0.12 * sin(TAU * 5.4 * f * t) * exp(-t * 14.0)
		s[i] = v * env * 0.42
	return s


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
