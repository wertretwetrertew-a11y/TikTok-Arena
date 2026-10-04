const socket=io();
const canvas=document.getElementById("arena");
const ctx=canvas.getContext("2d");
const fightersEl=document.getElementById("fighters");
const timerEl=document.getElementById("timer");
const connectionEl=document.getElementById("connection");
const winnerEl=document.getElementById("winner");
const fighters=new Map();
const colors=["#6f8cff","#ff668f","#64dfb0","#ffc857","#bd7cff","#55c7ff","#ff8c52","#c5e86c"];
let running=false;
let timeLeft=60;
let roundStartedAt=0;
let lastFrame=performance.now();
let seq=0;

function makeFighter(user,hp,source,power=1,giftName=""){
  const id=user.uniqueId||user.nickname||("viewer-"+(++seq));
  if(fighters.has(id)){
    const f=fighters.get(id);
    if(source==="gift"){
      const bonus=Math.max(0,hp-5);
      f.maxHp+=bonus;
      f.hp=Math.min(f.maxHp,f.hp+bonus);
      f.power+=Math.max(0,power-1)*0.35;
      if(giftName) f.giftName=giftName;
    }
    return f;
  }
  const f={
    id:id,
    name:user.nickname||id,
    avatar:user.profilePictureUrl||"",
    avatarImage:null,
    avatarLoaded:false,
    maxHp:hp,
    hp:hp,
    kills:0,
    source:source,
    giftName:giftName||"",
    power:power,
    x:85+Math.random()*730,
    y:60+Math.random()*500,
    vx:(Math.random()-0.5)*70,
    vy:(Math.random()-0.5)*70,
    color:colors[fighters.size%colors.length],
    hitCooldown:0,
    alive:true
  };
  fighters.set(id,f);
  if(f.avatar){
    const img=new Image();
    img.onload=function(){ f.avatarImage=img; f.avatarLoaded=true; };
    img.onerror=function(){ f.avatarLoaded=false; };
    img.src=f.avatar;
  }
  renderLeaderboard();
  return f;
}

function giftHp(value){
  const v=Math.max(1,Number(value||1));
  return Math.max(5,Math.min(35,Math.round(5+Math.sqrt(v)*2)));
}

function handleGift(d){
  makeFighter(d.user,giftHp(d.giftValue),"gift",Math.max(1,Math.sqrt(Math.max(1,d.giftValue))),d.giftName||"Подарок");
}

function handleLike(d){
  if(Number(d.likeCount||0)>=100){
    makeFighter(d.user,3,"likes");
  }
}

function handleSubscribe(d){
  makeFighter(d.user,4,"subscribe");
}

socket.on("tiktok_connected",function(){
  connectionEl.textContent="● TikTok подключён";
  connectionEl.style.color="#8ff0ad";
});

socket.on("tiktok_disconnected",function(){
  connectionEl.textContent="TikTok отключён";
});

socket.on("tiktok_error",function(d){
  connectionEl.textContent="Ошибка: "+d.message;
  connectionEl.style.color="#ff718d";
});

socket.on("tiktok_gift",handleGift);
socket.on("tiktok_like",handleLike);
socket.on("tiktok_subscribe",handleSubscribe);

document.getElementById("connect").onclick=function(){
  const username=document.getElementById("username").value.trim();
  if(username) socket.emit("join-room",{username:username});
};

document.getElementById("start").onclick=startRound;

document.getElementById("demoGift").onclick=function(){
  const n=Math.floor(Math.random()*999);
  handleGift({
    user:{uniqueId:"demo-"+n,nickname:"Viewer_"+n},
    giftValue:1,
    giftName:"Rose"
  });
};

document.getElementById("demoLike").onclick=function(){
  const n=Math.floor(Math.random()*999);
  handleLike({
    user:{uniqueId:"like-"+n,nickname:"Like_"+n},
    likeCount:100
  });
};

document.getElementById("demoSub").onclick=function(){
  const n=Math.floor(Math.random()*999);
  handleSubscribe({
    user:{uniqueId:"sub-"+n,nickname:"Sub_"+n}
  });
};

function startRound(){
  if(fighters.size===0){
    makeFighter({uniqueId:"demo-a",nickname:"Player_A"},5,"gift");
    makeFighter({uniqueId:"demo-b",nickname:"Player_B"},5,"gift");
  }
  fighters.forEach(function(f){
    f.hp=f.maxHp;
    f.alive=true;
    f.kills=0;
    f.x=85+Math.random()*730;
    f.y=60+Math.random()*500;
    f.vx=(Math.random()-0.5)*70;
    f.vy=(Math.random()-0.5)*70;
  });
  running=true;
  timeLeft=60;
  roundStartedAt=performance.now();
  winnerEl.classList.add("hidden");
}

function finishRound(){
  running=false;
  const alive=Array.from(fighters.values()).filter(function(f){return f.alive;});
  const sorted=Array.from(fighters.values()).sort(function(a,b){
    return b.kills-a.kills||b.hp-a.hp;
  });
  const winner=alive.length===1?alive[0]:sorted[0];
  if(winner){
    winnerEl.textContent="🏆 ПОБЕДИТЕЛЬ — "+winner.name+" — "+winner.kills+" киллов";
  }else{
    winnerEl.textContent="🏆 Нет победителя";
  }
  winnerEl.classList.remove("hidden");
}

function update(dt){
  if(!running) return;
  timeLeft=Math.max(0,60-(performance.now()-roundStartedAt)/1000);
  timerEl.textContent=Math.ceil(timeLeft);

  fighters.forEach(function(f){
    if(!f.alive) return;
    f.hitCooldown-=dt;
    f.x+=f.vx*dt;
    f.y+=f.vy*dt;
    if(f.x<85||f.x>815) f.vx*=-1;
    if(f.y<60||f.y>560) f.vy*=-1;
    f.x=Math.max(85,Math.min(815,f.x));
    f.y=Math.max(60,Math.min(560,f.y));
  });

  const alive=Array.from(fighters.values()).filter(function(f){return f.alive;});
  for(let i=0;i<alive.length;i++){
    for(let j=i+1;j<alive.length;j++){
      const a=alive[i];
      const b=alive[j];
      const dx=b.x-a.x;
      const dy=b.y-a.y;
      const d=Math.hypot(dx,dy);
      if(d<46){
        if(d>0){
          const nx=dx/d;
          const ny=dy/d;
          a.x-=nx*0.8;
          a.y-=ny*0.8;
          b.x+=nx*0.8;
          b.y+=ny*0.8;
        }
        if(a.hitCooldown<=0){
          b.hp-=Math.max(0.5,a.power);
          a.hitCooldown=0.55;
          if(b.hp<=0){
            b.hp=0;
            b.alive=false;
            a.kills++;
          }
        }
        if(b.alive&&b.hitCooldown<=0){
          a.hp-=Math.max(0.5,b.power);
          b.hitCooldown=0.55;
          if(a.hp<=0){
            a.hp=0;
            a.alive=false;
            b.kills++;
          }
        }
      }
    }
  }

  const living=Array.from(fighters.values()).filter(function(f){return f.alive;}).length;
  if(timeLeft<=0||living<=1) finishRound();
  renderLeaderboard();
}

function draw(){
  ctx.clearRect(0,0,900,620);
  const g=ctx.createRadialGradient(450,300,20,450,300,500);
  g.addColorStop(0,"#17244b");
  g.addColorStop(1,"#050817");
  ctx.fillStyle=g;
  ctx.fillRect(0,0,900,620);

  for(let i=0;i<90;i++){
    ctx.fillStyle="rgba(255,255,255,.35)";
    ctx.fillRect((i*97)%900,(i*53)%620,1.5,1.5);
  }

  fighters.forEach(function(f){
    if(!f.alive) return;
    ctx.save();
    ctx.globalAlpha=f.alive?1:0.22;
    ctx.beginPath();
    ctx.arc(f.x,f.y,22,0,Math.PI*2);
    ctx.fillStyle=f.color;
    ctx.fill();
    ctx.save();
    ctx.beginPath();
    ctx.arc(f.x,f.y,19,0,Math.PI*2);
    ctx.clip();
    if(f.avatarLoaded && f.avatarImage){
      ctx.drawImage(f.avatarImage,f.x-19,f.y-19,38,38);
    }else{
      ctx.fillStyle=f.color;
      ctx.fillRect(f.x-19,f.y-19,38,38);
      ctx.fillStyle="#fff";
      ctx.font="bold 16px system-ui";
      ctx.textAlign="center";
      ctx.textBaseline="middle";
      ctx.fillText((f.name||"?").charAt(0).toUpperCase(),f.x,f.y);
    }
    ctx.restore();
    ctx.strokeStyle="#fff";
    ctx.lineWidth=2;
    ctx.stroke();
    ctx.globalAlpha=0.8;
    ctx.fillStyle="#111";
    ctx.fillRect(f.x-22,f.y-31,44,5);
    ctx.fillStyle="#6ff28c";
    ctx.fillRect(f.x-22,f.y-31,44*(f.hp/Math.max(1,f.maxHp)),5);
    ctx.globalAlpha=1;
    ctx.fillStyle="#fff";
    ctx.font="bold 12px system-ui";
    ctx.textAlign="center";
    ctx.fillText(f.name.slice(0,16),f.x,f.y+38);
    ctx.restore();
  });
}

function escapeHtml(value){
  return String(value)
    .split("&").join("&amp;")
    .split("<").join("&lt;")
    .split(">").join("&gt;")
    .split('"').join("&quot;")
    .split("'").join("&#039;");
}

function renderLeaderboard(){
  fightersEl.innerHTML=Array.from(fighters.values())
    .sort(function(a,b){return b.kills-a.kills||b.hp-a.hp;})
    .map(function(f){
      const status=f.alive?'':' · Погиб';
      const hp=f.alive?(Math.ceil(f.hp)+'/'+f.maxHp):'0 HP';
      const source=f.source==="gift"?("🎁 "+escapeHtml(f.giftName||"Подарок")):f.source==="likes"?"❤️ 100 лайков":"⭐ Подписка";
      return '<div class="fighter"><img class="avatar" src="'+escapeHtml(f.avatar)+'" alt=""><div><div class="name">'+escapeHtml(f.name)+'</div><div class="meta">⚔ '+f.kills+' киллов · '+source+status+'</div></div><div class="hp">'+hp+'</div></div>';
    }).join("");
}

function frame(now){
  const dt=Math.min(0.05,(now-lastFrame)/1000);
  lastFrame=now;
  update(dt);
  draw();
  requestAnimationFrame(frame);
}

renderLeaderboard();
fetch("/api/health").then(function(r){return r.json();}).then(function(d){var el=document.getElementById("buildVersion");if(el) el.textContent=d.version||"dev";}).catch(function(){});
requestAnimationFrame(frame);
