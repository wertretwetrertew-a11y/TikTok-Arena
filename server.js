import express from "express";
import http from "http";
import { Server } from "socket.io";
import { WebcastPushConnection } from "tiktok-live-connector";
import path from "path";
import { fileURLToPath } from "url";
import fs from "fs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const server = http.createServer(app);
const io = new Server(server);
const PORT = process.env.PORT || 3000;
const versionFile = path.join(__dirname, ".tiktok-arena-version");
const buildVersion = fs.existsSync(versionFile) ? fs.readFileSync(versionFile,"utf8").trim().slice(0,7) : "dev";
const connections = new Map();

app.use((req,res,next)=>{\n  res.setHeader("Cache-Control","no-store, no-cache, must-revalidate, proxy-revalidate");\n  res.setHeader("Pragma","no-cache");\n  res.setHeader("Expires","0");\n  next();\n});\napp.use(express.static(path.join(__dirname, "public"), { etag: false, lastModified: false, maxAge: 0 }));
app.get("/api/health", (_req,res) => res.json({ok:true,game:"TikTok Arena",version:buildVersion,serverTime:Date.now()}));

function emitRoom(username,event,payload){ io.to(username).emit(event,payload); }

async function connectTikTok(username){
  const key=String(username).replace(/^@/,"").trim().toLowerCase();
  if(!key) throw new Error("TikTok username is required");
  if(connections.has(key)) return;
  const connection=new WebcastPushConnection(key,{processInitialData:false,enableExtendedGiftInfo:true});
  connection.on("gift",data=>{
    if(data.giftType===1 && !data.repeatEnd) return;
    emitRoom(key,"tiktok_gift",{user:{uniqueId:data.uniqueId,nickname:data.nickname||data.uniqueId,profilePictureUrl:data.profilePictureUrl||""},giftId:data.giftId,giftName:data.giftName,giftValue:Number(data.diamondCount||0)*Math.max(1,Number(data.repeatCount||1)),repeatCount:Number(data.repeatCount||1),timestamp:Date.now()});
  });
  connection.on("like",data=>emitRoom(key,"tiktok_like",{user:{uniqueId:data.uniqueId,nickname:data.nickname||data.uniqueId,profilePictureUrl:data.profilePictureUrl||""},likeCount:Number(data.likeCount||0),totalLikeCount:Number(data.totalLikeCount||0),timestamp:Date.now()}));
  connection.on("subscribe",data=>emitRoom(key,"tiktok_subscribe",{user:{uniqueId:data.uniqueId,nickname:data.nickname||data.uniqueId,profilePictureUrl:data.profilePictureUrl||""},timestamp:Date.now()}));
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
