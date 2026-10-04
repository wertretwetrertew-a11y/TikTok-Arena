import express from "express";
import http from "http";
import { Server } from "socket.io";
import { TikTokLiveConnection, WebcastEvent } from "tiktok-live-connector";
import path from "path";
import { fileURLToPath } from "url";
import fs from "fs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const server = http.createServer(app);
const io = new Server(server);
const PORT = process.env.PORT || 3000;
const versionFile = path.join(__dirname, ".tiktok-arena-version");
const buildVersion = process.env.BUILD_VERSION || (fs.existsSync(versionFile) ? fs.readFileSync(versionFile,"utf8").trim().slice(0,7) : "dev");
const connections = new Map();
const likeBuckets = new Map();
const subscribedUsers = new Set();
const likeTotals = new Map();
const likeUsers = new Map();

app.use((req,res,next)=>{
  res.setHeader("Cache-Control","no-store, no-cache, must-revalidate, proxy-revalidate");
  res.setHeader("Pragma","no-cache");
  res.setHeader("Expires","0");
  next();
});
app.use(express.static(path.join(__dirname, "public"), { etag: false, lastModified: false, maxAge: 0 }));
app.get("/api/health", (_req,res) => res.json({ok:true,game:"TikTok Arena",version:buildVersion,serverTime:Date.now()}));

app.get("/api/avatar", async (req,res) => {
  try {
    const rawUrl=String(req.query.url||"");
    const url=new URL(rawUrl);
    const host=url.hostname.toLowerCase();
    if(!(host==="tiktokcdn.com" || host.endsWith(".tiktokcdn.com"))) return res.status(400).end();
    const response=await fetch(url,{headers:{"User-Agent":"Mozilla/5.0 TikTok Arena"}});
    if(!response.ok) return res.status(response.status).end();
    const contentType=response.headers.get("content-type")||"image/jpeg";
    if(!contentType.startsWith("image/")) return res.status(415).end();
    const buffer=Buffer.from(await response.arrayBuffer());
    res.setHeader("Content-Type",contentType);
    res.setHeader("Cache-Control","public, max-age=3600");
    res.send(buffer);
  } catch {
    res.status(400).end();
  }
});

function emitRoom(username,event,payload){ io.to(username).emit(event,payload); }
\nfunction emitLikeLeaderboard(username){
  const rows=[];
  const prefix=username+":";
  likeTotals.forEach((total,bucketKey)=>{
    if(!bucketKey.startsWith(prefix)) return;
    const uniqueId=bucketKey.slice(prefix.length);
    const profile=likeUsers.get(bucketKey)||{};
    rows.push({
      uniqueId,
      nickname:profile.nickname||uniqueId,
      profilePictureUrl:profile.profilePictureUrl||"",
      likes:total
    });
  });
  rows.sort((a,b)=>b.likes-a.likes||a.nickname.localeCompare(b.nickname));
  emitRoom(username,"tiktok_like_leaderboard",{
    entries:rows.slice(0,10),
    timestamp:Date.now()
  });
}


async function connectTikTok(username){
  const key=String(username).replace(/^@/,"").trim().toLowerCase();
  if(!key) throw new Error("TikTok username is required");
  if(connections.has(key)) return;
  const connection=new TikTokLiveConnection(key,{processInitialData:false,enableExtendedGiftInfo:false});
  const processedGiftEvents=new Set();
  connection.on(WebcastEvent.GIFT,data=>{
    // TikTok can emit several messages while a streakable gift is being sent.
    // We create exactly one fighter: only process the final streak event.
    const giftType=Number(data.giftType ?? data.giftDetails?.giftType ?? data.gift?.giftType ?? 0);
    const repeatEnd=Boolean(data.repeatEnd ?? data.gift?.repeatEnd ?? false);
    if(giftType===1 && !repeatEnd) return;

    const user=data.user||{};
    const uniqueId=user.uniqueId||data.uniqueId||user.userId||data.userId;
    const nickname=user.nickname||data.nickname||uniqueId||"Зритель";
    const profilePictureUrl=user.profilePictureUrl||data.profilePictureUrl||user.userDetails?.profilePictureUrls?.[0]||"";
    const giftId=data.giftId ?? data.giftDetails?.giftId ?? data.gift?.giftId ?? data.gift?.gift_id;
    const repeatCount=Math.max(1,Number(data.repeatCount ?? data.gift?.repeatCount ?? data.gift?.repeat_count ?? 1));
    const eventId=data.msgId||data.messageId;
    if(eventId){
      if(processedGiftEvents.has(eventId)) return;
      processedGiftEvents.add(eventId);
      if(processedGiftEvents.size>500) processedGiftEvents.delete(processedGiftEvents.values().next().value);
    }

    const giftName=data.giftName||data.giftDetails?.giftName||data.gift?.name||"Подарок";
    const diamondCount=Number(data.diamondCount ?? data.giftDetails?.diamondCount ?? data.gift?.diamondCount ?? 0);
    emitRoom(key,"tiktok_gift",{
      user:{uniqueId,nickname,profilePictureUrl},
      giftId,
      giftName,
      giftValue:diamondCount*repeatCount,
      repeatCount,
      timestamp:Date.now()
    });
  });
  connection.on(WebcastEvent.LIKE,data=>{
    const user=data.user||{};
    const uniqueId=user.uniqueId||data.uniqueId||user.userId||data.userId;
    const nickname=user.nickname||data.nickname||uniqueId||"Зритель";
    const profilePictureUrl=user.profilePictureUrl||data.profilePictureUrl||user.userDetails?.profilePictureUrls?.[0]||"";
    const incoming=Math.max(0,Number(data.likeCount||0));
    if(!uniqueId || incoming<=0) return;
    const bucketKey=key+":"+uniqueId;
    const previousTotal=likeTotals.get(bucketKey)||0;
    const newTotal=previousTotal+incoming;
    const previousHundreds=Math.floor(previousTotal/100);
    const newHundreds=Math.floor(newTotal/100);
    likeTotals.set(bucketKey,newTotal);
    likeBuckets.set(bucketKey,newTotal%100);
    likeUsers.set(bucketKey,{nickname,profilePictureUrl});
    emitLikeLeaderboard(key);
    const newMilestones=newHundreds-previousHundreds;
    if(newMilestones>0){
      emitRoom(key,"tiktok_like",{
        user:{uniqueId,nickname,profilePictureUrl},
        likeCount:newMilestones*100,
        totalLikeCount:newTotal,
        timestamp:Date.now()
      });
    }
  });
  const subscribeEvent=WebcastEvent.SUBSCRIBE||"subscribe";
  connection.on(subscribeEvent,data=>{
    const user=data.user||{};
    const uniqueId=user.uniqueId||data.uniqueId||user.userId||data.userId;
    if(!uniqueId) return;
    const userKey=key+":"+uniqueId;
    if(subscribedUsers.has(userKey)) return;
    subscribedUsers.add(userKey);
    emitRoom(key,"tiktok_subscribe",{
      user:{
        uniqueId,
        nickname:user.nickname||data.nickname||uniqueId,
        profilePictureUrl:user.profilePictureUrl||data.profilePictureUrl||user.userDetails?.profilePictureUrls?.[0]||""
      },
      timestamp:Date.now()
    });
  });
  connection.on("connected",()=>emitRoom(key,"tiktok_connected",{roomId:key,timestamp:Date.now()}));
  connection.on("disconnected",reason=>emitRoom(key,"tiktok_disconnected",{reason:String(reason||""),timestamp:Date.now()}));
  connection.on("error",error=>emitRoom(key,"tiktok_error",{message:error?.message||String(error),timestamp:Date.now()}));
  await connection.connect();
  connections.set(key,connection);
}

io.on("connection",socket=>{
  socket.on("join-room",async ({username}={})=>{
    const key=String(username||"").replace(/^@/,"").trim().toLowerCase();
    if(!key) return socket.emit("tiktok_error",{message:"Введите TikTok username"});
    socket.join(key);
    emitLikeLeaderboard(key);
    try { await connectTikTok(key); socket.emit("tiktok_status",{connected:true,username:key}); }
    catch(error){ socket.emit("tiktok_error",{message:error?.message||String(error)}); }
  });
});

server.listen(PORT,()=>console.log("TikTok Arena: http://localhost:"+PORT));
