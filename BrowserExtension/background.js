// Download Manager — Background Service Worker
// MV3 uyumlu, module syntax YOK (service worker'da import desteklenmez)

var API_BASE    = "http://127.0.0.1:60315";
var NATIVE_HOST = "com.localdownloadmanager.host";

// ── Context Menu ──────────────────────────────────────────────────────────────
chrome.runtime.onInstalled.addListener(function () {
  chrome.contextMenus.removeAll(function () {
    chrome.contextMenus.create({
      id:       "dm-link",
      title:    "Download Manager ile İndir",
      contexts: ["link", "video", "audio", "image"]
    });
    chrome.contextMenus.create({
      id:       "dm-page",
      title:    "Bu sayfayı Download Manager'a gönder",
      contexts: ["page"]
    });
  });
});

chrome.contextMenus.onClicked.addListener(function (info, tab) {
  var url = info.linkUrl || info.srcUrl || info.pageUrl || (tab && tab.url) || "";
  if (!url) return;
  sendToApp({ url: url, referer: (tab && tab.url) || "", filename: guessFilename(url) });
});

// ── Content script mesajları ──────────────────────────────────────────────────
chrome.runtime.onMessage.addListener(function (msg, sender, sendResponse) {
  if (msg.type === "DOWNLOAD") {
    sendToApp({
      url:      msg.url      || "",
      referer:  msg.referer  || (sender.tab && sender.tab.url) || "",
      filename: msg.filename || "",
    }).then(function (ok) { sendResponse({ ok: ok }); });
    return true; // async
  }
  // iframe'den gelen stream bildirimi — ana frame'e ilet
  if (msg.type === "STREAM_FOUND" && sender.tab) {
    chrome.tabs.sendMessage(sender.tab.id, {
      type: "STREAM_FOUND",
      url:  msg.url,
      referer: msg.referer
    });
    return false;
  }
  if (msg.type === "CHECK_APP") {
    checkApp().then(function (ok) { sendResponse({ ok: ok }); });
    return true;
  }
});

// ── HTTP API ──────────────────────────────────────────────────────────────────
function sendToApp(payload) {
  return fetch(API_BASE + "/add", {
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify(payload),
    signal:  AbortSignal.timeout(5000)
  })
  .then(function (res) { return res.json(); })
  .then(function (data) {
    if (data.ok) {
      notify("İndirme eklendi ✓", payload.filename || payload.url);
    }
    return data.ok;
  })
  .catch(function () {
    // Uygulama kapalı — native messaging ile dene
    return sendViaNative(payload);
  });
}

function checkApp() {
  return fetch(API_BASE + "/status", { signal: AbortSignal.timeout(2000) })
    .then(function (r) { return r.ok; })
    .catch(function () { return false; });
}

function sendViaNative(payload) {
  return new Promise(function (resolve) {
    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST, payload, function (response) {
        resolve(!!(response && response.ok));
      });
    } catch (e) {
      notify("Download Manager çalışmıyor", "Uygulamayı açıp tekrar deneyin.");
      resolve(false);
    }
  });
}

// ── Bildirim ──────────────────────────────────────────────────────────────────
function notify(title, message) {
  var body = (message || "").length > 80
    ? (message || "").slice(0, 77) + "…"
    : (message || "");
  chrome.notifications.create({
    type:    "basic",
    iconUrl: "icons/icon48.png",
    title:   title,
    message: body
  });
}

// ── Yardımcı ──────────────────────────────────────────────────────────────────
function guessFilename(url) {
  try {
    var last = new URL(url).pathname.split("/").pop();
    return (last && last.indexOf(".") > -1) ? decodeURIComponent(last) : "";
  } catch (e) { return ""; }
}
