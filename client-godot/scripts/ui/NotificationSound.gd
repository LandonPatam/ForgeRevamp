extends AudioStreamPlayer
## Optional cue when the stack starts waiting on this player. Built-in sounds are synthesized
## soft tones; a dropped MP3 is copied to user:// and used as the custom sound.
const CUSTOM_PATH := "user://notification.mp3"
const CHOICES := ["Off", "Chime", "Bell", "Pop", "Custom"]
const RATE := 22050

var choice := 0
var volume := 0.6
var _cache: Dictionary = {}

func _ready() -> void:
	bus = "Master"

func configure(index: int, level: float) -> void:
	choice = clampi(index, 0, CHOICES.size() - 1)
	volume = clampf(level, 0.0, 1.0)

static func has_custom() -> bool:
	return FileAccess.file_exists(CUSTOM_PATH)

## Copies a dropped MP3 into user:// so it survives restarts. Returns false if unreadable.
static func import_custom(path: String) -> bool:
	if not path.to_lower().ends_with(".mp3"): return false
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty(): return false
	var probe := AudioStreamMP3.new()
	probe.data = bytes
	if probe.get_length() <= 0.0: return false
	var file := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.close()
	return true

func play_cue(index: int = -1) -> void:
	var which := choice if index < 0 else index
	if which <= 0 or volume <= 0.0: return
	var cue := _stream(which)
	if cue == null: return
	stream = cue
	volume_db = linear_to_db(volume)
	play()

func _stream(which: int) -> AudioStream:
	if which == 4:
		if not has_custom(): return null
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(CUSTOM_PATH)
		return mp3
	if not _cache.has(which):
		match which:
			1: _cache[which] = _tones([[880.0, 0.0, 0.5], [1318.5, 0.12, 0.6]], 0.75)
			2: _cache[which] = _tones([[659.3, 0.0, 1.1], [1318.5, 0.0, 0.5], [1977.0, 0.0, 0.3]], 1.1)
			3: _cache[which] = _tones([[520.0, 0.0, 0.09]], 0.12)
	return _cache.get(which)

## Sums decaying sine notes: [frequency, start seconds, decay seconds].
func _tones(notes: Array, length: float) -> AudioStreamWAV:
	var count := int(length * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / RATE
		var sample := 0.0
		for note in notes:
			var local: float = t - note[1]
			if local < 0.0: continue
			var attack := minf(1.0, local / 0.008)
			sample += sin(TAU * note[0] * local) * attack * exp(-local / note[2] * 3.0)
		data.encode_s16(i * 2, int(clampf(sample * 0.32, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
