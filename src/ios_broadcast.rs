// C entry points for the ReplayKit broadcast upload extension, which runs the host server
// in its own process and shares the config dir (App Group container) with the main app.
use base::config::keys::OPTION_AV1_TEST;
use hbb_common::{
    config::{self, Config},
    log,
    tokio::{
        self,
        sync::{mpsc::{UnboundedReceiver, UnboundedSender}, oneshot},
    },
    ResultType,
};
use std::{
    ffi::{c_char, CStr},
    sync::Mutex,
    time::Duration,
};

lazy_static::lazy_static! {
    static ref STOP_TX: Mutex<Option<oneshot::Sender<()>>> = Default::default();
}

#[no_mangle]
pub extern "C" fn vita_broadcast_start(app_dir: *const c_char) -> i32 {
    if app_dir.is_null() {
        return -1;
    }
    let Ok(app_dir) = unsafe { CStr::from_ptr(app_dir) }.to_str() else {
        return -1;
    };
    let mut stop_tx = STOP_TX.lock().unwrap();
    if stop_tx.is_some() {
        return 0;
    }
    {
        use hbb_common::env_logger::*;
        try_init_from_env(Env::default().filter_or(DEFAULT_FILTER_ENV, "info")).ok();
    }
    *config::APP_DIR.write().unwrap() = app_dir.to_owned();
    // The app may have changed the password since this process last read the config.
    Config::reload();
    // The AV1 encoder is too heavy for the extension's memory limit.
    if Config::get_option(OPTION_AV1_TEST).is_empty() {
        Config::set_option(OPTION_AV1_TEST.to_owned(), "N".to_owned());
    }
    let rt = match tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            log::error!("Failed to create the broadcast runtime: {e}");
            return -1;
        }
    };
    let (tx, rx) = oneshot::channel::<()>();
    let spawned = std::thread::Builder::new()
        .name("vita-broadcast".to_owned())
        .spawn(move || {
            rt.block_on(async move {
                tokio::select! {
                    _ = crate::RendezvousMediator::start_all() => {}
                    _ = rx => {}
                }
            });
            // Dropping the runtime's tasks closes every connection.
            rt.shutdown_timeout(Duration::from_secs(1));
            scrap::clear_frames();
            log::info!("Broadcast server stopped");
        });
    if let Err(e) = spawned {
        log::error!("Failed to start the broadcast server thread: {e}");
        return -1;
    }
    *stop_tx = Some(tx);
    log::info!("Broadcast server started, id: {}", Config::get_id());
    0
}

#[no_mangle]
pub extern "C" fn vita_broadcast_frame(
    data: *const u8,
    len: usize,
    width: u32,
    height: u32,
    stride: u32,
) {
    if data.is_null() || len == 0 {
        return;
    }
    let data = unsafe { std::slice::from_raw_parts(data, len) };
    scrap::push_frame(data, width as _, height as _, stride as _);
}

#[no_mangle]
pub extern "C" fn vita_broadcast_stop() {
    if let Some(tx) = STOP_TX.lock().unwrap().take() {
        tx.send(()).ok();
    }
    scrap::clear_frames();
}

// No UI in the extension. The customer starting a broadcast is their consent, so
// logins without a password are approved straight away.
pub(crate) fn start_headless_cm(
    mut rx: UnboundedReceiver<crate::ipc::Data>,
    tx: UnboundedSender<crate::ipc::Data>,
) {
    tokio::spawn(async move {
        while let Some(data) = rx.recv().await {
            if let crate::ipc::Data::Login {
                authorized: false, ..
            } = data
            {
                tx.send(crate::ipc::Data::Authorize).ok();
            }
        }
    });
}

// View only: remote input is dropped.
pub(crate) fn call_main_service_pointer_input(
    _kind: &str,
    _mask: i32,
    _x: i32,
    _y: i32,
) -> ResultType<()> {
    Ok(())
}
