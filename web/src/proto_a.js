// 試作 A: カード式ローグライト（本命の方向）。盤面にはペグがあり、玉が左右に散る。
// 毎ターン山札から5枚引き、エネルギーを払ってカードを出す。ゲートのカードは光った候補マス（最大3つ）から置き場所を選ぶ。
// 「注ぐ」でターン終了: 玉を注いで弾倉に溜め、ミニガンで撃つ。敵が残れば敵の攻撃を受ける（ブロックで減らせる）。
// 盤面は戦闘ごとにリセットし、デッキは戦闘をまたいで育つ。勝つとカード3枚から1枚を選ぶ。

const CARDS = {
  // ゲート（値・経路・盤面・守り）
  add: { name: "+3", cost: 1, gate: "add" },
  mul: { name: "×2", cost: 1, gate: "mul" },
  sq: { name: "x²", cost: 2, gate: "sq" },
  bounce: { name: "跳ね返し", cost: 1, gate: "bounce" },
  right: { name: "右へ", cost: 0, gate: "right" },
  left: { name: "左へ", cost: 0, gate: "left" },
  cheer: { name: "応援", cost: 1, gate: "cheer" },
  charge: { name: "充電", cost: 1, gate: "charge" },
  shield: { name: "盾", cost: 1, gate: "shield" },
  // すぐ効く（玉・守り・銃）
  more: { name: "玉 +5", cost: 1, desc: "このターン +5 個", play: S => { S.balls += 5; } },
  guard: { name: "防御", cost: 1, desc: "ブロック +7", play: S => { S.block += 7; } },
  heal: { name: "応急手当", cost: 1, desc: "HP +6", play: S => { S.hp = Math.min(PLAYER_HP, S.hp + 6); } },
  load: { name: "増量装填", cost: 1, desc: "弾倉 ×1.5", play: S => { S.ammoMul *= 1.5; } },
  burst: { name: "炸裂弾", cost: 1, desc: "玉1つごとに +2", play: S => { S.perBall += 2; } },
};
const START_DECK = ["add", "add", "add", "mul", "mul", "sq", "guard", "guard", "shield"];
const REWARD_POOL = Object.keys(CARDS);
const HAND_SIZE = 5, ENERGY = 3, BALLS_PER_TURN = 10, GATE_USES = 6, FIRE_TIME = 2.0;
const PLAYER_HP = 40, HEAL_AFTER_FIGHT = 5;

const game = {
  board: makeBoard({ pegs: true, useDisplay: "count" }),
  S: null,
  fireT: 0, fireHpStart: 0, enemyTimer: 0, msg: "",

  newRun() {
    return { phase: "turn", fight: 1, hp: PLAYER_HP, block: 0, deck: START_DECK.slice(), draw: [], discard: [], hand: [],
      energy: ENERGY, balls: BALLS_PER_TURN, ammo: 0, ammoMul: 1, perBall: 0, collected: 0,
      enemy: this.enemyFor(1), selected: -1, rewards: [], lastHit: 0 };
  },

  enemyFor(f) {
    const max = Math.round(45 * Math.pow(1.6, f - 1));
    return { hp: max, max, atk: 5 + 2 * f };
  },

  startFight() {
    const S = this.S;
    this.board.slots.fill(null);
    S.draw = shuffle(S.deck.slice());
    S.discard = [];
    S.hand = [];
    S.enemy = this.enemyFor(S.fight);
    this.startTurn();
  },

  startTurn() {
    const S = this.S;
    S.phase = "turn";
    S.energy = ENERGY;
    S.balls = BALLS_PER_TURN;
    S.block = 0;
    S.ammo = 0;
    S.ammoMul = 1;
    S.perBall = 0;
    S.collected = 0;
    S.selected = -1;
    this.board.highlight.clear();
    this.board.blockGain = 0;
    for (const g of this.board.slots) if (g) { g.uses = GATE_USES; g.max = GATE_USES; }
    for (let i = 0; i < HAND_SIZE; i++) {
      if (S.draw.length === 0) { S.draw = shuffle(S.discard); S.discard = []; }
      if (S.draw.length === 0) break;
      S.hand.push(S.draw.pop());
    }
    this.msg = "カードを選ぶ。ゲートは光ったマスに置く";
  },

  playCard(i) {
    const S = this.S;
    const card = CARDS[S.hand[i]];
    if (S.phase !== "turn" || S.energy < card.cost) return;
    if (!card.gate) {
      S.energy -= card.cost;
      card.play(S);
      S.discard.push(S.hand.splice(i, 1)[0]);
      S.selected = -1;
      this.board.highlight.clear();
      return;
    }
    if (S.selected === i) { S.selected = -1; this.board.highlight.clear(); return; }
    const empty = this.board.slots.map((g, k) => g ? -1 : k).filter(k => k >= 0);
    if (empty.length === 0) { this.msg = "盤面が埋まっていて置けない"; return; }
    S.selected = i;
    this.board.highlight = new Set(shuffle(empty).slice(0, 3));
    this.msg = `${card.name}：${GATE_DEFS[card.gate].desc}。光ったマスを選ぶ`;
  },

  onSlot(i) {
    const S = this.S;
    if (S.phase !== "turn" || S.selected < 0 || !this.board.highlight.has(i)) return;
    const card = CARDS[S.hand[S.selected]];
    S.energy -= card.cost;
    this.board.slots[i] = newGate(card.gate, GATE_USES);
    S.discard.push(S.hand.splice(S.selected, 1)[0]);
    S.selected = -1;
    this.board.highlight.clear();
    this.msg = "カードを選ぶ。ゲートは光ったマスに置く";
  },

  pour() {
    const S = this.S;
    S.phase = "pour";
    S.discard.push(...S.hand);
    S.hand = [];
    S.selected = -1;
    this.board.highlight.clear();
    this.board.toPour = S.balls;
    this.msg = "注いでいる…（上の帯でカップを動かせる）";
  },

  update(dt) {
    const S = this.S, B = this.board;
    if (B.blockGain > 0) { S.block += B.blockGain; B.blockGain = 0; }
    B.ammoShown = S.phase === "fire" ? Math.max(S.ammo * (1 - this.fireT / FIRE_TIME), 0) : S.ammo;
    if (S.phase === "pour" && B.toPour === 0 && B.balls.length === 0) {
      S.ammo *= S.ammoMul;
      S.phase = "fire";
      this.fireT = 0;
      this.fireHpStart = S.enemy.hp;
      B.firing = S.ammo > 0;
    } else if (S.phase === "fire") {
      this.fireT += dt;
      S.enemy.hp = this.fireHpStart - S.ammo * Math.min(this.fireT / FIRE_TIME, 1);
      this.msg = `発射！ 残弾 ${fmt(B.ammoShown)}`;
      if (S.enemy.hp <= 0 || this.fireT >= FIRE_TIME) {
        B.firing = false;
        S.ammo = 0;
        if (S.enemy.hp <= 0) {
          S.enemy.hp = 0;
          S.phase = "reward";
          S.rewards = shuffle(REWARD_POOL.slice()).slice(0, 3);
          this.msg = "勝利！ デッキに加えるカードを1枚選ぶ";
        } else {
          S.phase = "enemy";
          this.enemyTimer = 1.2;
          const dmg = Math.max(0, S.enemy.atk - S.block);
          S.lastHit = dmg;
          this.msg = S.block > 0 ? `敵の攻撃 ${S.enemy.atk}！ ブロック ${S.block} で防いで ${dmg} ダメージ`
            : `敵の攻撃！ ${dmg} ダメージ`;
          S.hp -= dmg;
        }
      }
    } else if (S.phase === "enemy") {
      this.enemyTimer -= dt;
      if (this.enemyTimer <= 0) {
        if (S.hp <= 0) { S.hp = 0; S.phase = "over"; this.msg = `敗北… 戦闘 ${S.fight} で倒れた`; }
        else this.startTurn();
      }
    }
  },

  takeReward(id) {
    const S = this.S;
    if (id) S.deck.push(id);
    S.fight += 1;
    S.hp = Math.min(PLAYER_HP, S.hp + HEAL_AFTER_FIGHT);
    this.startFight();
  },

  drawTop() {
    const S = this.S, B = this.board;
    text(`戦闘 ${S.fight}   敵 HP ${fmt(Math.max(S.enemy.hp, 0))} / ${fmt(S.enemy.max)}`, 20, 40, 28, "#eef0f6", "left", 700);
    text(`次の攻撃 ${S.enemy.atk}`, W - 20, 40, 22, "#ff9a8a", "right", 700);
    drawBar(20, 52, W - 40, 16, S.enemy.hp / S.enemy.max, "#e5504d", B.hitShake);
    text(`HP ${S.hp} / ${PLAYER_HP}`, 20, 96, 22, "#8fe3a6", "left", 700);
    text(`ブロック ${S.block}`, 170, 96, 22, S.block > 0 ? "#9cc4ff" : "rgba(156,196,255,0.45)", "left", 700);
    const mods = (S.ammoMul !== 1 ? `  弾倉×${S.ammoMul}` : "") + (S.perBall ? `  玉ごと+${S.perBall}` : "");
    text(`エネルギー ${S.energy}/${ENERGY}   山札 ${S.draw.length}  捨て札 ${S.discard.length}${mods}`,
      W - 20, 96, 17, "rgba(238,240,246,0.75)", "right");
    drawBar(20, 104, 140, 8, S.hp / PLAYER_HP, "#4fbf6f");
  },

  drawPanel() {
    drawLines(this.msg, 16, 936, 20, "#eef0f6", W - 32, 1);
    if (this.S.phase === "reward") text("（取らない場合はそのまま次の戦闘へ）", 16, 1250, 18, "rgba(238,240,246,0.6)");
  },

  cardButton(id, x, y, w, h, enabled, selected, act) {
    const c = CARDS[id];
    return c.gate
      ? { x, y, w, h, gate: c.gate, text: `${c.name}  ${c.cost}`, sub: GATE_DEFS[c.gate].desc, enabled, selected, act }
      : { x, y, w, h, text: `${c.name}  ${c.cost}`, sub: c.desc, enabled, selected, act };
  },

  buttons() {
    const S = this.S;
    const list = [];
    if (S.phase === "turn" || S.phase === "pour" || S.phase === "fire" || S.phase === "enemy") {
      S.hand.forEach((id, i) => {
        list.push(this.cardButton(id, 12 + i * 141, 955, 133, 132, S.phase === "turn" && S.energy >= CARDS[id].cost,
          S.selected === i, () => this.playCard(i)));
      });
      list.push({ x: 12, y: 1110, w: 696, h: 84, big: true, enabled: S.phase === "turn",
        text: S.phase === "turn" ? `玉を ${S.balls} 個注ぐ（ターン終了）` : "…", act: () => this.pour() });
    } else if (S.phase === "reward") {
      S.rewards.forEach((id, i) => list.push(this.cardButton(id, 12 + i * 236, 965, 224, 132, true, false,
        () => this.takeReward(id))));
      list.push({ x: 12, y: 1120, w: 696, h: 84, big: true, enabled: true, text: "取らない", act: () => this.takeReward(null) });
    } else if (S.phase === "over") {
      list.push({ x: 12, y: 1110, w: 696, h: 84, big: true, enabled: true, text: "最初から",
        act: () => { this.S = this.newRun(); this.startFight(); } });
    }
    return list;
  },

  snapshot() { return { S: this.S, slots: this.board.slots }; },

  restore(data) {
    // 戦闘の途中で更新されたら、そのターンの初めからやり直す
    if (data.S && data.S.phase !== "over" && data.S.ammoMul !== undefined) {
      this.S = data.S;
      this.board.slots = data.slots || this.board.slots;
      if (["pour", "fire", "enemy"].includes(this.S.phase)) { this.S.hand = []; this.startTurn(); }
    } else {
      this.S = this.newRun();
      this.startFight();
    }
    this.board.onCollect = v => { this.S.ammo += v + this.S.perBall; this.S.collected += 1; };
  },
};

run(game);
