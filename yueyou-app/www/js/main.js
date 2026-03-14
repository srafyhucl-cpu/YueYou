import { AudioManager } from './modules/AudioManager.js';
import { GameEngine } from './modules/GameEngine.js';
import { Renderer } from './modules/Renderer.js';
import { LocalDB } from './modules/LocalDB.js';

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
            bestScore: p.bestScore,
            novel_index: l.cursor,
            current_novel_id: l.novelID
          };
          localStorage.setItem("local_save_data", JSON.stringify(st));
          let shelfText = localStorage.getItem("local_bookshelf");
          if (shelfText) {
              try {
                  let shelf = JSON.parse(shelfText);
                  let b = shelf.find(x => x.id === l.novelID);
                  if (b) {
                      b.cursor = l.cursor;
                      localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
                  }
              } catch(e){}
          }
        },
        async loadLocalState() {
          let st = localStorage.getItem("local_save_data");
          if(st) {
            try {
              let I = JSON.parse(st);
              p.board = JSON.parse(I.board_data);
              p.score = I.score || 0; 
              p.bestScore = Math.max(p.bestScore || 0, I.bestScore || 0, p.score);
              e.render(p);
              if (I.current_novel_id) {
                  l.novelID = I.current_novel_id;
                  l.cursor = I.novel_index || 0;
              }
            } catch(e){}
          }
        }
      },
      t = {
        sound: localStorage.getItem("setting_sound") !== "false",
        vibration: localStorage.getItem("setting_vibration") !== "false",
        ambientVol: parseFloat(localStorage.getItem("setting_ambient_vol") || "0.5"),
        ambientTheme: localStorage.getItem("setting_ambient_theme") || "wuxia",
        storyTTS: localStorage.getItem("setting_story_tts") === "true",
      };

    // 初始化声音管理器（使用模块化组件）
    const l = new AudioManager(t);
    let y = null;

    // 浏览器音频策略静音解锁器（全域首次交互 - iOS/Chrome AutoPlay Policy）
    const unlockAudioEngine = () => {
        // 解锁 AudioManager 内部的 AudioContext
        l.unlockAudio();
        if (l.u && l.u.state === 'suspended') {
            l.u.resume().then(() => console.log('[Audio] AudioContext resumed on user interaction.')).catch(() => {});
        }
        // 尝试播放一段无声的极炉音频以解锁浏览器静音策略
        try {
            let silentAudio = new Audio('data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=');
            silentAudio.volume = 0.01;
            silentAudio.play().then(() => silentAudio.pause()).catch(() => {});
        } catch(e) {}
        document.removeEventListener('touchstart', unlockAudioEngine);
        document.removeEventListener('click', unlockAudioEngine);
    };
    document.addEventListener('touchstart', unlockAudioEngine, { once: true });
    document.addEventListener('click', unlockAudioEngine, { once: true });

    window._showToast = (f) => {
        let i = document.getElementById("sys-toast");
        (i ||
          ((i = document.createElement("div")),
          (i.id = "sys-toast"),
          (i.style.cssText =
            "position:fixed; bottom:120px; left:50%; transform:translateX(-50%); background:rgba(0,0,0,0.8); color:#fff; padding:12px 24px; border-radius:30px; font-size:14px; word-break:keep-all; z-index:9999; opacity:0; transition:opacity 0.3s; pointer-events:none;"),
          document.body.appendChild(i)),
          (i.innerText = f),
          (i.style.opacity = "1"),
          clearTimeout(i._to),
          (i._to = setTimeout(() => (i.style.opacity = "0"), 3e3)));
    };

    let v = () => {
        s.saveLocalState();
    },
    A = () => {
        (y && clearTimeout(y), (y = setTimeout(v, 1e3)));
    };

    (document.addEventListener("visibilitychange", () => {
      document.hidden && v();
    }),
    s.loadLocalState(), 
    localStorage.getItem("score_version_v2") ||
    (localStorage.removeItem("bestScore_premium"),
    localStorage.setItem("score_version_v2", "1"),
    (p.bestScore = 0)));

    let G = async (f) => {
        let i = document.getElementById("tile-container");
        if (p.phaseJustCleared || i.classList.contains("targeting")) return;
        let res = p.move(f);
        let c = res.moved;
        let a = res.mergedTiles;
        if (res.mergedTiles && res.mergedTiles.isResetAction) {
            e.render(p);
            return;
        }
        if (c) {
          if ((l.heartbeat(), A(), e.render(p, a), a.length > 0)) {
            let g = Math.max(...a.map((x) => x.value));
            l.playMergeSound(g);
            if (t.vibration && navigator.vibrate) {
                if (g >= 512) { e.shake(); navigator.vibrate([80, 30, 40]); }
                else if (g >= 128) { e.shake(); navigator.vibrate([50, 20, 30]); }
                else if (g >= 64) { navigator.vibrate(30); }
                else { navigator.vibrate(10); }
            }
            if ([512, 1024, 2048].includes(g)) {
                [g * 2, g * 4, g * 8, g * 16].forEach((x, T) =>
                    setTimeout(() => l.playMergeSound(x), T * 150)
                );
            }
          }
          if ((p.won || p.phaseJustCleared)) {
            s.saveScore(localStorage.getItem("player_name"), p.score);
          }
          if (p.over) {
              await e.playTransition("defeat");
              e.render(p);
          }
        }
    };

    // UI 控制与事件监听
    (() => {
      let B = (o, d) => {
        let S = document.getElementById(o);
        S && (S.onclick = d);
      };

      B("player-mute-btn", () => {
        let o = !l.enabled;
        l.toggle(o);
        let toggle = document.getElementById("toggle-story");
        if (toggle) toggle.checked = o;
        let btn = document.getElementById("player-mute-btn");
        if (btn) btn.innerText = o ? "\u{1F50A}" : "\u{1F507}";
      });

      document.querySelectorAll('.modal-overlay').forEach(overlay => {
          overlay.addEventListener('click', (e) => {
              if (e.target === overlay) {
                  let closeBtnId = overlay.id === 'modal-settings' ? 'close-settings' :
                                 overlay.id === 'modal-library' ? 'close-library' :
                                 overlay.id === 'modal-leaderboard' ? 'close-leaderboard' : null;
                  if (closeBtnId) {
                      let btn = document.getElementById(closeBtnId);
                      if (btn) btn.click();
                  } else {
                      overlay.classList.add('hidden');
                  }
              }
          });
      });

      let C = document.getElementById("toggle-sound"),
        D = document.getElementById("toggle-vibration"),
        z = document.getElementById("toggle-story"),
        T = document.getElementById("ambient-theme"),
        R = document.getElementById("idle-timeout");

      if (C) C.checked = t.sound;
      if (D) D.checked = t.vibration;
      if (z) z.checked = t.storyTTS;
      if (T) T.value = t.ambientTheme;
      if (R) {
        let o = parseInt(localStorage.getItem("setting_idle_timeout") || "1");
        R.value = o;
        let label = document.getElementById("idle-timeout-label");
        if (label) label.innerText = o == 0 ? "永不停止" : o + " 分钟";
      }
      let ttsVoiceSelect = document.getElementById("tts-voice-select");
      if (ttsVoiceSelect) {
          let savedVoice = localStorage.getItem("tts_voice");
          if (savedVoice) ttsVoiceSelect.value = savedVoice;
          ttsVoiceSelect.addEventListener("change", (e) => {
              localStorage.setItem("tts_voice", e.target.value);
              l.jumpToChapter(l.cursor);
          });
      }

      B("btn-settings", () => document.getElementById("modal-settings").classList.remove("hidden"));
      B("close-settings", () => {
          if (C) t.sound = C.checked;
          if (D) t.vibration = D.checked;
          if (z) l.toggle(z.checked);
          let o = document.getElementById("ambient-volume");
          if (o) t.ambientVol = parseFloat(o.value);
          if (R) {
            let d = parseInt(R.value);
            localStorage.setItem("setting_idle_timeout", d);
            l.idleTimeout = d * 6e4;
          }
          localStorage.setItem("setting_sound", t.sound);
          localStorage.setItem("setting_vibration", t.vibration);
          localStorage.setItem("setting_ambient_vol", t.ambientVol);
          document.getElementById("modal-settings").classList.add("hidden");
          t.sound ? l.syncGameState(p) : l.stopAmbient();
          document.body.className = 'theme-wuxia';
      });

      B("btn-admin", () => document.getElementById("admin-panel").classList.toggle("hidden"));
      B("btn-leaderboard", () => {
          document.getElementById("modal-leaderboard").classList.remove("hidden");
          s.loadLeaderboard();
      });
      B("close-leaderboard", () => document.getElementById("modal-leaderboard").classList.add("hidden"));
      B("restart-btn", () => {
          if (confirm("重置进度？")) { p.reset(); e.render(p); }
      });
      // 目录按钮事件
      const renderChapterList = () => {
          let list = document.getElementById("chapter-list");
          if (!list) return;
          list.innerHTML = "";
          if (!l.chapters || l.chapters.length === 0) {
              list.innerHTML = '<p style="text-align:center; color:#a0a0b0; margin-top:20px;">当前书籍未解析出目录或尚未加载...</p>';
              return;
          }
          let displayChapters = [...l.chapters];
          displayChapters.forEach((ch, originalIdx) => {
              // 匹配原数组中对应的对象以判断 isActive，用原始 index 计算范围
              let nextCh = l.chapters[originalIdx + 1];
              let isActive = (l.cursor >= ch.lineIndex) && (!nextCh || l.cursor < nextCh.lineIndex);
              
              let li = document.createElement("li");
              li.className = "chapter-item" + (isActive ? " active" : "");
              li.innerHTML = `<span>${ch.title}</span>`;
              li.onclick = () => {
                  l.jumpToChapter(ch.lineIndex);
                  document.getElementById("modal-chapters").classList.add("hidden");
              };
              list.appendChild(li);
          });
          // 自动滚动到当前活动章节
          setTimeout(() => {
              let activeItem = list.querySelector(".chapter-item.active");
              if (activeItem) activeItem.scrollIntoView({ behavior: "smooth", block: "center" });
          }, 50);
      };

      B("btn-chapter-list", () => {
          let modal = document.getElementById("modal-chapters");
          if (!modal) return;
          renderChapterList();
          modal.classList.remove("hidden");
      });
      
      B("btn-sort-chapters", () => {
          document.getElementById("chapter-list").classList.toggle("reversed");
      });

      B("btn-close-chapters", () => document.getElementById("modal-chapters").classList.add("hidden"));
      let V = document.getElementById("modal-library");
      let H = document.getElementById("library-content");
      let renderLibrary = () => {
          if (!H) return;
          let shelfText = localStorage.getItem("local_bookshelf");
          let shelf = shelfText ? JSON.parse(shelfText) : [];
          if(shelf.length === 0) {
              H.innerHTML = '<p style="text-align:center;color:rgba(255,255,255,0.5);margin-top:20px;">当前书架为空，请导入 TXT 本地小说</p>';
              return;
          }
          H.innerHTML = '<div style="display:flex; flex-direction:column; gap:12px;">' + shelf.map((b, I) => {
              let isCur = (String(b.id) === String(l.novelID));
              let pct = b.total > 0 ? Math.floor((b.cursor / b.total) * 100) : 0;
              return `
                <div style="display:flex; justify-content:space-between; align-items:center; padding:16px; border-radius:12px; cursor:pointer; transition:all 0.2s; background:rgba(255,255,255,0.1); border:1px solid ${isCur ? 'var(--accent-pink)' : 'rgba(255,255,255,0.15)'}; box-shadow:0 4px 6px rgba(0,0,0,0.2);" 
                     onclick="window._readBook(${b.id}, '${b.title.replace(/'/g, "\\'")}', ${b.cursor})">
                    <div style="flex:1; min-width:0; margin-right:12px;">
                        <div style="display:flex; align-items:center; gap:8px; margin-bottom:6px;">
                            <span style="font-size:20px;">📖</span>
                            <div style="color:#fff; font-weight:800; font-size:14px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${b.title}</div>
                            ${isCur ? '<span style="background:var(--accent-pink); color:#fff; font-size:9px; padding:2px 6px; border-radius:4px; font-weight:800; flex-shrink:0;">阅读中</span>' : ''}
                        </div>
                        <div style="display:flex; align-items:center; gap:8px;">
                            <div style="flex:1; height:4px; background:rgba(255,255,255,0.1); border-radius:2px; overflow:hidden;">
                                <div style="width:${pct}%; height:100%; background:${isCur ? 'var(--accent-pink)' : 'rgba(255,255,255,0.4)'}; border-radius:2px;"></div>
                            </div>
                            <span style="font-size:11px; color:rgba(255,255,255,0.5); font-weight:bold; flex-shrink:0;">${pct}%</span>
                        </div>
                    </div>
                    <div style="width:32px; height:32px; background:rgba(255,80,80,0.15); border:1px solid rgba(255,80,80,0.3); border-radius:8px; display:flex; align-items:center; justify-content:center; font-size:14px; flex-shrink:0; cursor:pointer; transition:all 0.2s;" 
                         onclick="window._deleteBook(${b.id}, event)" 
                         onmouseover="this.style.background='rgba(255,80,80,0.4)'" 
                         onmouseout="this.style.background='rgba(255,80,80,0.15)'"
                    >🗑️</div>
                </div>
              `;
          }).join("") + '</div>';
      };

      window._deleteBook = async (id, e) => {
          e.stopPropagation();
          if(!confirm("确认从本地数据库中彻底抹除此书的维度记录？")) return;
          let shelfText = localStorage.getItem("local_bookshelf");
          let shelf = shelfText ? JSON.parse(shelfText) : [];
          shelf = shelf.filter(b => b.id !== id);
          localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
          await LocalDB.deleteBook(id);
          
          if (String(localStorage.getItem("current_novel_id")) === String(id)) {
              localStorage.removeItem("current_novel_id");
              localStorage.removeItem("novel_progress");
              l.stop();
              l.lines = [];
              l.novelID = null;
              l.novelTitle = "未加载书籍";
              l.cursor = 0;
              let titleEl = document.getElementById("player-title");
              if (titleEl) titleEl.innerText = "未加载书籍";
              let chapEl = document.getElementById("player-chapter");
              if (chapEl) chapEl.innerText = "";
              l.updateUI();
          }

          renderLibrary();
          if (typeof window._syncIdleState === 'function') window._syncIdleState();
          window._showToast("书籍已从维度中抹除");
      };

      window._readBook = async (id, title, cursor) => {
           await l.loadNovel(id, title, cursor);
           if (V) V.classList.add("hidden");
           // 自动播放：用户点击本身就是 User Gesture，不会被浏览器拦截
           let autoTts = document.getElementById("toggle-story");
           if (autoTts && autoTts.checked) {
               if (l.u && l.u.state === 'suspended') l.u.resume().catch(() => {});
               l.setEnabled(true);
           }
           renderLibrary();
      };

      let uploader = document.getElementById("upload-novel-file");
      if (uploader) {
        uploader.addEventListener("change", (e) => {
          let file = e.target.files[0];
          if (!file) return;
          let reader = new FileReader();
          reader.onload = async (ev) => {
             let mask = document.createElement("div");
             mask.style.cssText = "position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.6); backdrop-filter:blur(10px); z-index:10000; display:flex; align-items:center; justify-content:center; color:#fff; font-weight:800;";
             mask.innerHTML = "<div style='text-align:center;'><div style='font-size:40px; margin-bottom:20px;'>📚</div>正在构建本地维度数据库...</div>";
             document.body.appendChild(mask);

             try {
                 let text = ev.target.result;
                 let rawLines = text.split("\n").map(line => line.trim()).filter(line => line.length > 0);
                 if (rawLines.length === 0) return alert("文件为空");
                 let newLines = rawLines.map((line, idx) => {
                    let speakers = ["zh-CN-YunyangNeural", "zh-CN-YunxiNeural", "zh-CN-YunxiaNeural", "zh-CN-YunjianNeural"];
                    return { v: speakers[idx % 4], t: line };
                 });
                 let title = file.name.replace(".txt", "");
                 
                 let chapters = [];
                 const chapterRegex = /^\s*(\d{1,5}\s+.*|\d{1,5}\s*第[0-9零一二三四五六七八九十百千两]+[章回节卷集部篇].*|第[0-9零一二三四五六七八九十百千两]+[章回节卷集部篇].*)$/;
                 rawLines.forEach((line, index) => {
                     let match = line.match(chapterRegex);
                     if (match) chapters.push({ title: match[1].trim(), lineIndex: index });
                 });

                 let bookId = Date.now();
                 await LocalDB.saveBook(bookId, { lines: newLines, chapters: chapters });
                 let shelfText = localStorage.getItem("local_bookshelf");
                 let shelf = shelfText ? JSON.parse(shelfText) : [];
                 shelf.unshift({ id: bookId, title: title, total: newLines.length, cursor: 0 });
                 localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
                 await l.loadNovel(bookId, title, 0);
                 // 导入后自动播放（用户参与了文件选择，算有效交互）
                 let autoTts = document.getElementById("toggle-story");
                 if (autoTts && autoTts.checked) {
                     if (l.u && l.u.state === 'suspended') l.u.resume().catch(() => {});
                     l.setEnabled(true);
                 }
                 window._showToast("加载本地小说成功");
                 renderLibrary();
             } catch (e) {
                 console.error("Import failed:", e);
                 window._showToast("导入失败: " + (e.message || "未知错误"));
             } finally {
                 mask.remove();
                 e.target.value = "";
             }
          };
          reader.readAsText(file, "UTF-8");
        });
      }
      B("btn-library", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
      B("player-info", () => {
          let modal = document.getElementById("modal-chapters");
          if (modal) {
              renderChapterList();
              modal.classList.remove("hidden");
          }
      });
      B("close-library", () => { if (V) V.classList.add("hidden"); });

      B("btn-idle-import", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
      window._syncIdleState = () => {
          let idle = document.getElementById("player-idle-state");
          let player = document.getElementById("mini-player");
          if (!idle) return;
          if (l.lines && l.lines.length > 0) {
              idle.style.display = "none";
              if (player) player.style.display = "flex";
          } else {
              idle.style.display = "flex";
              if (player) player.style.display = "none";
          }
      };
      window._syncIdleState();

      document.body.className = 'theme-wuxia';

      window.onkeydown = (o) => {
          let d = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right" }[o.key];
          if (d) { o.preventDefault(); G(d); }
      };

      let F, X;
      window.ontouchstart = (o) => { F = o.touches[0].clientX; X = o.touches[0].clientY; };
      window.ontouchend = (o) => {
          let d = o.changedTouches[0].clientX - F, S = o.changedTouches[0].clientY - X;
          if (Math.max(Math.abs(d), Math.abs(S)) > 30) {
            G(Math.abs(d) > Math.abs(S) ? (d > 0 ? "right" : "left") : (S > 0 ? "down" : "up"));
          }
      };
    })();

    const startApp = () => {
        e.render(p);
        l.syncGameState(p);
        if (!t.sound) l.stopAmbient();
        l.checkHeadphonesAndStart();
    };

    const pm = document.getElementById('privacy-modal');
    if (!pm || localStorage.getItem('privacy_agreed') === 'true') {
        if (pm) pm.classList.add('hidden');
        startApp();
    } else {
        pm.classList.remove('hidden');
        const btnAgree = document.getElementById('btn-privacy-agree');
        if (btnAgree) {
            btnAgree.onclick = () => {
                localStorage.setItem('privacy_agreed', 'true');
                pm.classList.add('hidden');
                startApp();
            };
        }
        const btnDisagree = document.getElementById('btn-privacy-disagree');
        if (btnDisagree) {
            btnDisagree.onclick = () => {
                const modalPart = pm.querySelector('.modal');
                if (modalPart) {
                    modalPart.innerHTML = `
                        <h3 style="text-align: center;">您已拒绝协议</h3>
                        <p style="margin: 20px 0; color: rgba(255,255,255,0.7); line-height: 1.6;">很抱歉，根据合规要求，若您不同意《隐私政策》，阅游将无法为您提供基本的本地书籍解析与保存服务。请通过系统多任务界面手动清理并退出本应用。</p>
                    `;
                }
            };
        }
    }
  });
})();
