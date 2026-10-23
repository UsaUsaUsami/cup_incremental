class_name Data
extends RefCounted
## カード・敵・レリックの定義と、強化後の値を引く道具。
## デッキの1枚は文字列で持つ。強化済みは末尾に "+" を付ける（例: "add+"）。

# up: 強化したときに上書きする値。val はゲートの効き目（+3 の 3 など）
const CARDS := {
	"add": {"name": "+3", "cost": 1, "gate": "add", "val": 3.0, "price": 45, "up": {"name": "+5", "val": 5.0}},
	"mul": {"name": "×2", "cost": 1, "gate": "mul", "val": 2.0, "price": 55, "up": {"name": "×3", "val": 3.0}},
	"sq": {"name": "x²", "cost": 2, "gate": "sq", "price": 75, "up": {"cost": 1}},
	"bounce": {"name": "跳ね返し", "cost": 1, "gate": "bounce", "price": 55, "up": {"cost": 0}},
	"right": {"name": "右へ", "cost": 0, "gate": "right", "price": 45, "up": {"uses_bonus": 4}},
	"left": {"name": "左へ", "cost": 0, "gate": "left", "price": 45, "up": {"uses_bonus": 4}},
	"cheer": {"name": "応援", "cost": 1, "gate": "cheer", "price": 70, "up": {"cost": 0}},
	"charge": {"name": "充電", "cost": 1, "gate": "charge", "val": 1.0, "price": 55, "up": {"val": 2.0}},
	"shield": {"name": "盾", "cost": 1, "gate": "shield", "val": 1.0, "price": 45, "up": {"val": 2.0}},
	"power": {"name": "発電", "cost": 1, "gate": "power", "val": 5.0, "price": 60, "up": {"val": 3.0}},
	"scout": {"name": "索敵", "cost": 1, "gate": "scout", "val": 3.0, "price": 60, "up": {"val": 2.0}},
	"more": {"name": "玉 +5", "cost": 1, "icon": "玉+", "desc": "注ぐ玉 +%d", "val": 5.0, "price": 50, "up": {"val": 8.0}},
	"guard": {"name": "防御", "cost": 1, "icon": "守", "desc": "ブロック +%d", "val": 7.0, "price": 45, "up": {"val": 11.0}},
	"heal": {"name": "応急手当", "cost": 1, "icon": "癒", "desc": "HP +%d", "val": 6.0, "price": 60, "up": {"val": 10.0}},
	"load": {"name": "増量装填", "cost": 1, "icon": "装", "desc": "弾倉 ×%.1f", "val": 1.5, "price": 65, "up": {"val": 2.0}},
	"burst": {"name": "炸裂弾", "cost": 1, "icon": "爆", "desc": "玉ごと +%d", "val": 2.0, "price": 60, "up": {"val": 4.0}},
	"focus": {"name": "集中", "cost": 0, "icon": "E+", "desc": "エネ+%d・除外", "val": 1.0, "exhaust": true, "price": 55, "up": {"val": 2.0}},
	"refill": {"name": "補充", "cost": 1, "icon": "引", "desc": "カードを%d枚引く", "val": 2.0, "price": 55, "up": {"val": 3.0}},
	"prep": {"name": "下準備", "cost": 0, "icon": "引", "desc": "カードを%d枚引く", "val": 1.0, "price": 45, "up": {"val": 2.0}},
	"save": {"name": "温存", "cost": 1, "icon": "次", "desc": "次ターン エネ+%d", "val": 2.0, "price": 55, "up": {"val": 3.0}},
}
const START_DECK: Array[String] = ["add", "add", "add", "mul", "mul", "sq", "guard", "guard", "shield"]

# 敵の行動（intent）: atk 攻撃 / multi 連続攻撃 / def 守り（弾を防ぐブロック）/ buff 攻撃力アップ /
# fast 次のターンのカップが速い / seal 次のターンにゲート1つが使えない / drain 次のターンのゲート回数 -n
const ENEMIES := {
	"slime": {"name": "スライム", "hp": 38, "hue": 0.5,
		"moves": [{"t": "atk", "n": 6}, {"t": "atk", "n": 6}, {"t": "def", "n": 10}]},
	"goblin": {"name": "ゴブリン", "hp": 46, "hue": 0.28,
		"moves": [{"t": "atk", "n": 7}, {"t": "buff", "n": 2}, {"t": "atk", "n": 7}]},
	"dart": {"name": "吹き矢の小鬼", "hp": 40, "hue": 0.12,
		"moves": [{"t": "multi", "n": 3, "k": 2}, {"t": "fast"}, {"t": "multi", "n": 3, "k": 2}]},
	"golem": {"name": "岩の番人", "hp": 64, "hue": 0.08,
		"moves": [{"t": "def", "n": 16}, {"t": "atk", "n": 11}, {"t": "atk", "n": 9}]},
	"mage": {"name": "封印の術師", "hp": 52, "hue": 0.75,
		"moves": [{"t": "seal"}, {"t": "atk", "n": 9}, {"t": "drain", "n": 2}, {"t": "atk", "n": 9}]},
	"giant": {"name": "鉄の巨人", "hp": 150, "hue": 0.6, "elite": true,
		"moves": [{"t": "atk", "n": 13}, {"t": "def", "n": 25}, {"t": "buff", "n": 3}, {"t": "atk", "n": 13}]},
	"witches": {"name": "双子の魔女", "hp": 125, "hue": 0.85, "elite": true,
		"moves": [{"t": "multi", "n": 5, "k": 3}, {"t": "seal"}, {"t": "drain", "n": 3}, {"t": "atk", "n": 12}]},
	"pegking": {"name": "ペグの王", "hp": 420, "hue": 0.95, "boss": true,
		"rule": "毎ターン、ペグの並びが変わる",
		"moves": [{"t": "atk", "n": 12}, {"t": "def", "n": 30}, {"t": "multi", "n": 6, "k": 3}, {"t": "fast"},
			{"t": "buff", "n": 4}, {"t": "atk", "n": 16}]},
}
const EASY_POOL: Array[String] = ["slime", "goblin", "dart"]
const NORMAL_POOL: Array[String] = ["slime", "goblin", "dart", "golem", "mage"]
const ELITE_POOL: Array[String] = ["giant", "witches"]

const RELICS := {
	"hourglass": {"name": "古い砂時計", "desc": "毎戦闘の最初のターン、エネルギー +1", "price": 140},
	"heavy_cup": {"name": "重いカップ", "desc": "毎ターン注ぐ玉 +2", "price": 150},
	"whetstone": {"name": "砥石", "desc": "+ のゲートの効き目 +1", "price": 130},
	"double": {"name": "二重底", "desc": "× のゲートの効き目 +0.5", "price": 150},
	"belt": {"name": "予備の弾帯", "desc": "弾倉がいつも ×1.2", "price": 140},
	"iron": {"name": "鉄の小盾", "desc": "毎ターン、ブロック +3", "price": 130},
	"oil": {"name": "油差し", "desc": "ゲートの回数 +2", "price": 130},
	"herb": {"name": "薬草袋", "desc": "戦闘に勝つたび HP +5", "price": 120},
	"golden": {"name": "金の杯", "desc": "戦闘で得るゴールド +50%", "price": 120},
	"scope": {"name": "照準器", "desc": "狙うときのカップが遅くなる", "price": 120},
	"pocket": {"name": "大きなポケット", "desc": "ターンの初めに引く枚数 +1", "price": 160},
}


static func base_id(card: String) -> String:
	return card.trim_suffix("+")


static func is_up(card: String) -> bool:
	return card.ends_with("+")


## 強化を反映した、そのカードの値（name・cost・val・desc など）
static func info(card: String) -> Dictionary:
	var base: Dictionary = CARDS[base_id(card)]
	var out := base.duplicate()
	out.erase("up")
	if is_up(card):
		for k in base["up"]:
			out[k] = base["up"][k]
		if not base["up"].has("name"):
			out["name"] = base["name"] + "+"
	if out.has("desc") and "%" in out["desc"]:
		out["desc"] = out["desc"] % out["val"]
	return out


## ゲートの説明（強化やレリックで変わる数字を入れる）
static func gate_desc(card: String) -> String:
	var i := info(card)
	match i.get("gate", ""):
		"add": return "値 +%d" % i["val"]
		"mul": return "値 ×%d" % i["val"]
		"charge": return "隣の回数 +%d" % i["val"]
		"shield": return "通過でブロック+%d" % i["val"]
		"power": return "%d回で次エネ+1" % i["val"]
		"scout": return "%d回で次+1枚" % i["val"]
		"right", "left":
			if i.has("uses_bonus"):
				return "%s・回数+%d" % [Board.GATE_DEFS[i["gate"]]["desc"], i["uses_bonus"]]
	return Board.GATE_DEFS[i["gate"]]["desc"]


static func scaled_enemy(id: String, floor_no: int) -> Dictionary:
	var e: Dictionary = ENEMIES[id].duplicate(true)
	var mult := 1.0 + 0.1 * maxf(floor_no - 1, 0)
	if e.get("boss", false):
		mult = 1.0
	e["max"] = roundf(e["hp"] * mult)
	e["hp"] = e["max"]
	e["id"] = id
	e["block"] = 0.0
	e["atk_bonus"] = 0
	e["move_i"] = 0
	return e
