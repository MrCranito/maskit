extends SceneTree
## Découpe les visuels de monnaie de la planche art/ui/monnaie_reference.png (packs d'or, packs de
## gemmes, icônes pièce et gemme) et retire son fond sombre, lueurs comprises, vers assets/ui/currency/.
##   godot --headless --path . -s res://tools/currency_cutout/currency_cutout.gd [-- --preview=/dossier]
## Fond : dégradé estimé sur les bords de chaque cadre ; tout ce qui est relié au bord et proche du
## fond devient transparent (bord doux), l'intérieur des objets reste opaque ; la teinte du fond
## est retirée des pixels semi-transparents (lueurs) pour qu'ils se posent sur n'importe quel fond.
## Packs : en plus, fondu ovale (« projecteur ») qui garde le fond sombre de la planche autour de
## l'objet ; sans lui, les parties sombres (sac de gemmes, bas du coffre) disparaissaient.

const SRC := "res://art/ui/monnaie_reference.png"
const OUT := "res://assets/ui/currency/"
## Cadres (x, y, largeur, hauteur) dans la planche 1536 × 1024.
const BOXES := {
	"gold_pack_1": Rect2i(70, 160, 220, 220),
	"gold_pack_2": Rect2i(395, 160, 230, 230),
	"gold_pack_3": Rect2i(685, 115, 315, 295),
	"gold_pack_4": Rect2i(1010, 80, 515, 335),
	"gems_pack_1": Rect2i(70, 680, 220, 205),
	"gems_pack_2": Rect2i(395, 630, 235, 245),
	"gems_pack_3": Rect2i(695, 605, 315, 295),
	"gems_pack_4": Rect2i(1040, 595, 485, 315),
	"coin": Rect2i(505, 28, 82, 66),
	"gem": Rect2i(548, 528, 82, 66),
}
## Écart au fond (luminosité et saturation, 0..1) : en dessous de BG_LO transparent, au-delà de BG_HI opaque.
const BG_LO := 0.08
const BG_HI := 0.22
const PAD := 6
## Taille minimale du plus petit côté (agrandissement Lanczos) : icônes 256 px, packs 320 px.
const MIN_ICON := 256
const MIN_PACK := 320

var preview_dir: String = ""


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--preview="):
			preview_dir = a.substr(10)
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if src == null:
		push_error("planche introuvable : " + SRC)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	# Aperçu : planche de contrôle sur fond gris moyen (les restes de fond s'y voient).
	var sheet := Image.create(1100, 760, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.42, 0.42, 0.45))
	var cursor := Vector2i(8, 8)
	var row_h := 0
	for id: String in BOXES:
		var is_pack := id.contains("pack")
		var img := cutout(src.get_region(BOXES[id]), not is_pack)
		var k := float(MIN_PACK if is_pack else MIN_ICON) / float(mini(img.get_width(), img.get_height()))
		if k > 1.0:
			img.resize(roundi(img.get_width() * k), roundi(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
		var path := ProjectSettings.globalize_path(OUT + id + ".png")
		img.save_png(path)
		print("%s : %d × %d" % [id, img.get_width(), img.get_height()])
		if preview_dir != "":
			var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
			bg.fill(Color(0.024, 0.027, 0.051))
			bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
			bg.save_png(preview_dir.path_join(id + ".png"))
			if cursor.x + img.get_width() > sheet.get_width():
				cursor = Vector2i(8, cursor.y + row_h + 8)
				row_h = 0
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cursor)
			cursor.x += img.get_width() + 8
			row_h = maxi(row_h, img.get_height())
	if preview_dir != "":
		sheet.save_png(preview_dir.path_join("_planche.png"))
	quit(0)


## Fond estimé : moyenne des bords (haut, bas, gauche, droite) interpolée vers l'intérieur.
static func _bg_at(top: PackedColorArray, bottom: PackedColorArray, left: PackedColorArray,
		right: PackedColorArray, x: int, y: int, w: int, h: int) -> Color:
	var fx := float(x) / maxf(1.0, w - 1.0)
	var fy := float(y) / maxf(1.0, h - 1.0)
	var vert := top[x].lerp(bottom[x], fy)
	var horiz := left[y].lerp(right[y], fx)
	return vert.lerp(horiz, 0.5)


static func _smooth_edge(img: Image, w: int, h: int, horizontal: bool, at: int) -> PackedColorArray:
	# Bord lissé (moyenne glissante sur 15 px, 3 px d'épaisseur) : gomme le quadrillage du sol.
	var n := w if horizontal else h
	var raw := PackedColorArray()
	raw.resize(n)
	for i in n:
		var c := Color(0, 0, 0, 0)
		for k in 3:
			var p := img.get_pixel(i, clampi(at + (k if at == 0 else -k), 0, h - 1)) if horizontal \
				else img.get_pixel(clampi(at + (k if at == 0 else -k), 0, w - 1), i)
			c += p
		raw[i] = c / 3.0
	var out := PackedColorArray()
	out.resize(n)
	for i in n:
		var c := Color(0, 0, 0, 0)
		var m := 0
		for k in range(-7, 8):
			var j := i + k
			if j >= 0 and j < n:
				c += raw[j]
				m += 1
		out[i] = c / float(m)
	return out


## `strict` : détourage seul (icônes) ; sinon fondu ovale en plus (packs).
static func cutout(img: Image, strict: bool) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var top := _smooth_edge(img, w, h, true, 0)
	var bottom := _smooth_edge(img, w, h, true, h - 1)
	var left := _smooth_edge(img, w, h, false, 0)
	var right := _smooth_edge(img, w, h, false, w - 1)
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	var bgs := PackedColorArray()
	bgs.resize(w * h)
	for y in h:
		for x in w:
			var bg := _bg_at(top, bottom, left, right, x, y, w, h)
			var c := img.get_pixel(x, y)
			bgs[y * w + x] = bg
			# Plus clair ou plus coloré que le fond : objet (le dallage sombre et terne n'en est pas).
			dist[y * w + x] = maxf(0.0, c.v - bg.v) + 0.6 * maxf(0.0, c.s * c.v - bg.s * bg.v)
	# Fond = relié au bord par des pixels proches du fond (remplissage depuis le cadre).
	var is_bg := PackedByteArray()
	is_bg.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if is_bg[i] == 1 or dist[i] >= BG_HI:
			continue
		is_bg[i] = 1
		var x := i % w
		var y := i / w
		if x > 0:
			stack.append(i - 1)
		if x < w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - w)
		if y < h - 1:
			stack.append(i + w)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			var i := y * w + x
			var a := 1.0
			if is_bg[i] == 1:
				a = smoothstep(BG_LO, BG_HI, dist[i])
			var spot := 0.0
			if not strict:
				var e := Vector2((x - w * 0.5) / (w * 0.5), (y - h * 0.52) / (h * 0.5)).length()
				spot = 1.0 - smoothstep(0.55, 0.98, e)
			var c := img.get_pixel(x, y)
			var bg := bgs[i]
			if spot >= a:
				if spot <= 0.004:
					continue
				c.a = spot
				out.set_pixel(x, y, c)
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
				continue
			if a <= 0.004:
				continue
			# Retire la teinte du fond des pixels semi-transparents (lueurs, bords).
			if a < 1.0:
				c = Color(clampf((c.r - bg.r * (1.0 - a)) / a, 0.0, 1.0),
					clampf((c.g - bg.g * (1.0 - a)) / a, 0.0, 1.0),
					clampf((c.b - bg.b * (1.0 - a)) / a, 0.0, 1.0))
			c.a = a
			out.set_pixel(x, y, c)
			if a > 0.05:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return out
	var r := Rect2i(maxi(0, x0 - PAD), maxi(0, y0 - PAD), 0, 0)
	r.end = Vector2i(mini(w, x1 + PAD + 1), mini(h, y1 + PAD + 1))
	return out.get_region(r)
