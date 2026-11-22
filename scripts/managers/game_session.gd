extends Node
## Autoload "GameSession": match configuration handed from menus to the Territory Board.

var mode: String = "ffa_ai"  # "ffa_ai" (4 player) | "team_2v2" | "custom_ai" (1vs1) | "tutorial"   (TODO: online)
var category: String = "arena"  # "journey" (1vs1, a win unlocks the next continent) | "arena" (free match, unlocks nothing)
var continent_id: String = "aetherion"
var faction_id: String = "solvaris"
var difficulty: String = "normal"
var ai_count: int = 3
var update_checked: bool = false  # the update check runs once per app start
var open_deck_tab: bool = false  # Collection & Deck opens on the Deck tab (New Match -> "Change faction")
var collection_return: String = ""  # scene the Collection & Deck "Back" button returns to ("" = Main Menu)
var resume_match: bool = false  # Main Menu "Continue Match" -> Territory Board loads user://match.json


func start_tutorial() -> void:
	mode = "tutorial"
	resume_match = false


func to_match_config() -> Dictionary:
	if mode == "tutorial":  # fixed, easy, 1v1 on Aetherion, 10 rounds
		return {"mode": mode, "continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "easy", "ai_count": 1,
			"player_name": SaveManager.data["profile"]["name"], "seed": 4242, "tutorial": true, "round_limit": 10}
	return {
		"mode": mode,
		"continent_id": continent_id,
		"faction_id": faction_id,
		"difficulty": difficulty,
		"ai_count": ai_count,
		"team_mode": mode == "team_2v2",
		"journey": category == "journey",
		"player_name": SaveManager.data["profile"]["name"],
		"seed": 0,
	}
