mod discord;
mod wow;

use std::ffi::{c_int, c_void};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use retour::static_detour;
use windows_sys::Win32::Foundation::HMODULE;
use windows_sys::Win32::System::LibraryLoader::DisableThreadLibraryCalls;
use windows_sys::Win32::System::Threading::Sleep;

const DISCORD_CLIENT_ID: &str = "1490096071706284192";
const IDLE_TIMEOUT: Duration = Duration::from_secs(15);

static_detour! {
    static SysMsgInitHook: extern "fastcall" fn();
    static LoadScriptFunctionsHook: extern "stdcall" fn();
}

static HOOKS_INITIALIZED: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Default)]
struct PresenceData {
    details: String,
    state: String,
    large_image: String,
    large_text: String,
    small_image: String,
    small_text: String,
    party_size: i32,
    party_max: i32,
    dirty: bool,
    clear: bool,
}

struct SharedState {
    presence: Mutex<PresenceData>,
    notify: Condvar,
    shutdown: AtomicBool,
    connected: AtomicBool,
}

impl SharedState {
    fn new() -> Self {
        Self {
            presence: Mutex::new(PresenceData::default()),
            notify: Condvar::new(),
            shutdown: AtomicBool::new(false),
            connected: AtomicBool::new(false),
        }
    }

    fn should_shutdown(&self) -> bool {
        self.shutdown.load(Ordering::Acquire)
    }

    fn signal_shutdown(&self) {
        self.shutdown.store(true, Ordering::Release);
        self.notify.notify_all();
    }

    fn set_presence(&self, data: PresenceData) {
        if let Ok(mut g) = self.presence.lock() {
            *g = data;
        }
        self.notify.notify_one();
    }

    fn take_if_dirty(&self) -> Option<PresenceData> {
        let mut g = self.presence.lock().ok()?;
        if !g.dirty {
            return None;
        }
        let snap = g.clone();
        g.dirty = false;
        Some(snap)
    }

    fn set_connected(&self, val: bool) {
        self.connected.store(val, Ordering::Relaxed);
    }

    fn is_connected(&self) -> bool {
        self.connected.load(Ordering::Relaxed)
    }

    fn wait_for_work(&self, timeout: Duration) -> bool {
        let guard = match self.presence.lock() {
            Ok(g) => g,
            Err(_) => return false,
        };
        let result = self
            .notify
            .wait_timeout_while(guard, timeout, |data| {
                !data.dirty && !self.should_shutdown()
            });
        match result {
            Ok((_, timeout_result)) => !timeout_result.timed_out(),
            Err(_) => false,
        }
    }
}

static SHARED: OnceLock<Arc<SharedState>> = OnceLock::new();

fn shared() -> Option<&'static Arc<SharedState>> {
    SHARED.get()
}

fn start_time() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

unsafe fn lua_get_string(api: &wow::WowApi, l: wow::LuaState, idx: i32, nargs: i32) -> String {
    if idx > nargs {
        return String::new();
    }
    api.tostring(l, idx).unwrap_or_default()
}

#[no_mangle]
pub unsafe extern "fastcall" fn Script_DiscordSetPresence(_l: wow::LuaState) -> c_int {
    let api = match wow::api() {
        Some(a) => a,
        None => return 0,
    };
    let state = match shared() {
        Some(s) => s,
        None => return 0,
    };

    let l = api.get_state();
    let nargs = api.gettop(l);

    let party_size = if nargs >= 7 { api.tonumber(l, 7) as i32 } else { 0 };
    let party_max = if nargs >= 8 { api.tonumber(l, 8) as i32 } else { 0 };

    state.set_presence(PresenceData {
        details: lua_get_string(api, l, 1, nargs),
        state: lua_get_string(api, l, 2, nargs),
        large_image: lua_get_string(api, l, 3, nargs),
        large_text: lua_get_string(api, l, 4, nargs),
        small_image: lua_get_string(api, l, 5, nargs),
        small_text: lua_get_string(api, l, 6, nargs),
        party_size,
        party_max,
        dirty: true,
        clear: false,
    });

    0
}

#[no_mangle]
pub unsafe extern "fastcall" fn Script_DiscordClearPresence(_l: wow::LuaState) -> c_int {
    if let Some(state) = shared() {
        state.set_presence(PresenceData {
            dirty: true,
            clear: true,
            ..Default::default()
        });
    }
    0
}

#[no_mangle]
pub unsafe extern "fastcall" fn Script_DiscordIsConnected(_l: wow::LuaState) -> c_int {
    let api = match wow::api() {
        Some(a) => a,
        None => return 0,
    };

    let l = api.get_state();
    let connected = shared().map_or(false, |s| s.is_connected());

    if connected {
        api.pushnumber(l, 1.0);
    } else {
        api.pushnil(l);
    }
    1
}

unsafe fn register_lua_functions() {
    let api = match wow::api() {
        Some(a) => a,
        None => return,
    };

    api.register_function(
        c"DiscordSetPresence".as_ptr(),
        Script_DiscordSetPresence as *const c_void,
    );
    api.register_function(
        c"DiscordClearPresence".as_ptr(),
        Script_DiscordClearPresence as *const c_void,
    );
    api.register_function(
        c"DiscordIsConnected".as_ptr(),
        Script_DiscordIsConnected as *const c_void,
    );
}

fn load_script_functions_detour() {
    LoadScriptFunctionsHook.call();
    unsafe {
        wow::init();
        register_lua_functions();
    }
}

fn sys_msg_init_detour() {
    SysMsgInitHook.call();

    if HOOKS_INITIALIZED.swap(true, Ordering::SeqCst) {
        return;
    }

    unsafe {
        let load_fn: wow::LoadScriptFunctionsFn =
            std::mem::transmute(wow::load_script_functions_addr());

        let _ = LoadScriptFunctionsHook
            .initialize(load_fn, load_script_functions_detour)
            .and_then(|h| h.enable());
    }
}

fn discord_thread(state: Arc<SharedState>) {
    let ts = start_time();
    let mut ipc = discord::DiscordIpc::new(DISCORD_CLIENT_ID);

    while !state.should_shutdown() {
        if !ipc.is_ready() {
            state.set_connected(false);
            if ipc.connect().is_ok() {
                let _ = ipc.handshake();
            }
            if !ipc.is_ready() {
                ipc.disconnect();
                state.wait_for_work(IDLE_TIMEOUT);
                continue;
            }
            state.set_connected(true);
        }

        state.wait_for_work(IDLE_TIMEOUT);

        if state.should_shutdown() { break; }

        if let Some(data) = state.take_if_dirty() {
            let result = if data.clear {
                ipc.clear_activity()
            } else {
                ipc.set_activity(
                    &data.details, &data.state,
                    &data.large_image, &data.large_text,
                    &data.small_image, &data.small_text,
                    ts,
                    data.party_size, data.party_max,
                )
            };
            if result.is_err() {
                ipc.disconnect();
                state.set_connected(false);
                continue;
            }
        }

        if ipc.is_ready() {
            if ipc.drain_responses().is_err() {
                ipc.disconnect();
                state.set_connected(false);
            }
        }
    }

    ipc.disconnect();
    state.set_connected(false);
}

#[no_mangle]
unsafe extern "system" fn DllMain(module: HMODULE, reason: u32, _reserved: *mut ()) -> i32 {
    const DLL_PROCESS_ATTACH: u32 = 1;
    const DLL_PROCESS_DETACH: u32 = 0;

    match reason {
        DLL_PROCESS_ATTACH => {
            DisableThreadLibraryCalls(module);

            let state = Arc::new(SharedState::new());
            let _ = SHARED.set(state.clone());

            let sys_msg_fn: wow::SysMsgInitializeFn =
                std::mem::transmute(wow::sys_msg_initialize_addr());

            let hook_ok = SysMsgInitHook
                .initialize(sys_msg_fn, sys_msg_init_detour)
                .and_then(|h| h.enable())
                .is_ok();

            if !hook_ok {
                return 1;
            }

            let thread_state = state.clone();
            thread::spawn(move || discord_thread(thread_state));
        }

        DLL_PROCESS_DETACH => {
            if let Some(state) = SHARED.get() {
                state.signal_shutdown();
            }
            Sleep(500);
        }

        _ => {}
    }

    1
}
