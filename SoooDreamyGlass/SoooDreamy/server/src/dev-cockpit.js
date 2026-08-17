export const DEV_COCKPIT_HTML = String.raw`<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>SoooDreamy Dev Cockpit</title>
  <style>
    :root { color-scheme: dark; font: 15px/1.45 system-ui; background:#0d0920; color:#f7f2ff }
    * { box-sizing:border-box }
    body { margin:0; padding:24px; background:radial-gradient(circle at top,#31205f,#0d0920 55%) fixed }
    header { max-width:1100px; margin:auto auto 18px }
    h1 { margin:0; color:#f59ac8 } .hint { color:#bdb2d8 }
    main { max-width:1100px; margin:auto; display:grid; grid-template-columns:1fr 1fr; gap:16px }
    section { border:1px solid #ffffff24; border-radius:22px; padding:18px; background:#ffffff0d; backdrop-filter:blur(20px) }
    input,button,select { width:100%; min-height:44px; margin:5px 0; border-radius:12px; border:1px solid #ffffff26; padding:10px 12px }
    input,select { background:#120d27; color:inherit } button { background:#be4e8c; color:white; font-weight:700; cursor:pointer }
    button.alt { background:#563b91 } pre { min-height:180px; max-height:340px; overflow:auto; white-space:pre-wrap; color:#c9f8e3; background:#070512; padding:12px; border-radius:12px }
    .row { display:grid; grid-template-columns:1fr 1fr; gap:8px }
    @media(max-width:760px){ main{grid-template-columns:1fr} }
  </style>
</head>
<body>
<header>
  <h1>💜 SoooDreamy Dev Cockpit</h1>
  <div class="hint">Zwei Partner · two partners — nur verfügbar mit <code>SOOODREAMY_DEV_COCKPIT=1</code>.</div>
</header>
<main>
  <section id="a"><h2>🦊 Mia</h2><div class="panel"></div><pre></pre></section>
  <section id="b"><h2>🐻 Ben</h2><div class="panel"></div><pre></pre></section>
</main>
<script>
const state={a:{name:'Mia',avatar:'🦊'},b:{name:'Ben',avatar:'🐻'}};
const log=(side,value)=>{const out=document.querySelector('#'+side+' pre');out.textContent=JSON.stringify(value,null,2)+'\\n'+out.textContent};
async function call(side,path,method='GET',body){
  const headers={'content-type':'application/json'}; if(state[side].token) headers.authorization='Bearer '+state[side].token;
  const res=await fetch(path,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});
  const value=await res.json().catch(()=>({status:res.status})); log(side,{status:res.status,path,value}); return {res,value};
}
async function create(){
  const {value}=await call('a','/api/couples','POST',{name:'Mia',avatar:'🦊',color:'#F472B6'});
  state.a.token=value.token; state.code=value.couple?.code; render();
}
async function join(){
  const {value}=await call('b','/api/couples/join','POST',{code:state.code,name:'Ben',avatar:'🐻',color:'#60A5FA'});
  state.b.token=value.token; render();
}
async function touch(side){await call(side,'/api/touches','POST',{type:'heartbeat'})}
async function daily(side){
  const key=new Date().toISOString().slice(0,10);
  await call(side,'/api/daily/'+key,'POST',{questionId:42,text:'Cockpit '+state[side].name+' 💜'});
}
async function game(side){
  if(!state.game){
    const {value}=await call(side,'/api/games','POST',{type:'connectfour',payload:{}});
    state.game=value.game?.id;
  } else {
    await call(side,'/api/games/'+state.game+'/join','POST',{});
    await call(side,'/api/games/'+state.game+'/move','POST',{data:{kind:'drop',column:0}});
  }
}
function renderSide(side){
  const paired=!!state[side].token;
  document.querySelector('#'+side+' .panel').innerHTML=
    (side==='a'?'<button onclick="create()">Paar erstellen · Create couple</button>':'<button onclick="join()" '+(!state.code?'disabled':'')+'>Mit '+(state.code||'Code')+' beitreten · Join</button>')+
    '<div class="row"><button class="alt" onclick="touch(\\''+side+'\\')" '+(!paired?'disabled':'')+'>💓 Touch</button>'+
    '<button class="alt" onclick="daily(\\''+side+'\\')" '+(!paired?'disabled':'')+'>❓ Daily</button></div>'+
    '<button onclick="game(\\''+side+'\\')" '+(!paired?'disabled':'')+'>🎮 Spiel erstellen/beitreten · game</button>';
}
function render(){renderSide('a');renderSide('b')} render();
</script>
</body></html>`;
