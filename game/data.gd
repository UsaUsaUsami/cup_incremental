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
	"chip": {"name": "刻み", "cost": 1, "gate": "chip", "val": 2.0, "price": 45, "up": {"val": 3.0}},
	"inv": {"name": "反転", "cost": 1, "gate": "inv", "val": 6.0, "price": 70, "up": {"val": 10.0}},  # 反転「C/x」の C（仮置き）
	"power": {"name": "発電", "cost": 1, "gate": "power", "val": 5.0, "price": 60, "up": {"val": 3.0}},
	"scout": {"name": "索敵", "cost": 1, "gate": "scout", "val": 3.0, "price": 60, "up": {"val": 2.0}},
	"more": {"name": "玉 +5", "cost": 1, "icon": "玉+", "desc": "注ぐ玉 +%d", "val": 5.0, "price": 50, "up": {"val": 8.0}},
	"extend": {"name": "延長", "cost": 1, "icon": "延", "desc": "制限ターン +%d・除外", "val": 1.0, "exhaust": true,
		"price": 70, "up": {"cost": 0}},
	"load": {"name": "増量装填", "cost": 1, "icon": "装", "desc": "弾倉 ×%.1f", "val": 1.5, "price": 65, "up": {"val": 2.0}},
	"burst": {"name": "炸裂弾", "cost": 1, "icon": "爆", "desc": "玉ごと +%d", "val": 2.0, "price": 60, "up": {"val": 4.0}},
	"focus": {"name": "集中", "cost": 0, "icon": "E+", "desc": "エネ+%d・除外", "val": 1.0, "exhaust": true, "price": 55, "up": {"val": 2.0}},
	"refill": {"name": "補充", "cost": 1, "icon": "引", "desc": "カードを%d枚引く", "val": 2.0, "price": 55, "up": {"val": 3.0}},
	"prep": {"name": "下準備", "cost": 0, "icon": "引", "desc": "カードを%d枚引く", "val": 1.0, "price": 45, "up": {"val": 2.0}},
	"save": {"name": "温存", "cost": 1, "icon": "次", "desc": "次ターン エネ+%d", "val": 2.0, "price": 55, "up": {"val": 3.0}},
}
const START_DECK: Array[String] = ["add", "add", "add", "mul", "mul", "sq", "more", "chip", "prep"]

# 敵は「ノルマ（制限ターン内に与える合計ダメージ）・制限ターン・ハンデ」で決まる。ハンデは二段構え:
# - すべての敵: 値を減らすデメリットゲートを盤面に常に置く（gates: [[種類, 行, 列], ...]、行は 0〜4、列は 0〜3）
# - 一部の敵だけ: 固有のハンデ（trait）。下の TRAITS のどれか
# 数字はすべて仮置き（つり合いは後で調整する）
const TURNS_NORMAL := 3
const TURNS_ELITE := 4
const TURNS_BOSS := 5
const ENEMIES := {
	"slime": {"name": "スライム", "quota": 38, "hue": 0.5, "gates": [["div2", 2, 1]]},
	"goblin": {"name": "ゴブリン", "quota": 46, "hue": 0.28, "gates": [["minus", 1, 2], ["minus", 3, 0]]},
	"dart": {"name": "吹き矢の小鬼", "quota": 40, "hue": 0.12, "gates": [["div2", 1, 0], ["div2", 1, 3]], "trait": "fast"},
	"golem": {"name": "岩の番人", "quota": 64, "hue": 0.08, "gates": [["root", 4, 1], ["root", 4, 2]]},
	"mage": {"name": "封印の術師", "quota": 52, "hue": 0.75, "gates": [["div2", 2, 2], ["minus", 0, 1]], "trait": "drain"},
	"giant": {"name": "鉄の巨人", "quota": 150, "hue": 0.6, "elite": true,
		"gates": [["root", 2, 1], ["div2", 3, 2], ["minus", 4, 3]], "trait": "fewer"},
	"witches": {"name": "双子の魔女", "quota": 125, "hue": 0.85, "elite": true,
		"gates": [["div2", 1, 1], ["div2", 1, 2], ["minus", 3, 0], ["minus", 3, 3]], "trait": "hand"},
	"pegking": {"name": "ペグの王", "quota": 420, "hue": 0.95, "boss": true,
		"gates": [["root", 2, 0], ["root", 2, 3], ["div2", 4, 1]], "trait": "pegs"},
}
# 固有のハンデ（戦闘のあいだずっと効く）
const TRAITS := {
	"fast": "カップが速い",
	"drain": "ゲートの回数 −2",
	"fewer": "注ぐ玉 −2",
	"hand": "引く枚数 −1",
	"pegs": "毎ターン、ペグの並びが変わる",
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
	"watch": {"name": "懐中時計", "desc": "どの戦闘も制限ターン +1", "price": 160},
	"oil": {"name": "油差し", "desc": "ゲートの回数 +2", "price": 130},
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
		"chip": return "通るたび弾倉+%d" % i["val"]
		"inv": return "値を %d÷値 に" % i["val"]
		"power": return "%d回で次エネ+1" % i["val"]
		"scout": return "%d回で次+1枚" % i["val"]
		"right", "left":
			if i.has("uses_bonus"):
				return "%s・回数+%d" % [Board.GATE_DEFS[i["gate"]]["desc"], i["uses_bonus"]]
	return Board.GATE_DEFS[i["gate"]]["desc"]


## 戦闘で使う敵の状態。hp / max は「残りノルマ / ノルマ」（敵の HP として見せる）
static func scaled_enemy(id: String, floor_no: int) -> Dictionary:
	var e: Dictionary = ENEMIES[id].duplicate(true)
	var mult := 1.0 + 0.1 * maxf(floor_no - 1, 0)
	if e.get("boss", false):
		mult = 1.0
	e["max"] = roundf(e["quota"] * mult)
	e["hp"] = e["max"]
	e["id"] = id
	e["turns"] = turns_for(id)
	return e


static func turns_for(id: String) -> int:
	var e: Dictionary = ENEMIES[id]
	if e.get("boss", false):
		return TURNS_BOSS
	return TURNS_ELITE if e.get("elite", false) else TURNS_NORMAL


## 戦闘画面用: 「÷2 ×1、−5 ×2 ／ カップが速い」のようなハンデの一覧
static func handicap_text(id: String) -> String:
	var counts := {}
	for g in ENEMIES[id]["gates"]:
		counts[g[0]] = counts.get(g[0], 0) + 1
	var parts := []
	for k in counts:
		parts.append("%s ×%d" % [Board.GATE_DEFS[k]["label"], counts[k]])
	var out := "、".join(parts)
	if ENEMIES[id].has("trait"):
		out += " ／ " + TRAITS[ENEMIES[id]["trait"]]
	return out
