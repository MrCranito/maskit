extends Node
## Voir render_boot.gd : rend la première image du splash (figé) en 1920 x 1080 dans boot.png.

const SIZE := Vector2i(1920, 1080)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = ProjectSettings.globalize_path("res://assets/ui/splash/boot.png")
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var s := (load("res://scenes/ui/menus/splash.tscn") as PackedScene).instantiate() as SplashScreen
	s.frozen = true
	s.auto_advance = false
	vp.add_child(s)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out)
	print("boot.png : ", out, " ", img.get_size())
	get_tree().quit(0)
