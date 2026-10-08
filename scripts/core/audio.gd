extends Node
## Small synthesized sound effects: no external audio license or download required.
var players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var scratch_clock: float = 0.0

func _ready() -> void:
	for i in 8:
		var player := AudioStreamPlayer.new()
		player.volume_db = -15.0
		add_child(player)
		players.append(player)
	for spec in [["click", 620.0, 0.06], ["reveal", 960.0, 0.12], ["win", 880.0, 0.3], ["big", 1320.0, 0.75], ["skill", 440.0, 0.4], ["scratch", 180.0, 0.06]]:
		sounds[spec[0]] = synth(float(spec[1]), float(spec[2]), spec[0] == "scratch")

func synth(frequency: float, duration: float, noise: bool) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var bytes := PackedByteArray()
	var count: int = int(duration * 22050)
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 123
	for i in count:
		var time: float = float(i) / 22050.0
		var envelope: float = pow(1.0 - float(i) / count, 2.0)
		var sample: float = random.randf_range(-0.4, 0.4) if noise else sin(TAU * frequency * time) * 0.35 + sin(TAU * frequency * 1.5 * time) * 0.12
		bytes.encode_s16(i * 2, int(sample * envelope * 30000))
	wave.data = bytes
	return wave

func play(sound: String) -> void:
	if Game.muted or not sounds.has(sound): return
	if sound == "scratch":
		if Time.get_ticks_msec() - scratch_clock < 60: return
		scratch_clock = Time.get_ticks_msec()
	for player in players:
		if not player.playing:
			player.stream = sounds[sound]
			player.play()
			return
