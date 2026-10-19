// 這兩項是 Supabase 專供瀏覽器使用的公開連線資訊。
// 資料存取仍受 Supabase Auth 與 Row Level Security (RLS) 保護。
window.ECON_SUPABASE = Object.freeze({
  url: "https://xkjhsqminwzrkxswqqia.supabase.co",
  publishableKey: "sb_publishable_2x7jEM4iAfij_nmXSOEUdQ_xofVq3AF",
  // 完成 Anonymous Sign-Ins、名冊與 005 SQL 後才改為 true。
  studentCloudAuthEnabled: false
});
