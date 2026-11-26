class_name StorySystem
extends RefCounted
## Journey story: a prologue, one chapter per continent (1st to 7th) and an epilogue. Text lives in data/story.json.
## A chapter is open once its continent is open in the Journey (SaveManager.is_continent_unlocked); the epilogue opens when the
## Journey road is finished (SaveManager.journey_difficulty_free). Pages the player has opened are remembered in the save ("story_seen").
## Page ids: "prologue", the continent id of a chapter, "epilogue". Pure data / rules, no UI (see StoryPanel).

const PATH := "res://data/story.json"
const PROLOGUE := "prologue"
const EPILOGUE := "epilogue"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var res = load(PATH)
		if res is JSON and res.data is Dictionary:
			_cache = res.data
		else:
			push_error("StorySystem: cannot load %s" % PATH)
	return _cache


## The chapters in order (continent 1..7): {id, title, lines, teaser, goal}.
static func chapters() -> Array:
	return data().get("chapters", [])


## Every page id in reading order: prologue, the chapters, epilogue.
static func page_ids() -> Array:
	var out: Array = [PROLOGUE]
	for c in chapters():
		out.append(String(c["id"]))
	out.append(EPILOGUE)
	return out


## 1-based chapter number of a continent id (0 = the prologue / epilogue / unknown).
static func chapter_number(id: String) -> int:
	var n := 0
	for c in chapters():
		n += 1
		if String(c["id"]) == id:
			return n
	return 0


## A page as {id, kind ("prologue" | "chapter" | "epilogue"), number, title, lines, teaser, goal} ({} if unknown).
static func page(id: String) -> Dictionary:
	if id == PROLOGUE or id == EPILOGUE:
		var p: Dictionary = (data().get(id, {}) as Dictionary).duplicate()
		p["id"] = id
		p["kind"] = id
		p["number"] = 0
		return p
	for c in chapters():
		if String(c["id"]) == id:
			var p: Dictionary = (c as Dictionary).duplicate()
			p["kind"] = "chapter"
			p["number"] = chapter_number(id)
			return p
	return {}


## Can the player read this page now? The prologue always, a chapter once its continent is open, the epilogue once the road is finished.
static func is_open(id: String) -> bool:
	if id == PROLOGUE:
		return true
	if id == EPILOGUE:
		return SaveManager.journey_difficulty_free()
	return SaveManager.is_continent_unlocked(id)


## The chapter that goes with the player right now: the newest open continent (the Journey frontier).
static func current_id() -> String:
	return SaveManager.journey_frontier()


static func is_seen(id: String) -> bool:
	return (SaveManager.data.get("story_seen", []) as Array).has(id)


static func mark_seen(id: String) -> void:
	if not SaveManager.data.has("story_seen") or not (SaveManager.data["story_seen"] is Array):
		SaveManager.data["story_seen"] = []
	var seen: Array = SaveManager.data["story_seen"]
	if not seen.has(id):
		seen.append(id)
		SaveManager.save_game()


## The first open page the player has not read yet ("" if none): the panel opens on it by itself.
static func first_unseen() -> String:
	for id in page_ids():
		if is_open(String(id)) and not is_seen(String(id)):
			return String(id)
	return ""
