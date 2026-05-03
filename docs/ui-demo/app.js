const modalLayer = document.querySelector('#modalLayer');
const modalTitle = document.querySelector('#modalTitle');
const modalBody = document.querySelector('#modalBody');
const playerConsole = document.querySelector('#playerConsole');
const playButton = document.querySelector('#playButton');
const speedButton = document.querySelector('#speedButton');
const toast = document.querySelector('#toast');
const mascot = document.querySelector('#mascot');
const scoreValue = document.querySelector('#scoreValue');
const activeSentence = document.querySelector('#activeSentence');
const chapterTitle = document.querySelector('#chapterTitle');
const toastText   = document.querySelector('#toastText');

const speeds = ['0.8x', '1.0x', '1.2x', '1.5x', '2.0x'];
const sentences = [
  '正欲纵云前行。',
  '忽听山间风雷滚滚。',
  '八戒提耙护住师父。',
  '那妖雾中现出金光。',
];
let speedIndex = 1;
let sentenceIndex = 0;
let score = 2048;
let playing = false;
let toastTimer;

const modalTemplates = {
  library: {
    title: '神经档案库',
    html: `
      <article class="book-card" data-cover="游" style="background: linear-gradient(135deg, rgba(34,211,238,0.35), rgba(139,92,246,0.24));">
        <h3>西游记</h3>
        <p class="hint">已读 37.8% · 默认云端卷宗</p>
        <div class="progress-bar"><i style="width: 37.8%"></i></div>
      </article>
      <article class="book-card" data-cover="剑" style="background: linear-gradient(135deg, rgba(254,1,154,0.34), rgba(245,175,25,0.22));">
        <h3>赛博剑客异闻录</h3>
        <p class="hint">已读 68.4% · 本地 TXT</p>
        <div class="progress-bar"><i style="width: 68.4%"></i></div>
      </article>
      <button class="setting-row" data-action="importBook"><span><strong>导入本地小说</strong><span>解析 TXT 并建立章节索引</span></span><b>＋</b></button>
    `,
  },
  chapters: {
    title: '章节目录',
    html: `
      <button class="chapter-item read" data-chapter="第十二回 玄奘秉诚建大会">第十二回 玄奘秉诚建大会 <span>已读</span></button>
      <button class="chapter-item read" data-chapter="第十三回 陷虎穴金星解厄">第十三回 陷虎穴金星解厄 <span>已读</span></button>
      <button class="chapter-item active" data-chapter="第十四回 心猿归正 六贼无踪">第十四回 心猿归正 六贼无踪 <span>当前</span></button>
      <button class="chapter-item" data-chapter="第十五回 蛇盘山诸神暗佑">第十五回 蛇盘山诸神暗佑 <span>未读</span></button>
      <button class="chapter-item" data-chapter="第十六回 观音院僧谋宝贝">第十六回 观音院僧谋宝贝 <span>未读</span></button>
      <button class="chapter-item" data-chapter="第十七回 孙行者大闹黑风山">第十七回 孙行者大闹黑风山 <span>未读</span></button>
    `,
  },
  settings: {
    title: '神经系统配置',
    html: `
      <button class="setting-row" data-toggle="storyTts"><span><strong>自动朗读</strong><span>接入神经链路，自动播报小说文本</span></span><b class="switch on"><i></i></b></button>
      <button class="setting-row" data-toggle="ambient"><span><strong>背景氛围音</strong><span>武侠风云 · 低频工业环境</span></span><b class="switch on"><i></i></b></button>
      <button class="setting-row" data-toggle="sfx"><span><strong>方块合并音效</strong><span>2048 核心交互音频反馈</span></span><b class="switch on"><i></i></b></button>
      <button class="setting-row" data-toggle="quality"><span><strong>动画质量</strong><span>自动 · 根据性能探测降级</span></span><b>Auto</b></button>
    `,
  },
};

function openModal(type) {
  const template = modalTemplates[type];
  if (!template) return;
  modalTitle.textContent = template.title;
  modalBody.innerHTML = template.html;
  modalLayer.classList.remove('modal-layer--hidden');
}

function closeModal() {
  modalLayer.classList.add('modal-layer--hidden');
}

function showToast(message) {
  toastText.textContent = `XIAOYO · ${message}`;
  toast.classList.remove('toast--hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.add('toast--hidden');
  }, 1800);
}

function togglePlayback() {
  playing = !playing;
  playerConsole.classList.toggle('playing', playing);
  playButton.textContent = playing ? 'Ⅱ' : '▶';
  showToast(playing ? '朗读链路已启动' : '朗读链路已暂停');
}

function nextSentence() {
  sentenceIndex = (sentenceIndex + 1) % sentences.length;
  activeSentence.textContent = sentences[sentenceIndex];
}

function bumpScore() {
  score += 128;
  scoreValue.textContent = score.toString();
  mascot.classList.add('active');
  setTimeout(() => mascot.classList.remove('active'), 220);
  showToast('棋盘状态已高亮');
}

function bindModalBodyAction(event) {
  const chapterButton = event.target.closest('[data-chapter]');
  if (chapterButton) {
    chapterTitle.textContent = chapterButton.dataset.chapter;
    document.querySelectorAll('.chapter-item').forEach((item) => {
      item.classList.remove('active');
    });
    chapterButton.classList.add('active');
    closeModal();
    showToast('章节跳转已模拟');
    return;
  }

  const toggleButton = event.target.closest('[data-toggle]');
  if (toggleButton) {
    const switchNode = toggleButton.querySelector('.switch');
    if (switchNode) switchNode.classList.toggle('on');
    showToast('设置状态已切换');
    return;
  }

  if (event.target.closest('[data-action="importBook"]')) {
    showToast('导入入口仅作视觉预览');
  }
}

document.querySelectorAll('[data-modal]').forEach((button) => {
  button.addEventListener('click', () => openModal(button.dataset.modal));
});

document.querySelectorAll('[data-modal-hint]').forEach((item) => {
  item.addEventListener('click', () => openModal(item.dataset.modalHint));
});

modalLayer.addEventListener('click', (event) => {
  if (event.target.closest('[data-close]')) {
    closeModal();
    return;
  }
  if (event.target.classList.contains('modal-backdrop')) {
    closeModal();
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !modalLayer.classList.contains('modal-layer--hidden')) {
    closeModal();
  }
});

modalBody.addEventListener('click', bindModalBodyAction);
playButton.addEventListener('click', togglePlayback);
playerConsole.addEventListener('dblclick', () => openModal('chapters'));
speedButton.addEventListener('click', () => {
  speedIndex = (speedIndex + 1) % speeds.length;
  speedButton.textContent = speeds[speedIndex];
  showToast(`倍速切换为 ${speeds[speedIndex]}`);
});

document.querySelectorAll('.tile').forEach((tile) => {
  tile.addEventListener('click', () => {
    tile.classList.add('pulse');
    setTimeout(() => tile.classList.remove('pulse'), 180);
    bumpScore();
  });
});

mascot.addEventListener('click', () => {
  mascot.classList.add('active');
  setTimeout(() => mascot.classList.remove('active'), 220);
  showToast('小游收到你的点击');
});

setInterval(() => {
  if (playing) nextSentence();
}, 2200);
