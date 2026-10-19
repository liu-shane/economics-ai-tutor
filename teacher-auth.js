(function () {
  "use strict";

  const config = window.ECON_SUPABASE;
  const sdk = window.supabase;
  const client = config && sdk ? sdk.createClient(config.url, config.publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  }) : null;

  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, ch => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[ch]);

  function addStyles() {
    if (document.getElementById("teacher-auth-style")) return;
    const style = document.createElement("style");
    style.id = "teacher-auth-style";
    style.textContent = `
      .teacher-entry{width:100%;margin-top:10px;background:#edf2f6;color:#10213a}
      .teacher-entry:hover{background:#dce7ec}
      .teacher-login-note{font-size:.82rem;color:#64748b;margin-top:14px}
      .auth-error{display:none;margin-top:12px;padding:10px 12px;border-radius:10px;background:#fee2e2;color:#991b1b;font-weight:800}
      .auth-error.show{display:block}
      .teacher-shell{min-height:100vh;background:#f3f7fa}
      .teacher-bar{min-height:70px;background:#071426;color:#fff;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px max(20px,calc((100vw - 1180px)/2))}
      .teacher-bar .brand{color:#55e1d2;letter-spacing:0}
      .teacher-main{max-width:1180px;margin:auto;padding:28px 22px 60px}
      .teacher-actions{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
      .teacher-status{color:#cbd5e1;font-size:.85rem}
      .teacher-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0}
      .teacher-section{padding:20px;margin-top:16px}
      .teacher-section h2{margin:0 0 12px}
      .teacher-empty{padding:28px;text-align:center;color:#64748b}
      @media(max-width:820px){.teacher-grid{grid-template-columns:repeat(2,1fr)}}
      @media(max-width:520px){.teacher-grid{grid-template-columns:1fr}.teacher-bar{align-items:flex-start;flex-direction:column}}
    `;
    document.head.appendChild(style);
  }

  function injectTeacherEntry() {
    const form = document.getElementById("login");
    if (!form || document.getElementById("teacherEntry")) return;
    const button = document.createElement("button");
    button.type = "button";
    button.id = "teacherEntry";
    button.className = "btn teacher-entry";
    button.textContent = "教師專用登入";
    button.addEventListener("click", showTeacherLogin);
    form.appendChild(button);
  }

  function showTeacherLogin() {
    addStyles();
    document.getElementById("app").innerHTML = `<main class="login"><section class="loginGrid"><div><div class="brand"><span class="logo">⌁</span>ECON AI LAB</div><p class="eyebrow">教師專用區</p><h1>查看班級的<br><span>學習進展。</span></h1><p class="lead">教師後台採獨立帳號登入，並由資料庫角色權限再次驗證。</p></div><form class="card loginCard" id="teacherLogin"><div class="logo">▤</div><h2>教師登入</h2><p>請使用已建立的教師 Email 與 Supabase 專用密碼。</p><label for="teacherEmail">教師 Email</label><input id="teacherEmail" class="control" type="email" autocomplete="username" required><label for="teacherPassword">密碼</label><input id="teacherPassword" class="control" type="password" autocomplete="current-password" required><div id="teacherLoginError" class="auth-error" role="alert"></div><button class="btn primary full" id="teacherLoginSubmit">登入教師後台</button><button class="btn teacher-entry" id="backToStudent" type="button">返回學生登入</button><p class="teacher-login-note">此處使用教師另外設定的 Supabase 密碼，不是 Gmail 密碼。</p></form></section></main>`;
    document.getElementById("backToStudent").onclick = () => window.login();
    document.getElementById("teacherLogin").onsubmit = teacherSignIn;
  }

  function showError(message) {
    const box = document.getElementById("teacherLoginError");
    if (!box) return;
    box.textContent = message;
    box.classList.add("show");
  }

  async function teacherSignIn(event) {
    event.preventDefault();
    if (!client) return showError("Supabase 元件載入失敗，請重新整理頁面後再試。");
    const submit = document.getElementById("teacherLoginSubmit");
    submit.disabled = true;
    submit.textContent = "驗證中…";
    const email = document.getElementById("teacherEmail").value.trim();
    const password = document.getElementById("teacherPassword").value;
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      submit.disabled = false;
      submit.textContent = "登入教師後台";
      return showError("登入失敗，請確認教師 Email 與 Supabase 專用密碼。");
    }
    const allowed = await verifyTeacher(data.user.id);
    if (!allowed) {
      await client.auth.signOut();
      submit.disabled = false;
      submit.textContent = "登入教師後台";
      return showError("此帳號沒有啟用中的教師權限，已安全登出。");
    }
    await renderTeacherDashboard(data.user);
  }

  async function verifyTeacher(userId) {
    const { data, error } = await client.from("teacher_roles")
      .select("role,active").eq("user_id", userId).eq("active", true).maybeSingle();
    return !error && data && (data.role === "teacher" || data.role === "admin");
  }

  async function renderTeacherDashboard(user) {
    document.getElementById("app").innerHTML = `<div class="teacher-shell"><header class="teacher-bar"><div class="brand"><span class="logo">⌁</span>經濟學 AI 助教 · 教師後台</div><div class="teacher-actions"><span class="teacher-status">${escapeHtml(user.email)}</span><button class="btn secondary" id="refreshTeacher">重新整理</button><button class="btn ghost" id="teacherLogout">安全登出</button></div></header><main class="teacher-main"><section class="teacherHead"><p class="kicker" style="color:#ffc083">TEACHER DASHBOARD</p><h1>班級學習儀表板</h1><p>資料直接來自受 RLS 保護的 Supabase 專案。</p></section><div id="teacherData"><div class="card teacher-empty">正在讀取教學紀錄…</div></div></main></div>`;
    document.getElementById("teacherLogout").onclick = async () => { await client.auth.signOut(); window.login(); };
    document.getElementById("refreshTeacher").onclick = loadTeacherData;
    await loadTeacherData();
  }

  async function loadTeacherData() {
    const host = document.getElementById("teacherData");
    if (!host) return;
    host.innerHTML = `<div class="card teacher-empty">正在讀取教學紀錄…</div>`;
    const [attemptsRes, consultationsRes, reportsRes, enrollmentsRes, classesRes] = await Promise.all([
      client.from("quiz_attempts").select("id,enrollment_id,unit_code,question_count,correct_count,score,status,completed_at").order("completed_at", { ascending:false }).limit(200),
      client.from("consultations").select("id,enrollment_id,topic,question,status,created_at").order("created_at", { ascending:false }).limit(200),
      client.from("challenge_reports").select("id,enrollment_id,source_type,error_type,status,submitted_at").order("submitted_at", { ascending:false }).limit(200),
      client.from("enrollments").select("id,class_id,student_number,active"),
      client.from("classes").select("id,name,code,active")
    ]);
    const failed = [attemptsRes, consultationsRes, reportsRes, enrollmentsRes, classesRes].find(x => x.error);
    if (failed) {
      host.innerHTML = `<div class="note">後台資料讀取失敗：${escapeHtml(failed.error.message)}。請確認教師角色與 RLS SQL 已完整執行。</div>`;
      return;
    }
    const attempts = attemptsRes.data || [], consultations = consultationsRes.data || [], reports = reportsRes.data || [];
    const enrollmentMap = new Map((enrollmentsRes.data || []).map(x => [x.id, x]));
    const classMap = new Map((classesRes.data || []).map(x => [x.id, x.name]));
    const completed = attempts.filter(x => x.status === "completed");
    const scored = completed.filter(x => Number.isFinite(x.score));
    const average = scored.length ? Math.round(scored.reduce((sum,x) => sum + x.score, 0) / scored.length) : 0;
    const students = new Set([...attempts, ...consultations].map(x => enrollmentMap.get(x.enrollment_id)?.student_number).filter(Boolean));
    const rows = completed.slice(0, 50).map(x => {
      const enrollment = enrollmentMap.get(x.enrollment_id) || {};
      return `<tr><td>${escapeHtml(classMap.get(enrollment.class_id) || "—")}</td><td>${escapeHtml(enrollment.student_number || "—")}</td><td>${escapeHtml(x.unit_code)}</td><td><b>${escapeHtml(x.score ?? "—")} 分</b></td><td>${escapeHtml(x.completed_at ? new Date(x.completed_at).toLocaleString("zh-TW") : "—")}</td></tr>`;
    }).join("");
    host.innerHTML = `<div class="teacher-grid"><div class="stat"><b>${students.size}</b><small>參與學生</small></div><div class="stat"><b>${completed.length}</b><small>完成測驗</small></div><div class="stat"><b>${average}</b><small>平均成績</small></div><div class="stat"><b>${consultations.length}</b><small>AI 諮詢</small></div></div><section class="card teacher-section"><h2>最近測驗紀錄</h2><div class="tableWrap"><table class="table"><thead><tr><th>班級</th><th>學號</th><th>單元</th><th>成績</th><th>完成時間</th></tr></thead><tbody>${rows || `<tr><td colspan="5" class="teacher-empty">目前尚無已同步的測驗紀錄。</td></tr>`}</tbody></table></div></section><section class="card teacher-section"><h2>AI 糾錯回報</h2><p>待處理：<b>${reports.filter(x => x.status === "submitted" || x.status === "under_review").length}</b> 件　｜　累積：${reports.length} 件</p></section><div class="note">教師後台不再使用本機示範資料。若統計為 0，表示學生端紀錄尚未透過受保護的後端流程寫入 Supabase。</div>`;
  }

  async function restoreTeacherSession() {
    if (!client) return injectTeacherEntry();
    const { data } = await client.auth.getSession();
    const user = data.session?.user;
    if (user && await verifyTeacher(user.id)) return renderTeacherDashboard(user);
    if (user) await client.auth.signOut();
    injectTeacherEntry();
  }

  addStyles();
  const observer = new MutationObserver(injectTeacherEntry);
  observer.observe(document.getElementById("app"), { childList:true, subtree:true });
  restoreTeacherSession();
})();
