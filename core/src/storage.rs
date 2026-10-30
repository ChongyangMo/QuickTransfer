use crate::types::Identity;
use std::{path::{Path, PathBuf}, fs};
use anyhow::{Context, ensure};
use serde::{Serialize, de::DeserializeOwned};

pub fn save<T: Serialize>(path: &Path, value: &T) -> anyhow::Result<()> {
    let temp = path.with_extension("json.tmp");
    fs::write(&temp, serde_json::to_vec_pretty(value)?)?;
    #[cfg(unix)] {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&temp, fs::Permissions::from_mode(0o600))?;
    }
    fs::rename(temp, path)?;
    Ok(())
}
pub fn load<T: DeserializeOwned>(path: &Path) -> anyhow::Result<T> {
    Ok(serde_json::from_slice(&fs::read(path).with_context(|| format!("读取配置失败：{}", path.display()))?)?)
}
pub fn identity(root: &Path) -> anyhow::Result<Identity> {
    fs::create_dir_all(root)?;
    let path = root.join("identity.json");
    if path.exists() { return load(&path); }
    let cert = localsend::crypto::cert::generate_self_signed()?;
    let identity = Identity { certificate: cert.certificate_pem, key: cert.private_key_pem, fingerprint: cert.fingerprint };
    save(&path, &identity)?;
    Ok(identity)
}
pub fn receive_path(root: &Path, session: &str, name: &str) -> anyhow::Result<PathBuf> {
    ensure!(!name.is_empty() && name.len() <= 240 && !name.chars().any(|c| c.is_control()), "文件名无效");
    ensure!(!name.contains('/') && !name.contains('\\') && name != "." && name != "..", "不支持目录或不安全的文件名");
    let dir = root.join("received").join(session);
    fs::create_dir_all(&dir)?;
    let path = dir.join(name);
    ensure!(!path.exists(), "同名文件已经存在");
    Ok(path)
}

