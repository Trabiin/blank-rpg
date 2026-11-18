class_name Techs
extends RefCounted
## Charged techs (issue #8). With a full power gauge, hold Attack: after TAP seconds the hero starts to
## glow, after `hold` seconds (data/techs.json) the tech is ready (flash + chime), and releasing fires it.
## Letting go before it is ready is an ordinary full-power swing, fired on release.
## A Hero keeps the state (charging, charge_t, charge_ready); this file holds the rules, the blast, the
## glow and two tiny synthesized sounds (there is no audio pipeline yet; issue #20).

const PATH := "res://data/techs.json"
const TAP := 0.16  # held shorter than this: no glow at all, just a swing on release
const CHARGE_SPEED := 0.55  # movement multiplier while charging
const HIT_INK := 2.0  # Ink for a tech that lands (a full-power swing gives Abilities.HIT_GAIN)

static var _data := {}
static var _sounds := {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


static func hold_time() -> float:
	return float(_load().get("hold", 1.0))


## The tech a hero knows, or {} if none.
static func for_hero(id: String) -> Dictionary:
	var d: Dictionary = _load().get("techs", {}).get(id, {})
	if d.is_empty():
		return {}
	var out := d.duplicate(true)
	out["id"] = id
	return out


static func color_of(h: Hero) -> Color:
	return Color(str(for_hero(h.hero_id).get("color", "ffe08a")))


## 0..1 progress of the glow (0 until TAP has passed, so a tap never flashes).
static func charge_ratio(h: Hero) -> float:
	if not h.charging:
		return 0.0
	return clampf((h.charge_t - TAP) / maxf(hold_time() - TAP, 0.01), 0.0, 1.0)


## Called every frame for the controlled hero while it can fight (not in town, quick menu closed).
## Replaces the old "attack pressed -> swing" so a full gauge waits for the release.
static func control(h: Hero, delta: float) -> void:
	if h.charging:
		if Input.is_action_pressed("attack"):
			h.charge_t += delta
			if not h.charge_ready and h.charge_t >= hold_time():
				h.charge_ready = true
				var col := color_of(h)
				Fx.burst(h.get_parent(), h.global_position + Vector2(0, -10), [col, Color.WHITE], 18, 60.0)
				play(h, "ready")
			return
		# Released.
		var ready := h.charge_ready
		cancel(h)
		if ready:
			fire(h)
		else:
			h.try_attack()
		return
	if Input.is_action_just_pressed("attack"):
		if h.power >= 1.0 and h.swing_t <= 0.0 and not for_hero(h.hero_id).is_empty():
			h.charging = true
			h.charge_t = 0.0
			h.charge_ready = false
		else:
			h.try_attack()


## Every frame (from Hero._update_abilities): drops a charge the hero can no longer hold.
static func tick(h: Hero) -> void:
	if not h.charging:
		return
	var menu_open: bool = h.party != null and h.party.get("quick_open") == true
	if h.dead or not h.controlled or h.peaceful or menu_open or h.dash_t > 0.0 or h.cast_t > 0.0:
		cancel(h)


static func cancel(h: Hero) -> void:
	h.charging = false
	h.charge_t = 0.0
	h.charge_ready = false


## The blast. Damage is the hero's full-power swing times the tech's mult.
static func fire(h: Hero) -> void:
	var t := for_hero(h.hero_id)
	if t.is_empty() or h.dead:
		return
	var parent := h.get_parent()
	var col := Color(str(t.get("color", "ffe08a")))
	var dir := h.facing.normalized()
	var step := float(t.get("step", 0))
	if step > 0.0:
		h.move_and_collide(dir * step)
	var reach := float(t.get("reach", 30))
	var half := deg_to_rad(float(t.get("arc", 90)))
	var center := h.global_position + dir * float(t.get("offset", 0))
	var dmg := maxi(1, roundi(h.base_damage * float(t.get("mult", 2.0))))
	var knock := float(t.get("knock", 260))

	# Spend the gauge and play the swing pose; the normal swing hit is skipped.
	h.power = 0.0
	h.swing_t = Hero.SWING_TIME
	h.swing_power = 1.0
	h.swing_hit_done = true
	h.tech_flash_t = 0.35

	if half >= PI - 0.01:
		Fx.ring(parent, center, reach + 6.0, col)
		Fx.burst(parent, center + Vector2(0, -6), [col, col.lightened(0.5), Color.WHITE], 26, 110.0)
	else:
		Fx.sweep(parent, center + Vector2(0, -6), dir.angle(), half, reach, col)
		Fx.burst(parent, center + dir * reach * 0.6 + Vector2(0, -6), [col, Color.WHITE], 14, 80.0)
	Fx.damage_number(parent, h.global_position + Vector2(0, -36), str(t.get("name", "")), col.lightened(0.3))
	play(h, "fire")

	var hit_any := false
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var to := enemy.global_position - center
		if to.length() > reach + enemy.radius:
			continue
		if half < PI - 0.01 and to.length() > 4.0 and absf(dir.angle_to(to)) > half:
			continue
		if enemy.take_hit(dmg, center - dir * 4.0, knock):
			hit_any = true
	if int(t.get("heal", 0)) > 0:
		for o in h.get_tree().get_nodes_in_group("heroes"):
			var other := o as Hero
			if other == null or other.dead or other.party != h.party:
				continue
			if other.global_position.distance_to(center) > reach + 8.0:
				continue
			var amount := mini(int(t["heal"]), other.max_hp - other.hp)
			if amount > 0:
				other.hp += amount
				Fx.damage_number(parent, other.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
	if hit_any:
		h.ink = minf(h.ink + HIT_INK, h.max_ink)
	if h.party:
		h.party.shake(5.0 if hit_any else 2.5)


## The glow around a charging hero, drawn on its overlay (above the sprite).
static func draw(h: Hero, o: Node2D) -> void:
	if h.tech_flash_t > 0.0:
		var f := h.tech_flash_t / 0.35
		o.draw_circle(Vector2(0, -7), 14.0 * (1.2 - f * 0.4), Color(color_of(h), 0.35 * f))
	if not h.charging or h.charge_t < TAP:
		return
	var col := color_of(h)
	var r := charge_ratio(h)
	if h.charge_ready:
		var pulse := 0.5 + 0.5 * sin(h.anim_t * 18.0)
		o.draw_circle(Vector2(0, -7), 11.0 + pulse * 2.0, Color(col, 0.22 + 0.12 * pulse))
		o.draw_arc(Vector2(0, -7), 13.0 + pulse * 1.5, 0, TAU, 28, Color(col.lightened(0.4), 0.95), 1.5)
		for k in 4:  # sparks orbiting the hero
			var a := h.anim_t * 7.0 + k * TAU / 4.0
			o.draw_circle(Vector2(cos(a) * 12.0, -7 + sin(a) * 6.0), 1.2, Color.WHITE)
	else:
		# Ring closing in as it fills: big and faint at first, tight and bright when ready.
		var rad := lerpf(20.0, 12.0, r)
		o.draw_arc(Vector2(0, -7), rad, -PI / 2.0, -PI / 2.0 + TAU * r, 28, Color(col, 0.35 + 0.6 * r), 1.5)
		o.draw_circle(Vector2(0, -7), 9.0 * r, Color(col, 0.15 * r))


# ---------------------------------------------------------------- sound

static func play(h: Hero, which: String) -> void:
	if not _sounds.has(which):
		_sounds[which] = _synth(which)
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[which]
	p.volume_db = -10.0
	h.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Builds a short 16-bit mono clip in code: "ready" is a rising two-note chime, "fire" a noisy whoosh.
static func _synth(which: String) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	var length := 0.32 if which == "ready" else 0.28
	var n := int(rate * length)
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		if which == "ready":
			var freq := 880.0 if t < 0.09 else 1318.5
			var local := t if t < 0.09 else t - 0.09
			s = sin(TAU * freq * t) * exp(-local * 14.0) * 0.6 + sin(TAU * freq * 2.0 * t) * exp(-local * 20.0) * 0.2
		else:
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18 + 0.5 * t)
			s = lp * minf(t * 60.0, 1.0) * exp(-t * 9.0) * 0.9 + sin(TAU * (180.0 - 300.0 * t) * t) * exp(-t * 12.0) * 0.4
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
