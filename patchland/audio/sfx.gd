class_name Sfx
extends Synth
## The reference's sound set.

const PENTA := [0, 2, 4, 7, 9]


static func note_hz(n: int) -> float:
	n = clampi(n, 0, 22)
	return 330.0 * pow(2.0, (int(n / 5) * 12 + PENTA[n % 5]) / 12.0)


func drop() -> void:
	tone(600, 0.1, "sine", 0.04, 0, 0.55)


func land() -> void:
	tone(120, 0.2, "sine", 0.32, 0, 0.45)
	noise_hit(0.09, 0.16, 700)


func tick(n: int) -> void:
	tone(note_hz(n), 0.13, "triangle", 0.15)


func soft(n: int) -> void:
	tone(note_hz(n), 0.09, "triangle", 0.08)


func mult(n: int) -> void:
	tone(note_hz(n + 4) * 0.5, 0.16, "square", 0.045)
	tone(note_hz(n + 4), 0.12, "triangle", 0.08)


func perfect(st: int) -> void:
	var b := 7 + mini(st, 8)
	for i in 3:
		tone(note_hz(b + [0, 2, 4][i]), 0.5, "sine", 0.13, i * 0.04)
	tone(note_hz(b + 7), 0.6, "triangle", 0.06, 0.12)


func gold() -> void:
	var ds := [0, 3, 5, 8]
	for i in ds.size():
		tone(note_hz(10 + ds[i]), 0.25, "sine", 0.09, i * 0.05)


func total(f: float) -> void:
	var n := mini(12, int(round(f * 40)))
	tone(note_hz(5 + n), 0.22, "triangle", 0.13)
	tone(note_hz(5 + n) * 0.5, 0.3, "sine", 0.11)


func dud() -> void:
	tone(180, 0.15, "triangle", 0.07, 0, 0.7)


func quest() -> void:
	var ds := [0, 2, 4, 7]
	for i in ds.size():
		tone(note_hz(9 + ds[i]), 0.35, "sine", 0.12, i * 0.07)


func clear() -> void:
	var ds := [0, 2, 4, 5, 7, 9, 10]
	for i in ds.size():
		tone(note_hz(5 + ds[i]), 0.3, "triangle", 0.11, i * 0.07)


func fail() -> void:
	for i in 3:
		tone(330.0 / (1 + i * 0.25), 0.45, "sawtooth", 0.05, i * 0.18, 0.85)


func rotate() -> void:
	tone(1400, 0.035, "square", 0.022)


func redraw() -> void:
	noise_hit(0.18, 0.07, 2400)
	tone(300, 0.18, "sine", 0.04, 0, 2)


func select() -> void:
	tone(880, 0.03, "sine", 0.03)


func pick() -> void:
	tone(note_hz(10), 0.12, "triangle", 0.1)
	tone(note_hz(12), 0.2, "triangle", 0.1, 0.07)


func boss() -> void:
	tone(110, 0.6, "sawtooth", 0.05, 0, 0.8)
	tone(165, 0.6, "sawtooth", 0.04, 0.05, 0.8)


func zap() -> void:
	tone(1500, 0.16, "sawtooth", 0.035, 0, 0.35)
	noise_hit(0.1, 0.05, 3000)


func gong() -> void:
	tone(98, 1.4, "sine", 0.3)
	tone(147, 1.1, "triangle", 0.08, 0.02)
	tone(196, 0.9, "sine", 0.06, 0.04)


func big(f: float) -> void:
	var b := 5 + mini(8, int(round(f * 6)))
	var ds := [0, 2, 4, 7]
	for i in ds.size():
		tone(note_hz(b + ds[i]), 0.7, "triangle", 0.1, i * 0.06)
	tone(note_hz(b) / 4.0, 0.9, "sine", 0.25)
	noise_hit(0.3, 0.1, 900)
