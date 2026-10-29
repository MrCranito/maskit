extends SceneTree
## Client automatisé du test d'intégration coop (lancé par tools/net_smoke_test.sh) :
##   godot --headless --path . -s res://tools/net_smoke/smoke_client.gd -- \
##       --role=host|guest --dir=/tmp/dossier [--shots=/dossier/captures]
## (URL du relais : variable RAIDERSGO_NET_URL ou --net-url=…). Le scénario est dans
## smoke_driver.gd, chargé après les autoloads (un script principal ne peut pas les nommer).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/net_smoke/smoke_driver.gd") as Script).new()
	driver.name = "NetSmokeDriver"
	root.add_child(driver)
