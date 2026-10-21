extends TestCase
## Licensing guard: every shipped asset file must be credited in
## assets/credits/*.json, every credited file must exist, and only the
## allowed licenses may appear. Fails CI the moment an un-credited model,
## texture, sound or font sneaks into assets/.

const ALLOWED := ["CC0 1.0", "CC BY 4.0", "CC BY 3.0", "SIL OFL 1.1", "MIT (project)"]
const ASSET_EXT := ["glb", "gltf", "ogg", "mp3", "wav", "hdr", "exr", "ttf", "otf", "jpg", "png", "webp"]


func test_every_asset_is_credited() -> void:
	var credited := {}
	for key in CreditsPanel.load_entries():
		for e in CreditsPanel.load_entries()[key]:
			check(e.get("license", "") in ALLOWED, "%s: license '%s' not allowed" % [e.get("asset"), e.get("license")])
			check(String(e.get("author", "")) != "", "%s: missing author" % e.get("asset"))
			if e.get("license") != "MIT (project)":
				check(String(e.get("source_url", "")) != "", "%s: missing source URL" % e.get("asset"))
			for f in e.get("files", []):
				credited[String(f)] = true
				var p := "res://" + String(f)
				check(FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p), "credited file missing: %s" % f)
	var missing: Array[String] = []
	for path in _shipped_assets("res://assets"):
		if not credited.has(path.trim_prefix("res://")):
			missing.append(path)
	check(missing.is_empty(), "%d asset file(s) without a credit: %s" % [missing.size(), ", ".join(missing.slice(0, 12))])


## Asset files that ship (skips generated/derived files Godot extracts on import,
## previews, manifests and credit files themselves).
func _shipped_assets(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		var ext := f.get_extension().to_lower()
		if not ext in ASSET_EXT:
			continue
		if f.begins_with("preview") or f == "lineup.png":
			continue
		var path := dir.path_join(f)
		if _is_extracted_texture(dir, f):
			continue
		out.append(path)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_shipped_assets(dir.path_join(d)))
	return out


func _is_extracted_texture(dir: String, f: String) -> bool:
	if not f.get_extension().to_lower() in ["png", "jpg", "webp"]:
		return false
	# "<model>_<image>.png" sitting next to "<model>.glb"
	for g in DirAccess.get_files_at(dir):
		if g.ends_with(".glb") and f.begins_with(g.get_basename() + "_"):
			return true
	return false
