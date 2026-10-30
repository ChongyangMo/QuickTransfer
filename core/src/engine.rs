use crate::{emit, fail, receive, send, storage, types::*};
use anyhow::{ensure, Context};
use localsend::{http::{client::LsHttpClientV2, dto_v2::RegisterDtoV2, server::{self, ServerConfigV2, ServerHandle, TlsConfig, web::WebConfig}, state::ClientInfo}, model::discovery::{DeviceType, ProtocolType, PROTOCOL_VERSION_V2}, multicast::{self, MulticastConfig, MulticastDevice, MulticastEvent, MulticastHandle}};
use serde_json::{json, Value};
use std::{collections::{BTreeMap, HashMap, HashSet}, path::PathBuf, sync::{Arc, Mutex}, time::Duration};
use tokio::sync::{mpsc, oneshot};
use tokio_util::sync::CancellationToken;

pub struct Engine {
    pub config: Config,
    pub root: PathBuf,
    pub identity: Identity,
    pub peers: Mutex<BTreeMap<String, Peer>>,
    pub trusted: Mutex<HashSet<String>>,
    pub pending: Mutex<HashMap<String, Pending>>,
    pub cancelled: Mutex<HashSet<String>>,
    pub outgoing: Mutex<HashMap<String, CancellationToken>>,
    pub server: ServerHandle,
    pub shutdown: CancellationToken,
    multicast: Mutex<Option<Arc<MulticastHandle>>>,
    stops: Mutex<Vec<oneshot::Sender<()>>>,
}
impl Engine {
    pub async fn start(config: Config) -> anyhow::Result<Arc<Self>> {
        ensure!(!config.alias.trim().is_empty(), "设备名称不能为空");
        let root = PathBuf::from(&config.root);
        let identity = storage::identity(&root)?;
        let trusted_path = root.join("trusted.json");
        let trusted = if trusted_path.exists() { storage::load(&trusted_path)? } else { HashSet::new() };
        let (event_tx, mut event_rx) = mpsc::channel(256);
        let (server_stop, stop_rx) = oneshot::channel();
        let server = server::start_with_port(config.port, Some(TlsConfig { cert: identity.certificate.clone(), private_key: identity.key.clone() }), ClientInfo {
            alias: config.alias.clone(), version: PROTOCOL_VERSION_V2.into(), device_model: Some(config.model.clone()),
            device_type: Some(if config.mobile { DeviceType::Mobile } else { DeviceType::Desktop }), token: identity.fingerprint.clone(),
        }, None, Some(ServerConfigV2 { pin: None, verify_checksums: true, event_tx }), WebConfig::default(), stop_rx).await.context("端口不可用，请退出占用同一端口的软件或在设置中修改端口")?;
        let engine = Arc::new(Self { config, root, identity, trusted: Mutex::new(trusted), peers: Mutex::new(BTreeMap::new()), pending: Mutex::new(HashMap::new()), cancelled: Mutex::new(HashSet::new()), outgoing: Mutex::new(HashMap::new()), server, shutdown: CancellationToken::new(), multicast: Mutex::new(None), stops: Mutex::new(vec![server_stop]) });
        let current = engine.clone();
        tokio::spawn(async move {
            loop { tokio::select! {
                _ = current.shutdown.cancelled() => break,
                event = event_rx.recv() => match event { Some(event) => receive::handle(current.clone(), event).await, None => break }
            } }
        });
        if engine.config.multicast {
            if let Err(error) = engine.start_multicast().await { engine.stop().await; return Err(error); }
        }
        emit(json!({"type":"ready","alias":engine.config.alias,"port":engine.server.port(),"fingerprint":engine.identity.fingerprint,"addresses":engine.server.local_addresses().iter().map(|v|v.to_string()).collect::<Vec<_>>()}));
        let current = engine.clone();
        tokio::spawn(async move { if let Err(error) = current.refresh().await { fail("发现设备失败", error); } });
        Ok(engine)
    }
    async fn start_multicast(self: &Arc<Self>) -> anyhow::Result<()> {
        let (event_tx, mut events) = mpsc::channel(128);
        let (stop, stop_rx) = oneshot::channel();
        let multicast = multicast::start(MulticastConfig {
            group: multicast::DEFAULT_MULTICAST_GROUP, group_v6: None, port: multicast::DEFAULT_PORT,
            interface_filter: Default::default(), device: MulticastDevice {
                alias: self.config.alias.clone(), version: PROTOCOL_VERSION_V2.into(), device_model: Some(self.config.model.clone()),
                device_type: Some(if self.config.mobile { DeviceType::Mobile } else { DeviceType::Desktop }), fingerprint: self.identity.fingerprint.clone(),
                port: self.server.port(), protocol: ProtocolType::Https, download: false,
            }, event_tx,
        }, stop_rx).await.context("LocalSend 设备发现启动失败")?;
        *self.multicast.lock().unwrap() = Some(Arc::new(multicast));
        self.stops.lock().unwrap().push(stop);
        let engine = self.clone();
        tokio::spawn(async move { loop { tokio::select! {
            _ = engine.shutdown.cancelled() => break,
            event = events.recv() => match event {
                Some(MulticastEvent::Discovered { ip, scope_id, message }) => {
                    if message.fingerprint == engine.identity.fingerprint { continue; }
                    let host = scope_id.map(|scope| format!("{ip}%{scope}")).unwrap_or_else(||ip.to_string());
                    let current = engine.clone();
                    tokio::spawn(async move { if let Err(err) = current.probe(&host, message.port, message.protocol).await { fail("连接附近设备失败", err); } });
                }
                Some(MulticastEvent::SocketsFailed) => { fail("设备发现已停止", "请重新连接"); break; }
                None => break,
            }
        } } });
        Ok(())
    }
    pub fn register_info(&self) -> RegisterDtoV2 {
        RegisterDtoV2 { alias: self.config.alias.clone(), version: PROTOCOL_VERSION_V2.into(), device_model: Some(self.config.model.clone()),
            device_type: Some(if self.config.mobile { DeviceType::Mobile } else { DeviceType::Desktop }), fingerprint: self.identity.fingerprint.clone(),
            port: self.server.port(), protocol: ProtocolType::Https, download: false }
    }
    pub async fn probe(&self, host: &str, port: u16, protocol: ProtocolType) -> anyhow::Result<()> {
        let client = LsHttpClientV2::try_new(&self.identity.key, &self.identity.certificate, None, Some(Duration::from_secs(3)))?;
        let response = client.register(protocol, host, port, self.register_info()).await?;
        let id = if protocol == ProtocolType::Https { response.cert_fingerprint.context("设备没有提供证书")? } else { response.body.fingerprint };
        self.upsert(Peer { id, alias: response.body.alias, host: host.into(), port, protocol: protocol.as_str().into(), mobile: response.body.device_type == Some(DeviceType::Mobile), trusted: false })?;
        Ok(())
    }
    pub fn upsert(&self, mut peer: Peer) -> anyhow::Result<()> {
        if peer.id == self.identity.fingerprint { return Ok(()); }
        peer.alias = peer.alias.chars().filter(|c|!c.is_control()).take(80).collect();
        peer.trusted = self.trusted.lock().unwrap().contains(&peer.id);
        let mut peers = self.peers.lock().unwrap();
        peers.insert(peer.id.clone(), peer);
        storage::save(&self.root.join("known.json"), &*peers)?;
        emit(json!({"type":"devices","devices":peers.values().collect::<Vec<_>>()}));
        Ok(())
    }
    pub async fn refresh(&self) -> anyhow::Result<()> {
        let multicast = self.multicast.lock().unwrap().clone();
        if let Some(multicast) = multicast { tokio::spawn(async move { multicast.announce().await; }); }
        let path = self.root.join("known.json");
        if path.exists() {
            let peers: BTreeMap<String, Peer> = storage::load(&path)?;
            for peer in peers.values() {
                // An offline remembered device is not displayed as available.
                if let Err(error) = self.probe(&peer.host, peer.port, peer.protocol()).await { emit(json!({"type":"offline","id":peer.id,"message":format!("设备离线：{error}")})); }
            }
        }
        Ok(())
    }
    pub async fn command(self: Arc<Self>, value: Value) -> anyhow::Result<()> {
        match value["action"].as_str().context("缺少操作名称")? {
            "refresh" => self.refresh().await?,
            "probe" => self.probe(value["host"].as_str().context("缺少设备地址")?, value["port"].as_u64().unwrap_or(53317).try_into()?, if value["protocol"] == "http" { ProtocolType::Http } else { ProtocolType::Https }).await?,
            "send" => {
                let id = value["peer"].as_str().context("请选择接收设备")?;
                let peer = self.peers.lock().unwrap().get(id).cloned().context("接收设备已离线")?;
                send::run(self.clone(), peer, value).await?;
            }
            "accept" | "decline" => receive::decide(&self, &value)?,
            "cancel" => {
                let id = value["id"].as_str().context("缺少任务编号")?;
                if let Some(cancel) = self.outgoing.lock().unwrap().get(id) { cancel.cancel(); }
                self.cancelled.lock().unwrap().insert(id.into());
                self.server.cancel_v2_session(id).await;
                emit(json!({"type":"cancelled","id":id}));
            }
            _ => anyhow::bail!("不支持的操作"),
        }
        Ok(())
    }
    pub async fn stop(&self) {
        self.shutdown.cancel();
        for cancel in self.outgoing.lock().unwrap().values() { cancel.cancel(); }
        let stops = std::mem::take(&mut *self.stops.lock().unwrap());
        for stop in stops { let _ = stop.send(()); }
        self.server.wait_stopped().await;
        let multicast = self.multicast.lock().unwrap().take();
        if let Some(multicast) = multicast { multicast.wait_stopped().await; }
    }
}
