use localsend::model::{discovery::ProtocolType, transfer::FileDto};
use localsend::http::server::v2::PrepareUploadDecisionV2;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::sync::oneshot;

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub root: String,
    pub alias: String,
    pub model: String,
    pub mobile: bool,
    pub port: u16,
    pub multicast: bool,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Identity { pub certificate: String, pub key: String, pub fingerprint: String }
#[derive(Clone, Serialize, Deserialize)]
pub struct Peer {
    pub id: String,
    pub alias: String,
    pub host: String,
    pub port: u16,
    pub protocol: String,
    pub mobile: bool,
    pub trusted: bool,
}
impl Peer { pub fn protocol(&self) -> ProtocolType { if self.protocol == "https" { ProtocolType::Https } else { ProtocolType::Http } } }
pub struct Pending {
    pub peer: Peer,
    pub files: HashMap<String, FileDto>,
    pub decision: oneshot::Sender<PrepareUploadDecisionV2>,
}

