extends Reference

# Orders notes by time, then position, so notes that share a timestamp
# always come out in the same order.
func by_time(a, b) -> bool:
	if float(a[2]) != float(b[2]):
		return float(a[2]) < float(b[2])
	if float(a[0]) != float(b[0]):
		return float(a[0]) < float(b[0])
	return float(a[1]) < float(b[1])
