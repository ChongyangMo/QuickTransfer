use crate::{emit, fail, engine::Engine, storage, types::{Peer, Pending}};
use localsend::{http::server::{v2::{ServerEventV2, PrepareUploadDecisionV2}, common::save::FileUploadTarget}, model::discovery::DeviceType};
use serde_json::{json, Value};
use std::{sync::Arc, collections::HashSet};
use anyhow::{Context, ensure};
use tokio::sync::{mpsc, oneshot};

pub async fn handle(engine: Arc<Engine>, event: ServerEventV2) {
    match event {
        ServerEventV2::Register { ip, info } => {
            if let Err(err) = engine.upsert(Peer { id: info.fingerprint, alias: info.alias, host: ip.to_string(), port: info.port, protocol: info.protocol.as_str().into(), mobile: info.device_type == Some(DeviceType::Mobile), trusted: false }) { fail("记录设备失败",err); }
        }
        ServerEventV2::PrepareUpload { session_id, ip, info, cert_fingerprint, files, decision_tx } => {
            let peer = Peer { id: cert_fingerprint.unwrap_or(info.fingerprint), alias: info.alias, host: ip.to_string(), port: info.port, protocol: info.protocol.as_str().into(), mobile: info.device_type == Some(DeviceType::Mobile), trusted: false };
            let names: HashSet<_> = files.values().map(|file|file.file_name.to_lowercase()).collect();
            let valid = !files.is_empty() && files.len() <= 1000 && names.len() == files.len() && files.values().all(|file| file.size <= 1024*1024*1024*1024 && storage::receive_path(&engine.root, &session_id, &file.file_name).is_ok());
            if !valid { let _ = decision_tx.send(PrepareUploadDecisionV2::Decline); fail("拒绝接收", "文件名或数量无效"); return; }
            let trusted = peer.protocol == "https" && engine.trusted.lock().unwrap().contains(&peer.id);
            let total: u64 = files.values().map(|f|f.size).sum();
            let preview = if files.len() == 1 { files.values().next().and_then(|f| if f.file_type == "text/plain" { f.preview.as_ref() } else { None }).cloned() } else { None };
            engine.pending.lock().unwrap().insert(session_id.clone(), Pending { peer: peer.clone(), files, decision: decision_tx });
            if trusted {
                if let Err(err) = decide(&engine, &json!({"action":"accept","id":session_id,"remember":false})) { fail("接收失败",err); }
            } else {
                emit(json!({"type":"incoming","id":session_id,"peer":peer.id,"alias":peer.alias,"count":engine.pending.lock().unwrap()[&session_id].files.len(),"size":total,"text":preview}));
            }
        }
        ServerEventV2::FileUpload { session_id, file_id, file, target_tx } => {
            let path = match storage::receive_path(&engine.root, &session_id, &file.file_name) { Ok(path) => path, Err(err) => { fail("接收失败",err); return; } };
            let part = path.with_file_name(format!("{}.part",uuid::Uuid::new_v4()));
            let (result_tx,result_rx) = oneshot::channel();
            let (progress_tx,mut progress_rx) = mpsc::channel(1);
            let id = format!("{session_id}:{file_id}");
            emit(json!({"type":"transfer","id":id,"session":session_id,"name":file.file_name,"size":file.size,"direction":"receive"}));
            let _ = target_tx.send(FileUploadTarget::Path { path: part.clone(), result_tx, progress_tx: Some(progress_tx) });
            let progress_id = id.clone();
            tokio::spawn(async move { while let Some(bytes) = progress_rx.recv().await { emit(json!({"type":"progress","id":progress_id,"bytes":bytes})); } });
            tokio::spawn(async move {
                let outcome = async {
                    result_rx.await.context("发送端已断开")?.map_err(anyhow::Error::msg)?;
                    ensure!(!engine.cancelled.lock().unwrap().contains(&session_id),"接收已取消");
                    tokio::fs::rename(&part,&path).await?;
                    Ok::<_,anyhow::Error>(())
                }.await;
                match outcome {
                    Ok(()) => emit(json!({"type":"received","id":id,"name":file.file_name,"path":path,"size":file.size,"fileType":file.file_type})),
                    Err(err) => { if part.exists() { if let Err(cleanup)=tokio::fs::remove_file(&part).await { fail("清理未完成文件失败",cleanup); } } emit(json!({"type":"failed","id":id,"message":format!("接收失败：{err}")})); }
                }
            });
        }
        ServerEventV2::PrepareUploadAborted { session_id } => {
            engine.pending.lock().unwrap().remove(&session_id);
            emit(json!({"type":"dismiss","id":session_id}));
        }
        ServerEventV2::SessionEnd { session_id, reason } => { emit(json!({"type":"sessionEnd","id":session_id,"reason":format!("{reason:?}")})); }
        ServerEventV2::ListenerFailed { error } => fail("接收服务已停止，请重新连接", error),
        ServerEventV2::CancelReceived { ip, session_id } => { emit(json!({"type":"remoteCancel","id":session_id,"host":ip.to_string()})); }
    }
}
pub fn decide(engine: &Engine, value: &Value) -> anyhow::Result<()> {
    let id = value["id"].as_str().context("缺少任务编号")?;
    let pending = engine.pending.lock().unwrap().remove(id).context("发送请求已失效")?;
    if value["action"] == "decline" { pending.decision.send(PrepareUploadDecisionV2::Decline).map_err(|_|anyhow::anyhow!("发送端已断开"))?; return Ok(()); }
    if value["remember"] == true {
        ensure!(pending.peer.protocol == "https", "只能记住使用加密连接的设备");
        let mut trusted = engine.trusted.lock().unwrap();
        trusted.insert(pending.peer.id.clone());
        storage::save(&engine.root.join("trusted.json"), &*trusted)?;
    }
    let text = if pending.files.len()==1 { pending.files.values().next().filter(|f|f.file_type=="text/plain" && f.size<=100_000).and_then(|f|f.preview.as_ref().filter(|p|p.len() as u64 == f.size)).cloned() } else { None };
    let ids = if text.is_some() { HashSet::new() } else { pending.files.keys().cloned().collect() };
    pending.decision.send(PrepareUploadDecisionV2::Accept(ids)).map_err(|_|anyhow::anyhow!("发送端已断开"))?;
    if let Some(text) = text { emit(json!({"type":"text","id":id,"alias":pending.peer.alias,"text":text})); }
    emit(json!({"type":"dismiss","id":id}));
    Ok(())
}
