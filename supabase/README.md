# Supabase 第一階段設定

此目錄是排行榜、積分、AI 糾錯及教師後台的後端基礎。尚未在 `index.html` 載入，因此建立檔案本身不會改變目前已上線的學生流程。

## 安全原則

- GitHub Pages 只能放 Supabase Project URL 與 publishable key。
- `secret`／`service_role` 金鑰只放在 Supabase Secrets，不可提交到 GitHub。
- 學生及教師先透過 Supabase Auth 取得 JWT，再由 RLS 限制資料列。
- 測驗判分、積分發放、糾錯審核及資料匯出由 Edge Functions 或受保護的資料庫函式執行。
- AI 糾錯截圖使用私有 `challenge-evidence` bucket，不使用公開網址。

## 建立順序

1. 由教師建立 Supabase 專案，地區與校方個資政策需先確認。
2. 在 Authentication 設定正式 Site URL：
   `https://liu-shane.github.io/economics-ai-tutor/`
3. 於 Google Cloud 建立 Web OAuth Client，將 Supabase callback URL 加入 Authorized redirect URIs。
4. 在 Supabase Auth 啟用 Google provider；Client Secret 僅輸入 Supabase Dashboard。
5. 依序套用 `migrations/001`、`002`、`003`。
6. 使用教師 Google 帳號登入一次，再由 SQL Editor 將該 Auth UUID 寫入 `teacher_roles`。
7. 建立學期、班級、群組設定與學生名冊；啟用碼只能儲存 `crypt()` 雜湊。
8. 執行 RLS 負面測試後，才將 Supabase 客戶端接入現有網站。

## 尚未啟用

- 現有網站仍使用 Google Apps Script 同步。
- Google OAuth 與學生啟用流程尚未載入學生頁面。
- 積分只建立資料模型；實際加分函式及每日上限將在下一階段以伺服器端交易完成。
- 排行榜快照排程與教師後台尚未上線。

## 不可提交的資訊

- Google OAuth Client Secret
- Supabase secret／service_role key
- 學生啟用碼明碼
- 教師私人帳號憑證
- 截圖與學生個資匯出檔
