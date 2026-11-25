// =====================================================================
// Orbit プッシュ通知（Supabase Edge Function「push」）
// Supabase の「Edge Functions → Deploy a new function → Via Editor」で、
// 名前を push にして、このファイルの中身をすべて貼り付けて Deploy してください。
// 鍵（VAPID）は初回に自動で作られ、データベースの push_config に保存されます。
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

// ---------- Web Push（RFC 8291 / RFC 8292）を Web Crypto だけで実装 ----------
const enc = new TextEncoder();
export function b64u(buf) {
  const b = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
export function unb64u(s) {
  s = String(s).replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}
const cat = (...a) => {
  const out = new Uint8Array(a.reduce((n, x) => n + x.length, 0));
  let o = 0;
  for (const x of a) { out.set(x, o); o += x.length; }
  return out;
};
async function hkdf(ikm, salt, info, len) {
  const k = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, k, len * 8));
}

// VAPID の鍵を作る（公開鍵は端末に渡す、秘密鍵は JWK でデータベースに保存）
export async function makeVapid() {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pub = new Uint8Array(await crypto.subtle.exportKey("raw", kp.publicKey));
  const jwk = await crypto.subtle.exportKey("jwk", kp.privateKey);
  return { publicKey: b64u(pub), privateJwk: JSON.stringify(jwk) };
}

// 通知の中身を暗号化（aes128gcm）
export async function encryptPayload(payload, p256dh, authSecret) {
  const uaPub = unb64u(p256dh), auth = unb64u(authSecret);
  const local = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const asPub = new Uint8Array(await crypto.subtle.exportKey("raw", local.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", uaPub, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, local.privateKey, 256));
  const ikm = await hkdf(shared, auth, cat(enc.encode("WebPush: info\0"), uaPub, asPub), 32);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(ikm, salt, enc.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(ikm, salt, enc.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const plain = cat(enc.encode(payload), new Uint8Array([2]));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, plain));
  const rs = new Uint8Array([0, 0, 16, 0]); // 4096
  return cat(salt, rs, new Uint8Array([asPub.length]), asPub, ct);
}

// VAPID の署名（ES256 の JWT）
export async function vapidAuth(endpoint, publicKey, privateJwk, subject) {
  const aud = new URL(endpoint).origin;
  const head = b64u(enc.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const body = b64u(enc.encode(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject })));
  const key = await crypto.subtle.importKey("jwk", JSON.parse(privateJwk), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(head + "." + body)));
  return `vapid t=${head}.${body}.${b64u(sig)}, k=${publicKey}`;
}

export async function sendPush(sub, payload, vapid, subject, fetchImpl = fetch) {
  const body = await encryptPayload(payload, sub.p256dh, sub.auth);
  const res = await fetchImpl(sub.endpoint, {
    method: "POST",
    headers: {
      "Content-Encoding": "aes128gcm",
      "Content-Type": "application/octet-stream",
      TTL: "86400",
      Urgency: "normal",
      Authorization: await vapidAuth(sub.endpoint, vapid.publicKey, vapid.privateJwk, subject),
    },
    body,
  });
  return res.status;
}

// ---------- 通知の文面 ----------
const TEXT = {
  ja: { like: "{n}さんがあなたの投稿にいいねしました", repost: "{n}さんがあなたの投稿をリポストしました", reply: "{n}さんが返信しました", quote: "{n}さんがあなたの投稿を引用しました", mention: "{n}さんがあなたについて投稿しました", follow: "{n}さんがあなたをフォローしました", freq: "{n}さんからフォローリクエストが届きました", dm: "{n}さんからメッセージが届きました", notice: "運営からのお知らせが届きました", someone: "だれか", image: "画像" },
  en: { like: "{n} liked your post", repost: "{n} reposted your post", reply: "{n} replied", quote: "{n} quoted your post", mention: "{n} mentioned you", follow: "{n} followed you", freq: "{n} sent you a follow request", dm: "New message from {n}", notice: "You have a notice from Orbit", someone: "Someone", image: "Image" },
  ko: { like: "{n}님이 게시물을 좋아합니다", repost: "{n}님이 게시물을 리포스트했습니다", reply: "{n}님이 답글을 남겼습니다", quote: "{n}님이 게시물을 인용했습니다", mention: "{n}님이 회원님을 언급했습니다", follow: "{n}님이 회원님을 팔로우했습니다", freq: "{n}님이 팔로우 요청을 보냈습니다", dm: "{n}님의 메시지가 도착했습니다", notice: "운영팀의 알림이 도착했습니다", someone: "누군가", image: "이미지" },
  "zh-CN": { like: "{n} 赞了你的帖子", repost: "{n} 转发了你的帖子", reply: "{n} 回复了你", quote: "{n} 引用了你的帖子", mention: "{n} 提到了你", follow: "{n} 关注了你", freq: "{n} 向你发送了关注请求", dm: "{n} 给你发来消息", notice: "你收到一条运营通知", someone: "有人", image: "图片" },
  "zh-TW": { like: "{n} 喜歡你的貼文", repost: "{n} 轉發了你的貼文", reply: "{n} 回覆了你", quote: "{n} 引用了你的貼文", mention: "{n} 提到了你", follow: "{n} 追蹤了你", freq: "{n} 向你發送了追蹤請求", dm: "{n} 傳來訊息", notice: "你收到一則營運通知", someone: "有人", image: "圖片" },
};
const hex = (s) => Array.from(enc.encode(String(s)), (b) => b.toString(16).padStart(2, "0")).join("");
export function buildMessage(kind, actorName, actorId, ref, snippet, lang = "ja") {
  const T = TEXT[lang] || TEXT.ja;
  const title = (T[kind] || T.notice).replace("{n}", actorName || T.someone);
  if (kind === "dm" && snippet === "画像") snippet = T.image;
  let url = "/#notifications";
  if (kind === "dm" && actorId) url = "/#dm-" + hex(actorId);
  else if (["reply", "quote", "mention", "like", "repost"].includes(kind) && ref) url = "/#post-" + ref;
  else if (kind === "follow" || kind === "freq") url = actorId ? "/#u-" + hex(actorId) : "/#notifications";
  return { title, body: snippet || "", url, tag: kind + ":" + (ref || actorId || ""), kind };
}

// ---------- 本体 ----------
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

function serviceKey() {
  const k = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (k) return k;
  try { const j = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}"); return j.default || Object.values(j)[0] || ""; } catch (_) { return ""; }
}

async function config(db, origin) {
  const { data } = await db.from("push_config").select("key,value");
  const c = Object.fromEntries((data || []).map((r) => [r.key, r.value]));
  const add = {};
  if (!c.vapid_public || !c.vapid_private) {
    const v = await makeVapid();
    add.vapid_public = v.publicKey; add.vapid_private = v.privateJwk;
  }
  const fn = Deno.env.get("SUPABASE_URL") + "/functions/v1/push";
  if (c.fn_url !== fn) add.fn_url = fn;
  if (origin && /^https:\/\//.test(origin) && !c.site_url) add.site_url = origin;
  if (Object.keys(add).length) {
    const vap = Object.entries(add).filter(([k]) => k.startsWith("vapid_")), rest = Object.entries(add).filter(([k]) => !k.startsWith("vapid_"));
    // 鍵が同時に作られた場合は、先に保存された方を使う（上書きしない）
    if (vap.length) await db.from("push_config").upsert(vap.map(([key, value]) => ({ key, value })), { onConflict: "key", ignoreDuplicates: true });
    if (rest.length) await db.from("push_config").upsert(rest.map(([key, value]) => ({ key, value })), { onConflict: "key" });
    const again = await db.from("push_config").select("key,value");
    return Object.fromEntries((again.data || []).map((r) => [r.key, r.value]));
  }
  return c;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  const db = createClient(Deno.env.get("SUPABASE_URL"), serviceKey(), { auth: { persistSession: false } });
  try {
    const cfg = await config(db, req.headers.get("origin"));
    // 端末から：通知の公開鍵を返す
    if (req.method === "GET") return json({ publicKey: cfg.vapid_public });
    // データベースから：通知を送る
    if (!cfg.hook_secret || req.headers.get("x-orbit-secret") !== cfg.hook_secret) return json({ error: "forbidden" }, 403);
    const { target, kind, actor, ref, snippet } = await req.json();
    const [subs, state, prof] = await Promise.all([
      db.from("push_subs").select("endpoint,p256dh,auth").eq("uid", target),
      db.from("private_docs").select("json").eq("uid", target).eq("key", "state").maybeSingle(),
      actor ? db.from("profiles").select("name,handle").eq("id", actor).maybeSingle() : Promise.resolve({ data: null }),
    ]);
    const st = (state.data && state.data.json) || {};
    const off = Array.isArray(st.notifOff) ? st.notifOff : [];
    const mutes = Array.isArray(st.mutes) ? st.mutes : [];
    const pushOff = st.pushOff === true;
    if (pushOff || (actor && mutes.includes(actor))) return json({ skipped: "muted" });
    const prefKind = kind === "freq" ? "follow" : kind === "notice" ? "ann" : kind;
    if (off.includes(prefKind)) return json({ skipped: "off" });
    const words = Array.isArray(st.muteWords) ? st.muteWords : [];
    if (snippet && words.some((w) => w && String(snippet).toLowerCase().includes(String(w).toLowerCase()))) return json({ skipped: "word" });
    const name = prof.data ? prof.data.name || prof.data.handle : "";
    const msg = buildMessage(kind, name, actor, ref, snippet, typeof st.lang === "string" && TEXT[st.lang] ? st.lang : "ja");
    const subject = cfg.site_url || "mailto:noreply@example.com";
    const vapid = { publicKey: cfg.vapid_public, privateJwk: cfg.vapid_private };
    let sent = 0;
    for (const s of subs.data || []) {
      try {
        const st2 = await sendPush(s, JSON.stringify(msg), vapid, subject);
        if (st2 === 404 || st2 === 410) await db.from("push_subs").delete().eq("endpoint", s.endpoint).eq("uid", target); // もう使われていない宛先
        else if (st2 < 300) sent++;
      } catch (e) { console.error("push failed", e); }
    }
    return json({ sent });
  } catch (e) {
    console.error(e);
    return json({ error: String(e && e.message || e) }, 500);
  }
});
