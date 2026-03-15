// ======================================
// 声音引擎管理器 (AudioManager.js)
// 职责：处理 Web Audio API 全息混响、TTS 有声书预加载与播报、环境白噪音、以及交互音效
// ======================================
import { LocalDB } from './LocalDB.js';

export class AudioManager {
    constructor(settings) {
        this.settings = settings;
        this.u = null; // AudioContext (Web Audio 上下文)
        this.ttsInput = null; // TTS 播报的音量输入节点
        this.currentTTSNodes = []; // 当前活跃的 TTS 处理滤镜节点
        this.m = { oscs: [], gains: [], masterGain: null, intervals: [] }; // 环境音效相关的资源跟踪
        this.M = null; // 当前活跃的环境白噪音主题标识符

        // --- TTS Novel Logic State ---
        this.lines = [];
        this.chapters = [];
        this.novelID = parseInt(localStorage.getItem("current_novel_id") || "1");
        this.novelTitle = localStorage.getItem("current_novel_title") || "\u4E09\u56FD\u6F14\u4E49\xB7\u6843\u56ED\u7ED3\u4E49\u7247\u6BB5";
        this.cursor = parseInt(localStorage.getItem("novel_index") || "0");
        this.fetchCursor = this.cursor;
        this.audioBufferArray = [];
        this.isPlaying = false;
        this.playingSession = 0; // 核心：记录当前正在运行播放循环的会话 ID
        this.prefetching = false;
        this.lastActive = Date.now();

        let idleMin = parseInt(localStorage.getItem("setting_idle_timeout") || "1");
        this.idleTimeout = idleMin * 60000;
        this.ttsURL = (typeof AppConfig !== "undefined" ? AppConfig.ttsURL : "http://8.218.177.149:3000/api/v1/tts/createStream");
        this.enabled = this.settings.storyTTS;
        this.loopSession = 1;

        this.initLibrary();

        setInterval(() => {
            if (this.enabled && this.isPlaying && this.idleTimeout > 0 && Date.now() - this.lastActive > this.idleTimeout && this.currentAudio && !this.currentAudio.paused) {
                this.currentAudio.pause();
                this.isSpeaking = false;
                this.updateUI();
                if (window._showToast) window._showToast("\u5DF2\u6682\u505C\u64AD\u62A5 (\u957F\u65F6\u95F4\u65E0\u64CD\u4F5C)");
            }
        }, 5000);
    }

    unlockAudio() {
        // 解锁音频上下文：这是为了绕过移动端浏览器对自动播放音频的限制
        this.initContext();
        if (this.u && this.u.state === "suspended") {
            this.u.resume();
        }
        // 注意：这里只解锁 AudioContext，绝不直接 play 任何小说音频！
        // 小说音频的播放完全由 startPlayLoop 单例循环控制，避免重音。
    }

    // --- Audio Context & Graph Setup ---
    initContext() {
        if (!this.u) {
            this.u = new (window.AudioContext || window.webkitAudioContext)();

            // 终极质感：总线动态压缩器 (让音效更饱满、不爆音)
            this.masterCompressor = this.u.createDynamicsCompressor();
            this.masterCompressor.threshold.setValueAtTime(-24, this.u.currentTime);
            this.masterCompressor.knee.setValueAtTime(40, this.u.currentTime);
            this.masterCompressor.ratio.setValueAtTime(12, this.u.currentTime);
            this.masterCompressor.attack.setValueAtTime(0, this.u.currentTime);
            this.masterCompressor.release.setValueAtTime(0.25, this.u.currentTime);
            this.masterCompressor.connect(this.u.destination);

            this.ttsInput = this.u.createGain();
            this.ttsInput.gain.value = 1.0;

            // 灵动岛律动：挂载 Web Audio 解析器
            window.analyser = this.u.createAnalyser();
            window.analyser.fftSize = 64;
            this.ttsInput.connect(window.analyser);

            this.updateTTSFilter();
        }
        if (this.u.state === "suspended") this.u.resume();
    }

    makeDistortionCurve(amount) {
        let k = typeof amount === 'number' ? amount : 50;
        let n_samples = 44100;
        let curve = new Float32Array(n_samples);
        let deg = Math.PI / 180;
        for (let i = 0; i < n_samples; ++i) {
            let x = i * 2 / n_samples - 1;
            curve[i] = (3 + k) * x * 20 * deg / (Math.PI + k * Math.abs(x));
        }
        return curve;
    }

    createReverbIR(audioCtx, duration, decay) {
        let sampleRate = audioCtx.sampleRate;
        let length = sampleRate * duration;
        let impulse = audioCtx.createBuffer(2, length, sampleRate);
        let left = impulse.getChannelData(0), right = impulse.getChannelData(1);
        for (let i = 0; i < length; i++) {
            left[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, decay);
            right[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, decay);
        }
        return impulse;
    }

    updateTTSFilter() {
        if (!this.u || !this.ttsInput) return;
        this.ttsInput.disconnect();
        this.currentTTSNodes.forEach(node => node.disconnect());
        this.currentTTSNodes = [];

        // 根据当前环境主题，为 TTS 播报添加不同的实时音频滤镜
        if (this.settings.ambientTheme === "wuxia") {
            // "武侠"主题：模拟山谷空灵效果 (卷积混响)
            let convolver = this.u.createConvolver();
            convolver.buffer = this.createReverbIR(this.u, 2.0, 3.0);
            let dry = this.u.createGain(), wet = this.u.createGain();
            dry.gain.value = 0.8; wet.gain.value = 0.4;
            this.ttsInput.connect(dry); dry.connect(this.masterCompressor);
            this.ttsInput.connect(convolver); convolver.connect(wet); wet.connect(this.masterCompressor);
            this.currentTTSNodes.push(convolver, dry, wet);
        } else {
            // 默认无滤镜
            this.ttsInput.connect(this.masterCompressor);
        }
    }

    // --- Interactive Sound Effects ---
    playMergeSound(value) {
        if (!this.settings.sound) return;
        this.initContext();
        let freqs = [0, 0, 261.63, 293.66, 329.63, 392, 440, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66, 1318.51];
        let idx = Math.min(Math.floor(Math.log2(value)), freqs.length - 1);
        let freq = freqs[idx] || 300;
        try {
            // 增强质感：双振荡器合成器音效 (Sine + Triangle 层叠)
            let osc1 = this.u.createOscillator();
            let osc2 = this.u.createOscillator();
            let g = this.u.createGain();

            osc1.type = "sine";
            osc1.frequency.setValueAtTime(freq, this.u.currentTime);
            osc1.frequency.exponentialRampToValueAtTime(freq * 1.5, this.u.currentTime + 0.1);

            osc2.type = "triangle";
            osc2.frequency.setValueAtTime(freq * 2, this.u.currentTime);
            osc2.frequency.exponentialRampToValueAtTime(freq, this.u.currentTime + 0.1);

            g.gain.setValueAtTime(0, this.u.currentTime);
            g.gain.linearRampToValueAtTime(0.2, this.u.currentTime + 0.01);
            g.gain.exponentialRampToValueAtTime(0.001, this.u.currentTime + 0.25);

            osc1.connect(g);
            osc2.connect(g);
            g.connect(this.masterCompressor);

            osc1.start();
            osc2.start();
            osc1.stop(this.u.currentTime + 0.3);
            osc2.stop(this.u.currentTime + 0.3);
        } catch { }
    }

    playSimpleSound(freq, type = "sine", duration = 0.1) {
        if (!this.settings.sound) return;
        this.initContext();
        try {
            let osc = this.u.createOscillator();
            let g = this.u.createGain();
            osc.type = type;
            osc.frequency.value = freq;
            g.gain.setValueAtTime(0.1, this.u.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, this.u.currentTime + duration);
            osc.connect(g);
            g.connect(this.masterCompressor);
            osc.start();
            osc.stop(this.u.currentTime + duration);
        } catch { }
    }

    // --- Ambient Soundscapes ---
    stopAmbient() {
        if (this.m.intervals) this.m.intervals.forEach(clearInterval);
        this.m.oscs.forEach(osc => { try { osc.stop(); } catch { } });
        this.m.oscs = [];
        this.m.gains = [];
        this.m.intervals = [];
        this.M = null;
    }

    playAmbient(phase) {
        let sig = phase + '_' + (this.settings.ambientTheme || 'wuxia');
        if (!this.settings.sound || !this.u || this.M === sig) return;
        this.stopAmbient();
        this.M = sig;

        let masterGain = this.u.createGain();
        masterGain.gain.value = this.settings.ambientVol;
        masterGain.connect(this.u.destination);
        this.m.masterGain = masterGain;

        const createNoiseSource = () => {
            const size = this.u.sampleRate * 2;
            const buffer = this.u.createBuffer(1, size, this.u.sampleRate);
            const data = buffer.getChannelData(0);
            for (let k = 0; k < size; k++) data[k] = Math.random() * 2 - 1;
            const source = this.u.createBufferSource();
            source.buffer = buffer;
            source.loop = true;
            return source;
        };

        if (this.settings.ambientTheme === "wuxia") {
            // --- 1. 竹林微风 ---
            let wind = createNoiseSource();
            let bp = this.u.createBiquadFilter();
            bp.type = "bandpass"; bp.frequency.value = 300; bp.Q.value = 0.5;
            let windGain = this.u.createGain(); windGain.gain.value = 0.1;
            wind.connect(bp); bp.connect(windGain); windGain.connect(masterGain);
            wind.start(); this.m.oscs.push(wind);

            // --- 2. 远笛 ---
            const fluteFreqs = [329.63, 392.00, 440.00, 523.25, 587.33];
            const playFlute = () => {
                if (this.M !== sig || !this.settings.sound) return;
                let freq = fluteFreqs[Math.floor(Math.random() * fluteFreqs.length)];
                let osc = this.u.createOscillator(); let g = this.u.createGain();
                osc.type = "sine"; osc.frequency.value = freq;
                g.gain.setValueAtTime(0, this.u.currentTime);
                g.gain.linearRampToValueAtTime(0.1, this.u.currentTime + 1.0);
                g.gain.exponentialRampToValueAtTime(0.001, this.u.currentTime + 4.0);
                osc.connect(g); g.connect(masterGain);
                osc.start(); osc.stop(this.u.currentTime + 4.1);
            };
            this.m.intervals.push(setInterval(playFlute, 4000));
            setTimeout(playFlute, 500);
        }
    }

    syncGameState(gameEngine) {
        if (!this.settings.sound || this.settings.ambientVol <= 0) {
            this.stopAmbient();
            return;
        }
        this.initContext();
        let phase = gameEngine.mode === "loop" ? gameEngine.phase : "classic";
        this.playAmbient(phase);
        if (this.m.masterGain) this.m.masterGain.gain.value = this.settings.ambientVol;
        this.updateTTSFilter();
        document.body.className = 'theme-' + (this.settings.ambientTheme || 'wuxia');

        // 启动单例循环（如果尚未运行）
        this.startPrefetchLoop();
        this.startPlayLoop();
    }

    checkHeadphonesAndStart() {
        // 只设置 enabled 状态，不再直接启动循环（循环由 initLibrary 或 syncGameState 控制）
        if (!this.enabled) {
            this.enabled = true;
            this.settings.storyTTS = true;
            localStorage.setItem("setting_story_tts", true);
        }
    }

    // --- TTS Novel Logic ---
    async initLibrary() {
        await this.loadNovel(this.novelID, this.novelTitle, this.cursor);
        // 如果加载后依然没内容，使用内置默认数据
        if (this.lines.length === 0) {
            this.lines = [
                { v: "zh-CN-XiaoxiaoNeural", t: "东汉末年，天下大乱。黄巾贼寇四起，百姓流离失所。" },
                { v: "zh-CN-YunxiNeural", t: "我乃中山靖王之后，汉景帝阁下玄孙，姓刘名备，字玄德。" },
                { v: "zh-CN-XiaoyiNeural", t: "大丈夫不与国家出力，在这里长吁短叹，有什么用！我乃燕人张飞，字翼德。" },
                { v: "zh-CN-YunjianNeural", t: "某姓关名羽，字云长，河东解良人氏。" }
            ];
            this.chapters = [{ title: "桃园三结义", lineIndex: 0 }];
            this.updateUI();
        }

        // 核心：在初始化工作流结束后，统一尝试启动循环
        if (this.enabled) {
            this.startPrefetchLoop();
            this.startPlayLoop();
        }
    }

    async loadNovel(id, title, newCursor = null) {
        try {
            this.loopSession = (this.loopSession || 1) + 1;
            let currentSession = this.loopSession;
            if (this.currentAudio) {
                this.currentAudio.pause();
                if (this.currentAudio instanceof HTMLMediaElement) {
                    this.currentAudio.removeAttribute("src");
                    this.currentAudio.load();
                } else if (this.currentAudio.isSpeech) {
                    window.speechSynthesis.cancel();
                }
                this.currentAudio = null;
            }
            this.audioBufferArray.forEach(x => { if (x.url) URL.revokeObjectURL(x.url); });
            this.audioBufferArray = [];
            this.isSpeaking = false;
            this.prefetching = false;
            // 核心修复：不要在这里重置 isPlaying，让旧循环自然退出，新循环通过 session 校验进入
            this.novelID = id;
            this.novelTitle = title;
            this.cursor = newCursor !== null ? newCursor : 0;
            this.fetchCursor = this.cursor;
            this.updateUI();

            let data = await LocalDB.loadBook(id);
            if (data) {
                if (this.loopSession !== currentSession) return;

                // 处理旧数据兼容和新结构
                if (Array.isArray(data)) {
                    this.lines = data;
                    this.chapters = [];
                } else {
                    this.lines = data.lines || [];
                    this.chapters = data.chapters || [];
                }

                this.cursor = (newCursor !== null && newCursor < this.lines.length) ? newCursor : 0;
                this.fetchCursor = this.cursor;
                localStorage.setItem("current_novel_id", id);
                localStorage.setItem("current_novel_title", title);
                localStorage.setItem("novel_index", this.cursor.toString());


                if (typeof window._syncIdleState === 'function') window._syncIdleState();
                this.updateUI();
                // 不在这里直接启动，交给调用者(initLibrary/jumpToChapter)控制
            }
        } catch (e) {
            console.error("Failed to load novel:", e);
        }
    }

    heartbeat() {
        this.lastActive = Date.now();
        if (!this.enabled) return;

        // 如果未在运行，或者当前运行的会话已经过期，则尝试启动新会话循环
        if (!this.isPlaying || this.playingSession !== this.loopSession) {
            this.startPlayLoop();
        } else if (this.isPlaying) {
            // 如果已经在运行（Session 正确），检查是否因为超时自动暂停了，如果是则恢复
            if (this.idleTimeout > 0 && this.currentAudio && this.currentAudio.paused && !this.currentAudio.ended) {
                this.currentAudio.play().then(() => {
                    this.isSpeaking = true;
                    this.updateUI();
                    if (window._showToast) window._showToast("\u5DF2\u6062\u590D\u64AD\u62A5");
                }).catch(err => console.warn(err));
            }
        }
    }

    toggle(enable) {
        this.setEnabled(enable);
    }

    setEnabled(enable) {
        this.enabled = enable;
        this.settings.storyTTS = enable;
        localStorage.setItem("setting_story_tts", enable);
        if (enable) {
            this.heartbeat();
            // 不再直接 play currentAudio！交给单例循环自然处理。
            // 只确保循环在运行。
            this.startPrefetchLoop();
            this.startPlayLoop();
        } else {
            if (this.currentAudio) this.currentAudio.pause();
            this.isSpeaking = false;
            this.isPlaying = false;
            this.prefetching = false;
            this.updateUI();
        }
    }

    stop() {
        this.loopSession++; // 递增 session 强制终止所有异步循环
        if (this.currentAudio) {
            this.currentAudio.pause();
            this.currentAudio.src = "";
            this.currentAudio = null;
        }
        this.audioBufferArray.forEach(x => { if (x.url) URL.revokeObjectURL(x.url); });
        this.audioBufferArray = [];
        this.isPlaying = false;
        this.isSpeaking = false;
        this.updateUI();
    }

    jumpToChapter(lineIndex) {
        if (!this.lines || lineIndex < 0 || lineIndex >= this.lines.length) return;

        // 增量更新会话，阻断原有播放
        this.loopSession++;

        if (this.currentAudio) {
            this.currentAudio.pause();
            if (this.currentAudio.isSpeech) {
                window.speechSynthesis.cancel();
            } else {
                this.currentAudio.removeAttribute("src");
            }
            this.currentAudio = null;
        }

        // 清空预加载缓冲
        this.audioBufferArray.forEach(x => {
            if (x.url && x.url !== "speech_synthesis") URL.revokeObjectURL(x.url);
        });
        this.audioBufferArray = [];
        this.isSpeaking = false;

        // 更新位置
        this.cursor = lineIndex;
        this.fetchCursor = lineIndex;
        localStorage.setItem("novel_index", this.cursor.toString());
        this.updateUI();

        // 确保循环在运行
        this.startPrefetchLoop();
        this.startPlayLoop();
    }

    async fetchTTS(text, voice) {
        voice = localStorage.getItem("tts_voice") || "zh-CN-XiaoxiaoNeural";
        let safeText = text.length < 5 ? text.padEnd(5, '。') : text;

        const maxRetries = 2; 
        for (let attempt = 0; attempt <= maxRetries; attempt++) {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 8000);

            try {
                let res = await fetch(this.ttsURL, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ text: safeText, voice: voice }),
                    signal: controller.signal
                });
                clearTimeout(timeoutId);

                if (!res.ok) {
                    let errorBody = "";
                    try { errorBody = await res.text(); } catch(e) {}
                    console.warn(`[TTS] Attempt ${attempt+1} failed with HTTP ${res.status}:`, errorBody);
                    
                    // 如果是服务器 500，且还没到最大重试次数，则等一下再试
                    if (res.status >= 500 && attempt < maxRetries) {
                        await new Promise(r => setTimeout(r, 1000 * (attempt + 1))); 
                        continue;
                    }
                    
                    let errMsg = `[TTS] 服务端返回 HTTP ${res.status}: ${errorBody.substring(0, 100)}`;
                    if (window._showToast) window._showToast(errMsg);
                    throw new Error("HTTP " + res.status);
                }

                let blob = await res.blob();
                let isValidType = blob.type.includes("audio") || blob.type === "application/octet-stream";
                if (!blob || blob.size === 0 || !isValidType) {
                    throw new Error("Invalid Audio Blob");
                }
                return URL.createObjectURL(blob);
            } catch (e) {
                clearTimeout(timeoutId);
                console.warn(`[TTS] Attempt ${attempt+1} caught error:`, e.message);
                if (attempt < maxRetries) {
                    await new Promise(r => setTimeout(r, 1000 * (attempt + 1)));
                    continue;
                }
                console.error("[TTS Final Error] Falling back to native SpeechSynthesis:", e.message || e);
                if ("speechSynthesis" in window) return "speech_synthesis";
                return null;
            }
        }
    }

    updateUI() {
        let titleEl = document.getElementById("player-title");
        if (titleEl) titleEl.innerText = `${this.novelTitle}`;
        
        // 核心：提前计算当前章节标题，解耦 UI 渲染
        let currentChapterTitle = "未分类 / 序章";
        if (this.chapters && this.chapters.length > 0) {
            for (let i = this.chapters.length - 1; i >= 0; i--) {
                if (this.cursor >= this.chapters[i].lineIndex) {
                    currentChapterTitle = this.chapters[i].title;
                    break;
                }
            }
        }

        let chapEl = document.getElementById("player-chapter");
        if (chapEl) chapEl.innerText = currentChapterTitle;
        
        // 灵动岛胶囊文本同步
        let capsuleEl = document.getElementById("player-progress-text");
        if (capsuleEl) {
            capsuleEl.innerText = (this.enabled && this.lines.length > 0) ? `${this.novelTitle} - ${currentChapterTitle}` : "▶ 点击任意处唤醒神经接入";
        }

        let statusEl = document.getElementById("player-status-icon");
        if (statusEl) statusEl.innerText = this.isSpeaking ? "\u23F8" : "\u25B6";

        let chapterStats = document.getElementById("chapter-stats");
        if (chapterStats) {
            let totalChapters = this.chapters ? this.chapters.length : 0;
            let percent = this.lines && this.lines.length > 0 ? ((this.cursor / this.lines.length) * 100).toFixed(1) : 0;
            chapterStats.innerText = `共 ${totalChapters} 章 | 阅读进度 ${percent}%`;
        }
    }

    async startPrefetchLoop() {
        if (this.prefetching) return;
        this.prefetching = true;

        while (this.enabled) {
            let session = this.loopSession; // 记录进入时的 Session

            if (this.idleTimeout > 0 && Date.now() - this.lastActive > this.idleTimeout) {
                await new Promise(r => setTimeout(r, 1000));
                continue;
            }
            if (this.audioBufferArray.length >= 3) { // 增加缓冲深度
                await new Promise(r => setTimeout(r, 300));
                continue;
            }
            if (!this.lines || this.lines.length === 0) {
                await new Promise(r => setTimeout(r, 1000));
                continue;
            }

            let line = this.lines[this.fetchCursor];
            if (!line) {
                await new Promise(r => setTimeout(r, 1000));
                continue;
            }

            let url = await this.fetchTTS(line.t, line.v);

            // 核心：请求回来后立即检查 Session，如果变了，直接丢弃结果并重试
            if (this.loopSession !== session) {
                if (url && url !== "speech_synthesis") URL.revokeObjectURL(url);
                continue;
            }

            if (url) {
                let id = Math.random().toString(36).substr(2, 9);
                if (url === "speech_synthesis") {
                    let mockAudio = {
                        isSpeech: true, text: line.t, paused: true, ended: false,
                        play: async function () {
                            this.paused = false; this.ended = false;
                            window.speechSynthesis.cancel();
                            return new Promise((resolve) => {
                                let u = new SpeechSynthesisUtterance(this.text);
                                u.lang = "zh-CN";
                                u.onend = () => { this.ended = true; this.paused = true; if (this.onended) this.onended(); resolve(); };
                                u.onerror = () => { this.ended = true; this.paused = true; if (this.onerror) this.onerror(); resolve(); };
                                window.speechSynthesis.speak(u);
                            });
                        },
                        pause: function () { this.paused = true; window.speechSynthesis.cancel(); }
                    };
                    this.audioBufferArray.push({ url: url, id: id, obj: mockAudio });
                } else {
                    let audioObj = new Audio(url);
                    audioObj.preload = "auto";
                    this.audioBufferArray.push({ url: url, id: id, obj: audioObj });
                }
                this.fetchCursor = (this.fetchCursor + 1) % this.lines.length;
            } else {
                await new Promise(r => setTimeout(r, 2000));
            }
        }
        this.prefetching = false;
    }

    async startPlayLoop() {
        if (this.isPlaying) return;
        this.isPlaying = true;

        while (this.enabled) {
            let session = this.loopSession; // 记录当前播放周期所属的 Session ID

            if (this.audioBufferArray.length === 0) {
                let ch = document.getElementById("player-chapter");
                if (this.enabled && ch) ch.innerHTML = '<span style="color:#fbbf24">⏳ 神经数据加载中...</span>';
                if (this.isSpeaking) { this.isSpeaking = false; this.updateUI(); }
                await new Promise(r => setTimeout(r, 200));
                continue;
            }

            let item = this.audioBufferArray.shift();
            if (!item || !item.obj) {
                if (this.loopSession === session) {
                    this.cursor = (this.cursor + 1) % (this.lines.length || 1);
                    this.updateUI();
                }
                continue;
            }

            this.isSpeaking = true;
            this.updateUI();

            await new Promise(resolve => {
                let audio = item.obj;
                this.currentAudio = audio;

                // 临门一脚检查
                if (this.loopSession !== session) return resolve();

                audio.onended = resolve;
                audio.onerror = resolve;

                if (audio.isSpeech) {
                    window.speechSynthesis.cancel();
                    audio.play().catch(resolve);
                } else {
                    if (!audio._routed && this.u && this.ttsInput) {
                        try {
                            let src = this.u.createMediaElementSource(audio);
                            src.connect(this.ttsInput); audio._routed = true;
                        } catch (e) { }
                    }
                    audio.play().catch(err => {
                        if (err.name === "NotAllowedError") {
                            let mask = document.getElementById("autoplay-mask");
                            if (mask) mask.classList.remove("hidden");
                            let btn = document.getElementById("btn-unblock-audio");
                            if (btn) btn.onclick = () => {
                                mask.classList.add("hidden");
                                if (this.loopSession === session) audio.play().then(resolve).catch(resolve);
                                else resolve();
                            };
                        } else resolve();
                    });
                }
            });

            // 检查完成一次播报后 Session 是否还一致
            if (this.loopSession !== session) {
                if (this.currentAudio) this.currentAudio.pause();
                this.currentAudio = null;
                continue;
            }

            this.currentAudio = null;
            if (item.url && item.url !== "speech_synthesis") URL.revokeObjectURL(item.url);

            if (this.lines && this.lines.length > 0) {
                this.cursor = (this.cursor + 1) % this.lines.length;
                localStorage.setItem("novel_index", this.cursor.toString());
                if (typeof window._syncIdleState === 'function') window._syncIdleState();
            }
        }
        this.isPlaying = false;
    }
}
