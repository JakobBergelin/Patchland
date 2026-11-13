class_name Scores
## Local scoreboard: the top runs, kept in the settings file (section "scores").
## Entries: {score, rounds (rounds cleared), won, relics, best_harvest, date}.

const KEEP := 10


static func load_list(path: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return []
	var list = cfg.get_value("scores", "list", [])
	return list if list is Array else []


## Adds a finished run. Returns its rank (1 = best) or 0 if it didn't make the list.
static func record(path: String, entry: Dictionary) -> int:
	var list := load_list(path)
	list.append(entry)
	list.sort_custom(func(a, b): return a.score > b.score)
	var rank := list.find(entry) + 1
	if list.size() > KEEP:
		list = list.slice(0, KEEP)
	if rank > KEEP:
		rank = 0
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("scores", "list", list)
	cfg.save(path)
	return rank


static func best(path: String) -> int:
	var list := load_list(path)
	return list[0].score if not list.is_empty() else 0


static func make_entry(s: RunState, won: bool) -> Dictionary:
	return {
		"score": s.total,
		"rounds": Defs.ROUNDS if won else s.round_idx,
		"won": won,
		"relics": s.relics.size(),
		"best_harvest": s.best_harvest,
		"date": Time.get_date_string_from_system(),
	}
