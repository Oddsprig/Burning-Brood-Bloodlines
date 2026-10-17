extends RefCounted
## Every trait at every level reads as English: "very" only in front of single adjectives, never phrases
## (regression: "very sticks with the squad").
func run(_t) -> int:
	var fails := 0
	for t in DB.TRAITS:
		for v in [0, 10, 20, 30, 50, 70, 80, 90, 100]:
			var w := Factory.trait_word(t, v)
			if w.begins_with("very ") and (w.split(" ").size() > 2 or w.begins_with("very a ")):
				print("bad phrasing: %s at %d -> '%s'" % [t, v, w]); fails += 1
	print("cohesion: ", Factory.trait_word("cohesion", 5), " / ", Factory.trait_word("cohesion", 95), "; appetite: ", Factory.trait_word("appetite", 5), " / ", Factory.trait_word("appetite", 95))
	return fails
