class_name ComboSystem
extends RefCounted
## Named synergy combos of a battle line-up. EVERY synergy is a SPECIAL EFFECT (burn, chill, stun, thorns, evade, execute, ...), never a flat stat bonus.
##
## 1. Faction Tier: units of the King's own faction on the field (units of other factions get none). ONE tier per faction (Rally 2 / Legion 4 / Host 6 units) that carries
##    the faction trait (see 4). There is no flat Faction Banner HP/ATK bonus (FACTION_TIERS / FACTION_ULTRA_BONUS are 0). Use faction_tier() / faction_tier_text() for it.
## 2. Role traits: one per role, three tiers (2 / 4 / 6 units of that role). Each is named for its role's job:
##    Iron Wall (Tank), Guardian Aura (Support), Shadow Strike (Assassin), Arcane Surge (Mage), Eagle Eye (Marksman),
##    Warband (Fighter), Tactician's Command (Controller).
## 3. Duo combos: two roles side by side (6 units of EACH role, DUO_UNITS), each with a special effect that fits its name:
##    Frontline Shield, Glass Cannon, Sniper's Nest, Pincer Strike, Arcane Ward, Battle Plan, Vanguard Line, Command Post,
##    Field Medic, Covering Fire, Spellblade, Crossfire, Arcane Tactics, Ambush Plan, Spell Bastion, War Council,
##    Bait and Strike, Venom Vial, Hold the Line, Ranged Barrage, Target Painting (every pair of the 7 roles has a duo combo),
##    Grand Army (all 7 roles, 2 units each = every role trait active).
##
## 4. Faction traits (FACTION_TRAITS): one own special effect per faction, part of the Faction Tier of that faction (see the constant).
##
## 5. Grand Army (Faction): the faction version of Grand Army. EVERY faction of the continent fields at least FACTION_ARMY_MIN (2) units, so every
##    Faction Tier is active at once, AND the faction units on the field total FACTION_ARMY_TOTAL (8 = 4 factions x 2): every unit
##    gains the special effects of FACTION_ARMY. Excludes ULTRA (which needs ONE faction). Judged against the King's continent OR the played continent (BattleEngine._army_active), so a foreign King can have it too, like the Faction Tier.
##
## 6. ULTRA: when ALL units of a line-up (8+) are of one home faction, or all of one role, that synergy goes beyond Host (see ULTRA_MIN).
##
## Effects: {"to": "all" or a list of roles, <special effect>: value, ...}. The special effects (FX_TYPES) are the same ones the engine already knows from the
## continent card buffs; the value means (see FX_COUNT / FX_TICKS, everything else is a fraction, 0.10 = 10%):
##   armor      damage taken -x                        evade       every Nth hit taken is avoided (count)
##   thorns     reflects x of the damage taken         execute     +x damage to enemies below 30% HP
##   frenzy     +x ATK per kill (max 5 kills)          rage        +x ATK while below half HP
##   aura_atk   adjacent allies +x ATK                 burn        attacks burn: x of ATK every 4 ticks for 12 ticks
##   stun_proc  every Nth attack stuns for 1 tick (count)   splash  x of the damage hits enemies next to the target
##   lifesteal  heals x of the damage dealt            chill       attacks slow the target for x ticks (ticks)
##   opener     the first attack hits +x harder        last_rites  on death heals adjacent allies x of their max HP
##   death_burst on death hits adjacent enemies for x of ATK   mend_self  heals x of max HP every 8 ticks
##   guard      allies within 2 cells take x less damage   second_life  returns once at x of max HP after falling
## Effects of every active combo add up (counts take the best = lowest, ticks and second_life the best = highest). The old stat keys (hp, atk, shield, move, range)
## still work in the effect dictionaries, but no combo uses them any more.

## Special effects a synergy can carry. Counts: lower is better; ticks: a duration; every other one is a fraction.
const FX_TYPES: Array[String] = ["armor", "evade", "thorns", "execute", "frenzy", "rage", "aura_atk", "burn", "stun_proc", "splash", "lifesteal", "chill",
	"opener", "last_rites", "death_burst", "mend_self", "guard", "second_life"]
const FX_COUNT: Array[String] = ["evade", "stun_proc"]
const FX_TICKS: Array[String] = ["chill"]
## A count never gets lower than this (Ultra, stacking): "every 2nd hit" would be a permanent stun-lock / 50% dodge.
const FX_COUNT_MIN: float = 3.0
## Fractions that may never go past this when effects add up / are scaled (armor 60% damage cut, second_life 90% HP).
const FX_CAP: Dictionary = {"armor": 0.6, "guard": 0.5, "second_life": 0.9, "thorns": 1.0}
const STAT_KEYS: Array[String] = ["hp", "atk", "shield", "move", "range"]

## Units of EACH of the two roles a pair duo combo needs (Host-sized squads). Grand Army (all 7 roles) is the exception: 2 units of each (the Role Trait minimum),
## because 7 x 6 = 42 units cannot be fielded (capacity is 30).
const DUO_UNITS: int = 6

## Grand Army (Faction): every faction of the played continent needs FACTION_ARMY_MIN units on the field (= every Faction Tier active).
const FACTION_ARMY_MIN: int = 2
## ... and the home-faction units on the field must total this many (8 = the 4 factions of a continent x FACTION_ARMY_MIN; every faction at 2+ already reaches it, the constant is a safety net).
const FACTION_ARMY_TOTAL: int = 8
const FACTION_ARMY: Dictionary = {"id": "grand_army_faction", "name": "Grand Army (Faction)",
	"blurb": "Every faction of the continent fights together (2+ units of each faction, 8 units or more in all): every unit heals its neighbours when it falls and mends itself over time.",
	"effects": [{"to": "all", "last_rites": 0.10, "mend_self": 0.03}]}

## 7. Continent Bond: one synergy that unites ALL 7 continents. It switches on when, for EVERY continent, the side fields at least BOND_FACTION_UNITS (2) units of ONE faction
## of that continent (= one Rally-sized faction group per continent, 2 x 7 = 14 units; a Pawn / shared piece belongs to the King's faction, see CardDatabase.effective_faction).
## The effect depends on the King: every unit gains the effect of the continent the King's faction belongs to (CONTINENT_BONDS, one effect per continent), nothing else.
## It stacks with everything else, Ultra included. A deck may hold unit cards of several continents (Deck), which is what makes this reachable.
const BOND_FACTION_UNITS: int = 2
const BOND_NAME: String = "Continent Bond"
const CONTINENT_BONDS: Dictionary = {
	"aetherion": {"id": "bond_aetherion", "name": "Royal Standard", "blurb": "The crown's banner steadies the whole army: every unit takes 3% less damage.",
		"effects": [{"to": "all", "armor": 0.03}]},
	"arcanum": {"id": "bond_arcanum", "name": "Arcane Resonance", "blurb": "Spell energy runs through the ranks: every attack splashes 10% onto the neighbours.",
		"effects": [{"to": "all", "splash": 0.10}]},
	"machina": {"id": "bond_machina", "name": "Clockwork Precision", "blurb": "Calibrated machines open the fight hard: every unit's first attack hits 15% harder.",
		"effects": [{"to": "all", "opener": 0.15}]},
	"sylvaris": {"id": "bond_sylvaris", "name": "Verdant Renewal", "blurb": "The forest mends its own: every unit heals 2% of its HP every 8 ticks.",
		"effects": [{"to": "all", "mend_self": 0.02}]},
	"drakmor": {"id": "bond_drakmor", "name": "War Fever", "blurb": "Battle lust grows with every wound: every unit gains +8% ATK under half HP.",
		"effects": [{"to": "all", "rage": 0.08}]},
	"thalassia": {"id": "bond_thalassia", "name": "Tidal Surge", "blurb": "The tide drags at the enemy: every attack slows its target for 2 ticks.",
		"effects": [{"to": "all", "chill": 2}]},
	"eclipsia": {"id": "bond_eclipsia", "name": "Time Fold", "blurb": "Time stutters around the army: every unit dodges every 8th hit.",
		"effects": [{"to": "all", "evade": 8}]},
}

const ROLES: Array[String] = ["Tank", "Support", "Assassin", "Mage", "Marksman", "Fighter", "Controller"]

## Faction Tiers: [units, flat HP and ATK bonus (0 = none), name]; the highest reached tier counts. The trait lists [Rally, Legion, Host] use the same index (0 / 1 / 2).
const FACTION_TIERS: Array = [[6, 0.0, "Host"], [4, 0.0, "Legion"], [2, 0.0, "Rally"]]
## Index into the [x, y, z] lists of FACTION_TRAITS used by Ultra (2 = Host strength, then x ULTRA_SCALE).
const FACTION_ULTRA_TRAIT_INDEX: int = 2
## Faction Ultra banner: no flat HP / ATK bonus either (the trait x ULTRA_SCALE and the Ultra special remain).
const FACTION_ULTRA_BONUS: float = 0.0

## ULTRA: the tier above Host. It switches on when EVERY unit of the line-up uses the same synergy (all of one home faction, or all of one
## role) and the line-up has at least ULTRA_MIN units. The faction trait / role trait at Host strength gets stronger by ULTRA_SCALE (fractions and ticks x1.5,
## counts / 1.5 but never below FX_COUNT_MIN, e.g. "every 6th hit" becomes "every 4th"). Plus an ULTRA SPECIAL effect (ULTRA_FACTION_SPECIAL / ULTRA_ROLE_SPECIALS), flat and only in Ultra.
const ULTRA_MIN: int = 8
const ULTRA_SCALE: float = 1.5
const ULTRA_NAME: String = "Ultra"

## ULTRA SPECIAL EFFECTS: on top of the scaled numbers, Ultra unlocks one special effect that no lower tier has (flat, NOT scaled).
## Faction Ultra: every unit of the faction gets it. Role Ultra: one special per role (the effect list is like a combo's).
const ULTRA_FACTION_SPECIAL: Dictionary = {"name": "Ultra Dominion", "blurb": "The whole faction fights as one: every unit drains 8% of the damage it deals and gains +4% ATK per kill.",
	"effects": [{"to": "all", "lifesteal": 0.08, "frenzy": 0.04}]}
const ULTRA_ROLE_SPECIALS: Dictionary = {
	"Tank": {"name": "Unbreakable", "blurb": "Tanks return once at 30% HP after falling.", "effects": [{"to": ["Tank"], "second_life": 0.30}]},
	"Support": {"name": "Sanctuary", "blurb": "The whole army takes 5% less damage.", "effects": [{"to": "all", "armor": 0.05}]},
	"Assassin": {"name": "Phantom Rush", "blurb": "Assassins dodge every 3rd hit and open with a +50% first strike.", "effects": [{"to": ["Assassin"], "evade": 3, "opener": 0.50}]},
	"Mage": {"name": "Arcane Overreach", "blurb": "Mage attacks burn for 20% of ATK and splash 20% to the neighbours.", "effects": [{"to": ["Mage"], "burn": 0.20, "splash": 0.20}]},
	"Marksman": {"name": "Deadeye Volley", "blurb": "Marksmen hit +30% harder against wounded foes and slow their target for 4 ticks.", "effects": [{"to": ["Marksman"], "execute": 0.30, "chill": 4}]},
	"Fighter": {"name": "Berserk Charge", "blurb": "Fighters hit +40% harder under half HP and drain 12% of the damage they deal.", "effects": [{"to": ["Fighter"], "rage": 0.40, "lifesteal": 0.12}]},
	"Controller": {"name": "Grand Strategy", "blurb": "Every 6th attack of the whole army stuns its target.", "effects": [{"to": "all", "stun_proc": 6}]},
}

const ROLE_TRAITS: Array = [
	{"id": "iron_wall", "name": "Iron Wall", "role": "Tank", "blurb": "Tanks stand shoulder to shoulder: they take less damage and, from 4, reflect part of it.",
		"tiers": [[2, [{"to": ["Tank"], "armor": 0.05}]],
			[4, [{"to": ["Tank"], "armor": 0.10, "thorns": 0.10}]],
			[6, [{"to": ["Tank"], "armor": 0.15, "thorns": 0.20}]]]},
	{"id": "guardian_aura", "name": "Guardian Aura", "role": "Support", "blurb": "Supports mend themselves over time and, from 4, shield the whole army from some damage.",
		"tiers": [[2, [{"to": ["Support"], "mend_self": 0.03}]],
			[4, [{"to": ["Support"], "mend_self": 0.05}, {"to": "all", "armor": 0.03}]],
			[6, [{"to": ["Support"], "mend_self": 0.07}, {"to": "all", "armor": 0.05}]]]},
	{"id": "shadow_strike", "name": "Shadow Strike", "role": "Assassin", "blurb": "Assassins strike from the dark: they finish wounded foes and, from 4, open with a harder first strike.",
		"tiers": [[2, [{"to": ["Assassin"], "execute": 0.15}]],
			[4, [{"to": ["Assassin"], "execute": 0.30, "opener": 0.25}]],
			[6, [{"to": ["Assassin"], "execute": 0.50, "opener": 0.50}]]]},
	{"id": "arcane_surge", "name": "Arcane Surge", "role": "Mage", "blurb": "Mages draw on each other's power: their spells splash onto the neighbours and, at 6, set the target ablaze.",
		"tiers": [[2, [{"to": ["Mage"], "splash": 0.15}]],
			[4, [{"to": ["Mage"], "splash": 0.25}]],
			[6, [{"to": ["Mage"], "splash": 0.40, "burn": 0.15}]]]},
	{"id": "eagle_eye", "name": "Eagle Eye", "role": "Marksman", "blurb": "Marksmen pin their targets down: arrows slow, and from 4 every kill sharpens the aim.",
		"tiers": [[2, [{"to": ["Marksman"], "chill": 3}]],
			[4, [{"to": ["Marksman"], "chill": 5, "frenzy": 0.04}]],
			[6, [{"to": ["Marksman"], "chill": 6, "frenzy": 0.06}]]]},
	{"id": "warband", "name": "Warband", "role": "Fighter", "blurb": "Fighters charge as one band: each kill fires them up, wounded Fighters rage and, at 6, drain life.",
		"tiers": [[2, [{"to": ["Fighter"], "frenzy": 0.04}]],
			[4, [{"to": ["Fighter"], "frenzy": 0.07, "rage": 0.15}]],
			[6, [{"to": ["Fighter"], "frenzy": 0.10, "rage": 0.30, "lifesteal": 0.10}]]]},
	{"id": "tacticians_command", "name": "Tactician's Command", "role": "Controller", "blurb": "Controllers give orders: they stun with their attacks and, from 4, the units next to them hit harder.",
		"tiers": [[2, [{"to": ["Controller"], "stun_proc": 5}]],
			[4, [{"to": ["Controller"], "stun_proc": 4, "aura_atk": 0.05}]],
			[6, [{"to": ["Controller"], "stun_proc": 3, "aura_atk": 0.08}]]]},
]

const DUO_COMBOS: Array = [
	{"id": "frontline_shield", "name": "Frontline Shield", "needs": {"Tank": DUO_UNITS, "Support": DUO_UNITS}, "blurb": "A Tank and a Support raise a shield over the army: every unit takes 6% less damage.",
		"effects": [{"to": "all", "armor": 0.06}]},
	{"id": "glass_cannon", "name": "Glass Cannon", "needs": {"Assassin": DUO_UNITS, "Mage": DUO_UNITS}, "blurb": "Assassins and Mages set targets ablaze (15% of ATK) and explode for 40% of ATK when they fall.",
		"effects": [{"to": ["Assassin", "Mage"], "burn": 0.15, "death_burst": 0.40}]},
	{"id": "snipers_nest", "name": "Sniper's Nest", "needs": {"Marksman": DUO_UNITS, "Tank": DUO_UNITS}, "blurb": "A Tank covers the Marksmen: they open with a +40% first shot and dodge every 5th hit.",
		"effects": [{"to": ["Marksman"], "opener": 0.40, "evade": 5}]},
	{"id": "pincer_strike", "name": "Pincer Strike", "needs": {"Assassin": DUO_UNITS, "Fighter": DUO_UNITS}, "blurb": "Assassins and Fighters close in from both sides: every 4th attack stuns the target.",
		"effects": [{"to": ["Assassin", "Fighter"], "stun_proc": 4}]},
	{"id": "arcane_ward", "name": "Arcane Ward", "needs": {"Mage": DUO_UNITS, "Support": DUO_UNITS}, "blurb": "A Support wards the Mages: they dodge every 5th hit.",
		"effects": [{"to": ["Mage"], "evade": 5}]},
	{"id": "battle_plan", "name": "Battle Plan", "needs": {"Controller": DUO_UNITS, "Fighter": DUO_UNITS}, "blurb": "A Controller plans the assault: every kill fires the Fighters up (+5% ATK per kill).",
		"effects": [{"to": ["Fighter"], "frenzy": 0.05}]},
	{"id": "vanguard_line", "name": "Vanguard Line", "needs": {"Tank": DUO_UNITS, "Fighter": DUO_UNITS}, "blurb": "A Tank anchors the front: Fighters reflect 10% of the damage they take and Tanks guard the allies around them (-6%).",
		"effects": [{"to": ["Fighter"], "thorns": 0.10}, {"to": ["Tank"], "guard": 0.06}]},
	{"id": "command_post", "name": "Command Post", "needs": {"Controller": DUO_UNITS, "Tank": DUO_UNITS}, "blurb": "A Controller directs the Tanks from behind cover: Tanks take 8% less damage.",
		"effects": [{"to": ["Tank"], "armor": 0.08}]},
	{"id": "field_medic", "name": "Field Medic", "needs": {"Support": DUO_UNITS, "Fighter": DUO_UNITS}, "blurb": "A Support patches up the Fighters: they heal 4% of their HP every 8 ticks.",
		"effects": [{"to": ["Fighter"], "mend_self": 0.04}]},
	{"id": "covering_fire", "name": "Covering Fire", "needs": {"Marksman": DUO_UNITS, "Support": DUO_UNITS}, "blurb": "A Support covers the Marksmen: they drain 10% of the damage they deal.",
		"effects": [{"to": ["Marksman"], "lifesteal": 0.10}]},
	{"id": "spellblade", "name": "Spellblade", "needs": {"Mage": DUO_UNITS, "Fighter": DUO_UNITS}, "blurb": "Steel and sorcery side by side: Mages and Fighters burn their targets (12% of ATK).",
		"effects": [{"to": ["Mage", "Fighter"], "burn": 0.12}]},
	{"id": "crossfire", "name": "Crossfire", "needs": {"Marksman": DUO_UNITS, "Assassin": DUO_UNITS}, "blurb": "Marksmen pin the target while Assassins strike: both deal +20% to wounded enemies.",
		"effects": [{"to": ["Marksman", "Assassin"], "execute": 0.20}]},
	{"id": "arcane_tactics", "name": "Arcane Tactics", "needs": {"Controller": DUO_UNITS, "Mage": DUO_UNITS}, "blurb": "A Controller sharpens the Mages' focus: their spells slow for 3 ticks, Controllers mend 4% HP every 8 ticks.",
		"effects": [{"to": ["Mage"], "chill": 3}, {"to": ["Controller"], "mend_self": 0.04}]},
	{"id": "ambush_plan", "name": "Ambush Plan", "needs": {"Assassin": DUO_UNITS, "Controller": DUO_UNITS}, "blurb": "A Controller marks the way in: Assassins open with a +50% first strike.",
		"effects": [{"to": ["Assassin"], "opener": 0.50}]},
	{"id": "spell_bastion", "name": "Spell Bastion", "needs": {"Tank": DUO_UNITS, "Mage": DUO_UNITS}, "blurb": "Tanks hold the line for the Mages: Mages take 8% less damage and Tanks reflect 10%.",
		"effects": [{"to": ["Mage"], "armor": 0.08}, {"to": ["Tank"], "thorns": 0.10}]},
	{"id": "war_council", "name": "War Council", "needs": {"Support": DUO_UNITS, "Controller": DUO_UNITS}, "blurb": "Support and Controller share one plan: every unit mends 2% of its HP every 8 ticks.",
		"effects": [{"to": "all", "mend_self": 0.02}]},
	{"id": "bait_and_strike", "name": "Bait and Strike", "needs": {"Tank": DUO_UNITS, "Assassin": DUO_UNITS}, "blurb": "A Tank draws the enemy's attention while Assassins slip in: Tanks reflect 15%, Assassins open with +30%.",
		"effects": [{"to": ["Tank"], "thorns": 0.15}, {"to": ["Assassin"], "opener": 0.30}]},
	{"id": "venom_vial", "name": "Venom Vial", "needs": {"Assassin": DUO_UNITS, "Support": DUO_UNITS}, "blurb": "A Support coats the blades: Assassins poison their targets (20% of ATK over time).",
		"effects": [{"to": ["Assassin"], "burn": 0.20}]},
	{"id": "hold_the_line", "name": "Hold the Line", "needs": {"Fighter": DUO_UNITS, "Marksman": DUO_UNITS}, "blurb": "Fighters screen the Marksmen: Fighters take 8% less damage, Marksmen deal +15% to wounded enemies.",
		"effects": [{"to": ["Fighter"], "armor": 0.08}, {"to": ["Marksman"], "execute": 0.15}]},
	{"id": "ranged_barrage", "name": "Ranged Barrage", "needs": {"Mage": DUO_UNITS, "Marksman": DUO_UNITS}, "blurb": "Spells and arrows rain together: Mages and Marksmen splash 15% onto the neighbours.",
		"effects": [{"to": ["Mage", "Marksman"], "splash": 0.15}]},
	{"id": "target_painting", "name": "Target Painting", "needs": {"Marksman": DUO_UNITS, "Controller": DUO_UNITS}, "blurb": "A Controller marks the targets: Marksmen deal +20% to wounded enemies, Controllers slow for 4 ticks.",
		"effects": [{"to": ["Marksman"], "execute": 0.20}, {"to": ["Controller"], "chill": 4}]},
	{"id": "grand_army", "name": "Grand Army", "needs": {"Tank": 2, "Support": 2, "Assassin": 2, "Mage": 2, "Marksman": 2, "Fighter": 2, "Controller": 2},
		"blurb": "All 7 roles fight together, 2 units of each (14 units): every unit takes 5% less damage and drains 5% of the damage it deals.", "effects": [{"to": "all", "armor": 0.05, "lifesteal": 0.05}]},
]


## 4. Faction traits: every faction has one own special effect, scaled by the same tiers as its Faction Tier (index 0 = Rally at 2 units, 1 = Legion at 4, 2 = Host at 6;
##    Ultra uses index 2 made stronger by ULTRA_SCALE). A trait only affects the units of ITS faction, and only on the home continent.
##    Each effect value is a [Rally, Legion, Host] list; a 0 means "not yet" (e.g. a death burst that only appears at Host).
const FACTION_TRAITS: Dictionary = {
	"solvaris": {"name": "Dawn Ward", "blurb": "The sun's blessing slowly mends the whole faction.",
		"effects": [{"to": "all", "mend_self": [0.02, 0.03, 0.04]}]},
	"nocthyr": {"name": "Nightfall", "blurb": "Nocthyr strikers open the fight with a hard first strike under cover of night.",
		"effects": [{"to": ["Assassin", "Marksman"], "opener": [0.15, 0.30, 0.50]}]},
	"valdoria": {"name": "Rally the Banner", "blurb": "Valdoria's banner inspires the units beside Fighters and keeps Supports mending.",
		"effects": [{"to": ["Fighter"], "aura_atk": [0.03, 0.05, 0.08]}, {"to": ["Support"], "mend_self": [0.02, 0.03, 0.05]}]},
	"elarion": {"name": "Moonlit Focus", "blurb": "Moonlight chills the foes the casters focus on.",
		"effects": [{"to": ["Mage", "Controller"], "chill": [2, 3, 4]}]},
	"astralis": {"name": "Star Charts", "blurb": "Star-guided casters and shooters dodge hits; at 6 units Mage spells splash.",
		"effects": [{"to": ["Mage", "Marksman"], "evade": [6, 5, 4]}, {"to": ["Mage"], "splash": [0, 0, 0.20]}]},
	"ignivar": {"name": "Wildfire", "blurb": "Fire spreads through the ranks: every attack of the faction burns its target.",
		"effects": [{"to": "all", "burn": [0.05, 0.08, 0.12]}]},
	"cryndel": {"name": "Frost Armor", "blurb": "A shell of ice cuts the damage the frontline takes and, from 4 units, slows attackers' targets.",
		"effects": [{"to": ["Tank", "Fighter", "Support"], "armor": [0.04, 0.07, 0.10]}, {"to": ["Tank", "Fighter", "Support"], "chill": [0, 2, 3]}]},
	"umbrael": {"name": "Umbral Step", "blurb": "Shadows let Assassins and Mages slip away from hits; at 6 units Assassins open with a deadly first strike.",
		"effects": [{"to": ["Assassin", "Mage"], "evade": [6, 5, 4]}, {"to": ["Assassin"], "opener": [0, 0, 0.40]}]},
	"ferrum": {"name": "Forged Hulls", "blurb": "Ferrum plating deflects part of every hit on the whole faction.",
		"effects": [{"to": "all", "armor": [0.02, 0.04, 0.06]}]},
	"voltrix": {"name": "Overcharge", "blurb": "Overcharged Marksmen shock their targets: every few shots stun.",
		"effects": [{"to": ["Marksman"], "stun_proc": [6, 5, 4]}]},
	"chronex": {"name": "Time Dilation", "blurb": "Frontliners slip out of the clock's way, dodging hits; at 6 units they open with a faster first strike.",
		"effects": [{"to": ["Tank", "Fighter", "Assassin"], "evade": [6, 5, 4]}, {"to": ["Tank", "Fighter", "Assassin"], "opener": [0, 0, 0.30]}]},
	"nexaris": {"name": "Linked Network", "blurb": "Controllers and Supports link up: the units next to them hit harder, and the whole faction mends a little.",
		"effects": [{"to": ["Controller", "Support"], "aura_atk": [0.03, 0.05, 0.08]}, {"to": "all", "mend_self": [0.01, 0.02, 0.03]}]},
	"verdantia": {"name": "Lifebloom", "blurb": "Life magic makes Supports and Controllers heal themselves steadily.",
		"effects": [{"to": ["Support", "Controller"], "mend_self": [0.03, 0.05, 0.08]}]},
	"besthara": {"name": "Pack Instinct", "blurb": "The pack hunts together: every kill whips Fighters and Assassins into a frenzy.",
		"effects": [{"to": ["Fighter", "Assassin"], "frenzy": [0.03, 0.05, 0.08]}]},
	"floralis": {"name": "Petal Veil", "blurb": "Petals veil the backline: the allies around Supports, Mages and Marksmen take less damage.",
		"effects": [{"to": ["Support", "Mage", "Marksman"], "guard": [0.03, 0.05, 0.08]}]},
	"terragorn": {"name": "Stone Skin", "blurb": "Stone-hard hides: Tanks and Fighters take much less damage.",
		"effects": [{"to": ["Tank", "Fighter"], "armor": [0.04, 0.07, 0.11]}]},
	"drakhan": {"name": "Dragon's Might", "blurb": "Dragon blood burns brighter when wounded: every unit of the faction rages under half HP.",
		"effects": [{"to": "all", "rage": [0.05, 0.10, 0.15]}]},
	"inferna": {"name": "Hellfire", "blurb": "Hellfire fuels the whole faction: its units burst into flames when they fall.",
		"effects": [{"to": "all", "death_burst": [0.15, 0.30, 0.50]}]},
	"bloodfang": {"name": "Bloodlust", "blurb": "The scent of blood drives Fighters and Assassins to drain life with every blow.",
		"effects": [{"to": ["Fighter", "Assassin"], "lifesteal": [0.04, 0.07, 0.10]}]},
	"warborn": {"name": "War Cry", "blurb": "A war cry lifts the whole faction: every unit rallies the allies next to it.",
		"effects": [{"to": "all", "aura_atk": [0.02, 0.03, 0.04]}]},
	"abyssal": {"name": "Crushing Depths", "blurb": "The pressure of the deep crushes attackers: Tanks and Mages reflect part of the damage they take.",
		"effects": [{"to": ["Tank", "Mage"], "thorns": [0.05, 0.10, 0.16]}]},
	"pelagia": {"name": "Tidal Blessing", "blurb": "Tides wash over the support line: Supports, Controllers and Mages mend themselves.",
		"effects": [{"to": ["Support", "Controller", "Mage"], "mend_self": [0.02, 0.03, 0.05]}]},
	"tempestra": {"name": "Storm Surge", "blurb": "Storm winds stun: every few attacks of Assassins and Fighters daze the target.",
		"effects": [{"to": ["Assassin", "Fighter"], "stun_proc": [7, 6, 5]}]},
	"corsaria": {"name": "Plunder", "blurb": "Raiders grab every edge: the whole faction finishes wounded enemies harder.",
		"effects": [{"to": "all", "execute": [0.08, 0.12, 0.20]}]},
	"solstice": {"name": "Radiant Zenith", "blurb": "Zenith light turns aside blows on Tanks and Supports, and fallen units heal their neighbours.",
		"effects": [{"to": ["Tank", "Support"], "armor": [0.03, 0.05, 0.08]}, {"to": "all", "last_rites": [0.03, 0.05, 0.08]}]},
	"paradox": {"name": "Paradox Loop", "blurb": "Backline units loop through time: they dodge hits and, at 6 units, return once after falling.",
		"effects": [{"to": ["Marksman", "Mage", "Controller"], "evade": [7, 6, 5]}, {"to": ["Marksman", "Mage", "Controller"], "second_life": [0, 0, 0.30]}]},
	"eternis": {"name": "Eternal Bulwark", "blurb": "Eternity wears down nothing: Tanks, Supports and Mages take less damage and, at 6 units, return once after falling.",
		"effects": [{"to": ["Tank", "Support", "Mage"], "armor": [0.03, 0.05, 0.08]}, {"to": ["Tank", "Support", "Mage"], "second_life": [0, 0, 0.25]}]},
	"oblivion": {"name": "Void Hunger", "blurb": "The void feeds Assassins and Mages: they drain life and finish wounded foes.",
		"effects": [{"to": ["Assassin", "Mage"], "lifesteal": [0.05, 0.08, 0.12]}, {"to": ["Assassin", "Mage"], "execute": [0.05, 0.10, 0.15]}]},
}


## FACTION TIER: the Faction Banner bonus and the faction trait fused into one tier of one faction (same numbers as before).
## Returns {} below 2 units, otherwise {"faction", "count", "name" (Rally / Legion / Host / Ultra), "ultra", "bonus" (HP and ATK fraction),
## "next" (units for the next tier, 0 = top), "trait" (trait name), "trait_blurb", "trait_effects" (plain effects, like a combo's)}.
static func faction_tier(fac: String, n: int, ultra: bool = false) -> Dictionary:
	var tier_name := faction_tier_name(n, ultra)
	if tier_name == "":
		return {}
	var t := faction_trait(fac)
	return {"faction": fac, "count": n, "name": tier_name, "ultra": ultra, "bonus": faction_bonus(n, ultra), "next": faction_next_tier(n),
		"trait": String(t.get("name", "")), "trait_blurb": String(t.get("blurb", "")), "trait_effects": faction_trait_effects(fac, n, ultra),
		"special": String(ULTRA_FACTION_SPECIAL["name"]) if ultra else "", "special_effects": ULTRA_FACTION_SPECIAL["effects"] if ultra else []}


## One line for a Faction Tier: "Dawn Ward: Army mend 4% HP / 8 ticks" ("" for an empty tier).
static func faction_tier_text(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var parts: Array[String] = []
	if float(info["bonus"]) != 0.0:
		parts.append("%+d%% HP and ATK" % int(round(float(info["bonus"]) * 100.0)))
	var fx: Array = info["trait_effects"]
	if not fx.is_empty():
		parts.append("%s: %s" % [info["trait"], effects_text(fx)])
	if String(info.get("special", "")) != "":
		parts.append("%s: %s" % [info["special"], effects_text(info["special_effects"])])
	return "; ".join(parts)


## Faction Banner bonus (fraction of HP and ATK) for `n` units of one home faction.
static func faction_bonus(n: int, ultra: bool = false) -> float:
	if ultra:
		return FACTION_ULTRA_BONUS
	for t in FACTION_TIERS:
		if n >= int(t[0]):
			return float(t[1])
	return 0.0


## "Rally" / "Legion" / "Host" / "Ultra" ("" below 2 units).
static func faction_tier_name(n: int, ultra: bool = false) -> String:
	if ultra:
		return ULTRA_NAME
	for t in FACTION_TIERS:
		if n >= int(t[0]):
			return String(t[2])
	return ""


## Units needed for the next Faction Banner tier (0 = already at the top).
static func faction_next_tier(n: int) -> int:
	var nxt := 0
	for t in FACTION_TIERS:
		if n < int(t[0]):
			nxt = int(t[0])
	return nxt


## Faction of an ULTRA line-up: `unit_facs` = the faction of every unit ("" for a unit without a home faction). Returns that faction when
## all units share it and there are at least ULTRA_MIN of them, otherwise "".
static func faction_ultra(unit_facs: Array) -> String:
	if unit_facs.size() < ULTRA_MIN:
		return ""
	var first := String(unit_facs[0])
	if first == "":
		return ""
	for f in unit_facs:
		if String(f) != first:
			return ""
	return first


## Role of an ULTRA line-up (role counts {"Tank": 8}): the role when ALL units have it and there are at least ULTRA_MIN, otherwise "".
static func role_ultra(counts: Dictionary) -> String:
	var total := 0
	for r in counts:
		total += int(counts[r])
	if total < ULTRA_MIN:
		return ""
	for r in counts:
		if int(counts[r]) == total:
			return String(r)
	return ""


## One special-effect value made stronger by `k` (Ultra): fractions and ticks x k, counts / k (never below FX_COUNT_MIN), capped by FX_CAP.
static func scaled_fx_value(key: String, v: float, k: float) -> float:  # counts / k (never below FX_COUNT_MIN)
	if FX_COUNT.has(key):
		return maxf(FX_COUNT_MIN, float(int(round(v / k))))
	if FX_TICKS.has(key):
		return float(int(round(v * k)))
	return minf(v * k, float(FX_CAP.get(key, 99.0)))


## Copy of `effects` made stronger by `k`: stat keys (hp / atk / shield) x k (move / range stay), special effects by scaled_fx_value.
static func scaled_effects(effects: Array, k: float) -> Array:
	var out: Array = []
	for e in effects:
		var r: Dictionary = (e as Dictionary).duplicate()
		for key in ["hp", "atk", "shield"]:
			if r.has(key):
				r[key] = float(r[key]) * k
		for key in FX_TYPES:
			if r.has(key):
				r[key] = scaled_fx_value(key, float(r[key]), k)
				if FX_COUNT.has(key) or FX_TICKS.has(key):
					r[key] = int(r[key])
		out.append(r)
	return out


## Effects of a role trait for `n` units of its role; `counts` (all role counts of the line-up) decides if it is ULTRA. [] below 2 units.
static func role_effects(combo: Dictionary, n: int, counts: Dictionary = {}) -> Array:
	var ti := role_tier_index(combo, n)
	if ti < 0:
		return []
	var tiers: Array = combo["tiers"]
	if role_ultra(counts) == String(combo["role"]):
		return scaled_effects(tiers[tiers.size() - 1][1], ULTRA_SCALE) + role_ultra_special_effects(String(combo["role"]))
	return tiers[ti][1]


## The special effect of an ULTRA role trait ({"name", "blurb", "effects"}); {} for a role without one.
static func role_ultra_special(role: String) -> Dictionary:
	return ULTRA_ROLE_SPECIALS.get(role, {})


static func role_ultra_special_effects(role: String) -> Array:
	return role_ultra_special(role).get("effects", [])


## Index of the highest tier of a role trait reached with `n` units (-1 = none).
static func role_tier_index(combo: Dictionary, n: int) -> int:
	var idx := -1
	var tiers: Array = combo["tiers"]
	for i in range(tiers.size()):
		if n >= int(tiers[i][0]):
			idx = i
	return idx


## Units needed for the next tier of a role trait (0 = already at the top).
static func role_next_tier(combo: Dictionary, n: int) -> int:
	for t in combo["tiers"]:
		if n < int(t[0]):
			return int(t[0])
	return 0


static func role_trait_of(role: String) -> Dictionary:
	for c in ROLE_TRAITS:
		if String(c["role"]) == role:
			return c
	return {}


## Roles a duo combo still lacks ([] = active).
static func missing(combo: Dictionary, counts: Dictionary) -> Array:
	var out: Array = []
	var needs: Dictionary = combo["needs"]
	for r in needs:
		if int(counts.get(r, 0)) < int(needs[r]):
			out.append(String(r))
	return out


## Every active combo of a line-up (role counts {"Tank": 2, ...}) as {"name", "kind": "role"|"duo", "tier", "effects"}.
static func active(counts: Dictionary) -> Array:
	var out: Array = []
	for c in ROLE_TRAITS:
		var n := int(counts.get(c["role"], 0))
		var ti := role_tier_index(c, n)
		if ti >= 0:
			var ult := role_ultra(counts) == String(c["role"])
			out.append({"name": c["name"], "kind": "role", "tier": ti + 1, "count": n, "ultra": ult, "effects": role_effects(c, n, counts)})
	for c in DUO_COMBOS:
		if missing(c, counts).is_empty():
			out.append({"name": c["name"], "kind": "duo", "tier": 1, "count": 0, "effects": c["effects"]})
	return out


## Units each faction of `continent_facs` (faction ids) still lacks for Grand Army (Faction): {faction: units lacking} ({} = active).
## `fac_counts` = home-faction units on the field ({"solvaris": 2, ...}). Returns every faction as missing when the list is empty-handed.
static func faction_army_missing(fac_counts: Dictionary, continent_facs: Array) -> Dictionary:
	var out := {}
	for f in continent_facs:
		var lack := FACTION_ARMY_MIN - int(fac_counts.get(String(f), 0))
		if lack > 0:
			out[String(f)] = lack
	return out


## Home-faction units of the continent's factions on the field.
static func faction_army_total(fac_counts: Dictionary, continent_facs: Array) -> int:
	var total := 0
	for f in continent_facs:
		total += int(fac_counts.get(String(f), 0))
	return total


## Units still lacking for Grand Army (Faction): the larger of "units the thin factions lack" and "units short of FACTION_ARMY_TOTAL" (0 = active).
static func faction_army_lacking(fac_counts: Dictionary, continent_facs: Array) -> int:
	var per_faction := 0
	var missing := faction_army_missing(fac_counts, continent_facs)
	for f in missing:
		per_faction += int(missing[f])
	return maxi(per_faction, FACTION_ARMY_TOTAL - faction_army_total(fac_counts, continent_facs))


## True when EVERY faction of the continent fields FACTION_ARMY_MIN or more units AND they total FACTION_ARMY_TOTAL (Grand Army, Faction version).
static func faction_army_active(fac_counts: Dictionary, continent_facs: Array) -> bool:
	return not continent_facs.is_empty() and faction_army_lacking(fac_counts, continent_facs) == 0


## Index of the Faction Banner tier reached with `n` units of one faction (0 = Rally, 1 = Legion, 2 = Host, -1 = none).
static func faction_tier_index(n: int) -> int:
	if n >= int(FACTION_TIERS[0][0]):
		return 2
	if n >= int(FACTION_TIERS[1][0]):
		return 1
	if n >= int(FACTION_TIERS[2][0]):
		return 0
	return -1


## The faction's own trait ({"name", "blurb", "effects"}); {} for a faction without one.
static func faction_trait(fac: String) -> Dictionary:
	return FACTION_TRAITS.get(fac, {})


## The trait of `fac` resolved for `n` units of that faction: a list of plain effects ({"to", "hp", "atk", ...} with numbers,
## zero values left out), the same shape as the effects of a combo. [] when the faction has no trait or fewer than 2 units.
static func faction_trait_effects(fac: String, n: int, ultra: bool = false) -> Array:
	var out: Array = []
	var ti := FACTION_ULTRA_TRAIT_INDEX if ultra else faction_tier_index(n)
	var t := faction_trait(fac)
	if ti < 0 or t.is_empty():
		return out
	for e in t["effects"]:
		var r := {"to": e["to"]}
		for k in STAT_KEYS + FX_TYPES:
			if e.has(k) and float(e[k][ti]) != 0.0:
				r[k] = int(e[k][ti]) if (k == "move" or k == "range" or FX_COUNT.has(k) or FX_TICKS.has(k)) else float(e[k][ti])
		if r.size() > 1:
			out.append(r)
	return scaled_effects(out, ULTRA_SCALE) if ultra else out


static func _new_mods() -> Dictionary:
	return {"hp": 0.0, "atk": 0.0, "move": 0, "shield": 0.0, "range": 0, "fx": {}}


## Adds one special effect to a unit's fx dictionary: counts keep the lowest (best), ticks and second_life the highest, fractions add up (capped by FX_CAP).
static func _add_fx(fx: Dictionary, key: String, v: float) -> void:
	if v == 0.0:
		return
	if not fx.has(key):
		fx[key] = v
	elif FX_COUNT.has(key):
		fx[key] = maxf(FX_COUNT_MIN, minf(float(fx[key]), v))
	elif FX_TICKS.has(key) or key == "second_life":
		fx[key] = maxf(float(fx[key]), v)
	else:
		fx[key] = float(fx[key]) + v
	if FX_CAP.has(key):
		fx[key] = minf(float(fx[key]), float(FX_CAP[key]))


static func _add_effects(m: Dictionary, effects: Array, role: String) -> void:
	for e in effects:
		var to: Variant = e["to"]
		if not (typeof(to) == TYPE_STRING or (to as Array).has(role)):
			continue
		m["hp"] += float(e.get("hp", 0.0))
		m["atk"] += float(e.get("atk", 0.0))
		m["shield"] += float(e.get("shield", 0.0))
		m["move"] += int(e.get("move", 0))
		m["range"] += int(e.get("range", 0))
		for k in FX_TYPES:
			if e.has(k):
				_add_fx(m["fx"], k, float(e[k]))


## Summed modifiers for one unit of `role`: {"hp", "atk", "move", "shield", "range", "fx"}; "fx" = {special effect: value} (see FX_TYPES). The stat keys stay 0 / empty,
## because no synergy gives a stat bonus any more. `fac` / `fac_n` (the unit's faction and how many units of it are on the field) add the faction's own trait on top of the role and duo combos.
static func unit_mods(role: String, counts: Dictionary, fac: String = "", fac_n: int = 0, fac_ultra: bool = false, fac_army: bool = false, bond: Dictionary = {}) -> Dictionary:
	var m := _new_mods()
	for a in active(counts):
		_add_effects(m, a["effects"], role)
	if fac != "":
		_add_effects(m, faction_trait_effects(fac, fac_n, fac_ultra), role)
		if fac_ultra:
			_add_effects(m, ULTRA_FACTION_SPECIAL["effects"], role)  # Ultra special: Ultra Dominion
	if fac_army:
		_add_effects(m, FACTION_ARMY["effects"], role)  # Grand Army (Faction)
	if not bond.is_empty():
		_add_effects(m, bond["effects"], role)  # Continent Bond
	return m


## Continents that still lack a faction group of BOND_FACTION_UNITS units for the Continent Bond (continent ids; [] = every continent is covered).
## `best` = per continent the units of its best-staffed faction on the field ({"aetherion": 2, "arcanum": 3, ...}).
static func bond_missing(best: Dictionary) -> Array:
	var out: Array = []
	for cid in CONTINENT_BONDS:
		if int(best.get(cid, 0)) < BOND_FACTION_UNITS:
			out.append(cid)
	return out


## The Continent Bond of a side: {"names": [name of its King's continent bond], "effects": [that effect]}; {} unless every continent has a faction group of
## BOND_FACTION_UNITS units, or the King's continent is unknown (no King).
static func bonds_for(best: Dictionary, king_continent: String) -> Dictionary:
	if not CONTINENT_BONDS.has(king_continent) or not bond_missing(best).is_empty():
		return {}
	var b: Dictionary = CONTINENT_BONDS[king_continent]
	return {"names": [String(b["name"])], "effects": b["effects"], "continent": king_continent}


## The Continent Bond of a continent ({} = unknown continent).
static func continent_bond(continent_id: String) -> Dictionary:
	return CONTINENT_BONDS.get(continent_id, {})


## Like unit_mods but ONLY from the duo combos (for tests and tooltips).
static func duo_mods(role: String, counts: Dictionary) -> Dictionary:
	var m := _new_mods()
	for a in active(counts):
		if String(a["kind"]) == "duo":
			_add_effects(m, a["effects"], role)
	return m


## Units a duo combo still lacks as {role: units} ({} = active).
static func missing_units(combo: Dictionary, counts: Dictionary) -> Dictionary:
	var out := {}
	var needs: Dictionary = combo["needs"]
	for r in needs:
		var lack := int(needs[r]) - int(counts.get(r, 0))
		if lack > 0:
			out[String(r)] = lack
	return out


## 3 -> "3rd", 4 -> "4th", 6 -> "6th".
static func _ordinal(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "%dth" % n
	match n % 10:
		1: return "%dst" % n
		2: return "%dnd" % n
		3: return "%drd" % n
	return "%dth" % n


## Short UI text of one special effect: fx_text("burn", 0.15) = "burn 15% ATK".
static func fx_text(key: String, v: float) -> String:
	var pct := int(round(v * 100.0))
	match key:
		"armor": return "-%d%% damage taken" % pct
		"evade": return "dodge every %s hit" % _ordinal(int(v))
		"thorns": return "reflect %d%% damage" % pct
		"execute": return "+%d%% vs wounded foes" % pct
		"frenzy": return "+%d%% ATK per kill" % pct
		"rage": return "+%d%% ATK under half HP" % pct
		"aura_atk": return "neighbours +%d%% ATK" % pct
		"burn": return "burn %d%% ATK" % pct
		"stun_proc": return "every %s attack stuns" % _ordinal(int(v))
		"splash": return "%d%% splash" % pct
		"lifesteal": return "%d%% lifesteal" % pct
		"chill": return "slow %d ticks" % int(v)
		"opener": return "+%d%% first strike" % pct
		"last_rites": return "heal neighbours %d%% on death" % pct
		"death_burst": return "%d%% ATK blast on death" % pct
		"mend_self": return "mend %d%% HP / 8 ticks" % pct
		"guard": return "allies within 2: -%d%% damage" % pct
		"second_life": return "returns once at %d%% HP" % pct
	return "%s %s" % [key, str(v)]


## "Tank: reflect 10% damage", "Army: -5% damage taken": a short line for the UI.
static func effects_text(effects: Array) -> String:
	var parts: Array[String] = []
	for e in effects:
		var who := "Army" if typeof(e["to"]) == TYPE_STRING else "/".join(PackedStringArray(e["to"]))
		var bits: Array[String] = []
		for k in FX_TYPES:
			if e.has(k):
				bits.append(fx_text(k, float(e[k])))
		if e.has("hp"):
			bits.append("%+d%% HP" % int(round(float(e["hp"]) * 100.0)))
		if e.has("atk"):
			bits.append("%+d%% ATK" % int(round(float(e["atk"]) * 100.0)))
		if e.has("shield"):
			bits.append("%d%% opening shield" % int(round(float(e["shield"]) * 100.0)))
		if e.has("move"):
			bits.append("%+d move" % int(e["move"]))
		if e.has("range"):
			bits.append("%+d range" % int(e["range"]))
		parts.append("%s %s" % [who, ", ".join(bits)])
	return "; ".join(parts)
