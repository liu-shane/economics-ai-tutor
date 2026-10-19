(function(){
  'use strict';
  if(!window.ECON_SUPABASE?.cloudLearningSyncEnabled||!window.supabase) return;
  const client=window.supabase.createClient(window.ECON_SUPABASE.url,window.ECON_SUPABASE.publishableKey,{auth:{persistSession:true,autoRefreshToken:true}});
  const previousSync=window.syncRecord;
  const pendingConsults=new Map();

  async function requireLinkedStudent(){
    const {data,error}=await client.auth.getSession();
    if(error||!data.session?.user?.is_anonymous||localStorage.getItem('econCloudLinked')!=='true') throw new Error('STUDENT_CLOUD_SESSION_REQUIRED');
  }

  async function send(action,payload){
    await requireLinkedStudent();
    if(action==='quiz'){
      const {error}=await client.rpc('record_student_quiz',{payload});
      if(error) throw error;
    }else if(action==='consult'){
      const request=client.rpc('record_student_consultation',{payload}).then(({error})=>{if(error)throw error});
      pendingConsults.set(payload.consultId,request);
      await request;
    }else if(action==='consult_check'){
      await pendingConsults.get(payload.consultId);
      const {error}=await client.rpc('record_student_consultation_check',{payload});
      if(error) throw error;
    }
  }

  window.syncRecord=function(action,payload){
    if(typeof previousSync==='function') previousSync(action,payload);
    if(!['quiz','consult','consult_check'].includes(action)) return;
    send(action,payload).catch(error=>console.warn('Supabase learning sync failed:',error.message));
  };
})();
