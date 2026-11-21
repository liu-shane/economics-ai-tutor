(function(){
  'use strict';
  if(!window.ECON_SUPABASE?.studentCloudAuthEnabled || !window.supabase) return;
  const client=window.supabase.createClient(window.ECON_SUPABASE.url,window.ECON_SUPABASE.publishableKey,{auth:{persistSession:true,autoRefreshToken:true}});
  const originalLogin=window.login;
  const passwordless=Boolean(window.ECON_SUPABASE.passwordlessStudentLoginEnabled);

  function configureStudentLogin(){
    const form=document.getElementById('login');
    if(!form||document.getElementById('studentAuthError')) return;
    const submit=form.querySelector('button.primary');
    const wrap=document.createElement('div');
    wrap.innerHTML=passwordless
      ? '<small style="display:block;margin-top:10px;color:#64748b">選擇原有班級並輸入學號即可進入。</small><div id="studentAuthError" class="auth-error" role="alert"></div>'
      : '<label for="activationCode">首次啟用碼</label><input id="activationCode" class="control" type="password" inputmode="text" autocomplete="one-time-code" placeholder="第一次使用或更換裝置時輸入"><small style="display:block;margin-top:6px;color:#64748b">同一裝置成功綁定後，之後不必再輸入。</small><div id="studentAuthError" class="auth-error" role="alert"></div>';
    form.insertBefore(wrap,submit);
    form.onsubmit=handleStudentLogin;
  }

  function errorMessage(message,className='',studentId=''){
    const map={INVALID_ACTIVATION_CODE:'啟用碼錯誤，請重新確認。',ENROLLMENT_NOT_FOUND:`查無此班級與學號（送出：${className}／${studentId}），請聯絡教師。`,ENROLLMENT_ALREADY_CLAIMED:'此帳號已綁定其他裝置，請由教師重設啟用碼。',ACTIVATION_CODE_EXPIRED:'啟用碼已過期，請向教師索取新碼。',USER_ALREADY_ENROLLED:'此瀏覽器目前綁定其他學生，請先登出後再試。'};
    return Object.entries(map).find(([key])=>message.includes(key))?.[1]||'雲端身分驗證失敗，請稍後再試或聯絡教師。';
  }

  function showError(message){
    const box=document.getElementById('studentAuthError');
    if(box){box.textContent=message;box.classList.add('show')}
  }

  async function handleStudentLogin(event){
    event.preventDefault();
    const className=document.getElementById('cls').value.normalize('NFKC').trim();
    const studentId=document.getElementById('sid').value.normalize('NFKC').trim().toUpperCase();
    const code=document.getElementById('activationCode')?.value.trim()||'';
    if(!className||!/^[A-Z][0-9]{8}$/.test(studentId)) return showError('請選擇班級，並輸入正確的學號。');
    const submit=event.currentTarget.querySelector('button.primary');
    submit.disabled=true;submit.textContent='驗證中…';
    try{
      let {data:{session}}=await client.auth.getSession();
      if(session&&!session.user?.is_anonymous){
        await client.auth.signOut();
        session=null;
      }
      if(!session){
        const signed=await client.auth.signInAnonymously();
        if(signed.error) throw signed.error;
        session=signed.data.session;
      }
      const own=await client.from('enrollments').select('id,student_number,classes(name)').eq('user_id',session.user.id).eq('active',true).maybeSingle();
      const linked=own.data&&own.data.student_number===studentId&&own.data.classes?.name===className;
      if(!linked){
        let activated;
        if(passwordless){
          activated=await client.rpc('claim_enrollment_without_code',{requested_class_name:className,requested_student_number:studentId});
        }else{
          if(!code) throw new Error('INVALID_ACTIVATION_CODE');
          activated=await client.rpc('activate_enrollment_by_class_name',{requested_class_name:className,requested_student_number:studentId,activation_code:code});
          // 010 尚未執行時暫時相容舊版函式，避免部署期間完全無法登入。
          if(activated.error?.code==='PGRST202'){
            activated=await client.rpc('activate_enrollment',{requested_class_id:await classId(className),requested_student_number:studentId,activation_code:code});
          }
        }
        if(activated.error) throw activated.error;
      }
      S.student={className,id:studentId};
      localStorage.setItem('econStudent',JSON.stringify(S.student));
      localStorage.setItem('econCloudLinked','true');
      window.render('home');
    }catch(error){
      showError(errorMessage(error.message||'',className,studentId));
      submit.disabled=false;submit.textContent='進入 AI 助教';
    }
  }

  async function classId(className){
    const {data,error}=await client.from('classes').select('id').eq('name',className).eq('active',true).single();
    if(error) throw error;
    return data.id;
  }

  window.login=function(){originalLogin();configureStudentLogin()};

  document.addEventListener('click',async event=>{
    const logoutButton=event.target.closest?.('#logout');
    if(!logoutButton) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    await client.auth.signOut();
    localStorage.removeItem('econStudent');
    localStorage.removeItem('econCloudLinked');
    S.student=null;
    window.login();
  },true);

  async function bootstrap(){
    const {data}=await client.auth.getSession();
    const linked=localStorage.getItem('econCloudLinked')==='true';
    const anonymousSession=Boolean(data.session?.user?.is_anonymous);
    let cloudIdentityMatches=false;
    if(linked&&anonymousSession&&S.student){
      const own=await client.from('enrollments').select('student_number,classes(name)').eq('user_id',data.session.user.id).eq('active',true).maybeSingle();
      cloudIdentityMatches=Boolean(own.data&&own.data.student_number===S.student.id&&own.data.classes?.name===S.student.className);
    }
    if(!linked||!anonymousSession||!cloudIdentityMatches){
      // 只移除舊版快速登入狀態；測驗與諮詢歷程仍保留在瀏覽器。
      localStorage.removeItem('econStudent');
      localStorage.removeItem('econCloudLinked');
      S.student=null;
      window.login();
      return;
    }
    configureStudentLogin();
  }
  bootstrap().catch(()=>{S.student=null;window.login()});
})();
