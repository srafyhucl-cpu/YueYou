const fs = require('fs');
let c = fs.readFileSync('d:/MyGO/GoProject/go_project/2048-app/www/main.js', 'utf8');

c = c.replace('(()=>{var V="http://8.218.177.149:3000";(()=>{', '(()=>{const API_BASE="http://8.218.177.149:8080";var V=API_BASE;(()=>{');

c = c.split('"${API_BASE}/api/state/save"').join('`${API_BASE}/api/state/save`');
c = c.split('"${API_BASE}/api/auth/login"').join('`${API_BASE}/api/auth/login`');
c = c.split('"${API_BASE}/api/auth/register"').join('`${API_BASE}/api/auth/register`');
c = c.split('"${API_BASE}/api/novels"').join('`${API_BASE}/api/novels`');
c = c.split('"${API_BASE}/api/novel/upload"').join('`${API_BASE}/api/novel/upload`');

c = c.replace('this.ttsURL="${API_BASE}/api/v1/tts/createStream"', 'this.ttsURL="http://8.218.177.149:3000/api/v1/tts/createStream"');

c = c.replace('l(),window._showToast=g=>{', `l();
window.addEventListener('touchstart', function unlockAudio(){
    l();
    let silentAudio = new Audio();
    silentAudio.src = "data:audio/mp3;base64,//NkxAA";
    silentAudio.play().catch(e=>{});
    window.removeEventListener('touchstart', unlockAudio);
}, {once: true});
window._showToast=g=>{`);

fs.writeFileSync('d:/MyGO/GoProject/go_project/2048-app/www/main.js', c);
console.log("main.js fixes applied successfully.");
