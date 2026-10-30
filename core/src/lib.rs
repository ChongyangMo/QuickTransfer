mod engine;
mod receive;
mod send;
mod storage;
mod types;

use std::{collections::VecDeque, ffi::{c_char, CStr, CString}, sync::{Arc, Mutex, OnceLock}};
use engine::Engine;
use serde_json::{json, Value};
use types::Config;

static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static CURRENT: Mutex<Option<Arc<Engine>>> = Mutex::new(None);
static EVENTS: Mutex<VecDeque<Value>> = Mutex::new(VecDeque::new());
static LIFECYCLE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

fn runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build().expect("传输线程初始化失败"))
}
pub(crate) fn emit(value: Value) {
    let mut events = EVENTS.lock().unwrap();
    if value["type"] == "devices" {
        if let Some(old)=events.iter_mut().find(|v|v["type"]=="devices") { *old=value;return; }
    }
    if value["type"] == "progress" {
        let id = &value["id"];
        if let Some(old) = events.iter_mut().find(|v| v["type"] == "progress" && &v["id"] == id) { *old = value; return; }
    }
    events.push_back(value);
}
pub(crate) fn fail(context: &str, error: impl std::fmt::Display) {
    emit(json!({"type":"error","message":format!("{context}：{error}")}));
}
unsafe fn read_json(ptr: *const c_char) -> anyhow::Result<Value> {
    anyhow::ensure!(!ptr.is_null(), "参数不能为空");
    Ok(serde_json::from_slice(CStr::from_ptr(ptr).to_bytes())?)
}
#[no_mangle]
pub unsafe extern "C" fn qt_start(ptr: *const c_char) {
    let config = read_json(ptr).and_then(|v| Ok(serde_json::from_value::<Config>(v)?));
    match config {
        Err(err) => fail("配置读取失败", err),
        Ok(config) => { runtime().spawn(async move {
            let _guard = LIFECYCLE.lock().await;
            let previous = CURRENT.lock().unwrap().take();
            if let Some(previous) = previous { previous.stop().await; }
            match Engine::start(config).await {
                Ok(engine) => { *CURRENT.lock().unwrap() = Some(engine); }
                Err(err) => fail("启动失败", err),
            }
        }); }
    }
}
#[no_mangle]
pub unsafe extern "C" fn qt_command(ptr: *const c_char) {
    let value = match read_json(ptr) { Ok(value) => value, Err(err) => { fail("操作失败", err); return; } };
    let engine = CURRENT.lock().unwrap().clone();
    if let Some(engine) = engine {
        runtime().spawn(async move { if let Err(err) = engine.command(value).await { fail("操作失败", err); } });
    } else { fail("操作失败", "传输服务尚未启动"); }
}
#[no_mangle]
pub extern "C" fn qt_stop() {
    runtime().spawn(async {
        let _guard = LIFECYCLE.lock().await;
        let engine = CURRENT.lock().unwrap().take();
        if let Some(engine) = engine { engine.stop().await; }
    });
}
#[no_mangle]
pub extern "C" fn qt_poll() -> *mut c_char {
    let value = EVENTS.lock().unwrap().pop_front();
    match value {
        Some(value) => CString::new(value.to_string()).unwrap().into_raw(),
        None => std::ptr::null_mut(),
    }
}
#[no_mangle]
pub unsafe extern "C" fn qt_free(ptr: *mut c_char) { if !ptr.is_null() { drop(CString::from_raw(ptr)); } }

