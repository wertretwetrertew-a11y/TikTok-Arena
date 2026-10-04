const socket=io();
const canvas=document.getElementById("arena"),ctx=canvas.getContext("2d");
const fightersEl=document.getElementById("fighters"),timerEl=document.getElementById("timer"),connectionEl=document.getElementById("connection"),winnerEl=document.getElementById("winner");
const fighters=new Map();
const colors=["#6f8cff","#ff668f","#64dfb0","#ffc857","#bd7cff","#55c7ff","#ff8c52","#c5e86c"];
let running=false,timeLeft=60,roundStartedAt=0,lastFrame=performance.now(),seq=0;

function makeFighter(user,hp,source,power=1){
  const id=user.uniqueId||user.nickname||("viewer-"+(++seq));
  if(fighters.has(id)){
    const f=fighters.get(id);
    if(source==="gift"){const bonus=Math.max(0,hp-5);f.maxHp+=bonus;f.hp=Math.min(f.maxHp,f.hp+bonus);f.power+=Math.max(0,power-1)*.35;}
    return f;
  }
  const f={id,name:user.nickname||id,avatar:user.profilePictureUrl||"",maxHp:hp,hp,kills:0,source,power,x:70+Math.random()*760,y:70+Math.random()*480,vx:(Math.random()-.5)*70,vy:(Math.random()-.5)*70,color:colors[fighters.size%colors.length],hitCooldown:0,alive:true};
  fighters.set(id,f);renderLeaderboard();return f;
}
function giftHp(value){const v=Math.max(1,Number(value||1));return Math.max(5,Math.min(35,Math.round(5+Math.sqrt(v)*2)));}
function handleGift(d){makeFighter(d.user,giftHp(d.giftValue),"gift",Math.max(1,Math.sqrt(Math.max(1,d.giftValue))));}
function handleLike(d){if(Number(d.likeCount||0)>=100)makeFighter(d.user,3,"likes");}
function handleSubscribe(d){makeFighter(d.user,4,"subscribe");}

socket.on("tiktok_connected",()=>{connectionEl.textContent="● TikTok подключён";connectionEl.style.color="#8ff0ad";});
socket.on("tiktok_disconnected",()=>connectionEl.textContent="TikTok отключён");
socket.on("tiktok_error",d=>{connectionEl.textContent="Ошибка: "+d.message;connectionEl.style.color="#ff718d";});
socket.on("tiktok_gift",handleGift);socket.on("tiktok_like",handleLike);socket.on("tiktok_subscribe",handleSubscribe);

document.getElementById("connect").onclick=()=>{const username=document.getElementById("username").value.trim();if(username)socket.emit("join-room",{username});};
document.getElementById("start").onclick=startRound;
document.getElementById("demoGift").onclick=()=>{const n=Math.floor(Math.random()*999);handleGift({user:{uniqueId:"demo-"+n,nickname:"Viewer_"+n},giftValue:1,giftName:"Rose"});};
document.getElementById("demoLike").onclick=()=>{const n=Math.floor(Math.random()*999);handleLike({user:{uniqueId:"like-"+n,nickname:"Like_"+n},likeCount:100});};
document.getElementById("demoSub").onclick=()=>{const n=Math.floor(Math.random()*999);handleSubscribe({user:{uniqueId:"sub-"+n,nickname:"Sub_"+n}});};

function startRound(){
  if(fighters.size===0){makeFighter({uniqueId:"demo-a",nickname:"Player_A"},5,"gift");makeFighter({uniqueId:"demo-b",nickname:"Player_B"},5,"gift");}
  for(const f of fighters.values()){f.hp=f.maxHp;f.alive=true;f.kills=0;f.x=70+Math.random()*760;f.y=70+Math.random()*480;f.vx=(Math.random()-.5)*70;f.vy=(Math.random()-.5)*70;}
  running=true;timeLeft=60;roundStartedAt=performance.now();winnerEl.classList.add("hidden");
}
function finishRound(){
  running=false;
  const alive=[...fighters.values()].filter(f=>f.alive);
  const sorted=[...fighters.values()].sort((a,b)=>b.kills-a.kills||b.hp-a.hp);
  const winner=alive.length===1?alive[0]:sorted[0];
  winnerEl.innerHTML=winner?"🏆 ПОБЕДИТЕЛЬ<br><small>"+escapeHtml(winner.name)+" — "+winner.kills+" киллов</small>":"🏆 Нет победителя";
  winnerEl.classList.remove("hidden");
}
function update(dt){
  if(!running)return;
  timeLeft=Math.max(0,60-(performance.now()-roundStartedAt)/1000);timerEl.textContent=Math.ceil(timeLeft);
  for(const f of fighters.values())if(f.alive){f.hitCooldown-=dt;f.x+=f.vx*dt;f.y+=f.vy*dt;if(f.x<35||f.x>865)f.vx*=-1;if(f.y<35||f.y>585)f.vy*=-1;f.x=Math.max(35,Math.min(865,f.x));f.y=Math.max(35,Math.min(585,f.y));}
  const alive=[...fighters.values()].filter(f=>f.alive);
  for(let i=0;i<alive.length;i++)for(let j=i+1;j<alive.length;j++){
    const a=alive[i],b=alive[j],dx=b.x-a.x,dy=b.y-a.y,d=Math.hypot(dx,dy);
    if(d<46){
      if(d>0){const nx=dx/d,ny=dy/d;a.x-=nx*.8;a.y-=ny*.8;b.x+=nx*.8;b.y+=ny*.8;}
      if(a.hitCooldown<=0){b.hp-=Math.max(.5,a.power);a.hitCooldown=.55;if(b.hp<=0){b.hp=0;b.alive=false;a.kills++;}}
      if(b.alive&&b.hitCooldown<=0){a.hp-=Math.max(.5,b.power);b.hitCooldown=.55;if(a.hp<=0){a.hp=0;a.alive=false;b.kills++;}}
    }
  }
  if(timeLeft<=0||[...fighters.values()].filter(f=>f.alive).length<=1)finishRound();
  renderLeaderboard();
}
function draw(){
  ctx.clearRect(0,0,900,620);
  const g=ctx.createRadialGradient(450,300,20,450,300,500);g.addColorStop(0,"#17244b");g.addColorStop(1,"#050817");ctx.fillStyle=g;ctx.fillRect(0,0,900,620);
  for(let i=0;i<90;i++){ctx.fillStyle="rgba(255,255,255,.35)";ctx.fillRect((i*97)%900,(i*53)%620,1.5,1.5);}
  for(const f of fighters.values()){
    ctx.save();ctx.globalAlpha=f.alive?1:.22;ctx.beginPath();ctx.arc(f.x,f.y,20,0,Math.PI*2);ctx.fillStyle=f.color;ctx.fill();ctx.strokeStyle="#fff";ctx.stroke();ctx.globalAlpha=.8;ctx.fillStyle="#111";ctx.fillRect(f.x-22,f.y-31,44,5);ctx.fillStyle="#6ff28c";ctx.fillRect(f.x-22,f.y-31,44*(f.hp/Math.max(1,f.maxHp)),5);ctx.globalAlpha=1;ctx.fillStyle="#fff";ctx.font="bold 12px system-ui";ctx.textAlign="center";ctx.fillText(f.name.slice(0,16),f.x,f.y+38);ctx.restore();
  }
}
function renderLeaderboard(){fightersEl.innerHTML=[...fighters.values()].sort((a,b)=>b.kills-a.kills||b.hp-a.hp).map(f=>'<div class="fighter"><img class="avatar" src="'+escapeAttr(f.avatar)+'" alt=""><div><div class="name">'+escapeHtml(f.name)+'</div><div class="meta">⚔ '+f.kills+' киллов · '+f.source+'</div></div><div class="hp">'+Math.ceil(f.hp)+'/'+f.maxHp+'</div></div>').join("");}
function escapeHtml(v){return String(v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"}[c]));}
function escapeAttr(v){return escapeHtml(v).replace(/\`/g,"");}
function frame(now){const dt=Math.min(.05,(now-lastFrame)/1000);lastFrame=now;update(dt);draw();requestAnimationFrame(frame);}
renderLeaderboard();requestAnimationFrame(frame);
