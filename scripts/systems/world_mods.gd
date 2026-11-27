class_name WorldMods
extends RefCounted
## World modifier of the continent being played (data/continents.json -> "modifier").
## Static on purpose: one match at a time. MatchController.setup() calls apply(); Battle Chess
## calls apply()/reset() too. Keys of the modifier dictionary map 1:1 to the variables below.

static var modifier_name: String = ""
static var start_bonus_extra: int = 0     # Aetherion: Royal Tithe
static var portals_per_region: int = 1    # portals kept active per region (the board has 1 portal tile per region)
static var stock_bias: float = 0.0        # Arcanum: Arcane Markets (added to the every-round stock change)
static var rent_mult: float = 1.0         # Machina: Industrial Age
static var unit_price_mult: float = 1.0   # Machina: Industrial Age
static var harvest_per_land: int = 0      # Sylvaris: Bountiful Harvest
static var atk_mult: float = 1.0          # Drakmor: War Fever
static var duel_win_gold: int = 0         # Drakmor: War Fever
static var tax_mult: float = 1.0          # Thalassia: Sea Trade
static var shop_reroll_price: int = -1    # Thalassia: Sea Trade (-1 = balance.json)
static var start_token: int = 0           # Eclipsia: Time Fold
static var bonus_rolls_extra: int = 0     # Eclipsia: Time Fold
static var corner_bonus: Dictionary = {}  # data/continents.json -> "corner_bonus": {"sanctuary"|"rift"|"crossroads": {text, effect keys}} (see MatchController._apply_corner_bonus)


static func reset() -> void:
	modifier_name = ""
	start_bonus_extra = 0
	portals_per_region = 1
	stock_bias = 0.0
	rent_mult = 1.0
	unit_price_mult = 1.0
	harvest_per_land = 0
	atk_mult = 1.0
	duel_win_gold = 0
	tax_mult = 1.0
	shop_reroll_price = -1
	start_token = 0
	bonus_rolls_extra = 0
	corner_bonus = {}


static func apply(continent: Dictionary) -> void:
	reset()
	var m: Dictionary = continent.get("modifier", {})
	modifier_name = String(m.get("name", ""))
	start_bonus_extra = int(m.get("start_bonus_extra", 0))
	portals_per_region = clampi(int(m.get("portals_per_region", 1)), 1, 3)
	stock_bias = float(m.get("stock_bias", 0.0))
	rent_mult = float(m.get("rent_mult", 1.0))
	unit_price_mult = float(m.get("unit_price_mult", 1.0))
	harvest_per_land = int(m.get("harvest_per_land", 0))
	atk_mult = float(m.get("atk_mult", 1.0))
	duel_win_gold = int(m.get("duel_win_gold", 0))
	tax_mult = float(m.get("tax_mult", 1.0))
	shop_reroll_price = int(m.get("shop_reroll_price", -1))
	start_token = int(m.get("start_token", 0))
	bonus_rolls_extra = int(m.get("bonus_rolls_extra", 0))
	corner_bonus = (continent.get("corner_bonus", {}) as Dictionary).duplicate(true)


## Continent bonus of a corner ("sanctuary" / "rift" / "crossroads"); {} when the continent has none.
static func corner_extra(kind: String) -> Dictionary:
	return corner_bonus.get(kind, {})


## Price of a Reroll Token in the Territory Shop.
static func token_price() -> int:
	return shop_reroll_price if shop_reroll_price > 0 else int(GameData.b("reroll_price"))
