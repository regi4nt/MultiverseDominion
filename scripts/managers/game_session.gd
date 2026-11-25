extends Node
## Autoload "GameSession": match configuration handed from menus to the Territory Board.

## Name of the Collection + Deck + Info screen (Main Menu button and screen title).
const CARD_HUB_NAME := "Card Hub"

var mode: String = "ffa_ai"  # "ffa_ai" (4 player) | "team_2v2" | "custom_ai" (1vs1) | "tutorial"   (TODO: online)
var category: String = "arena"  # "journey" (1vs1, a win unlocks the next continent) | "arena" (free match, unlocks nothing)
var continent_id: String = "aetherion"
var battle_deck_continent: String = ""  # Battle Chess: continent of the Card Hub deck to use ("" = the map continent); the map itself is random
var faction_id: String = "solvaris"
var difficulty: String = "normal"
var continent_random: bool = false  # Arena: the continent is drawn at the start (with a coin bonus on a win) instead of chosen
var random_bonus_active: bool = false  # the match that is running was started with a random map
var ai_count: int = 3
var chaos_mode: bool = false  # the Chaos card of New Match (an Arena match on the 40-tile board)
var update_checked: bool = false  # the update check runs once per app start
var open_deck_tab: bool = false  # the Card Hub opens on the Deck tab (New Match -> "Change faction")
var collection_return: String = ""  # scene the Card Hub "Back" button returns to ("" = Main Menu)
var setup_return: String = ""  # "journey" | "arena": New Match reopens that setup view (not the mode hub) when it is entered again from the Card Hub
var wager: int = 0  # Aether Coins staked on the next Arena match / Battle Chess battle (already paid when it is set to start)
var wager_odds: float = 2.0  # win multiplier of that stake (ShopSystem.wager_odds)
var battle_series: String = "survival"  # Battle Chess is always a Survival run now; the difficulty sets the lives (Easy 5 / Normal 3 / Hard 1)
var resume_match: bool = false  # Main Menu "Continue Match" -> Territory Board loads user://match.json


func start_tutorial() -> void:
	mode = "tutorial"
	resume_match = false


func to_match_config() -> Dictionary:
	if mode == "tutorial":  # fixed, normal AI, 1v1 on Aetherion, 10 rounds
		return {"mode": mode, "continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1,
			"player_name": SaveManager.data["profile"]["name"], "seed": 4242, "tutorial": true, "round_limit": 10}
	return {
		"mode": mode,
		"continent_id": continent_id,
		"faction_id": faction_id,
		"difficulty": difficulty,  # Journey: match_setup sets it from the trophies (SaveManager.journey_difficulty)
		"ai_count": ai_count,
		"team_mode": mode == "team_2v2",
		"journey": category == "journey",
		"wager": wager if (category == "arena" or category == "journey") else 0,
		"wager_odds": wager_odds,
		"random_map": random_bonus_active and category == "arena",
		"chaos": chaos_mode and category == "arena",
		"random_first": true,  # Journey / Arena / Chaos: a random seat opens the match (the tutorial returns above)
		"any_continent_enemies": category == "arena",  # Arena: the AI rulers come from factions of every continent, not only the map's
		"player_name": SaveManager.data["profile"]["name"],
		"king_b": SaveManager.king_b(SaveManager.player_champion_id()),  # B3 = territory skill unlocked
		"seed": 0,
		"round_limit": GameData.round_limit_for("chaos" if (chaos_mode and category == "arena") else category, difficulty),  # differs per mode (Journey / Arena / Chaos) and difficulty
	}
