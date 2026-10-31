extends SceneTree
## Banc de profilage rejouable (voir tools/perf_bench/README.md) : un vrai raid joué par le bot de
## playtest (tools/playtest/playtest_bot.gd), AVEC rendu, et un enregistreur de temps d'image.
##   godot --path . --fixed-fps 60 --resolution 2000x923 -s res://tools/perf_bench/perf_bench_main.gd -- \
##       --map=perm_dust_creek --seed=42 --profile=agressif --difficulty=2 --frames=1800 --out=bench.json
## Options de l'enregistreur : --frames (images mesurées, 1800 = 30 s de jeu à --fixed-fps 60),
## --out (JSON), --disable=Classe1,Classe2 (nœuds de ces classes désactivés et cachés : attribution
## du coût par sous-système), --fire (tir continu forcé).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var bot: Node = (load("res://tools/playtest/playtest_bot.gd") as Script).new()
	bot.name = "PlaytestBot"
	root.add_child(bot)
	var rec: Node = (load("res://tools/perf_bench/perf_recorder.gd") as Script).new()
	rec.name = "PerfRecorder"
	rec.set("bot", bot)
	root.add_child(rec)
