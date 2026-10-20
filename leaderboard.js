(function(){
  'use strict';
  if(!window.ECON_SUPABASE?.leaderboardEnabled||!window.supabase) return;
  const client=window.supabase.createClient(window.ECON_SUPABASE.url,window.ECON_SUPABASE.publishableKey,{auth:{persistSession:true,autoRefreshToken:true}});
  const originalShell=window.shell,originalRender=window.render,originalHome=window.home;
  let boardType='all',boardScope='weekly',boardWeek=null;

  window.shell=function(content){
    return originalShell(content).replace('<button data-v="history"','<button data-v="leaderboard" class="'+(S.view==='leaderboard'?'on':'')+'">★　學習排行榜</button><button data-v="history"');
  };
  window.home=function(){
    return originalHome().replace('</div><div class="stats">','<article class="card tile" data-v="leaderboard"><div class="ico">★</div><h3>學習挑戰排行榜</h3><p>查看每週與學期累積積分排名。</p><span class="go">查看排行榜 →</span></article></div><div class="stats">');
  };
  window.render=function(view){
    if(view!=='leaderboard') return originalRender(view);
    S.view='leaderboard';app.innerHTML=shell(boardPage());nav();bindBoard();loadBoard();
  };

  function boardPage(){return `<p class="kicker">學習挑戰排行榜</p><h1 class="title">一起累積每一次認真學習</h1><div class="chips board-types"><button class="chip" data-board="trade_logistics">國貿＋流通</button><button class="chip" data-board="fashion">時尚班級</button><button class="chip" data-board="all">全部班級</button></div><div class="chips board-scopes"><button class="chip" data-scope="weekly">本週積分</button><button class="chip" data-scope="semester">學期累積</button></div><section id="myRank" class="card review">正在讀取個人排名…</section><section class="card teacher-section" style="margin-top:16px"><h2>前 10 名</h2><div id="boardTable" class="teacher-empty">正在讀取排行榜…</div></section><section class="card teacher-section" style="margin-top:16px"><h2>排行榜顯示設定</h2><label for="boardNickname">暱稱（最多 20 個字元）</label><input id="boardNickname" class="control" maxlength="20" placeholder="未設定時會遮罩顯示學號"><label style="display:flex;gap:10px;align-items:center"><input id="boardPublic" type="checkbox" checked>公開顯示我的排名</label><button id="saveBoardProfile" class="btn primary">儲存設定</button><span id="boardSaveStatus" style="margin-left:10px;color:#64748b"></span></section><div class="note">選擇不公開後，你仍可看到自己的個人排名；前十名不會顯示你的資料，教師仍可依教學授權查看紀錄。</div>`}

  function bindBoard(){
    document.querySelectorAll('[data-board]').forEach(x=>{if(x.dataset.board===boardType)x.classList.add('on');x.onclick=()=>{boardType=x.dataset.board;render('leaderboard')}});
    document.querySelectorAll('[data-scope]').forEach(x=>{if(x.dataset.scope===boardScope)x.classList.add('on');x.onclick=()=>{boardScope=x.dataset.scope;render('leaderboard')}});
    document.getElementById('saveBoardProfile').onclick=saveProfile;
  }
  async function loadBoard(){
    const [{data,error},{data:{user}}]=await Promise.all([
      client.rpc('get_learning_leaderboard',{requested_type:boardType,requested_scope:boardScope,requested_week_start:boardWeek}),
      client.auth.getUser()
    ]);
    if(error){document.getElementById('boardTable').innerHTML=`<div class="note">排行榜讀取失敗：${esc(error.message)}</div>`;return}
    const top=data?.top||[],me=data?.me;
    document.getElementById('myRank').innerHTML=me?`<b>我的排名：第 ${me.rank} 名</b><p>${esc(me.className)} · ${esc(me.nickname)} · ${me.points} 分${me.public?'':' · 未公開'}</p>`:'<b>目前尚未取得積分</b><p>完成測驗或有效 AI 諮詢後，就會出現個人排名。</p>';
    document.getElementById('boardTable').innerHTML=top.length?`<div class="tableWrap"><table class="table"><thead><tr><th>排名</th><th>班級</th><th>暱稱</th><th>積分</th></tr></thead><tbody>${top.map(x=>`<tr><td><b>${x.rank}</b></td><td>${esc(x.className)}</td><td>${esc(x.nickname)}</td><td><b>${x.points}</b></td></tr>`).join('')}</tbody></table></div>`:'<div class="teacher-empty">目前尚無排行榜資料。</div>';
    if(user){const profile=await client.from('profiles').select('nickname,leaderboard_public').eq('user_id',user.id).maybeSingle();if(profile.data){document.getElementById('boardNickname').value=profile.data.nickname||'';document.getElementById('boardPublic').checked=profile.data.leaderboard_public!==false}}
  }
  async function saveProfile(){
    const saveButton=document.getElementById('saveBoardProfile'),status=document.getElementById('boardSaveStatus');
    saveButton.disabled=true;status.textContent='儲存中…';
    const {error}=await client.rpc('update_my_leaderboard_profile',{requested_nickname:document.getElementById('boardNickname').value,requested_public:document.getElementById('boardPublic').checked});
    saveButton.disabled=false;status.textContent=error?'儲存失敗，請稍後再試。':'已儲存';if(!error)loadBoard();
  }
})();
