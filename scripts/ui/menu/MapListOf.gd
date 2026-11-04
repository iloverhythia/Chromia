extends Reference

# The map list (Main/Maps/MapRegistry/S/VBoxContainer) seen from a control in
# the Maps page, wherever it is now (the filter checkboxes moved into the
# Filters page, MapFiltersPage.gd)
static func find(from: Node) -> Node:
	var n = from.get_parent() if from != null else null
	while n != null:
		var l = n.get_node_or_null("MapRegistry/S/VBoxContainer")
		if l != null:
			return l
		l = n.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
		if l != null:
			return l
		n = n.get_parent()
	return Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
