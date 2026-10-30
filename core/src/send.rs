use crate::{emit, engine::Engine, types::Peer};
use anyhow::{ensure, Context};
use localsend::{http::{client::LsHttpClientV2, dto_v2::PrepareUploadRequestDtoV2}, model::transfer::{FileDto,FileContent,FileMetadata}, reqwest::Body};
use serde_json::{json, Value};
use std::{sync::{Arc, atomic::{AtomicU64,Ordering}}, path::PathBuf, collections::HashMap, time::Instant};
use futures_util::{StreamExt,TryStreamExt};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

pub async fn run(engine: Arc<Engine>, peer: Peer, value: Value) -> anyhow::Result<()> {
    ensure!(peer.protocol=="https", "请在接收端开启加密传输");
    let id = value["id"].as_str().map(String::from).unwrap_or_else(||Uuid::new_v4().to_string());
    let cancel = CancellationToken::new();
    engine.outgoing.lock().unwrap().insert(id.clone(),cancel.clone());
    let outcome = transfer(&engine,&peer,&value,&id,cancel).await;
    engine.outgoing.lock().unwrap().remove(&id);
    if let Err(err) = &outcome { emit(json!({"type":"failed","id":id,"message":format!("发送失败：{err}")})); }
    outcome
}
async fn transfer(engine:&Engine,peer:&Peer,value:&Value,id:&str,cancel:CancellationToken)->anyhow::Result<()> {
    let mut files = HashMap::new();
    let mut sources = HashMap::<String,Source>::new();
    if let Some(text) = value["text"].as_str() {
        ensure!(!text.is_empty() && text.len()<=2_000_000,"文字为空或超过 2 MB");
        let fid = Uuid::new_v4().to_string();
        files.insert(fid.clone(),FileDto { id:fid.clone(),file_name:"文字.txt".into(),size:text.len() as u64,file_type:"text/plain".into(),sha256:None,preview:if text.len()<=100_000 {Some(text.into())} else {None},metadata:None });
        sources.insert(fid,Source::Text(text.into()));
    }
    if let Some(paths) = value["paths"].as_array() {
        for path in paths {
            let path = PathBuf::from(path.as_str().context("文件路径无效")?);
            let metadata = tokio::fs::metadata(&path).await.with_context(||format!("无法读取文件：{}",path.display()))?;
            ensure!(metadata.is_file(),"请选择文件，暂不支持文件夹");
            let fid=Uuid::new_v4().to_string();
            let name=path.file_name().and_then(|v|v.to_str()).context("文件名无效")?.to_string();
            files.insert(fid.clone(),FileDto { id:fid.clone(),file_name:name,size:metadata.len(),file_type:mime_guess::from_path(&path).first_or_octet_stream().to_string(),sha256:None,preview:None,metadata:FileMetadata::from_path(&path) });
            sources.insert(fid,Source::Path(path));
        }
    }
    ensure!(!files.is_empty() && files.len()<=1000,"请选择 1 到 1000 个文件");
    let total:u64=files.values().map(|f|f.size).sum();
    let name=if files.len()==1 { files.values().next().unwrap().file_name.clone() } else {format!("{} 个文件",files.len())};
    emit(json!({"type":"transfer","id":id,"name":name,"size":total,"direction":"send","paths":value["paths"]}));
    let client=Arc::new(LsHttpClientV2::try_new(&engine.identity.key,&engine.identity.certificate,Some(peer.id.clone()),None)?);
    let prepared=tokio::select! {
        res=client.prepare_upload(peer.protocol(),&peer.host,peer.port,None,PrepareUploadRequestDtoV2 {info:engine.register_info(),files:files.clone()},value["pin"].as_str(),cancel.clone()) => res?,
        _=tokio::time::sleep(std::time::Duration::from_secs(120)) => anyhow::bail!("等待接收超时"),
        _=engine.shutdown.cancelled() => anyhow::bail!("服务已停止"),
    };
    if let Some(response)=prepared.response {
        ensure!(response.files.len()==files.len(),"接收端没有接受全部文件");
        let sent=Arc::new(AtomicU64::new(0));
        let clock=Instant::now();
        let progress_id=id.to_string();
        let progress_sent=sent.clone();
        let progress_stop=CancellationToken::new();
        let progress_cancel=progress_stop.clone();
        tokio::spawn(async move { loop { tokio::select! {
            _=progress_cancel.cancelled()=>break,
            _=tokio::time::sleep(std::time::Duration::from_millis(100))=>emit(json!({"type":"progress","id":progress_id,"bytes":progress_sent.load(Ordering::Relaxed),"elapsed":clock.elapsed().as_secs_f64()}))
        } } });
        let outcome=futures_util::stream::iter(sources).map(|(fid,source)|{
            let client=client.clone();let cancel=cancel.clone();let sent=sent.clone();let sid=response.session_id.clone();let token=response.files.get(&fid).cloned();
            async move {
                let token=token.context("文件令牌缺失")?;
                let body=match source {
                    Source::Path(path)=>Body::wrap_stream(FileContent::Path(path).into_stream().map_ok(move |bytes|{sent.fetch_add(bytes.len() as u64,Ordering::Relaxed);bytes})),
                    Source::Text(text)=>{sent.fetch_add(text.len() as u64,Ordering::Relaxed);Body::from(text)}
                };
                client.upload(peer.protocol(),&peer.host,peer.port,None,&sid,&fid,&token,body,cancel).await?;
                Ok::<_,anyhow::Error>(())
            }
        }).buffer_unordered(3).try_collect::<Vec<_>>().await;
        progress_stop.cancel();
        if let Err(error)=outcome {
            cancel.cancel();
            if let Err(cancel_error)=client.cancel(peer.protocol(),&peer.host,peer.port,&response.session_id).await { return Err(error.context(format!("取消远端会话失败：{cancel_error}"))); }
            return Err(error);
        }
    } else {
        ensure!(files.len()==1 && files.values().all(|file|file.preview.is_some()),"接收端未接受文件");
    }
    emit(json!({"type":"sent","id":id,"size":total,"peer":peer.alias}));
    Ok(())
}
enum Source { Path(PathBuf),Text(String) }
