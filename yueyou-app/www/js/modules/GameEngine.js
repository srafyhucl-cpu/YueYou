// ======================================
// 游戏引擎管理器 (GameEngine.js)
// 职责：处理 2048 棋盘的状态、移动、消除、分数计算
// （已精简：移除了多维度和所有阶段机制，专注于无尽版经典经典 2048，以便玩家集中注意力听书）
// ======================================

export class GameEngine {
    constructor() {
        let e = localStorage.getItem("bestScore_premium");
        this.bestScore = e && !isNaN(e) ? parseInt(e) : 0;
        this.maxCombo = parseInt(localStorage.getItem('maxCombo')) || 0;
        this.oldScore = 0;
        this.reset();
    }
    reset() {
        this.size = 4;
        this.score = 0;
        this.combo = 0;
        this.nextId = Date.now();
        this.over = false;
        this.awaitingRestart = false;
        this.initBoard();
        this.addRandomTile();
        this.addRandomTile();
        this.updateScore();
    }
    initBoard() {
        this.board = Array(this.size)
            .fill()
            .map(() => Array(this.size).fill(null));
    }
    triggerDeathConfirm() {
        if (confirm("你失败了！请重新开始\n\n点击【确定】重新开局\n点击【取消】关闭弹窗")) {
            this.reset();
            this.awaitingRestart = false;
            return true;
        }
        return false;
    }
    move(e) {
        if (this.over) {
            if (this.awaitingRestart) {
                let didReset = this.triggerDeathConfirm();
                return { moved: false, mergedTiles: Object.assign([], { isResetAction: didReset }) };
            } else {
                this.awaitingRestart = true;
            }
            return { moved: false, mergedTiles: [] };
        }
        let s = false,
            t = [],
            r = this.getVector(e),
            { rows: l, cols: y } = this.getTraversalOrder(r),
            v = Array(this.size)
                .fill()
                .map(() => Array(this.size).fill(null));
        this.board.forEach((u, w) =>
            u.forEach((h, E) => {
                if(h) v[w][E] = { ...h };
            })
        );
        let A = Array(this.size)
            .fill()
            .map(() => Array(this.size).fill(false));
            
        l.forEach((u) => {
            y.forEach((w) => {
                let h = v[u][w];
                if (!h) return;
                let E = { r: u, c: w },
                    m = { r: u + r.y, c: w + r.x };
                for (; this.inBounds(m.r, m.c) && !v[m.r][m.c]; ) {
                    v[m.r][m.c] = h;
                    v[E.r][E.c] = null;
                    E = { r: m.r, c: m.c };
                    m = { r: m.r + r.y, c: m.c + r.x };
                    s = true;
                }
                if (this.inBounds(m.r, m.c)) {
                    let M = v[m.r][m.c];
                    if (M && M.value === h.value && !A[m.r][m.c]) {
                        M.value = M.value * 2;
                        v[E.r][E.c] = null;
                        A[m.r][m.c] = true;
                        s = true;
                        this.combo++;
                        if (this.combo > this.maxCombo) {
                            this.maxCombo = this.combo;
                            localStorage.setItem("maxCombo", this.maxCombo);
                        }
                        t.push({
                            r: m.r,
                            c: m.c,
                            value: M.value,
                            combo: this.combo,
                        });
                    }
                }
            });
        });
        
        if (s) {
            if (t.length === 0) this.combo = 0;
            this.board = v;
            this.addRandomTile();
            this.updateScore();
            if(!this.movesAvailable()) {
                this.over = true;
                this.awaitingRestart = true;
                setTimeout(() => {
                    if (this.triggerDeathConfirm()) {
                        document.dispatchEvent(new CustomEvent('game-reset'));
                    }
                }, 500);
            }

            // --- 注入：3D 物理惯性倾斜 ---
            const gridEl = document.getElementById('grid-container');
            if (gridEl) {
                const tilt = 
                    e === 'up'    ? 'perspective(800px) rotateX(10deg)' :
                    e === 'right' ? 'perspective(800px) rotateY(10deg)' :
                    e === 'down'  ? 'perspective(800px) rotateX(-10deg)' :
                    e === 'left'  ? 'perspective(800px) rotateY(-10deg)' : '';
                gridEl.style.transform = tilt;
                
                setTimeout(() => {
                    gridEl.style.transform = 'perspective(800px) rotateX(0deg) rotateY(0deg)';
                }, 150);
            }
        }
        return { moved: s, mergedTiles: t, combo: this.combo };
    }
    updateScore() {
        this.score = 0;
        this.board.forEach((s) =>
            s.forEach((t) => {
                if (t) this.score += t.value;
            })
        );

        // 注入：机械翻页动画接管当前得分
        if (window.animateValue) {
            window.animateValue('score', this.oldScore || 0, this.score, 600);
        } else {
            const scoreEl = document.getElementById('score');
            if (scoreEl) scoreEl.innerText = this.score;
        }
        this.oldScore = this.score;

        if (this.score > this.bestScore) {
            this.bestScore = this.score;
            localStorage.setItem("bestScore_premium", this.bestScore);
        }
    }
    getMaxTileValue() {
        let e = 2;
        this.board.forEach((s) =>
            s.forEach((t) => {
                if(t) e = Math.max(e, t.value);
            })
        );
        return e;
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
        if(e.y === 1) s.reverse();
        if(e.x === 1) t.reverse();
        return { rows: s, cols: t };
    }
    movesAvailable() {
        for (let e = 0; e < this.size; e++)
            for (let s = 0; s < this.size; s++) {
                if (!this.board[e][s]) return true;
                for (let t of ["up", "down", "left", "right"]) {
                    let r = this.getVector(t),
                        l = e + r.y,
                        y = s + r.x;
                    if (this.inBounds(l, y)) {
                        let v = this.board[l][y];
                        if (!v || v.value === this.board[e][s].value)
                            return true;
                    }
                }
            }
        return false;
    }
    addRandomTile() {
        let e = [];
        for (let s = 0; s < this.size; s++)
            for (let t = 0; t < this.size; t++)
                if(!this.board[s][t]) e.push({ r: s, c: t });
        if (e.length) {
            let { r: s, c: t } = e[Math.floor(Math.random() * e.length)];
            this.board[s][t] = {
                id: this.nextId++,
                value: Math.random() < 0.9 ? 2 : 4,
            };
        }
    }
}
