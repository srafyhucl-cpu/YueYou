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
        this.lines = [
            { v: "zh-CN-YunyangNeural", t: "\u4E1C\u6C49\u672B\u5E74\uFF0C\u5929\u4E0B\u5927\u4E71\u3002\u9EC4\u5DFE\u8D3C\u5BC7\u56DB\u8D77\uFF0C\u767E\u59D3\u6D41\u79BB\u5931\u6240\u3002" },
            { v: "zh-CN-YunxiNeural", t: "\u6211\u4E43\u4E2D\u5C71\u9756\u738B\u4E4B\u540E\uFF0C\u6C49\u666F\u5E1D\u9601\u4E0B\u7384\u5B59\uFF0C\u59D3\u5218\u540D\u5907\uFF0C\u5B57\u7384\u5FB7\u3002" },
            { v: "zh-CN-YunxiaNeural", t: "\u5927\u4E08\u592B\u4E0D\u4E0E\u56FD\u5BB6\u51FA\u529B\uFF0C\u5728\u8FD9\u91CC\u957F\u5401\u77ED\u53F9\uFF0C\u6709\u4EC0\u4E48\u7528\uFF01\u6211\u4E43\u71D5\u4EBA\u5F20\u98DE\uFF0C\u5B57\u7FFC\u5FB7\u3002" },
            { v: "zh-CN-YunjianNeural", t: "\u67D0\u59D3\u5173\u540D\u7FBD\uFF0C\u5B57\u4E91\u957F\uFF0C\u6CB3\u4E1C\u89E3\u826F\u4EBA\u6C0F\u3002" },
            { v: "zh-CN-YunxiaNeural", t: "\u597D\uFF01\u6B63\u5408\u6211\u610F\uFF01\u6211\u5E84\u540E\u6709\u4E00\u5EA7\u6843\u56ED\uFF0C\u82B1\u5F00\u6B63\u76DB\u3002" },
            { v: "zh-CN-YunxiNeural", t: "\u5FF5\u5218\u5907\u3001\u5173\u7FBD\u3001\u5F20\u98DE\uFF0C\u867D\u7136\u5F02\u59D3\uFF0C\u65E2\u7ED3\u4E3A\u5144\u5F1F\uFF0C\u5219\u540C\u5FC3\u534F\u529B\u3002" },
            { v: "zh-CN-YunjianNeural", t: "\u4E0D\u6C42\u540C\u5E74\u540C\u6708\u540C\u65E5\u751F\u3002" },
            { v: "zh-CN-YunxiaNeural", t: "\u4F46\u613F\u540C\u5E74\u540C\u6708\u540C\u65E5\u6B7B\uFF01" },
            { v: "zh-CN-YunyangNeural", t: "\u8A93\u6BD5\uFF0C\u62DC\u5218\u5907\u4E3A\u5144\uFF0C\u5173\u7FBD\u6B21\u4E4B\uFF0C\u5F20\u98DE\u4E3A\u5F1F\u3002\u6843\u56ED\u6625\u98CE\u6D69\u8361\uFF0C\u4E09\u4EBA\u4ECE\u6B64\u809D\u80C6\u76F8\u7167\uFF0C\u5171\u8D74\u5929\u4E0B\u3002" }
        ];
        this.novelID = parseInt(localStorage.getItem("current_novel_id") || "1");
        this.novelTitle = localStorage.getItem("current_novel_title") || "\u4E09\u56FD\u6F14\u4E49\xB7\u6843\u56ED\u7ED3\u4E49\u7247\u6BB5";
        this.cursor = parseInt(localStorage.getItem("novel_index") || "0");
        this.fetchCursor = this.cursor;
        this.audioBufferArray = [];
        this.isPlaying = false;
        this.prefetching = false;
        this.lastActive = Date.now();
        
        let idleMin = parseInt(localStorage.getItem("setting_idle_timeout") || "1");
        this.idleTimeout = idleMin * 60000;
        this.ttsURL = (typeof AppConfig !== "undefined" ? AppConfig.ttsURL : "http://8.218.177.149:3000/api/v1/tts/createStream");
        this.enabled = this.settings.storyTTS;
        this.loopSession = 1;

        this.initLibrary().then(() => {
            if (this.enabled) {
                this.startPrefetchLoop();
                this.startPlayLoop();
            }
        });

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
        // 播放一段极短的静音音频，强制浏览器激活该页面的音频输出
        const silentAudio = new Audio();
        silentAudio.src = "data:audio/mp3;base64,//NkxAA";
        silentAudio.play().catch(e => console.log("静音解锁失败 (如果不是由手势触发则属正常):", e));
    }

    // --- Audio Context & Graph Setup ---
    initContext() {
        if (!this.u) {
            this.u = new (window.AudioContext || window.webkitAudioContext)();
            this.ttsInput = this.u.createGain();
            this.ttsInput.gain.value = 1.0;
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
        if (this.settings.ambientTheme === "rain") {
            // "暗雨"主题：模仿无线电对讲机音效 (带通滤波 + 畸变)
            let bp = this.u.createBiquadFilter(), dist = this.u.createWaveShaper();
            bp.type = "bandpass"; bp.frequency.value = 1500; bp.Q.value = 1.0;
            dist.curve = this.makeDistortionCurve(20); dist.oversample = '4x';
            this.ttsInput.connect(bp); bp.connect(dist); dist.connect(this.u.destination);
            this.currentTTSNodes.push(bp, dist);
        } else if (this.settings.ambientTheme === "wuxia") {
            // "武侠"主题：模拟山谷空灵效果 (卷积混响)
            let convolver = this.u.createConvolver();
            convolver.buffer = this.createReverbIR(this.u, 2.0, 3.0);
            let dry = this.u.createGain(), wet = this.u.createGain();
            dry.gain.value = 0.8; wet.gain.value = 0.4;
            this.ttsInput.connect(dry); dry.connect(this.u.destination);
            this.ttsInput.connect(convolver); convolver.connect(wet); wet.connect(this.u.destination);
            this.currentTTSNodes.push(convolver, dry, wet);
        } else if (this.settings.ambientTheme === "relax") {
            // "冥想"主题：追求温暖 ASMR 听感 (低通滤波)
            let lp = this.u.createBiquadFilter();
            lp.type = "lowpass"; lp.frequency.value = 1000;
            this.ttsInput.connect(lp); lp.connect(this.u.destination);
            this.currentTTSNodes.push(lp);
        } else {
            // 默认无滤镜
            this.ttsInput.connect(this.u.destination);
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
            let osc = this.u.createOscillator();
            let g = this.u.createGain();
            osc.type = "sine";
            osc.frequency.setValueAtTime(freq, this.u.currentTime);
            osc.frequency.exponentialRampToValueAtTime(freq * 2.5, this.u.currentTime + 0.15);
            g.gain.setValueAtTime(0, this.u.currentTime);
            g.gain.linearRampToValueAtTime(0.3, this.u.currentTime + 0.02);
            g.gain.exponentialRampToValueAtTime(0.001, this.u.currentTime + 0.2);
            osc.connect(g);
            g.connect(this.u.destination);
            osc.start();
            osc.stop(this.u.currentTime + 0.25);
        } catch {}
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
            g.connect(this.u.destination);
            osc.start();
            osc.stop(this.u.currentTime + duration);
        } catch {}
    }

    // --- Ambient Soundscapes ---
    stopAmbient() {
        if(this.m.intervals) this.m.intervals.forEach(clearInterval);
        this.m.oscs.forEach(osc => { try { osc.stop(); } catch{} });
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

        if (this.settings.ambientTheme === "rain") {
            // --- 1. 底层雨声与微风起伏 ---
            let src = createNoiseSource();
            let lp = this.u.createBiquadFilter();
            lp.type = "lowpass"; lp.frequency.value = 400; 
            let rainGain = this.u.createGain(); rainGain.gain.value = 0.5;
            let lfo = this.u.createOscillator(); let lfoGain = this.u.createGain();
            lfo.frequency.value = 0.05; lfoGain.gain.value = 0.2; 
            lfo.connect(lfoGain); lfoGain.connect(rainGain.gain);
            src.connect(lp); lp.connect(rainGain); rainGain.connect(masterGain);
            src.start(); lfo.start();
            this.m.oscs.push(src, lfo);

            // --- 2. 随机全息水滴 ---
            const playDrip = () => {
                if (this.M !== sig || !this.settings.sound) return;
                let freq = 800 + Math.random() * 600;
                let osc = this.u.createOscillator(); let g = this.u.createGain();
                osc.frequency.setValueAtTime(freq, this.u.currentTime);
                osc.frequency.exponentialRampToValueAtTime(300, this.u.currentTime + 0.1);
                g.gain.setValueAtTime(0, this.u.currentTime);
                g.gain.linearRampToValueAtTime(0.05, this.u.currentTime + 0.01);
                g.gain.exponentialRampToValueAtTime(0.001, this.u.currentTime + 0.2);
                osc.connect(g); g.connect(masterGain);
                osc.start(); osc.stop(this.u.currentTime + 0.3);
                this.m.intervals.push(setTimeout(playDrip, 500 + Math.random() * 1500));
            };
            playDrip();

            // --- 3. 深空沉雷 ---
            const playThunder = () => {
                if (this.M !== sig || !this.settings.sound) return;
                let noise = createNoiseSource();
                let filter = this.u.createBiquadFilter();
                filter.type = "lowpass"; filter.frequency.value = 150;
                let g = this.u.createGain();
                g.gain.setValueAtTime(0, this.u.currentTime);
                g.gain.linearRampToValueAtTime(0.1, this.u.currentTime + 1.5);
                g.gain.exponentialRampToValueAtTime(0.001, this.u.currentTime + 7.5);
                noise.connect(filter); filter.connect(g); g.connect(masterGain);
                noise.start(); noise.stop(this.u.currentTime + 8.0);
                this.m.intervals.push(setTimeout(playThunder, 10000 + Math.random() * 15000));
            };
            this.m.intervals.push(setTimeout(playThunder, 5000));
        } else if (this.settings.ambientTheme === "wuxia") {
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
        } else if (this.settings.ambientTheme === "relax") {
            // --- 云端冥想 (空灵的和弦) ---
            const chord = [130.81, 164.81, 196.00, 246.94];
            chord.forEach((freq) => {
                let osc = this.u.createOscillator(); let g = this.u.createGain();
                osc.type = "triangle"; osc.frequency.value = freq; g.gain.value = 0.03;
                let lfo = this.u.createOscillator(); let lfoGain = this.u.createGain();
                lfo.frequency.value = 0.05 + Math.random() * 0.03; lfoGain.gain.value = 0.015;
                lfo.connect(lfoGain); lfoGain.connect(g.gain);
                osc.connect(g); g.connect(masterGain);
                osc.start(); lfo.start();
                this.m.oscs.push(osc, lfo);
            });
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
    }

    checkHeadphonesAndStart() {
        navigator.mediaDevices.enumerateDevices().then(devices => {
            let hasHeadphones = devices.filter(d => d.kind === "audiooutput").some(d => {
                let label = d.label.toLowerCase();
                return label.includes("headphone") || label.includes("earbud") || label.includes("bluetooth") || label.includes("\u8033\u673A");
            });
            if(hasHeadphones) {
                console.log("Headphones detected, silent TTS trigger.");
                this.toggle(true);
            } else {
                 this.toggle(true);
            }
        }).catch(err => {
            console.warn("enumerateDevices rejected:", err);
            this.toggle(true);
        });
    }

    // --- TTS Novel Logic ---
    async initLibrary() {
        if (!this.lines || this.lines.length === 0) {
            await this.loadNovel(this.novelID, this.novelTitle, this.cursor);
        }
    }

    async loadNovel(id, title, newCursor = null) {
        try {
            this.loopSession = (this.loopSession || 1) + 1;
            let currentSession = this.loopSession;
            if (this.currentAudio) {
                this.currentAudio.pause();
                this.currentAudio.removeAttribute("src");
                this.currentAudio = null;
            }
            this.audioBufferArray.forEach(x => { if(x.url) URL.revokeObjectURL(x.url); });
            this.audioBufferArray = [];
            this.isSpeaking = false;
            this.prefetching = false;
            this.isPlaying = false;
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
                if (this.enabled) {
                    this.startPrefetchLoop();
                    this.startPlayLoop();
                }
            }
        } catch (e) {
            console.error("Failed to load novel:", e);
        }
    }

    heartbeat() {
        this.lastActive = Date.now();
        if (this.enabled) {
            if (this.isPlaying) {
                if (this.idleTimeout > 0 && this.currentAudio && this.currentAudio.paused && !this.currentAudio.ended) {
                    this.currentAudio.play().then(() => {
                        this.isSpeaking = true;
                        this.updateUI();
                        if(window._showToast) window._showToast("\u5DF2\u6062\u590D\u64AD\u62A5");
                    }).catch(err => console.warn(err));
                }
            } else {
                this.startPlayLoop();
            }
        }
    }

    toggle(enable) {
        this.enabled = enable;
        this.settings.storyTTS = enable;
        localStorage.setItem("setting_story_tts", enable);
        if (enable) {
            this.heartbeat();
            if (this.currentAudio && this.currentAudio.paused && !this.currentAudio.ended) {
                this.isSpeaking = true;
                this.currentAudio.play().catch(c => console.warn("Failed to resume audio:", c));
                this.updateUI();
            } else {
                this.startPrefetchLoop();
                this.startPlayLoop();
            }
        } else {
            if (this.currentAudio) this.currentAudio.pause();
            this.isSpeaking = false;
            this.updateUI();
        }
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
            if(x.url && x.url !== "speech_synthesis") URL.revokeObjectURL(x.url); 
        });
        this.audioBufferArray = [];
        this.prefetching = false;
        this.isPlaying = false;
        this.isSpeaking = false;

        // 更新位置
        this.cursor = lineIndex;
        this.fetchCursor = lineIndex;
        localStorage.setItem("novel_index", this.cursor.toString());
        this.updateUI();

        // 重新启动引擎
        if (this.enabled) {
            this.startPrefetchLoop();
            this.startPlayLoop();
        }
    }

    async fetchTTS(text, voice) {
        voice = localStorage.getItem("tts_voice") || "zh-CN-XiaoxiaoNeural";

        // 如果文本太短，服务器最低要求 5 个字符，自动在末尾补充无声的句号
        let safeText = text.length < 5 ? text.padEnd(5, '。') : text;

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 8000); // 把超时放宽到 8 秒，保障远程云端大模型有充足时间生成音频

        try {
            let res = await fetch(this.ttsURL, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ text: safeText, voice: voice }),
                signal: controller.signal
            });
            clearTimeout(timeoutId);
            
            // 服务端如果返回 400（比如由于太多任务并发排队等），只降级当前这句
            if (!res.ok) {
                console.warn(`[TTS] Server returned HTTP ${res.status}. Falling back to native temporarily.`);
                throw new Error("HTTP " + res.status);
            }
            
            let blob = await res.blob();
            return URL.createObjectURL(blob);
        } catch (e) {
            clearTimeout(timeoutId);
            // 无论任何失败，只对“当前这句”执行原生兜底，不把整套系统限死，后续句子接着请求服务器
            console.error("[TTS Error] Falling back to native SpeechSynthesis for this sentence due to:", e.message || e);
            if ("speechSynthesis" in window) return "speech_synthesis";
            return null;
        }
    }

    updateUI() {
        let titleEl = document.getElementById("player-title");
        if (titleEl) titleEl.innerText = `${this.novelTitle}`;
        let chapEl = document.getElementById("player-chapter");
        if (chapEl) {
            let currentChapterTitle = "未分类 / 序章";
            if (this.chapters && this.chapters.length > 0) {
                for (let i = this.chapters.length - 1; i >= 0; i--) {
                    if (this.cursor >= this.chapters[i].lineIndex) {
                        currentChapterTitle = this.chapters[i].title;
                        break;
                    }
                }
            }
            chapEl.innerText = currentChapterTitle;
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
        let session = this.loopSession;
        while (this.enabled && this.loopSession === session) {
            if (this.idleTimeout > 0 && Date.now() - this.lastActive > this.idleTimeout) {
                await new Promise(r => setTimeout(r, 1000));
                continue;
            }
            if (this.audioBufferArray.length >= 2) {
                await new Promise(r => setTimeout(r, 200));
                continue;
            }
            let line = this.lines[this.fetchCursor];
            if (!line) {
                await new Promise(r => setTimeout(r, 1000));
                continue;
            }
            let url = await this.fetchTTS(line.t, line.v);
            if (this.loopSession !== session) break;
            if (url) {
                let id = Math.random().toString(36).substr(2, 9);
                if (url === "speech_synthesis") {
                    let mockAudio = {
                        isSpeech: true,
                        text: line.t,
                        paused: true,
                        ended: false,
                        play: async function() {
                            this.paused = false; this.ended = false;
                            window.speechSynthesis.cancel(); 
                            return new Promise((resolve, reject) => {
                                let u = new SpeechSynthesisUtterance(this.text);
                                u.lang = "zh-CN";
                                u.rate = 1.1; // 稍微加快语速
                                u.onend = () => { this.ended = true; this.paused = true; if(this.onended) this.onended(); resolve(); };
                                u.onerror = () => { this.ended = true; this.paused = true; if(this.onerror) this.onerror(); resolve(); };
                                window.speechSynthesis.speak(u);
                            });
                        },
                        pause: function() {
                            this.paused = true;
                            window.speechSynthesis.cancel();
                        }
                    };
                    this.audioBufferArray.push({ url: url, id: id, obj: mockAudio });
                } else {
                    let audioObj = new Audio(url);
                    audioObj.preload = "auto";
                    this.audioBufferArray.push({ url: url, id: id, obj: audioObj });
                }
                this.fetchCursor = (this.fetchCursor + 1) % this.lines.length;
            } else {
                this.audioBufferArray.push({ url: null, id: "fail", obj: null });
                this.fetchCursor = (this.fetchCursor + 1) % this.lines.length;
                await new Promise(r => setTimeout(r, 1000));
            }
        }
        if (this.loopSession === session) this.prefetching = false;
    }

    async startPlayLoop() {
        if (this.isPlaying) return;
        this.isPlaying = true;
        let session = this.loopSession;
        while (this.enabled && this.loopSession === session) {
            if (this.audioBufferArray.length === 0) {
                let ch = document.getElementById("player-chapter");
                if (this.enabled && ch) ch.innerHTML = '<span style="color:#fbbf24">⏳ 神经信号缓冲中...</span>';
                if (this.isSpeaking) {
                    this.isSpeaking = false;
                    this.updateUI();
                }
                await new Promise(r => setTimeout(r, 100));
                continue;
            }
            let item = this.audioBufferArray.shift();
            if (!item.obj) {
                if (this.lines && this.lines.length > 0) {
                    this.cursor = (this.cursor + 1) % this.lines.length;
                    localStorage.setItem("novel_index", this.cursor.toString());
                    if(typeof window._syncIdleState === 'function') window._syncIdleState();
                }
                this.updateUI();
                continue;
            }
            this.isSpeaking = true;
            this.updateUI();
            
            await new Promise(resolve => {
                let audio = item.obj;
                this.currentAudio = audio;
                
                if (audio.isSpeech) {
                    audio.onended = resolve;
                    audio.onerror = resolve;
                    audio.play().catch(() => resolve());
                } else {
                    audio.onended = () => resolve();
                    audio.onerror = () => resolve();
                    
                    if (!audio._routed && this.u && this.ttsInput) {
                        try {
                            let src = this.u.createMediaElementSource(audio);
                            src.connect(this.ttsInput);
                            audio._routed = true;
                        } catch(e) { console.warn("TTS Audio routing failed:", e); }
                    }
                    
                    let playPromise = audio.play();
                    if (playPromise !== undefined) {
                        playPromise.catch(err => {
                            if (err.name === "NotAllowedError") {
                                let mask = document.getElementById("autoplay-mask");
                                if (mask) mask.classList.remove("hidden");
                                let btn = document.getElementById("btn-unblock-audio");
                                if (btn) {
                                    btn.onclick = () => {
                                        mask.classList.add("hidden");
                                        audio.play().then(() => resolve()).catch(() => resolve());
                                    };
                                }
                            } else if (err.name !== "AbortError") {
                                resolve();
                            }
                        });
                    }
                }
            });
            if (this.loopSession !== session) break;
            
            this.currentAudio = null;
            if (item.url) URL.revokeObjectURL(item.url);
            if (this.lines && this.lines.length > 0) {
                this.cursor = (this.cursor + 1) % this.lines.length;
                localStorage.setItem("novel_index", this.cursor.toString());
                if(typeof window._syncIdleState === 'function') window._syncIdleState();
            }
        }
        if (this.loopSession === session) {
            this.isPlaying = false;
            this.updateUI();
        }
    }
}
