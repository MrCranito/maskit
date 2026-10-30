extends SceneTree
## Point d'entrée des parties automatiques (bot de playtest).
##   godot --headless --path . --fixed-fps 60 -s res://tools/playtest/playtest_main.gd -- \
##       --mode=raid|boss|duel --map=perm_dust_creek --difficulty=1 --profile=prudent \
##       --tier=debutant --seed=123 --out=/chemin/partie.json [--enemy=fw_buffalo] [--max-time=240]
## Le scénario est dans playtest_bot.gd, chargé après les autoloads (un script principal ne peut
## pas les nommer). Voir tools/playtest/README.md.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var bot: Node = (load("res://tools/playtest/playtest_bot.gd") as Script).new()
	bot.name = "PlaytestBot"
	root.add_child(bot)
