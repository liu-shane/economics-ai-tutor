// 這兩項是 Supabase 專供瀏覽器使用的公開連線資訊。
// 資料存取仍受 Supabase Auth 與 Row Level Security (RLS) 保護。
window.ECON_SUPABASE = Object.freeze({
  url: "https://xkjhsqminwzrkxswqqia.supabase.co",
  publishableKey: "sb_publishable_2x7jEM4iAfij_nmXSOEUdQ_xofVq3AF",
  // Anonymous Sign-Ins、005 SQL 與學生名冊均已完成。
  studentCloudAuthEnabled: true
});
