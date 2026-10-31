extends SceneTree
## Rend assets/ui/splash/boot.png (image de démarrage du moteur) depuis la PREMIÈRE IMAGE de
## l'écran de démarrage animé (SplashScreen figé), dans un SubViewport 1920 x 1080 : le relais
## moteur → jeu se fait donc sans saut. À relancer après toute retouche du logo ou des couleurs :
##   Godot_v4.7.2-stable_win64.exe --path . -s res://tools/splash_boot/render_boot.gd [-- --out=C:/x.png]
## (exécutable avec rendu, pas --headless), puis --headless --import.
## Le travail est fait par render_boot_driver.gd (chargé après les autoloads).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/splash_boot/render_boot_driver.gd") as Script).new()
	driver.name = "RenderBootDriver"
	root.add_child(driver)
