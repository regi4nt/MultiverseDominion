extends Node
## Journey story (StorySystem + data/story.json): 7 chapters in continent order, which pages are open, "seen" memory.
## Run: godot --headless --path . res://tests/story_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	var ch := StorySystem.chapters()
	check(ch.size() == 7, "the story has 7 chapters")
	var order_ok := ch.size() == GameData.continents.size()
	for i in range(ch.size()):
		if i < GameData.continents.size() and String(ch[i]["id"]) != String(GameData.continents[i]["id"]):
			order_ok = false
	check(order_ok, "the chapters follow the order of the continents (1st to 7th)")
	var text_ok := true
	for c in ch:
		if String(c.get("title", "")) == "" or (c.get("lines", []) as Array).size() < 3 or String(c.get("goal", "")) == "":
			text_ok = false
	check(text_ok, "every chapter has a title, a goal and at least 3 paragraphs")
	check(StorySystem.page(StorySystem.PROLOGUE).has("lines") and StorySystem.page(StorySystem.EPILOGUE).has("lines"), "prologue and epilogue have text")
	check(StorySystem.page_ids().size() == 9 and StorySystem.page_ids()[0] == "prologue" and StorySystem.page_ids()[8] == "epilogue", "pages read: prologue, 7 chapters, epilogue")
	check(StorySystem.chapter_number("aetherion") == 1 and StorySystem.chapter_number("eclipsia") == 7 and StorySystem.chapter_number("nope") == 0, "chapter numbers")

	var backup: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_data()
	check(StorySystem.is_open("prologue") and StorySystem.is_open("aetherion"), "a new save can read the prologue and chapter 1")
	check(not StorySystem.is_open("arcanum") and not StorySystem.is_open("eclipsia") and not StorySystem.is_open("epilogue"), "later chapters and the epilogue stay locked")
	check(StorySystem.first_unseen() == "prologue", "a new save opens on the prologue")
	StorySystem.mark_seen("prologue")
	check(StorySystem.is_seen("prologue") and StorySystem.first_unseen() == "aetherion", "after the prologue the next unread page is chapter 1")
	StorySystem.mark_seen("aetherion")
	StorySystem.mark_seen("aetherion")
	check((SaveManager.data["story_seen"] as Array).count("aetherion") == 1, "a page is remembered once")
	check(StorySystem.first_unseen() == "", "nothing new to read until another continent opens")
	SaveManager.unlock_continent("arcanum")
	check(StorySystem.is_open("arcanum") and StorySystem.first_unseen() == "arcanum", "opening a continent opens its chapter")
	SaveManager.data = backup

	print("STORY TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
