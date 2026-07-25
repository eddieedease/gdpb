extends Node
## The high score table, autoloaded as HighScores. Keeps the best MAX_ENTRIES
## runs and persists them to user:// so they survive restarts.
##
## Entries are always kept sorted best-first, so `entries[0]` is the record and
## the last one is the cut-off any new score has to beat.

const MAX_ENTRIES := 10
const NAME_LENGTH := 3
const SAVE_PATH := "user://highscores.cfg"
const DEFAULT_NAME := "AAA"

## [{name: String, score: int}], best first.
var entries: Array = []

## Score waiting to be entered on the high score screen. table_game sets this
## on game over; the screen clears it once handled, so returning to the table
## later cannot re-trigger a name entry for a score already recorded.
var pending_score := 0


func _ready() -> void:
	load_scores()


func load_scores() -> void:
	entries.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return   # no save yet, or unreadable - start from an empty table
	for i in MAX_ENTRIES:
		var key := "entry_%d" % i
		if not cfg.has_section_key("scores", key):
			continue
		var v = cfg.get_value("scores", key)
		if v is Dictionary and v.has("name") and v.has("score"):
			entries.append({"name": str(v["name"]), "score": int(v["score"])})
	_sort()


func save_scores() -> void:
	var cfg := ConfigFile.new()
	for i in entries.size():
		cfg.set_value("scores", "entry_%d" % i, entries[i])
	cfg.save(SAVE_PATH)


## Would this score make the table? A zero score never does, so bailing out of
## a game immediately doesn't prompt for a name.
func qualifies(score: int) -> bool:
	if score <= 0:
		return false
	if entries.size() < MAX_ENTRIES:
		return true
	return score > int(entries[entries.size() - 1]["score"])


## Insert a score and return the row it landed on (0 = new record), or -1 if it
## didn't qualify. Ties land BELOW the existing entry, so an older run keeps the
## better placing.
func submit(player_name: String, score: int) -> int:
	if not qualifies(score):
		return -1
	var row := entries.size()
	for i in entries.size():
		if score > int(entries[i]["score"]):
			row = i
			break
	entries.insert(row, {"name": player_name, "score": score})
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)
	save_scores()
	return row


func clear_all() -> void:
	entries.clear()
	save_scores()


func _sort() -> void:
	entries.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
