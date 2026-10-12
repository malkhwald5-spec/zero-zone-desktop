extends SceneTree
## Prepares a downloaded rigged character for the game:
## godot --headless --path godot -s res://tools/prep_character.gd -- --src=res://x/scene.gltf --out=res://assets/models/chars/x.glb [--tex=1024]
## - bone names become plain Mixamo ones ("mixamorig:Hips_01" -> "mixamorig_Hips"),
##   in the skeleton and in the skins, so the retargeted moves fit;
## - its own animations are dropped (the game brings its own);
## - textures are shrunk to --tex pixels;
## - the result is written as one .glb.

func _init() -> void:
	var src := ""
	var out := ""
	var tex := 1024
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="): src = a.substr(6)
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tex="): tex = int(a.substr(6))
	var sc: Node = load(src).instantiate()
	for ap in sc.find_children("*", "AnimationPlayer", true, false):
		ap.get_parent().remove_child(ap)
		ap.free()
	var suffix := RegEx.create_from_string("_\\d+$")
	var rename := {}
	for sk: Skeleton3D in sc.find_children("*", "Skeleton3D", true, false):
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i).replace(":", "_")
			if n.begins_with("mixamorig"): n = suffix.sub(n, "")
			rename[sk.get_bone_name(i)] = n
			sk.set_bone_name(i, n)
	var done := {}
	for mi: MeshInstance3D in sc.find_children("*", "MeshInstance3D", true, false):
		if mi.skin:
			mi.skin = mi.skin.duplicate()
			for b in mi.skin.get_bind_count():
				var bn := String(mi.skin.get_bind_name(b))
				if rename.has(bn): mi.skin.set_bind_name(b, rename[bn])
		if mi.mesh == null: continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null or done.has(m): continue
			done[m] = true
			for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
				var t: Texture2D = m.get(p)
				if t == null: continue
				var img := t.get_image()
				if img == null: continue
				if img.is_compressed(): img.decompress()
				var k := float(tex) / maxf(img.get_width(), img.get_height())
				if k < 1.0: img.resize(maxi(4, int(img.get_width() * k)), maxi(4, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
				m.set(p, ImageTexture.create_from_image(img))
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(sc, st)
	if err == OK: err = doc.write_to_filesystem(st, ProjectSettings.globalize_path(out))
	print("prep ", src, " -> ", out, " err=", err, " bones renamed=", rename.size())
	sc.free()
	quit()
