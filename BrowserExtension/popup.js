"use strict";
var API = "http://127.0.0.1:60315";

var dot       = document.getElementById("dot");
var appLabel  = document.getElementById("app-label");
var activeBar = document.getElementById("active-bar");
var activeText= document.getElementById("active-text");
var cnt       = document.getElementById("cnt");
var tabCard   = document.getElementById("tab-card");
var tabTitle  = document.getElementById("tab-title");
var tabUrl    = document.getElementById("tab-url");
var tabFav    = document.getElementById("tab-fav");
var tabDl     = document.getElementById("tab-dl");
var urlIn     = document.getElementById("url-in");
var btnAdd    = document.getElementById("btn-add");
var toast     = document.getElementById("toast");
var openApp   = document.getElementById("open-app");

var currentTab = null;

// ── Uygulama durumu ──────────────────────────────────────────────────────────
function checkStatus() {
  fetch(API + "/status", { signal: AbortSignal.timeout(2000) })
    .then(function(r){ return r.json(); })
    .then(function(d){
      dot.classList.add("on");
      appLabel.textContent = "Uygulama çalışıyor";
      var n = d.active || 0;
      cnt.textContent = n;
      if (n > 0) {
        activeBar.classList.add("show");
        activeText.textContent = n + " indirme devam ediyor";
      } else {
        activeBar.classList.remove("show");
      }
    })
    .catch(function(){
      dot.classList.remove("on");
      appLabel.textContent = "Uygulama açık değil";
      cnt.textContent = "—";
      activeBar.classList.remove("show");
    });
}

// ── Mevcut sekme ─────────────────────────────────────────────────────────────
function loadTab() {
  chrome.tabs.query({ active: true, currentWindow: true }, function(tabs){
    if (!tabs || !tabs[0]) return;
    currentTab = tabs[0];
    tabTitle.textContent = currentTab.title || currentTab.url || "";
    tabUrl.textContent   = currentTab.url   || "";
    if (currentTab.favIconUrl) tabFav.src = currentTab.favIconUrl;

    // YouTube / video sitesi ise "VİDEOYU İNDİR" göster
    var isVideo = isStreamingHost(currentTab.url);
    tabDl.textContent = isVideo ? "VİDEO İNDİR ↓" : "İNDİR ↓";
    tabDl.style.color = isVideo ? "#5CE8C2" : "";
  });
}

function isStreamingHost(url) {
  var hosts = ["youtube.com","youtu.be","vimeo.com","tiktok.com","twitter.com",
               "x.com","instagram.com","facebook.com","dailymotion.com","twitch.tv",
               "reddit.com","bilibili.com","soundcloud.com","rumble.com"];
  try {
    var h = new URL(url).hostname.replace("www.","");
    return hosts.some(function(s){ return h === s || h.endsWith("."+s); });
  } catch(e){ return false; }
}

// ── Mevcut sekmeyi indir ─────────────────────────────────────────────────────
tabCard.addEventListener("click", function(){
  if (!currentTab) return;
  send({ url: currentTab.url, referer: currentTab.url, filename: "" })
    .then(function(ok){ showToast(ok ? "İndirme başlatıldı ✓" : "Uygulama açık değil.", ok); });
});

// ── Manuel URL ───────────────────────────────────────────────────────────────
btnAdd.addEventListener("click", addUrl);
urlIn.addEventListener("keydown", function(e){ if (e.key === "Enter") addUrl(); });

function addUrl() {
  var url = urlIn.value.trim();
  if (!url) return;
  try { new URL(url); } catch(e){ showToast("Geçerli bir URL girin.", false); return; }
  btnAdd.disabled = true;
  send({ url: url, referer: "", filename: "" }).then(function(ok){
    showToast(ok ? "İndirme eklendi ✓" : "Uygulama açık değil.", ok);
    if (ok) urlIn.value = "";
    btnAdd.disabled = false;
    if (ok) checkStatus();
  });
}

// ── HTTP API ─────────────────────────────────────────────────────────────────
function send(payload) {
  return fetch(API + "/add", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(4000)
  })
  .then(function(r){ return r.json(); })
  .then(function(d){ return !!d.ok; })
  .catch(function(){ return false; });
}

// ── Toast ─────────────────────────────────────────────────────────────────────
var toastTimer = null;
function showToast(msg, ok) {
  clearTimeout(toastTimer);
  toast.textContent = msg;
  toast.className   = "toast " + (ok ? "ok" : "err");
  toastTimer = setTimeout(function(){ toast.className = "toast"; }, 3000);
}

// ── Uygulamayı öne al ────────────────────────────────────────────────────────
openApp.addEventListener("click", function(e){
  e.preventDefault();
  // HTTP isteği ile uygulamanın API'sine ulaşarak onu tetikle
  fetch(API + "/status").catch(function(){});
  // Mac'te özel URL scheme ile ön plana getirilemez browser'dan
  // En iyi yol kullanıcıya dock'tan tıklamasını söylemek
  showToast("Mac'te Dock'tan tıklayarak öne alabilirsin.", true);
});

// ── Başlat ───────────────────────────────────────────────────────────────────
checkStatus();
loadTab();
// Her 3 saniyede durumu güncelle (popup açıkken)
setInterval(checkStatus, 3000);
