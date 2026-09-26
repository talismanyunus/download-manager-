// Download Manager — Content Script v5
// document_start + all_frames: true ile çalışır
// iframe içindeki stream URL'leri ana frame'e iletilir
(function () {
  "use strict";

  var ACCENT = "#5CE8C2";
  var BG     = "rgba(6,9,14,0.97)";
  var isTopFrame = (window === window.top);

  // ── Reklam filtresi ───────────────────────────────────────────────────────
  function isAd(url) {
    var u = url.toLowerCase();
    // Reklam domain'leri
    if (u.includes("googlead") || u.includes("doubleclick") ||
        u.includes("prebid")   || u.includes("vast")        ||
        u.includes("googlesyndication") || u.includes("moatads") ||
        u.includes("adserver") || u.includes("adsystem"))    return true;
    // Path tabanlı reklam — /rekla/, /reklam/, /ads/, /ad/ vb.
    try {
      var path = new URL(url).pathname.toLowerCase();
      if (/^\/(rekla|reklam|ads?|banner|sponsor|promo|campaign)\//i.test(path)) return true;
      // Çok kısa mp4'ler (reklam büyük ihtimalle — 30 sn altı = küçük dosya)
      // URL'de izleme parametreleri
      var search = new URL(url).search.toLowerCase();
      if (search.includes("vast") || search.includes("adid") ||
          search.includes("creative") || search.includes("placement")) return true;
    } catch(e) {}
    return false;
  }

  function isMediaStream(url) {
    var u = String(url);
    return /\.(m3u8|mpd)(\?|#|$)/i.test(u) || u.includes(".m3u8") || u.includes("/m3u8");
  }

  function isVideoFile(url) {
    if (isAd(url)) return false;
    return /\.(mp4|mkv|webm|avi|mov|flv|m4v|ts)(\?|#|$)/i.test(url);
  }

  // ── XHR/Fetch intercept (document_start'ta çalışır) ──────────────────────
  var origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    try {
      var u = String(url || "");
      if ((isMediaStream(u) || isVideoFile(u)) && !isAd(u)) {
        var full = /^https?:\/\//.test(u) ? u : new URL(u, location.href).href;
        notifyStream(full);
      }
    } catch (e) {}
    return origOpen.apply(this, arguments);
  };

  var origFetch = window.fetch;
  window.fetch = function (input) {
    try {
      var u = typeof input === "string" ? input : (input && input.url) || "";
      if ((isMediaStream(u) || isVideoFile(u)) && !isAd(u)) {
        var full = /^https?:\/\//.test(u) ? u : new URL(u, location.href).href;
        notifyStream(full);
      }
    } catch (e) {}
    return origFetch.apply(this, arguments);
  };

  // ── Stream URL'sini bildir ────────────────────────────────────────────────
  // YouTube ve bilinen yt-dlp siteleri için stream yakalama gerekmiyor —
  // yt-dlp sayfanın URL'sinden kendi halleder.
  var YTDLP_DIRECT = [
    "youtube.com","youtu.be","vimeo.com","twitter.com","x.com",
    "instagram.com","facebook.com","tiktok.com","dailymotion.com",
    "twitch.tv","reddit.com","bilibili.com","soundcloud.com","rumble.com",
    "odysee.com","ok.ru"
  ];

  function isYtdlpDirect(url) {
    try {
      var h = new URL(url).hostname.replace(/^www\./,"");
      return YTDLP_DIRECT.some(function(s){ return h===s||h.endsWith("."+s); });
    } catch(e){ return false; }
  }

  function notifyStream(url) {
    // yt-dlp'nin doğrudan desteklediği sitelerde stream yakalama yok
    if (isYtdlpDirect(location.href)) return;
    if (isTopFrame) {
      addStream(url);
    } else {
      try {
        window.top.postMessage({ __dm: true, type: "stream", url: url, referer: location.href }, "*");
      } catch (e) {
        try { chrome.runtime.sendMessage({ type: "STREAM_FOUND", url: url, referer: location.href }); } catch(e2) {}
      }
    }
  }

  // iframe'den gelen mesajları dinle (sadece top frame'de)
  if (isTopFrame) {
    window.addEventListener("message", function (e) {
      if (e.data && e.data.__dm && e.data.type === "stream") {
        addStream(e.data.url, e.data.referer);
      }
    });

    // background'dan gelen stream bildirimleri
    try {
      chrome.runtime.onMessage.addListener(function (msg) {
        if (msg.type === "STREAM_FOUND" && msg.url) {
          addStream(msg.url, msg.referer);
        }
      });
    } catch(e) {}
  }

  // ── Stream listesi (sadece top frame tutar) ───────────────────────────────
  if (!isTopFrame) return; // iframe'lerde aşağıdaki kod çalışmaz

  // Sayfa guard — bir kez çalış
  if (window.__dmInjected) return;
  window.__dmInjected = true;

  var streams    = [];
  var streamUrls = new Set();

  function addStream(url, referer) {
    if (!url || streamUrls.has(url)) return;
    if (isAd(url)) return;   // reklam filtresi
    // /rekla/ veya /reklam/ path'i kesinlikle reklam
    try {
      var p = new URL(url).pathname.toLowerCase();
      if (p.startsWith("/rekla") || p.startsWith("/reklam")) return;
    } catch(e) {}
    streamUrls.add(url);
    var label = guessLabel(url);
    streams.push({ url: url, label: label, referer: referer || location.href });
    updatePanel();
    if (streams.length === 1 && document.querySelector("video")) showPanel();
  }

  function guessLabel(url) {
    if (url.includes("1080")) return "1080p HD";
    if (url.includes("720"))  return "720p HD";
    if (url.includes("480"))  return "480p";
    if (url.includes("360"))  return "360p";
    if (url.includes("master") || url.includes("Master")) return "Ana Akış (tüm kaliteler)";
    if (url.includes("playlist")) return "Playlist Stream";
    if (isVideoFile(url)) {
      var ext = url.split("?")[0].split(".").pop().toUpperCase();
      return "Doğrudan " + ext;
    }
    try { return new URL(url).hostname; } catch(e) { return "Stream"; }
  }

  // ── Stil ───────────────────────────────────────────────────────────────────
  var style = document.createElement("style");
  style.textContent = [
    ".dm-btn{position:absolute;z-index:2147483647;display:flex;align-items:center;gap:5px;",
    "padding:6px 11px;background:"+BG+";color:"+ACCENT+";",
    "font:600 12px/1 -apple-system,sans-serif;border:1.5px solid "+ACCENT+"55;",
    "border-radius:8px;cursor:pointer;backdrop-filter:blur(16px);",
    "transition:opacity .2s,transform .15s;white-space:nowrap;pointer-events:all;}",
    ".dm-btn:hover{background:rgba(92,232,194,.12);transform:scale(1.04);}",
    ".dm-panel{position:fixed;bottom:18px;right:18px;z-index:2147483647;width:370px;",
    "background:"+BG+";border:1px solid rgba(92,232,194,.2);border-radius:14px;",
    "box-shadow:0 16px 56px rgba(0,0,0,.85);overflow:hidden;",
    "font-family:-apple-system,BlinkMacSystemFont,sans-serif;",
    "animation:dm-in .22s ease;}",
    ".dm-hdr{display:flex;align-items:center;gap:8px;padding:11px 14px;",
    "background:rgba(92,232,194,.05);border-bottom:1px solid rgba(92,232,194,.12);}",
    ".dm-hdr-title{flex:1;font:600 12px/1 -apple-system,sans-serif;color:#fff;}",
    ".dm-hdr button{background:none;border:none;color:rgba(255,255,255,.4);",
    "cursor:pointer;font-size:16px;line-height:1;padding:2px 4px;border-radius:4px;}",
    ".dm-hdr button:hover{background:rgba(255,255,255,.08);color:#fff;}",
    ".dm-row{display:flex;align-items:center;gap:10px;padding:10px 14px;",
    "border-bottom:1px solid rgba(255,255,255,.04);transition:background .12s;}",
    ".dm-row:last-child{border-bottom:none;}",
    ".dm-row:hover{background:rgba(92,232,194,.05);}",
    ".dm-row-info{flex:1;min-width:0;}",
    ".dm-row-label{font:600 12px/1.4 -apple-system,sans-serif;color:#eee;",
    "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}",
    ".dm-row-url{font:10px/1.4 monospace;color:rgba(255,255,255,.28);",
    "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px;}",
    ".dm-dl{background:"+ACCENT+";color:#000;border:none;border-radius:7px;",
    "padding:6px 13px;font:700 11px -apple-system,sans-serif;cursor:pointer;",
    "flex-shrink:0;transition:opacity .12s;}",
    ".dm-dl:hover{opacity:.85;}",
    ".dm-empty{padding:16px;text-align:center;font:12px -apple-system,sans-serif;",
    "color:rgba(255,255,255,.3);line-height:1.6;}",
    ".dm-fab{position:fixed;bottom:18px;right:18px;z-index:2147483646;",
    "display:flex;align-items:center;gap:7px;padding:9px 15px;",
    "background:"+BG+";color:"+ACCENT+";",
    "font:700 12px/1 -apple-system,sans-serif;",
    "border:1.5px solid "+ACCENT+"55;border-radius:10px;cursor:pointer;",
    "backdrop-filter:blur(20px);box-shadow:0 4px 24px rgba(0,0,0,.7);",
    "transition:transform .15s,border-color .15s;}",
    ".dm-fab:hover{transform:scale(1.05);border-color:"+ACCENT+";}",
    "@keyframes dm-in{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}"
  ].join("");
  (document.head || document.documentElement).appendChild(style);

  var ICON = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="'+ACCENT
    +'" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">'
    +'<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>'
    +'<polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';

  // ── Panel ─────────────────────────────────────────────────────────────────
  var panel = null;

  function showPanel() {
    if (panel) { updatePanel(); return; }
    // FAB'ı kaldır
    var fab = document.getElementById("dm-fab");
    if (fab) fab.remove();

    panel = document.createElement("div");
    panel.className = "dm-panel";
    panel.innerHTML =
      '<div class="dm-hdr">'
      + ICON
      + '<div class="dm-hdr-title">Download Manager — Stream Seç</div>'
      + '<button id="dm-clr" title="Listeyi temizle">↺</button>'
      + '<button id="dm-cls">\u00d7</button>'
      + '</div>'
      + '<div id="dm-list"></div>';
    document.body && document.body.appendChild(panel);

    document.getElementById("dm-cls").onclick = hidePanel;
    document.getElementById("dm-clr").onclick = function(){
      streams = []; streamUrls.clear(); updatePanel();
    };
    updatePanel();
  }

  function hidePanel() {
    if (panel) { panel.remove(); panel = null; }
    showFab();
  }

  function updatePanel() {
    if (!panel) return;
    var list = document.getElementById("dm-list");
    if (!list) return;
    if (streams.length === 0) {
      list.innerHTML = '<div class="dm-empty">Stream bekleniyor…<br><small>Videoyu oynat, m3u8 URL\'si yakalanacak.</small></div>';
      return;
    }
    // En son yakalananlar üstte
    list.innerHTML = streams.slice().reverse().map(function(s) {
      var urlShort = s.url.length > 52 ? s.url.slice(0,52)+"…" : s.url;
      return '<div class="dm-row">'
        + '<div class="dm-row-info">'
        +   '<div class="dm-row-label">'+esc(s.label)+'</div>'
        +   '<div class="dm-row-url">'+esc(urlShort)+'</div>'
        + '</div>'
        + '<button class="dm-dl" data-url="'+esc(s.url)+'" data-ref="'+esc(s.referer||location.href)+'">İndir</button>'
        + '</div>';
    }).join("");

    list.querySelectorAll(".dm-dl").forEach(function(btn){
      btn.onclick = function(){
        doDownload(btn.getAttribute("data-url"), btn.getAttribute("data-ref"));
        btn.textContent = "✓ Eklendi";
        btn.style.background = "rgba(92,232,194,.25)";
        btn.style.color = ACCENT;
        setTimeout(function(){ btn.textContent="İndir"; btn.style.background=""; btn.style.color=""; }, 3000);
      };
    });
  }

  // ── FAB (sabit buton) ─────────────────────────────────────────────────────
  function showFab() {
    if (document.getElementById("dm-fab")) return;
    var direct = isYtdlpDirect(location.href);
    var fab = document.createElement("button");
    fab.id = "dm-fab";
    fab.className = "dm-fab";
    fab.innerHTML = ICON + "<span>DM İndir"
      + (!direct && streams.length > 0
          ? ' <span style="background:'+ACCENT+';color:#000;border-radius:10px;padding:1px 6px;font-size:10px;margin-left:4px">'+streams.length+'</span>'
          : '')
      + "</span>";
    fab.onclick = function() {
      if (direct) {
        // YouTube/Vimeo vb. — direkt yt-dlp'ye gönder
        doDownload(location.href, location.href);
        fab.innerHTML = ICON + "<span>Eklendi \u2713</span>";
        setTimeout(function(){ fab.innerHTML = ICON + "<span>DM \u0130ndir</span>"; }, 2500);
      } else {
        showPanel();
      }
    };
    document.body && document.body.appendChild(fab);
  }

  // ── Video butonu (player üzerinde) ────────────────────────────────────────
  var injected = new WeakSet();

  function injectButton(video) {
    if (!(video instanceof HTMLVideoElement)) return;
    if (injected.has(video)) return;
    injected.add(video);

    var direct = isYtdlpDirect(location.href);

    // Video src'sini de yakala (yt-dlp sitesi DEĞİLSE)
    function checkSrc() {
      if (direct) return;
      var src = video.src || video.currentSrc;
      if (src && !/^blob:/.test(src) && (isMediaStream(src) || isVideoFile(src))) {
        addStream(src);
      }
      video.querySelectorAll("source").forEach(function(s) {
        if (s.src && !/^blob:/.test(s.src) && (isMediaStream(s.src) || isVideoFile(s.src))) {
          addStream(s.src);
        }
      });
    }
    checkSrc();
    video.addEventListener("loadedmetadata", checkSrc);
    video.addEventListener("play", function(){
      checkSrc();
      if (!direct) showPanel();
    }, { once: true });

    var btn = document.createElement("button");
    btn.className = "dm-btn";
    btn.innerHTML = ICON + "<span>DM İndir</span>";
    btn.style.cssText = "top:10px;right:10px;opacity:0;";
    btn.onclick = function(e){
      e.stopPropagation(); e.preventDefault();
      if (direct) {
        // yt-dlp sitesi — sayfanın URL'sini direkt gönder
        doDownload(location.href, location.href);
        btn.innerHTML = ICON + "<span>Eklendi ✓</span>";
        setTimeout(function(){ btn.innerHTML = ICON + "<span>DM İndir</span>"; }, 2500);
      } else {
        showPanel();
      }
    };

    var wrap = video.parentElement;
    if (!wrap) return;
    if (getComputedStyle(wrap).position === "static") wrap.style.position = "relative";
    wrap.appendChild(btn);

    var t = null;
    function show(){ clearTimeout(t); btn.style.opacity="1"; }
    function hide(){ t = setTimeout(function(){ btn.style.opacity="0"; }, 800); }
    wrap.addEventListener("mouseenter", show); wrap.addEventListener("mouseleave", hide);
    btn.addEventListener("mouseenter", show);  btn.addEventListener("mouseleave", hide);
  }

  // DOM gözlemcisi
  function scan() { document.querySelectorAll("video").forEach(injectButton); }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", scan);
  } else {
    scan();
  }
  new MutationObserver(function(muts){
    muts.forEach(function(m){
      m.addedNodes.forEach(function(n){
        if (n.nodeType !== 1) return;
        if (n.tagName === "VIDEO") injectButton(n);
        else if (n.querySelectorAll) n.querySelectorAll("video").forEach(injectButton);
      });
    });
  }).observe(document.documentElement, { childList:true, subtree:true });

  // SPA navigasyon
  var lastHref = location.href;
  setInterval(function(){
    if (location.href !== lastHref) {
      lastHref = location.href;
      streams = []; streamUrls.clear();
      if (panel) { panel.remove(); panel = null; }
      setTimeout(scan, 1200);
    }
  }, 800);

  // ── Dosya linki yakalama ──────────────────────────────────────────────────
  var FILE_EXTS = /\.(mp4|mkv|webm|avi|mov|flv|mp3|m4a|zip|rar|7z|gz|pdf|dmg|pkg|iso|exe|apk)(\?|#|$)/i;
  document.addEventListener("click", function(e){
    var a = e.target && e.target.closest ? e.target.closest("a") : null;
    if (!a || !a.href || a.href.startsWith("javascript:")) return;
    if (FILE_EXTS.test(a.href)) {
      e.preventDefault(); e.stopImmediatePropagation();
      doDownload(a.href, location.href);
      var b = document.createElement("span");
      b.textContent = "✓ DM";
      b.style.cssText = "margin-left:5px;padding:2px 6px;background:"+ACCENT
        +";color:#000;font:700 9px sans-serif;border-radius:4px;vertical-align:middle;";
      a.appendChild(b);
      setTimeout(function(){ b.remove(); }, 2000);
    }
  }, true);

  // ── İndirme gönder ────────────────────────────────────────────────────────
  function doDownload(url, referer) {
    var filename = isMediaStream(url)
      ? document.title.replace(/[/\\:*?"<>|]/g,"_").slice(0,80)
      : (guessFilename(url) || document.title.slice(0,80));
    chrome.runtime.sendMessage({
      type:      "DOWNLOAD",
      url:       url,
      referer:   referer || location.href,
      filename:  filename,
      userAgent: navigator.userAgent,
    });
  }

  function guessFilename(url) {
    try {
      var last = new URL(url).pathname.split("/").pop();
      return (last && last.includes(".")) ? decodeURIComponent(last) : "";
    } catch(e) { return ""; }
  }

  function esc(s) {
    return String(s||"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
  }

  // ── Streaming sitede buton göster ────────────────────────────────────────
  var STREAMING = ["youtube.com","youtu.be","vimeo.com","hdfilmcehennemi.com",
    "dizipal.com","diziwatch.com","filmizlesene.com","turkanime.co","dizibox.me",
    "fullhdfilm.co","jetfilmizle.com","puhu.tv","gain.tv","exxen.com","blu.tv",
    "tabii.com","mubi.com","streamable.com","streamtape.com","doodstream.com",
    "ok.ru","tiktok.com","twitter.com","x.com","instagram.com","dailymotion.com",
    "twitch.tv","reddit.com","bilibili.com","rumble.com","odysee.com"];

  function onPage(url) {
    try {
      var h = new URL(url).hostname.replace(/^www\./,"");
      return STREAMING.some(function(s){ return h===s||h.endsWith("."+s); });
    } catch(e){ return false; }
  }

  function isYouTube(url) {
    try {
      var h = new URL(url).hostname.replace(/^www\./,"");
      return h === "youtube.com" || h === "youtu.be";
    } catch(e){ return false; }
  }

  // YouTube player controls'a entegre buton
  function injectYouTubeButton() {
    if (document.getElementById("dm-yt-btn")) return;
    // YouTube'un sağ kontrol grubu: .ytp-right-controls
    var controls = document.querySelector(".ytp-right-controls");
    if (!controls) return;

    var btn = document.createElement("button");
    btn.id = "dm-yt-btn";
    btn.title = "Download Manager ile indir";
    btn.style.cssText = [
      "background:none;border:none;cursor:pointer;",
      "display:inline-flex;align-items:center;gap:5px;",
      "padding:0 8px;height:48px;",
      "color:"+ACCENT+";",
      "font:700 13px/1 -apple-system,sans-serif;",
      "opacity:0.9;transition:opacity .15s;",
      "vertical-align:top;"
    ].join("");

    // İndirme ikonu SVG
    btn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"'
      + ' stroke="'+ACCENT+'" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
      + '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>'
      + '<polyline points="7 10 12 15 17 10"/>'
      + '<line x1="12" y1="15" x2="12" y2="3"/>'
      + '</svg>'
      + '<span style="font-size:12px;font-weight:700;letter-spacing:.3px">DM</span>';

    btn.onmouseenter = function(){ btn.style.opacity="1"; btn.style.transform="scale(1.1)"; };
    btn.onmouseleave = function(){ btn.style.opacity="0.9"; btn.style.transform=""; };

    btn.onclick = function(e) {
      e.stopPropagation();
      doDownload(location.href, location.href);
      // Kısa onay animasyonu
      btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"'
        + ' stroke="'+ACCENT+'" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">'
        + '<polyline points="20 6 9 17 4 12"/></svg>'
        + '<span style="font-size:12px;font-weight:700">Eklendi</span>';
      setTimeout(function(){
        btn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"'
          + ' stroke="'+ACCENT+'" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
          + '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>'
          + '<polyline points="7 10 12 15 17 10"/>'
          + '<line x1="12" y1="15" x2="12" y2="3"/>'
          + '</svg>'
          + '<span style="font-size:12px;font-weight:700;letter-spacing:.3px">DM</span>';
      }, 2500);
    };

    // En başa ekle (sol taraf, diğer butonlardan önce)
    controls.insertBefore(btn, controls.firstChild);
  }

  if (isYouTube(location.href)) {
    // Player controls'u bekle (YouTube SPA — DOM geç hazır olur)
    var ytBtnInterval = setInterval(function(){
      if (document.querySelector(".ytp-right-controls")) {
        injectYouTubeButton();
        clearInterval(ytBtnInterval);
      }
    }, 500);

    // SPA navigasyon — her video değişiminde yeniden inject et
    var ytLastUrl = location.href;
    setInterval(function(){
      if (location.href !== ytLastUrl) {
        ytLastUrl = location.href;
        // Eski butonu kaldır
        var old = document.getElementById("dm-yt-btn");
        if (old) old.remove();
        // Yeni sayfada tekrar inject
        setTimeout(injectYouTubeButton, 1500);
      }
    }, 800);

  } else if (onPage(location.href)) {
    // Diğer streaming siteler için FAB
    setTimeout(showFab, 1200);
  }
})();
