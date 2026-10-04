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

app.use((req,res,next)=>{
  res.setHeader("Cache-Control","no-store, no-cache, must-revalidate, proxy-revalidate");
  res.setHeader("Pragma","no-cache");
  res.setHeader("Expires","0");
  next();
});
app.use(express.static(path.join(__dirname, "public"), { etag: false, lastModified: false, maxAge: 0 }));
app.get("/api/health", (_req,res) => res.json({ok:true,game:"TikTok Arena",version:buildVersion,serverTime:Date.now()}));

function emitRoom(username,event,payload){ io.to(username).emit(event,payload); }

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
    emitRoom(key,"tiktok_like",{user:{uniqueId:user.uniqueId||data.uniqueId,nickname:user.nickname||data.nickname||user.uniqueId||data.uniqueId,profilePictureUrl:user.profilePictureUrl||data.profilePictureUrl||user.userDetails?.profilePictureUrls?.[0]||""},likeCount:Number(data.likeCount||0),totalLikeCount:Number(data.totalLikeCount||0),timestamp:Date.now()});
  });
  connection.on("subscribe",data=>{
    const user=data.user||{};
    emitRoom(key,"tiktok_subscribe",{user:{uniqueId:user.uniqueId||data.uniqueId,nickname:user.nickname||data.nickname||user.uniqueId||data.uniqueId,profilePictureUrl:user.profilePictureUrl||data.profilePictureUrl||user.userDetails?.profilePictureUrls?.[0]||""},timestamp:Date.now()});
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
    try { await connectTikTok(key); socket.emit("tiktok_status",{connected:true,username:key}); }
    catch(error){ socket.emit("tiktok_error",{message:error?.message||String(error)}); }
  });
});

server.listen(PORT,()=>console.log("TikTok Arena: http://localhost:"+PORT));
