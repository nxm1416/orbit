// ===== Orbit の設定 =====
// Supabase の「Project Settings → API」にある 2 つの値を、下の '' の中に貼り付けてください。
// anon key は公開しても大丈夫な鍵です（データは schema.sql の権限設定で守られています）。
// ※ service_role key は絶対に貼らないでください。
window.ORBIT_CONFIG = {
  SUPABASE_URL: 'https://aqwmuwnbcrjkzrzaguui.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_9FgAsW05EL7zAM1KDxK8pA_pTPFWz0G',
  // ロボット対策（Cloudflare Turnstile）の「サイトキー」。空のあいだはロボット対策なしで動きます
  TURNSTILE_SITE_KEY: '0x4AAAAAAGSu033cVO8i0TzG',
};
