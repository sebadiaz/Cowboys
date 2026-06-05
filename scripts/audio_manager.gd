extends Node
## AudioManager (autoload)
## Sons SYNTHÉTISÉS à la volée (aucun fichier audio requis) : chaque effet est
## un petit AudioStreamWAV calculé une fois au démarrage, puis joué via un pool
## de lecteurs (round-robin) pour ne pas se couper. Web-compatible (GL/WebGL).
##
## Utilisation : AudioManager.play("shot"), .play("reload"), etc.

const MIX_RATE := 22050
const VOICES := 8           # lecteurs simultanés

var _streams: Dictionary = {}      # nom -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
var muted := false


func _ready() -> void:
	_rng.randomize()
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build_all()


## Joue un son par nom, avec une légère variation de hauteur pour la vie.
func play(name: String, volume_db: float = 0.0, pitch_var := 0.06) -> void:
	if muted or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


# --- Construction des sons ---

func _build_all() -> void:
	_streams["shot"] = _make(0.18, func(t): return _shot(t))
	_streams["reload"] = _make(0.22, func(t): return _reload(t))
	_streams["pickup"] = _make(0.28, func(t): return _pickup(t))
	_streams["safe"] = _make(0.45, func(t): return _safe(t))
	_streams["alarm"] = _make(0.40, func(t): return _alarm(t))
	_streams["hit_player"] = _make(0.30, func(t): return _hit_player(t))
	_streams["hit_guard"] = _make(0.14, func(t): return _hit_guard(t))
	_streams["win"] = _make(0.70, func(t): return _win(t))
	_streams["lose"] = _make(0.80, func(t): return _lose(t))
	_streams["click"] = _make(0.06, func(t): return _click(t))
	# Notes de piano (gamme de do majeur) pour la mélodie du saloon.
	var scale := [261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88, 523.25]
	for i in scale.size():
		_streams["piano%d" % i] = _make(0.55, _piano.bind(float(scale[i])))


## Crée un AudioStreamWAV mono 16 bits à partir d'une fonction échantillon f(t).
func _make(duration: float, gen: Callable) -> AudioStreamWAV:
	var n := int(duration * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v: float = clampf(gen.call(t), -1.0, 1.0)
		var s := int(v * 32767.0)
		bytes.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


# --- Enveloppes / oscillateurs ---

func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return maxf(0.0, 1.0 - (t - attack) / maxf(decay, 0.0001))

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

func _tone(t: float, freq: float) -> float:
	return sin(TAU * freq * t)


# --- Voix (chaque son) ---

func _shot(t: float) -> float:
	# Claquement : bruit large + coup grave, déclin rapide.
	var e := _env(t, 0.002, 0.16)
	var body := _noise() * 0.7 + _tone(t, 130.0) * 0.5
	return body * e * e

func _piano(t: float, freq: float) -> float:
	# Note "honky-tonk" : fondamentale + harmoniques, attaque vive, déclin doux,
	# avec une corde légèrement désaccordée (saloon).
	var e := _env(t, 0.004, 0.5)
	var s := _tone(t, freq) * 0.6 + _tone(t, freq * 2.0) * 0.22 + _tone(t, freq * 3.0) * 0.1
	s += _tone(t, freq * 1.01) * 0.18   # désaccord léger
	return s * e * e

func _hit_guard(t: float) -> float:
	var e := _env(t, 0.001, 0.13)
	return (_noise() * 0.6 + _tone(t, 320.0) * 0.4) * e

func _hit_player(t: float) -> float:
	# Coup sourd + descente grave (douleur).
	var e := _env(t, 0.003, 0.28)
	var f := 220.0 - 140.0 * (t / 0.30)
	return (_tone(t, f) * 0.7 + _noise() * 0.3) * e

func _reload(t: float) -> float:
	# Deux "clics" mécaniques (barillet).
	var c1 := _noise() * _env(t, 0.001, 0.04)
	var c2 := _noise() * _env(maxf(0.0, t - 0.12), 0.001, 0.04)
	return (c1 + c2) * 0.8

func _click(t: float) -> float:
	return _noise() * _env(t, 0.001, 0.05) * 0.7

func _pickup(t: float) -> float:
	# Petit "ding" montant (deux notes).
	var f := 660.0 if t < 0.12 else 990.0
	return _tone(t, f) * _env(t, 0.005, 0.26) * 0.7

func _safe(t: float) -> float:
	# "Thunk" grave + verrou métallique à la fin.
	var thunk := _tone(t, 90.0) * _env(t, 0.005, 0.30) * 0.8
	var latch := _noise() * _env(maxf(0.0, t - 0.30), 0.001, 0.08) * 0.6
	return thunk + latch

func _alarm(t: float) -> float:
	# Sirène : porteuse modulée en fréquence.
	var f := 600.0 + 260.0 * sin(TAU * 6.0 * t)
	return _tone(t, f) * _env(t, 0.02, 0.40) * 0.6

func _win(t: float) -> float:
	# Arpège ascendant majeur (do-mi-sol-do).
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var idx := int(t / 0.17)
	idx = clampi(idx, 0, notes.size() - 1)
	var lt := t - idx * 0.17
	return _tone(t, notes[idx]) * _env(lt, 0.01, 0.16) * 0.6

func _lose(t: float) -> float:
	# Descente grave (échec).
	var f := 330.0 - 180.0 * (t / 0.80)
	return (_tone(t, f) * 0.7 + _tone(t, f * 0.5) * 0.3) * _env(t, 0.02, 0.78) * 0.6
