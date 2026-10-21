extends TestCase
## Pure maths: the two-bone solver and rotation helpers the animator relies on.


func test_two_bone_reaches_reachable_target() -> void:
	var root := Vector3(0, 1, 0)
	var target := Vector3(0.3, 0.6, 0.2)
	var sol := IKMath.solve_two_bone(root, 0.3, 0.3, target, Vector3(0, 1, 1))
	check_near(sol[1], target, 0.001, "end effector reaches target")
	check_near(root.distance_to(sol[0]), 0.3, 0.001, "upper bone length preserved")
	check_near(sol[0].distance_to(sol[1]), 0.3, 0.001, "lower bone length preserved")


func test_two_bone_bends_toward_pole() -> void:
	var root := Vector3.ZERO
	var target := Vector3(0, -0.4, 0)
	var sol := IKMath.solve_two_bone(root, 0.3, 0.3, target, Vector3(0, -0.2, 1))
	check(sol[0].z > 0.05, "knee bends forward toward the pole (z=%f)" % sol[0].z)


func test_two_bone_clamps_unreachable_target() -> void:
	var sol := IKMath.solve_two_bone(Vector3.ZERO, 0.3, 0.2, Vector3(0, 0, 5), Vector3.UP)
	check_near(sol[1].length(), 0.5, 0.01, "end stops at full reach")
	check(sol[1].z > 0.49, "reaches straight toward the target")


func test_from_to_rotates_direction() -> void:
	var a := Vector3(1, 0.2, -0.3).normalized()
	var b := Vector3(-0.2, 0.9, 0.4).normalized()
	check_near(Basis(IKMath.from_to(a, b)) * a, b, 1e-4, "from_to maps a onto b")
	check_near(Basis(IKMath.from_to(a, -a)) * a, -a, 1e-4, "handles opposite vectors")


func test_spread_stays_inside_cone() -> void:
	var dir := Vector3(0.3, 0.1, -1).normalized()
	var worst := 0.0
	for i in 500:
		var d := Projectiles._spread_dir(dir, 4.0)
		worst = maxf(worst, rad_to_deg(dir.angle_to(d)))
	check(worst <= 4.001, "spread never exceeds the cone (worst %.3f°)" % worst)
	check(worst > 2.0, "spread actually spreads (worst %.3f°)" % worst)
