extends MeshInstance

func _process(delta):
	transform.origin.z += delta * Rhythia.approach_rate * 0.1
	if transform.origin.z >= 45: transform.origin.z -= 105
