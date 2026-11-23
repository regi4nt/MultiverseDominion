class_name BattleUnit
extends RefCounted
## A unit fighting on the 8x8 Battle Board (regular unit or Champion/King).

var uid: int = 0
var side: int = 0  # 0 = bottom (rows 4-7), 1 = top (rows 0-3)
var card_id: String = ""
var is_king: bool = false
var is_monster: bool = false  # a wild territory monster (foe) or a tamed Monster card fighting beside the King
var display_name: String = ""
var chess: String = "pawn"
var role: String = "Fighter"
var faction: String = ""
var stars: int = 1
var max_hp: int = 1
var hp: int = 1
var base_atk: int = 1
var atk_range: int = 1
var move: int = 1
var skill_id: String = ""
var skill_value: float = 0.0  # champion active skill strength (data: active_value)
var params: Dictionary = {}  # per-continent skill numbers (data: skill.params); empty = base values
var extra: String = ""  # the card's continent buff: effect type (data/card_buffs.json), see CardDatabase.BUFF_TYPES
var extra_value: float = 0.0  # strength of the buff (a count for evade / stun_proc / chill)
var kills: int = 0
var burn_until: int = 0
var burn_amount: int = 0
var buff_next_tick: int = 0
var strike_bonus: float = 0.0  # Knight (Assassin): damage bonus of the next attack, set by the teleport
var second_life_used: bool = false
var cell: Vector2i = Vector2i.ZERO
var alive: bool = true
var shield: int = 0

var attacks_made: int = 0
var hits_taken: int = 0
var next_attack_tick: int = 0
var next_skill_tick: int = 0
var stun_until: int = 0
var slow_until: int = 0
var taunt_uid: int = -1
var taunt_until: int = 0
var buff_mult: float = 1.0
var buff_until: int = 0
var reduce_until: int = 0
var brace_active: bool = false
var opened: bool = false
