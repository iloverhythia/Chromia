extends Resource
class_name NamedSound

export(String) var id
export(String) var name
export(String) var creator
export(String) var path

func _init(idI: String, nameI: String, creatorI: String = "You", pathI: String = ""):
	id = idI
	name = nameI
	creator = creatorI
	path = pathI
