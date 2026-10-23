// 試作 B: インクリ特化。
// カップは自動で注ぎ続け、弾倉に溜まった分をミニガンが撃ち続ける。敵は倒すたびに強くなる。
// 制限時間内に倒せないとステージが1つ戻る（＝壁）。ゲートは自由に買って置き、いつでも外せる。
// ステージ 10 以上に届いたら転生でき、星（永続の倍率）をもらって最初から。留守の間もコインが入る。

const GATE_COST = { add: 8, mul: 40, sq: 250 };
const ENEMY_TIME = 20, SAVE_KEY = "cup-gate-idle-v1", OFFLINE_CAP = 2 * 3600, PRESTIGE_AT = 10;

const game = {
  board: makeBoard({ autoCup: true, useDisplay: "bar" }),
  S: null,
  msg: "", msgT: 0, confirmUntil: 0, saveT: 0, incomeWin: 0, incomeT: 0,

  newRun(stars = 0, bestEver = 0) {
    return { stage: 1, maxStage: 1, bestEver, enemyHp: this.hpFor(1), enemyMax: this.hpFor(1), timeLeft: ENEMY_TIME,
      coins: 0, stars, pourLv: 0, capLv: 0, inventory: { add: 1, mul: 0, sq: 0 }, bought: { add: 0, mul: 0, sq: 0 },
      selected: "add", slots: null, ammo: 0, coinRate: 0 };
  },

  hpFor: s => Math.round(15 * Math.pow(1.38, s - 1)),
  rewardFor(s) { return Math.ceil(this.hpFor(s) * 0.12 + s * 2); },
  pourRate() { return 2 + this.S.pourLv * 1; },
  capacity() { return 4 + this.S.capLv * 3; },
  starMul() { return 1 + 0.5 * this.S.stars; },
  gateCost(t) { return Math.round(GATE_COST[t] * Math.pow(1.5, this.S.bought[t])); },
  pourCost() { return Math.round(10 * Math.pow(1.45, this.S.pourLv)); },
  capCost() { return Math.round(15 * Math.pow(1.6, this.S.capLv)); },
  starsGain() { return Math.max(0, this.S.maxStage - (PRESTIGE_AT - 1)); },

  say(m, t = 3) { this.msg = m; this.msgT = t; },

  nextEnemy() {
    const S = this.S;
    S.enemyMax = this.hpFor(S.stage);
    S.enemyHp = S.enemyMax;
    S.timeLeft = ENEMY_TIME;
  },

  onSlot(i) {
    const S = this.S, B = this.board;
    const g = B.slots[i];
    if (g) {
      S.inventory[g.type] += 1;
      B.slots[i] = null;
      S.selected = g.type;
    } else if (S.inventory[S.selected] > 0) {
      B.slots[i] = newGate(S.selected, this.capacity());
      S.inventory[S.selected] -= 1;
    }
  },

  buy(cost, fn) {
    if (this.S.coins < cost) return;
    this.S.coins -= cost;
    fn();
  },

  prestige() {
    const gain = this.starsGain();
    if (gain <= 0) return;
    if (this.board.t < this.confirmUntil) {
      const S = this.S;
      this.S = this.newRun(S.stars + gain, Math.max(S.bestEver, S.maxStage));
      this.board.slots.fill(null);
      this.board.balls = [];
      this.confirmUntil = 0;
      this.say(`転生！ 星 +${gain}（基礎値 ×${this.starMul().toFixed(1)}）`, 4);
    } else {
      this.confirmUntil = this.board.t + 3;
    }
  },

  update(dt) {
    const S = this.S, B = this.board;
    B.pourRate = this.pourRate();
    B.toPour = Infinity;
    B.baseVal = this.starMul();
    const cap = this.capacity();
    for (const g of B.slots) if (g) { g.max = cap; g.uses = Math.min(cap, g.uses + cap * dt); }

    // 弾倉を撃ち続ける（溜まった分の多くを毎秒撃ち出す）
    const shot = S.ammo > 0.01 ? Math.min(S.ammo, S.ammo * Math.min(1, dt * 3) + dt * 2) : 0;
    S.ammo -= shot;
    B.firing = shot > 0;
    B.ammoShown = S.ammo;
    S.enemyHp -= shot;
    if (S.enemyHp <= 0) {
      const r = this.rewardFor(S.stage);
      S.coins += r;
      this.incomeWin += r;
      S.stage += 1;
      S.maxStage = Math.max(S.maxStage, S.stage);
      this.nextEnemy();
    } else {
      S.timeLeft -= dt;
      if (S.timeLeft <= 0) {
        if (S.stage > 1) { S.stage -= 1; this.say("時間切れ… ステージが 1 つ戻った（壁）"); }
        this.nextEnemy();
      }
    }

    this.incomeT += dt;
    if (this.incomeT >= 5) {
      S.coinRate = S.coinRate * 0.5 + (this.incomeWin / this.incomeT) * 0.5;
      this.incomeWin = 0;
      this.incomeT = 0;
    }
    this.msgT -= dt;
    this.saveT += dt;
    if (this.saveT > 5) { this.saveT = 0; this.save(); }
  },

  save() {
    try {
      const S = { ...this.S, slots: this.board.slots.map(g => g && g.type), savedAt: Date.now() };
      localStorage.setItem(SAVE_KEY, JSON.stringify(S));
    } catch (_) { /* 保存できない環境では何もしない */ }
  },

  drawTop() {
    const S = this.S, B = this.board;
    text(`ステージ ${S.stage}   敵 HP ${fmt(Math.max(S.enemyHp, 0))} / ${fmt(S.enemyMax)}`, 20, 40, 28, "#eef0f6", "left", 700);
    text(`残り ${Math.ceil(S.timeLeft)} 秒`, W - 20, 40, 22, S.timeLeft < 5 ? "#ff9a8a" : "rgba(238,240,246,0.7)", "right", 700);
    drawBar(20, 52, W - 40, 16, S.enemyHp / S.enemyMax, "#e5504d", B.hitShake);
    drawBar(20, 72, W - 40, 5, S.timeLeft / ENEMY_TIME, "rgba(238,240,246,0.5)");
    text(`コイン ${fmt(S.coins)}   約 ${fmt(S.coinRate)}/秒   星 ${S.stars}（×${this.starMul().toFixed(1)}）   最高 ${S.maxStage}`,
      20, 104, 19, "rgba(238,240,246,0.8)");
  },

  drawPanel() {
    const S = this.S;
    const held = ["add", "mul", "sq"].map(t => `${GATE_DEFS[t].label}×${S.inventory[t]}`).join("  ");
    const base = `置く: ${GATE_DEFS[S.selected].label}   手持ち ${held}\n空きマスをタップで置く／置いたゲートをタップで回収`;
    drawLines(this.msgT > 0 ? this.msg : base, 16, 934, 20, this.msgT > 0 ? "#ffd966" : "#eef0f6", W - 32, 2);
    text("ゲートの下のバーは容量（1秒に通せる玉の数）。使い切ると素通り", 16, 1250, 16, "rgba(238,240,246,0.55)");
  },

  buttons() {
    const S = this.S;
    const list = [];
    const bw = 228, bh = 72, x0 = 12, gap = 8;
    ["add", "mul", "sq"].forEach((t, i) => {
      const cost = this.gateCost(t);
      list.push({ x: x0 + i * (bw + gap), y: 990, w: bw, h: bh, text: `${GATE_DEFS[t].label} を買う`, sub: fmt(cost),
        enabled: S.coins >= cost, selected: S.selected === t && S.inventory[t] > 0,
        act: () => this.buy(cost, () => { S.bought[t] += 1; S.inventory[t] += 1; S.selected = t; }) });
    });
    const pc = this.pourCost(), cc = this.capCost();
    list.push({ x: x0, y: 1070, w: bw, h: bh, text: `注ぐ ${this.pourRate()}/秒 → +1`, sub: fmt(pc), enabled: S.coins >= pc,
      act: () => this.buy(pc, () => { S.pourLv += 1; }) });
    list.push({ x: x0 + bw + gap, y: 1070, w: bw, h: bh, text: `容量 ${this.capacity()} → +3`, sub: fmt(cc), enabled: S.coins >= cc,
      act: () => this.buy(cc, () => { S.capLv += 1; }) });
    const gain = this.starsGain();
    const confirming = this.board.t < this.confirmUntil;
    list.push({ x: x0 + 2 * (bw + gap), y: 1070, w: bw, h: bh,
      text: confirming ? "もう一度で転生" : "転生", sub: gain > 0 ? `星 +${gain}` : `ステージ ${PRESTIGE_AT} から`,
      enabled: gain > 0, selected: confirming, act: () => this.prestige() });
    // ゲートの種類を選ぶだけのボタン（手持ちがあるとき）
    ["add", "mul", "sq"].forEach((t, i) => {
      list.push({ x: x0 + i * (bw + gap), y: 1152, w: bw, h: 56, text: `${GATE_DEFS[t].label} を置く（${S.inventory[t]}）`,
        enabled: S.inventory[t] > 0, selected: S.selected === t, act: () => { S.selected = t; } });
    });
    return list;
  },

  snapshot() { return { S: { ...this.S, slots: this.board.slots.map(g => g && g.type) } }; },

  restore(data) {
    let saved = data.S;
    let offline = 0;
    if (!saved) {
      try {
        const raw = localStorage.getItem(SAVE_KEY);
        if (raw) {
          saved = JSON.parse(raw);
          offline = Math.min(OFFLINE_CAP, Math.max(0, (Date.now() - saved.savedAt) / 1000));
        }
      } catch (_) { saved = null; }
    }
    this.S = saved ? { ...this.newRun(), ...saved } : this.newRun();
    const types = this.S.slots || [];
    this.board.slots = this.board.slots.map((_, i) => types[i] ? newGate(types[i], this.capacity()) : null);
    this.board.onCollect = v => { this.S.ammo += v; };
    if (offline > 60 && this.S.coinRate > 0) {
      const gain = this.S.coinRate * offline * 0.5;
      this.S.coins += gain;
      this.say(`留守の間（${Math.round(offline / 60)} 分）に +${fmt(gain)} コイン`, 6);
    }
  },
};

run(game);
