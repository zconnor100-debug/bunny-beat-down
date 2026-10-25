class_name UpdateCheck
extends Node
## Asks GitHub, once a session, whether there's a newer release than the one
## running, and if so says so on the main menu (a button that opens the
## download page). Releases are built and published by
## .github/workflows/release.yml on every push that changes the game, and the
## build stamps its own version into application/config/version, so this only
## compares the two. One small anonymous request; never in test runs, and off
## in Settings ("check_updates").

signal found(version: String, url: String)

const LATEST := "https://api.github.com/repos/zconnor100-debug/bunny-beat-down/releases/latest"
const PAGE := "https://github.com/zconnor100-debug/bunny-beat-down/releases/latest"

static var checked := false           ## asked already this session
static var newer := ""                ## the newer version found ("" = up to date / unknown)
static var newer_url := PAGE


## Look (once a session) and emit `found` if there's something newer. A menu
## opened again later gets the answer from the first look straight away.
func start() -> void:
	if newer != "":
		found.emit.call_deferred(newer, newer_url)
		return
	if checked or Settings.is_test_run() or not Settings.get_value(&"check_updates"):
		return
	checked = true
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(_on_done.bind(http))
	if http.request(LATEST, ["User-Agent: BunnyBeatDown", "Accept: application/vnd.github+json"]) != OK:
		http.queue_free()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	var tag := str(data.get("tag_name", "")).trim_prefix("v")
	if is_newer(tag, str(ProjectSettings.get_setting("application/config/version", "0"))):
		newer = tag
		newer_url = str(data.get("html_url", PAGE))
		found.emit(newer, newer_url)


## Dotted version numbers, compared part by part ("0.6.1.2" > "0.6.1" > "0.6.0").
static func is_newer(candidate: String, current: String) -> bool:
	if candidate == "":
		return false
	var a := candidate.split(".")
	var b := current.split(".")
	for i in maxi(a.size(), b.size()):
		var x := int(a[i]) if i < a.size() else 0
		var y := int(b[i]) if i < b.size() else 0
		if x != y:
			return x > y
	return false
