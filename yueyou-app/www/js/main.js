import { AudioManager } from './modules/AudioManager.js';
import { GameEngine } from './modules/GameEngine.js';
import { Renderer } from './modules/Renderer.js';
import { LocalDB } from './modules/LocalDB.js';

let analyser = null;
let visualizerCtx = null;

(() => {
  document.addEventListener("DOMContentLoaded", () => {
    let p = new GameEngine(),
      e = new Renderer(),
      s = {
        async saveScore(f, i) {},
        async loadLeaderboard() { 
          let lb = document.getElementById("leaderboard-content"); 
          if(lb) lb.innerHTML = "<p style=\"text-align:center;color:gray\">离线单机模式不支持排行榜</p>"; 
        },
        saveLocalState() {
          let st = {
            board_data: JSON.stringify(p.board),
            score: p.score, 
            combo: p.combo,
            bestScore: p.bestScore,
            maxCombo: p.maxCombo,
            novel_index: l.cursor,
            current_novel_id: l.novelID
          };
          localStorage.setItem("local_save_data", JSON.stringify(st));
        }
      },
      t = {
        sound: localStorage.getItem("setting_sound") !== "false",
        vibration: localStorage.getItem("setting_vibration") !== "false",
        ambientVol: parseFloat(localStorage.getItem("setting_ambient_vol") || "0.5"),
        ambientTheme: localStorage.getItem("setting_ambient_theme") || "wuxia",
        storyTTS: localStorage.getItem("setting_story_tts") === "true",
      };

    const l = new AudioManager(t);
    window.AudioManager = l;
    Object.defineProperty(window, 'u', { get: () => l.u });

    function B(i, f) { let el = document.getElementById(i); if(el) el.addEventListener("click", f); }
    let V = document.getElementById("modal-library");
    let S = document.getElementById("modal-settings");
    let L = document.getElementById("modal-leaderboard");
    let C = document.getElementById("modal-chapters");

    // 恢复游戏进度
    const loadSavedState = () => {
        const saved = localStorage.getItem("local_save_data");
        if (saved) {
            try {
                const st = JSON.parse(saved);
                if (st.board_data) {
                    p.board = JSON.parse(st.board_data);
                    p.score = st.score || 0;
                    p.combo = st.combo || 0;
                    p.bestScore = st.bestScore || p.bestScore;
                    p.maxCombo = st.maxCombo || p.maxCombo;
                    
                    // 确保 ID 不冲突
                    let maxId = 0;
                    p.board.forEach(row => row.forEach(tile => {
                        if (tile && tile.id) maxId = Math.max(maxId, tile.id);
                    }));
                    p.nextId = maxId + 1;
                }
            } catch (err) { console.error("Failed to load game state", err); }
        }
    };

    const renderLibrary = async () => {
        let shelfText = localStorage.getItem("local_bookshelf");
        let shelf = shelfText ? JSON.parse(shelfText) : [];
        let container = document.getElementById("library-content");
        if (!container) return;
        if (shelf.length === 0) {
            container.innerHTML = `<div style="text-align:center;padding:40px;color:rgba(255,255,255,0.3);"><div style="font-size:40px;margin-bottom:10px;">🕳️</div>书架空空的</div>`;
            return;
        }
        container.innerHTML = shelf.map(b => `
            <div class="book-card" onclick="loadBookFromShelf(${b.id}, '${b.title.replace(/'/g, "\\'")}', ${b.cursor})">
                <div class="book-cover">📖</div>
                <div class="book-info">
                    <div class="book-title">${b.title}</div>
                    <div class="book-meta">进度: ${Math.floor((b.cursor/b.total)*100)}%</div>
                </div>
                <div class="book-delete" onclick="event.stopPropagation(); deleteBook(${b.id})">🗑️</div>
            </div>
        `).join('');
    };

    window.loadBookFromShelf = async (id, title, cursor) => {
        await l.loadNovel(id, title, cursor);
        if (V) V.classList.add("hidden");
    };

    window.deleteBook = (id) => {
        if (!confirm("确定删除本书吗？")) return;
        let shelf = JSON.parse(localStorage.getItem("local_bookshelf") || "[]");
        shelf = shelf.filter(x => x.id !== id);
        localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
        LocalDB.deleteBook(id);
        renderLibrary();
    };

    const renderChapterList = () => {
        let container = document.getElementById("chapter-list");
        if (!container) return;
        if (!l.chapters || l.chapters.length === 0) {
            container.innerHTML = `<div style="text-align:center;padding:20px;color:gray;">暂无目录数据</div>`;
            return;
        }
        
        // 计算当前活动章节
        let activeIdx = -1;
        for (let i = l.chapters.length - 1; i >= 0; i--) {
            if (l.cursor >= l.chapters[i].lineIndex) {
                activeIdx = i;
                break;
            }
        }

        container.innerHTML = l.chapters.map((c, i) => {
            let cls = "";
            if (i === activeIdx) cls = "active";
            else if (i < activeIdx) cls = "read";
            
            return `
                <div id="chapter-item-${i}" class="chapter-item ${cls}" onclick="jumpTo(${c.lineIndex})">
                    <span class="chapter-status-dot"></span>
                    ${c.title}
                </div>
            `;
        }).join('');

        // 自动滚动到当前章节
        if (activeIdx !== -1) {
            setTimeout(() => {
                const activeEl = document.getElementById(`chapter-item-${activeIdx}`);
                if (activeEl) activeEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }, 100);
        }
    };

    window.jumpTo = (idx) => {
        l.jumpToChapter(idx);
        if (C) C.classList.add("hidden");
    };

    const fileInput = document.getElementById("upload-novel-file");
    if (fileInput) {
        fileInput.addEventListener("change", async (e) => {
           let file = e.target.files[0];
           if (!file) return;
           let reader = new FileReader();
           reader.onload = async (ev) => {
              let mask = document.createElement("div");
              mask.style.cssText = "position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.6); backdrop-filter:blur(10px); z-index:10000; display:flex; align-items:center; justify-content:center; color:#fff;";
              mask.innerHTML = "<div style='text-align:center;'><div style='font-size:40px; margin-bottom:20px;'>📚</div>正在构建本地库...</div>";
              document.body.appendChild(mask);
              try {
                  let text = ev.target.result;
                  let rawLines = text.split("\n").map(line => line.trim()).filter(line => line.length > 0);
                  let newLines = rawLines.map((line, idx) => ({ v: "zh-CN-XiaoxiaoNeural", t: line }));
                  let title = file.name.replace(".txt", "");
                  let chapters = [];
                  const chapterRegex = /^第[0-9零一二三四五六七八九十百千两]+[章回节卷集部篇].*$/;
                  rawLines.forEach((line, index) => {
                      if (line.match(chapterRegex)) chapters.push({ title: line.trim(), lineIndex: index });
                  });
                  let bookId = Date.now();
                  await LocalDB.saveBook(bookId, { lines: newLines, chapters: chapters });
                  let shelf = JSON.parse(localStorage.getItem("local_bookshelf") || "[]");
                  shelf.unshift({ id: bookId, title: title, total: newLines.length, cursor: 0 });
                  localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
                  await l.loadNovel(bookId, title, 0);
                  renderLibrary();
              } catch (err) { console.error(err); } finally { mask.remove(); e.target.value = ""; }
           };
           reader.readAsText(file, "UTF-8");
        });
    }

    B("btn-library", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
    B("close-library", () => { if (V) V.classList.add("hidden"); });
    
    B("btn-settings", () => { if (S) S.classList.remove("hidden"); });
    B("close-settings", () => { if (S) S.classList.add("hidden"); });
    
    B("btn-leaderboard", () => { s.loadLeaderboard(); if (L) L.classList.remove("hidden"); });
    B("close-leaderboard", () => { if (L) L.classList.add("hidden"); });

    B("btn-chapter-list", () => { if (C) { renderChapterList(); C.classList.remove("hidden"); } });

    B("play-pause-icon", (e) => {
        window.toggleTTS(e);
    });

    B("player-progress-text", () => {
        if (C) { renderChapterList(); C.classList.remove("hidden"); }
    });

    B("player-capsule", (e) => {
        if (e.target.id === "play-pause-icon") return;
        if (C) { renderChapterList(); C.classList.remove("hidden"); }
    });
    B("btn-close-chapters", () => { if (C) C.classList.add("hidden"); });
    B("btn-idle-import", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
    
    B("restart-btn", () => {
        if (confirm("确定要重新开始游戏吗？进度将丢失。")) {
            p.reset();
            e.render(p);
            s.saveLocalState();
        }
    });

    // 点击空白处关闭弹窗
    document.querySelectorAll('.modal-overlay').forEach(overlay => {
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) overlay.classList.add('hidden');
        });
    });

    // 游戏核心输入绑定
    const handleMove = (dir) => {
        const result = p.move(dir);
        if (result.moved) {
            e.render(p, Array.isArray(result.mergedTiles) ? result.mergedTiles : []); 
            if (result.mergedTiles && result.mergedTiles.length > 0) l.playEffect('merge');
            l.unlockAudio(); 
            s.saveLocalState(); // 移动后强制保存进度
        }
    };

    document.addEventListener("keydown", (e) => {
        const map = {
            ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
            w: "up", s: "down", a: "left", d: "right",
            W: "up", S: "down", A: "left", D: "right"
        };
        if (map[e.key]) {
            e.preventDefault();
            handleMove(map[e.key]);
        }
    });

    // 触摸滑动支持
    let tsX, tsY;
    document.addEventListener("touchstart", (e) => { tsX = e.touches[0].clientX; tsY = e.touches[0].clientY; }, { passive: false });
    document.addEventListener("touchend", (e) => {
        if (!tsX || !tsY) return;
        let teX = e.changedTouches[0].clientX, teY = e.changedTouches[0].clientY;
        let dx = teX - tsX, dy = teY - tsY;
        if (Math.abs(dx) > 30 || Math.abs(dy) > 30) {
            if (Math.abs(dx) > Math.abs(dy)) handleMove(dx > 0 ? "right" : "left");
            else handleMove(dy > 0 ? "down" : "up");
        }
        tsX = null; tsY = null;
    }, { passive: false });

    window._syncIdleState = () => {
        let idle = document.getElementById("player-idle-state");
        let capsule = document.getElementById("player-capsule");
        if (!idle) return;
        if (l.lines && l.lines.length > 0) {
            idle.classList.add("hidden");
            if (capsule) capsule.classList.remove("hidden");
        } else {
            idle.classList.remove("hidden");
            if (capsule) capsule.classList.add("hidden");
        }
    };

    const startApp = () => {
        loadSavedState(); // 启动时注入存档
        e.render(p);
        l.syncGameState(p);
        l.checkHeadphonesAndStart();
    };

    let pm = document.getElementById('privacy-modal');
    if (!pm || localStorage.getItem('privacy_agreed') === 'true') {
        if (pm) pm.classList.add('hidden');
        startApp();
    } else {
        pm.classList.remove('hidden');
        B('btn-privacy-agree', () => {
            localStorage.setItem('privacy_agreed', 'true');
            pm.classList.add('hidden');
            startApp();
        });
    }

    const drawVisualizer = () => {
        requestAnimationFrame(drawVisualizer);
        if (!analyser && window.analyser) analyser = window.analyser;
        let canvas = document.getElementById('audio-visualizer');
        if (!canvas) return;
        if (!visualizerCtx) visualizerCtx = canvas.getContext('2d');
        visualizerCtx.clearRect(0, 0, canvas.width, canvas.height);
        const barCount = 4; const barWidth = 3; const gap = 3;
        const totalWidth = barCount * barWidth + (barCount - 1) * gap;
        const startX = (canvas.width - totalWidth) / 2;
        let dataArray = new Uint8Array(32);
        if (analyser) analyser.getByteFrequencyData(dataArray);
        for (let i = 0; i < barCount; i++) {
            let value = dataArray[[1, 3, 5, 8][i]] || 0;
            if (l.isSpeaking) { if (value < 10) value = 50 + Math.random() * 150; } 
            else if (l.enabled) { value = 40 + Math.sin(Date.now() / 200 + i) * 30; } 
            else { value = 5; }
            let percent = Math.pow(value / 255, 0.85); 
            let barHeight = Math.max(2, percent * canvas.height * 1.2); 
            if (barHeight > canvas.height) barHeight = canvas.height;
            let gradient = visualizerCtx.createLinearGradient(0, (canvas.height - barHeight)/2, 0, (canvas.height + barHeight)/2);
            gradient.addColorStop(0, '#00f2fe'); gradient.addColorStop(0.5, '#4facfe'); gradient.addColorStop(1, '#00f2fe');
            visualizerCtx.fillStyle = gradient;
            const x = startX + i * (barWidth + gap);
            const y = (canvas.height - barHeight) / 2;
            visualizerCtx.beginPath();
            visualizerCtx.roundRect(x, y, barWidth, barHeight, 2);
            visualizerCtx.fill();
        }
    };
    drawVisualizer();
  });
})();

window.toggleTTS = (e) => {
    e.stopPropagation();
    if (!window.AudioManager) return;
    const am = window.AudioManager;
    if (!am.lines || am.lines.length === 0) {
        if (window._showToast) window._showToast("请先在图书馆中加载书籍");
        return;
    }
    if (window.u && window.u.state === 'suspended') window.u.resume();
    am.setEnabled(!am.enabled);
};
