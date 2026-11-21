// 這兩項是 Supabase 專供瀏覽器使用的公開連線資訊。
// 資料存取仍受 Supabase Auth 與 Row Level Security (RLS) 保護。
window.ECON_SUPABASE = Object.freeze({
  url: "https://xkjhsqminwzrkxswqqia.supabase.co",
  publishableKey: "sb_publishable_2x7jEM4iAfij_nmXSOEUdQ_xofVq3AF",
  // Anonymous Sign-Ins、005 SQL 與學生名冊均已完成。
  studentCloudAuthEnabled: true,
  // 011 SQL 完成後改為 true，學生只需班級＋學號即可登入。
  passwordlessStudentLoginEnabled: true,
  // 007 題庫與伺服器判分 SQL 已完成。
  cloudLearningSyncEnabled: true,
  // 008 排行榜 SQL 已完成。
  leaderboardEnabled: true
});
