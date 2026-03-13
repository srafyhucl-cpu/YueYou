/**
 * 2048: 无限闭环 - 核心内核 (v4.1 Final)
 */
export class Game {
    constructor() {
        this.MODES = { CLASSIC: 'classic', LOOP: 'loop' };
        this.PHASES = { NORMAL: 'normal', DISASSEMBLE: 'disassemble', REASSEMBLE: 'reassemble' };
        const savedBest = localStorage.getItem('bestScore_premium');
        this.bestScore = (savedBest && !isNaN(savedBest)) ? parseInt(savedBest) : 0;
        this.reset();
    }

    reset() {
        this.mode = this.MODES.CLASSIC;
        this.phase = this.PHASES.NORMAL;
        this.size = 4;
        this.score = 0;
        this.combo = 0;
        this.nextId = Date.now();
        this.over = false;
        this.won = false;
        this.phaseJustCleared = false;
        this.initBoard();
        this.addRandomTile();
        this.addRandomTile();
    }

    initBoard() {
        this.board = Array(this.size).fill().map(() => Array(this.size).fill(null));
        if (this.mode === this.MODES.LOOP) {
            this.board[2][2] = { id: 0, value: 2048, isAnchor: true };
        }
    }

    jumpToStage(stage) {
        this.won = false;
        this.over = false;
        this.phaseJustCleared = false;
        this.combo = 0;
        if (stage === 'classic') {
            this.mode = this.MODES.CLASSIC;
            this.size = 4;
            this.phase = this.PHASES.NORMAL;
            this.initBoard();
            this.addRandomTile(); this.addRandomTile();
        } else if (stage === 'loop_1') {
            this.mode = this.MODES.LOOP;
            this.size = 5;
            this.phase = this.PHASES.DISASSEMBLE;
            this.initBoard();
            this.seedDisassembleTiles();
        } else if (stage === 'loop_2') {
            this.mode = this.MODES.LOOP;
            this.size = 5;
            this.phase = this.PHASES.REASSEMBLE;
            this.initBoard();
            this.addLoopTile();
        } else if (stage === 'fast_win') {
            this.jumpToStage('loop_2');
            const ns = [{ r: 1, c: 2 }, { r: 3, c: 2 }, { r: 2, c: 1 }, { r: 2, c: 3 }];
            ns.forEach(p => this.board[p.r][p.c] = { id: this.nextId++, value: 512 });
            this.checkPhaseTransition();
        }
    }

    seedDisassembleTiles() {
        const values = [512, 256, 128, 64];
        for (let i = 0; i < 4; i++) {
            const empty = [];
            for (let r = 0; r < 5; r++) for (let c = 0; c < 5; c++)
                if (!this.board[r][c] && (r === 0 || r === 4 || c === 0 || c === 4)) empty.push({ r, c });
            if (empty.length) {
                const p = empty[Math.floor(Math.random() * empty.length)];
                this.board[p.r][p.c] = { id: this.nextId++, value: values[i] };
            }
        }
    }

    move(direction) {
        if (this.over || this.won || this.phaseJustCleared) return { moved: false, mergedTiles: [] };

        let moved = false;
        const mergedTiles = [];
        const vector = this.getVector(direction);
        const { rows, cols } = this.getTraversalOrder(vector);

        const newBoard = Array(this.size).fill().map(() => Array(this.size).fill(null));
        this.board.forEach((r, i) => r.forEach((t, j) => { if (t) newBoard[i][j] = { ...t }; }));

        const merged = Array(this.size).fill().map(() => Array(this.size).fill(false));

        rows.forEach(r => {
            cols.forEach(c => {
                const tile = newBoard[r][c];
                if (!tile || tile.isAnchor) return;

                let curr = { r, c }, next = { r: r + vector.y, c: c + vector.x };
                while (this.inBounds(next.r, next.c) && !newBoard[next.r][next.c]) {
                    newBoard[next.r][next.c] = tile;
                    newBoard[curr.r][curr.c] = null;
                    curr = { r: next.r, c: next.c };
                    next = { r: next.r + vector.y, c: next.c + vector.x };
                    moved = true;
                }

                if (this.inBounds(next.r, next.c)) {
                    const target = newBoard[next.r][next.c];
                    if (target && !target.isAnchor && target.value === tile.value && !merged[next.r][next.c]) {
                        const isDis = (this.mode === this.MODES.LOOP && this.phase === this.PHASES.DISASSEMBLE);
                        target.value = isDis ? Math.max(2, target.value / 2) : target.value * 2;
                        newBoard[curr.r][curr.c] = null;
                        merged[next.r][next.c] = true;
                        moved = true;
                        this.combo++;
                        this.score += target.value;
                        if (this.score > this.bestScore) {
                            this.bestScore = this.score;
                            localStorage.setItem('bestScore_premium', this.bestScore);
                        }
                        mergedTiles.push({ r: next.r, c: next.c, value: target.value, combo: this.combo });
                    }
                }
            });
        });

        if (moved) {
            if (mergedTiles.length === 0) this.combo = 0;
            this.board = newBoard;
            if (this.mode === this.MODES.LOOP) {
                this.addLoopTile();
                this.checkPhaseTransition();
            } else {
                this.addRandomTile();
                if (this.getMaxTileValue() >= 2048) this.phaseJustCleared = true;
            }
            if (!this.movesAvailable()) this.over = true;
        }
        return { moved, mergedTiles, combo: this.combo };
    }

    addLoopTile() {
        const outer = [];
        for (let r = 0; r < 5; r++) for (let c = 0; c < 5; c++)
            if ((r === 0 || r === 4 || c === 0 || c === 4) && !this.board[r][c]) outer.push({ r, c });
        if (outer.length) {
            const p = outer[Math.floor(Math.random() * outer.length)];
            const val = (this.phase === this.PHASES.REASSEMBLE) ? (Math.random() < 0.9 ? 2 : 4) : this.getMaxTileValue();
            this.board[p.r][p.c] = { id: this.nextId++, value: val };
        }
    }

    checkPhaseTransition() {
        if (this.phase === this.PHASES.DISASSEMBLE) {
            let needsWork = false, tileCount = 0;
            this.board.forEach(row => row.forEach(t => { if (t && !t.isAnchor) { tileCount++; if (t.value > 2) needsWork = true; } }));
            if (tileCount > 0 && !needsWork) this.phaseJustCleared = true;
        } else if (this.phase === this.PHASES.REASSEMBLE) {
            const ns = [{ r: 1, c: 2 }, { r: 3, c: 2 }, { r: 2, c: 1 }, { r: 2, c: 3 }];
            let win = true;
            ns.forEach(p => { if (!this.board[p.r][p.c] || this.board[p.r][p.c].value < 512) win = false; });
            if (win) this.won = true;
        }
    }

    clearTile(r, c) { if (this.board[r][c] && !this.board[r][c].isAnchor) { this.board[r][c] = null; return true; } return false; }
    getMaxTileValue() { let max = 2; this.board.forEach(row => row.forEach(t => { if (t && !t.isAnchor) max = Math.max(max, t.value); })); return max; }
    inBounds(r, c) { return r >= 0 && r < this.size && c >= 0 && c < this.size; }
    getVector(dir) { return { up: { x: 0, y: -1 }, down: { x: 0, y: 1 }, left: { x: -1, y: 0 }, right: { x: 1, y: 0 } }[dir]; }
    getTraversalOrder(v) {
        const r = [...Array(this.size).keys()], c = [...Array(this.size).keys()];
        if (v.y === 1) r.reverse(); if (v.x === 1) c.reverse();
        return { rows: r, cols: c };
    }
    movesAvailable() {
        for (let r = 0; r < this.size; r++) for (let c = 0; c < this.size; c++) {
            if (!this.board[r][c]) return true;
            for (let d of ['up', 'down', 'left', 'right']) {
                let v = this.getVector(d), tr = r + v.y, tc = c + v.x;
                if (this.inBounds(tr, tc)) {
                    const target = this.board[tr][tc];
                    if (!target || (!target.isAnchor && target.value === this.board[r][c].value)) return true;
                }
            }
        }
        return false;
    }
    addRandomTile() {
        const empty = [];
        for (let r = 0; r < this.size; r++) for (let c = 0; c < this.size; c++) if (!this.board[r][c]) empty.push({ r, c });
        if (empty.length) {
            const { r, c } = empty[Math.floor(Math.random() * empty.length)];
            this.board[r][c] = { id: this.nextId++, value: Math.random() < 0.9 ? 2 : 4 };
        }
    }
}
