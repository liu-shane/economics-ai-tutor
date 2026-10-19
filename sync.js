const BACKEND_URL='https://script.google.com/macros/s/AKfycbzKB-5qRrxHpRsAna57vkVYiWCYpzdQNxjWWJYe3F8lXGNi3vXqy4kBnpoc_8YLq7yA7g/exec';
const CLIENT_ID=localStorage.getItem('econClientId')||(crypto.randomUUID?crypto.randomUUID():`${Date.now()}-${Math.random()}`);localStorage.setItem('econClientId',CLIENT_ID);
function syncRecord(action,payload){if(!BACKEND_URL)return;fetch(BACKEND_URL,{method:'POST',mode:'no-cors',headers:{'Content-Type':'text/plain;charset=utf-8'},body:JSON.stringify({action,payload})}).catch(()=>{})}
document.addEventListener('submit',e=>{if(e.target?.id==='login')syncRecord('login',{className:document.getElementById('cls')?.value||'',studentId:document.getElementById('sid')?.value.trim()||'',clientId:CLIENT_ID})},true);
