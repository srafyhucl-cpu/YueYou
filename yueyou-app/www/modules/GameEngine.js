// ======================================
// 游戏引擎管理器 (GameEngine.js)
// 职责：处理 2048 棋盘的状态、移动、消除、分数计算与阶段跃迁逻辑
// ======================================

export class GameEngine {
    constructor() {
      ((this.MODES = { CLASSIC: "classic", LOOP: "loop" }),
        (this.PHASES = {
          NORMAL: "normal",
          DISASSEMBLE: "disassemble",
          REASSEMBLE: "reassemble",
        }));
      let e = localStorage.getItem("bestScore_premium");
      ((this.bestScore = e && !isNaN(e) ? parseInt(e) : 0), this.reset());
    }
    reset() {
      ((this.mode = this.MODES.CLASSIC),
        (this.phase = this.PHASES.NORMAL),
        (this.size = 4),
        (this.score = 0),
        (this.combo = 0),
        (this.nextId = Date.now()),
        (this.over = !1),
        (this.won = !1),
        (this.phaseJustCleared = !1),
        this.initBoard(),
        this.addRandomTile(),
        this.addRandomTile());
    }
    initBoard() {
      ((this.board = Array(this.size)
        .fill()
        .map(() => Array(this.size).fill(null))),
        this.mode === this.MODES.LOOP &&
          (this.board[2][2] = { id: 0, value: 2048, isAnchor: !0 }));
    }
    jumpToStage(e) {
      ((this.won = !1),
        (this.over = !1),
        (this.phaseJustCleared = !1),
        (this.combo = 0),
        e === "classic"
          ? ((this.mode = this.MODES.CLASSIC),
            (this.size = 4),
            (this.phase = this.PHASES.NORMAL),
            this.initBoard(),
            this.addRandomTile(),
            this.addRandomTile())
          : e === "loop_1"
            ? ((this.mode = this.MODES.LOOP),
              (this.size = 5),
              (this.phase = this.PHASES.DISASSEMBLE),
              this.initBoard(),
              this.seedDisassembleTiles())
            : e === "loop_2"
              ? ((this.mode = this.MODES.LOOP),
                (this.size = 5),
                (this.phase = this.PHASES.REASSEMBLE),
                this.initBoard(),
                this.addLoopTile())
              : e === "fast_win" &&
                (this.jumpToStage("loop_2"),
                [
                  { r: 1, c: 2 },
                  { r: 3, c: 2 },
                  { r: 2, c: 1 },
                  { r: 2, c: 3 },
                ].forEach(
                  (t) =>
                    (this.board[t.r][t.c] = { id: this.nextId++, value: 512 }),
                ),
                this.checkPhaseTransition()));
    }
    seedDisassembleTiles() {
      let e = [512, 256, 128, 64];
      for (let s = 0; s < 4; s++) {
        let t = [];
        for (let r = 0; r < 5; r++)
          for (let l = 0; l < 5; l++)
            !this.board[r][l] &&
              (r === 0 || r === 4 || l === 0 || l === 4) &&
              t.push({ r, c: l });
        if (t.length) {
          let r = t[Math.floor(Math.random() * t.length)];
          this.board[r.r][r.c] = { id: this.nextId++, value: e[s] };
        }
      }
    }
    move(e) {
      if (this.over || this.won || this.phaseJustCleared)
        return { moved: !1, mergedTiles: [] };
      let s = !1,
        t = [],
        r = this.getVector(e),
        { rows: l, cols: y } = this.getTraversalOrder(r),
        v = Array(this.size)
          .fill()
          .map(() => Array(this.size).fill(null));
      this.board.forEach((u, w) =>
        u.forEach((h, E) => {
          h && (v[w][E] = { ...h });
        }),
      );
      let A = Array(this.size)
        .fill()
        .map(() => Array(this.size).fill(!1));
      return (
        l.forEach((u) => {
          y.forEach((w) => {
            let h = v[u][w];
            if (!h || h.isAnchor) return;
            let E = { r: u, c: w },
              m = { r: u + r.y, c: w + r.x };
            for (; this.inBounds(m.r, m.c) && !v[m.r][m.c]; )
              ((v[m.r][m.c] = h),
                (v[E.r][E.c] = null),
                (E = { r: m.r, c: m.c }),
                (m = { r: m.r + r.y, c: m.c + r.x }),
                (s = !0));
            if (this.inBounds(m.r, m.c)) {
              let M = v[m.r][m.c];
              if (M && !M.isAnchor && M.value === h.value && !A[m.r][m.c]) {
                let $ =
                  this.mode === this.MODES.LOOP &&
                  this.phase === this.PHASES.DISASSEMBLE;
                ((M.value = $ ? Math.max(2, M.value / 2) : M.value * 2),
                  (v[E.r][E.c] = null),
                  (A[m.r][m.c] = !0),
                  (s = !0),
                  this.combo++,
                  (this.score += M.value),
                  this.score > this.bestScore &&
                    ((this.bestScore = this.score),
                    localStorage.setItem("bestScore_premium", this.bestScore)),
                  t.push({
                    r: m.r,
                    c: m.c,
                    value: M.value,
                    combo: this.combo,
                  }));
              }
            }
          });
        }),
        s &&
          (t.length === 0 && (this.combo = 0),
          (this.board = v),
          this.mode === this.MODES.LOOP
            ? (this.addLoopTile(), this.checkPhaseTransition())
            : (this.addRandomTile(),
              this.getMaxTileValue() >= 2048 && (this.phaseJustCleared = !0)),
          this.movesAvailable() || (this.over = !0)),
        { moved: s, mergedTiles: t, combo: this.combo }
      );
    }
    addLoopTile() {
      let e = [];
      for (let s = 0; s < 5; s++)
        for (let t = 0; t < 5; t++)
          (s === 0 || s === 4 || t === 0 || t === 4) &&
            !this.board[s][t] &&
            e.push({ r: s, c: t });
      if (e.length) {
        let s = e[Math.floor(Math.random() * e.length)],
          t =
            this.phase === this.PHASES.REASSEMBLE
              ? Math.random() < 0.9
                ? 2
                : 4
              : this.getMaxTileValue();
        this.board[s.r][s.c] = { id: this.nextId++, value: t };
      }
    }
    checkPhaseTransition() {
      if (this.phase === this.PHASES.DISASSEMBLE) {
        let e = !1,
          s = 0;
        (this.board.forEach((t) =>
          t.forEach((r) => {
            r && !r.isAnchor && (s++, r.value > 2 && (e = !0));
          }),
        ),
          s > 0 && !e && (this.phaseJustCleared = !0));
      } else if (this.phase === this.PHASES.REASSEMBLE) {
        let e = [
            { r: 1, c: 2 },
            { r: 3, c: 2 },
            { r: 2, c: 1 },
            { r: 2, c: 3 },
          ],
          s = !0;
        (e.forEach((t) => {
          (!this.board[t.r][t.c] || this.board[t.r][t.c].value < 512) &&
            (s = !1);
        }),
          s && (this.won = !0));
      }
    }
    clearTile(e, s) {
      return this.board[e][s] && !this.board[e][s].isAnchor
        ? ((this.board[e][s] = null), !0)
        : !1;
    }
    getMaxTileValue() {
      let e = 2;
      return (
        this.board.forEach((s) =>
          s.forEach((t) => {
            t && !t.isAnchor && (e = Math.max(e, t.value));
          }),
        ),
        e
      );
    }
    inBounds(e, s) {
      return e >= 0 && e < this.size && s >= 0 && s < this.size;
    }
    getVector(e) {
      return {
        up: { x: 0, y: -1 },
        down: { x: 0, y: 1 },
        left: { x: -1, y: 0 },
        right: { x: 1, y: 0 },
      }[e];
    }
    getTraversalOrder(e) {
      let s = [...Array(this.size).keys()],
        t = [...Array(this.size).keys()];
      return (
        e.y === 1 && s.reverse(),
        e.x === 1 && t.reverse(),
        { rows: s, cols: t }
      );
    }
    movesAvailable() {
      for (let e = 0; e < this.size; e++)
        for (let s = 0; s < this.size; s++) {
          if (!this.board[e][s]) return !0;
          for (let t of ["up", "down", "left", "right"]) {
            let r = this.getVector(t),
              l = e + r.y,
              y = s + r.x;
            if (this.inBounds(l, y)) {
              let v = this.board[l][y];
              if (!v || (!v.isAnchor && v.value === this.board[e][s].value))
                return !0;
            }
          }
        }
      return !1;
    }
    addRandomTile() {
      let e = [];
      for (let s = 0; s < this.size; s++)
        for (let t = 0; t < this.size; t++)
          this.board[s][t] || e.push({ r: s, c: t });
      if (e.length) {
        let { r: s, c: t } = e[Math.floor(Math.random() * e.length)];
        this.board[s][t] = {
          id: this.nextId++,
          value: Math.random() < 0.9 ? 2 : 4,
        };
      }
    }
  }
