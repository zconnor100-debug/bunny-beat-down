extends TestCase
## Asset import settings that are easy to lose: every texture drawn in 3D
## needs mipmaps (and VRAM compression). Godot's editor sets that up when it
## first sees a texture used in 3D, but command-line imports never do, and
## without mipmaps distant ground, roofs and fur alias into grainy speckle.


func test_3d_textures_have_mipmaps() -> void:
	var files: Array[String] = []
	for dir in DirAccess.get_directories_at("res://assets/textures"):
		for f in DirAccess.get_files_at("res://assets/textures/" + dir):
			if f.ends_with(".import"):
				files.append("res://assets/textures/%s/%s" % [dir, f])
	for critter in DirAccess.get_directories_at("res://assets/characters"):
		var skins := "res://assets/characters/%s/skins" % critter
		if DirAccess.dir_exists_absolute(skins):
			for f in DirAccess.get_files_at(skins):
				if f.ends_with(".import"):
					files.append(skins + "/" + f)
	check(files.size() > 100, "found the 3D textures (%d)" % files.size())
	var bad: Array[String] = []
	var checked := 0
	for path in files:
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK or cfg.get_value("remap", "importer", "") != "texture":
			continue
		checked += 1
		if not cfg.get_value("params", "mipmaps/generate", false) or int(cfg.get_value("params", "compress/mode", 0)) != 2:
			bad.append(path.get_file() + " in " + path.get_base_dir().get_file())
	check(checked > 100, "read their import settings (%d)" % checked)
	check(bad.is_empty(), "every 3D texture has mipmaps and VRAM compression (missing: %s)" % [bad])
