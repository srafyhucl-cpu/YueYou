import { AudioManager } from './modules/AudioManager.js';
import { GameEngine } from './modules/GameEngine.js';
import { Renderer } from './modules/Renderer.js';
import { LocalDB } from './modules/LocalDB.js';

// 全局高维阅读进度引擎
window.ProgressManager = {
    // 获取指定书籍的进度
    getRecord(bookId) {
        let records = JSON.parse(localStorage.getItem('reading_records') || '{}');
        return records[bookId] || { cursor: 0, total: 1, percent: 0 };
    },
    // 更新指定书籍的进度
    updateRecord(bookId, cursor, total) {
        if (!bookId || total <= 0) return;
        let records = JSON.parse(localStorage.getItem('reading_records') || '{}');
        let percent = Math.min(100, (cursor / total) * 100);
        records[bookId] = { cursor, total, percent: parseFloat(percent.toFixed(2)) };
        localStorage.setItem('reading_records', JSON.stringify(records));
    },
    // 删除指定书籍的进度
    deleteRecord(bookId) {
        let records = JSON.parse(localStorage.getItem('reading_records') || '{}');
        delete records[bookId];
        localStorage.setItem('reading_records', JSON.stringify(records));
    }
};

// 全局赛博数字翻页器 (Odometer Engine)
window.animateValue = (elementId, start, end, duration) => {
    const obj = document.getElementById(elementId);
    if (!obj) return;
    if (end - start === 0) {
        obj.innerText = end;
        return;
    }
    let startTimestamp = null;
    const step = (timestamp) => {
        if (!startTimestamp) startTimestamp = timestamp;
        const progress = Math.min((timestamp - startTimestamp) / duration, 1);
        const easeOutProgress = 1 - Math.pow(1 - progress, 3); 
        obj.innerText = Math.floor(easeOutProgress * (end - start) + start);
        if (progress < 1) {
            window.requestAnimationFrame(step);
        } else {
            obj.innerText = end;
        }
    };
    window.requestAnimationFrame(step);
};

// 字符串转高定色彩流体渐变算法
window.generateCoverGradient = (title) => {
    let hash = 0;
    for (let i = 0; i < title.length; i++) hash = title.charCodeAt(i) + ((hash << 5) - hash);
    const h1 = Math.abs(hash % 360);
    const h2 = (h1 + 40) % 360; // 取相邻色相产生高级流体感
    return `linear-gradient(135deg, hsl(${h1}, 80%, 60%), hsl(${h2}, 80%, 40%))`;
};

let analyser = null;
let visualizerCtx = null;

// --- 浮动说明框系统 ---
window._showToast = (e, text) => {
    if (e && e.stopPropagation) e.stopPropagation();
    
    // 清除旧的 tooltip
    const old = document.querySelector('.floating-tooltip');
    if (old) old.remove();

    const tooltip = document.createElement('div');
    tooltip.className = 'floating-tooltip';
    tooltip.innerText = text;
    document.body.appendChild(tooltip);

    // 计算位置 (优先尝试在点击点上方)
    const x = e.clientX || (e.touches && e.touches[0].clientX);
    const y = e.clientY || (e.touches && e.touches[0].clientY);
    
    tooltip.style.left = Math.min(window.innerWidth - 200, Math.max(20, x - 100)) + 'px';
    tooltip.style.top = (y - 50) + 'px';

    // 3秒后自动淡出并销毁
    setTimeout(() => {
        tooltip.classList.add('tooltip-fade-out');
        setTimeout(() => tooltip.remove(), 500);
    }, 3000);
};

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
        ambientVol: parseFloat(localStorage.getItem("setting_ambient_vol") || "0.5"),
        ambientEnabled: localStorage.getItem("setting_ambient_enabled") !== "false", // 默认开启
        ambientTheme: localStorage.getItem("setting_ambient_theme") || "wuxia",
        storyTTS: localStorage.getItem("setting_story_tts") !== "false", 
        voice: localStorage.getItem("setting_voice") || "zh-CN-XiaoxiaoNeural",
        idleTimeout: parseInt(localStorage.getItem("setting_idle_timeout") || "1"),
      };

    const l = new AudioManager(t);
    window.AudioManager = l;
    Object.defineProperty(window, 'u', { get: () => l.u });

    function B(i, f) { let el = document.getElementById(i); if(el) el.addEventListener("click", f); }
    let V = document.getElementById("modal-library");
    let S = document.getElementById("modal-settings");
    let L = document.getElementById("modal-leaderboard");
    let C = document.getElementById("modal-chapters");

    let lastInteractionTime = Date.now();
    const updateInteraction = () => { lastInteractionTime = Date.now(); };
    ['mousedown', 'touchstart', 'keydown'].forEach(evt => document.addEventListener(evt, updateInteraction));

    setInterval(() => {
        if (!l.enabled || t.idleTimeout === 0) return;
        const idleTime = (Date.now() - lastInteractionTime) / 1000 / 60; 
        if (idleTime > t.idleTimeout && l.isSpeaking) {
            l.setEnabled(false);
            window._showToast({clientX: window.innerWidth/2, clientY: 100}, "由于长时间未操作，播报已自动暂停");
        }
    }, 10000); 

    const syncSettingsUI = () => {
        const ts = document.getElementById("toggle-sound");
        const tst = document.getElementById("toggle-story");
        const tv = document.getElementById("tts-voice-select");
        const ta = document.getElementById("toggle-ambient");
        const it = document.getElementById("idle-timeout");
        const itl = document.getElementById("idle-timeout-label");
        
        if (ts) ts.checked = t.sound;
        if (tst) tst.checked = t.storyTTS;
        if (tv) tv.value = t.voice;
        if (ta) ta.checked = t.ambientEnabled;
        if (it) it.value = t.idleTimeout;
        if (itl) itl.innerText = t.idleTimeout === 0 ? '永不停止' : t.idleTimeout + ' 分钟';
    };

    const updateSetting = (key, value) => {
        t[key] = value;
        const storageKey = `setting_${key === 'storyTTS' ? 'story_tts' : (key === 'ambientEnabled' ? 'ambient_enabled' : (key === 'idleTimeout' ? 'idle_timeout' : key))}`;
        localStorage.setItem(storageKey, value);
        l.settings = { ...t };
        
        if (key === 'voice' || key === 'storyTTS') {
            if (t.storyTTS) l.refreshSession();
            else l.setEnabled(false);
        }
        if (key === 'ambientEnabled') {
            if (value) l.playAmbient('game');
            else l.stopAmbient();
        }
        if (key === 'idleTimeout') {
            const itl = document.getElementById("idle-timeout-label");
            if (itl) itl.innerText = value === 0 ? '永不停止' : value + ' 分钟';
        }
    };

    const initSettingsListeners = () => {
        const ts = document.getElementById("toggle-sound");
        if (ts) ts.onchange = (e) => updateSetting('sound', e.target.checked);
        const tst = document.getElementById("toggle-story");
        if (tst) tst.onchange = (e) => updateSetting('storyTTS', e.target.checked);
        const tv = document.getElementById("tts-voice-select");
        if (tv) tv.onchange = (e) => updateSetting('voice', e.target.value);
        const ta = document.getElementById("toggle-ambient");
        if (ta) ta.onchange = (e) => updateSetting('ambientEnabled', e.target.checked);
        const it = document.getElementById("idle-timeout");
        if (it) it.oninput = (e) => updateSetting('idleTimeout', parseInt(e.target.value));
    };
    initSettingsListeners();

    B("btn-settings", () => { syncSettingsUI(); if (S) S.classList.remove("hidden"); });
    B("close-settings", () => { if (S) S.classList.add("hidden"); });

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

        container.innerHTML = shelf.map(b => {
            const record = window.ProgressManager.getRecord(b.id);
            const progressValue = record.percent || 0;
            const cleanTitle = (b.title || "未知").replace(/\.txt$/i, '');
            const coverChar = cleanTitle.charAt(0);
            const coverBg = window.generateCoverGradient(cleanTitle);
            const dashOffset = 62.8 - (progressValue / 100) * 62.8;

            return `
                <div class="bento-card" onclick="loadBookFromShelf(${b.id}, '${b.title.replace(/'/g, "\\'")}', ${b.cursor})">
                    <div class="bento-full-cover" style="background: ${coverBg};">
                        <span class="bento-watermark">${coverChar}</span>
                        <div class="bento-info-overlay">
                            <div class="bento-title">${cleanTitle}</div>
                            <div class="bento-meta">
                                <svg class="progress-ring" viewBox="0 0 24 24">
                                    <circle class="progress-ring-bg" cx="12" cy="12" r="10"></circle>
                                    <circle class="progress-ring-fill" cx="12" cy="12" r="10" stroke-dasharray="62.8" stroke-dashoffset="${dashOffset}"></circle>
                                </svg>
                                <button class="btn-bento-delete" onclick="event.stopPropagation(); deleteBook(${b.id})">删</button>
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    };

    window.loadBookFromShelf = async (id, title, cursor) => {
        await l.loadNovel(id, title, cursor);
        if (V) V.classList.add("hidden");
    };

    window.deleteBook = (id) => {
        if (!confirm("确定删除本书吗？")) return;
        if (window.ProgressManager) window.ProgressManager.deleteRecord(id);
        let shelf = JSON.parse(localStorage.getItem("local_bookshelf") || "[]");
        shelf = shelf.filter(x => x.id !== id);
        localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
        LocalDB.deleteBook(id);
        renderLibrary();
    };

    window._chapterReversed = false;
    const renderChapterList = () => {
        let container = document.getElementById("chapter-list");
        if (!container) return;
        if (!l.chapters || l.chapters.length === 0) {
            container.innerHTML = `<div style="text-align:center;padding:20px;color:gray;">暂无目录数据</div>`;
            const stats = document.getElementById("chapter-stats");
            if (stats) stats.innerText = "共 0 章 | 阅读进度 0%";
            return;
        }

        const total = l.chapters.length;
        const readPercent = Math.floor((l.cursor / l.lines.length) * 100);
        const stats = document.getElementById("chapter-stats");
        if (stats) stats.innerText = `共 ${total} 章 | 阅读进度 ${readPercent}%`;
        
        let activeIdx = -1;
        for (let i = l.chapters.length - 1; i >= 0; i--) {
            if (l.cursor >= l.chapters[i].lineIndex) {
                activeIdx = i;
                break;
            }
        }

        let displayChapters = window._chapterReversed ? [...l.chapters].reverse() : l.chapters;
        let html = "";
        for (let i = 0; i < displayChapters.length; i++) {
            const c = displayChapters[i];
            const originalIdx = window._chapterReversed ? (total - 1 - i) : i;
            let cls = "";
            if (originalIdx === activeIdx) cls = "active";
            else if (originalIdx < activeIdx) cls = "read";
            html += `
                <div id="chapter-item-${originalIdx}" class="chapter-item ${cls}" onclick="jumpTo(${c.lineIndex})">
                    <span class="chapter-status-dot"></span>
                    ${c.title}
                </div>
            `;
        }
        container.innerHTML = html;

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
                  const buffer = ev.target.result;
                  let text = "";
                  try {
                      const utf8Decoder = new TextDecoder('utf-8', { fatal: true });
                      text = utf8Decoder.decode(buffer);
                  } catch (e) {
                      const gbkDecoder = new TextDecoder('gb18030');
                      text = gbkDecoder.decode(buffer);
                  }
                  let rawLines = text.split(/\r?\n/).map(line => line.trim()).filter(line => line.length > 0);
                  let title = file.name.replace(".txt", "");
                  let bookId = Date.now();
                  await LocalDB.saveBook(bookId, rawLines);
                  let shelf = JSON.parse(localStorage.getItem("local_bookshelf") || "[]");
                  shelf.unshift({ id: bookId, title: title, total: rawLines.length, cursor: 0 });
                  localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
                  await l.loadNovel(bookId, title, 0);
                  renderLibrary();
              } catch (err) { console.error(err); } finally { mask.remove(); e.target.value = ""; }
           };
           reader.readAsArrayBuffer(file);
        });
    }

    B("btn-library", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
    B("close-library", () => { if (V) V.classList.add("hidden"); });
    B("btn-leaderboard", () => { s.loadLeaderboard(); if (L) L.classList.remove("hidden"); });
    B("close-leaderboard", () => { if (L) L.classList.add("hidden"); });
    B("btn-chapter-list", () => { if (C) { renderChapterList(); C.classList.remove("hidden"); } });
    B("btn-sort-chapters", () => { window._chapterReversed = !window._chapterReversed; renderChapterList(); });
    B("play-pause-icon", (e) => { window.toggleTTS(e); updateInteraction(); });
    B("player-progress-text", () => { if (C) { renderChapterList(); C.classList.remove("hidden"); } });
    B("player-capsule", (e) => { if (e.target.id === "play-pause-icon") return; if (C) { renderChapterList(); C.classList.remove("hidden"); } });
    B("btn-close-chapters", () => { if (C) C.classList.add("hidden"); });
    B("btn-idle-import", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
    B("restart-btn", () => { if (confirm("确定要重新开始游戏吗？进度将丢失。")) { p.reset(); e.render(p); s.saveLocalState(); } });
    document.querySelectorAll('.modal-overlay').forEach(overlay => { overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.classList.add('hidden'); }); });

    const handleMove = (dir) => {
        const result = p.move(dir);
        if (result.moved) {
            e.render(p, Array.isArray(result.mergedTiles) ? result.mergedTiles : []); 
            if (result.mergedTiles && result.mergedTiles.length > 0 && t.sound) l.playEffect('merge');
            l.unlockAudio(); 
            s.saveLocalState();
            updateInteraction();
        }
    };
    document.addEventListener("keydown", (e) => {
        const map = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right", w: "up", s: "down", a: "left", d: "right", W: "up", S: "down", A: "left", D: "right" };
        if (map[e.key]) { e.preventDefault(); handleMove(map[e.key]); }
    });
    let tsX, tsY;
    document.addEventListener("touchstart", (e) => { tsX = e.touches[0].clientX; tsY = e.touches[0].clientY; }, { passive: false });
    document.addEventListener("touchend", (e) => { if (!tsX || !tsY) return; let teX = e.changedTouches[0].clientX, teY = e.changedTouches[0].clientY; let dx = teX - tsX, dy = teY - tsY; if (Math.abs(dx) > 30 || Math.abs(dy) > 30) { if (Math.abs(dx) > Math.abs(dy)) handleMove(dx > 0 ? "right" : "left"); else handleMove(dy > 0 ? "down" : "up"); } tsX = null; tsY = null; }, { passive: false });

    window._syncIdleState = () => {
        let idle = document.getElementById("player-idle-state");
        let capsule = document.getElementById("player-capsule");
        if (!idle) return;
        if (l.lines && l.lines.length > 0) { idle.classList.add("hidden"); if (capsule) capsule.classList.remove("hidden"); }
        else { idle.classList.remove("hidden"); if (capsule) capsule.classList.add("hidden"); }
    };

    const startApp = () => { loadSavedState(); e.render(p); l.syncGameState(p); l.checkHeadphonesAndStart(); };
    let pm = document.getElementById('privacy-modal');
    if (!pm || localStorage.getItem('privacy_agreed') === 'true') { if (pm) pm.classList.add('hidden'); startApp(); }
    else { pm.classList.remove('hidden'); B('btn-privacy-agree', () => { localStorage.setItem('privacy_agreed', 'true'); pm.classList.add('hidden'); startApp(); }); }

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
    if (!am.lines || am.lines.length === 0) { window._showToast(e, "请先在图书馆中加载书籍"); return; }
    if (window.u && window.u.state === 'suspended') window.u.resume();
    am.setEnabled(!am.enabled);
};
