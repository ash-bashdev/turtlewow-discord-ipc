//! FFI bindings for discord_game_sdk.dll (C vtable API).
//!
//! Only the types and functions we actually need are bound here:
//! - DiscordCreate
//! - IDiscordCore (run_callbacks, get_activity_manager, destroy, set_log_hook)
//! - IDiscordActivityManager (update_activity, clear_activity)
//! - DiscordActivity and related structs
//!
//! On Win32, DISCORD_API is __stdcall. All function pointers use "stdcall".
//!
//! Reference: discord_game_sdk.h (version 3)

#![allow(dead_code)]

use std::ffi::{c_char, c_void};
use std::ptr;

// =========================================================================
// Constants
// =========================================================================

pub const DISCORD_VERSION: i32 = 3;
pub const DISCORD_APPLICATION_MANAGER_VERSION: i32 = 1;
pub const DISCORD_USER_MANAGER_VERSION: i32 = 1;
pub const DISCORD_IMAGE_MANAGER_VERSION: i32 = 1;
pub const DISCORD_ACTIVITY_MANAGER_VERSION: i32 = 1;
pub const DISCORD_RELATIONSHIP_MANAGER_VERSION: i32 = 1;
pub const DISCORD_LOBBY_MANAGER_VERSION: i32 = 1;
pub const DISCORD_NETWORK_MANAGER_VERSION: i32 = 1;
pub const DISCORD_OVERLAY_MANAGER_VERSION: i32 = 2;
pub const DISCORD_STORAGE_MANAGER_VERSION: i32 = 1;
pub const DISCORD_STORE_MANAGER_VERSION: i32 = 1;
pub const DISCORD_VOICE_MANAGER_VERSION: i32 = 1;
pub const DISCORD_ACHIEVEMENT_MANAGER_VERSION: i32 = 1;

// =========================================================================
// Enums
// =========================================================================

#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EDiscordResult {
    Ok = 0,
    ServiceUnavailable = 1,
    InvalidVersion = 2,
    LockFailed = 3,
    InternalError = 4,
    InvalidPayload = 5,
    InvalidCommand = 6,
    InvalidPermissions = 7,
    NotFetched = 8,
    NotFound = 9,
    Conflict = 10,
    NotRunning = 27,
}

#[repr(i32)]
#[derive(Debug, Clone, Copy)]
pub enum EDiscordCreateFlags {
    Default = 0,
    NoRequireDiscord = 1,
}

#[repr(i32)]
#[derive(Debug, Clone, Copy)]
pub enum EDiscordLogLevel {
    Error = 1,
    Warn = 2,
    Info = 3,
    Debug = 4,
}

#[repr(i32)]
#[derive(Debug, Clone, Copy)]
pub enum EDiscordActivityType {
    Playing = 0,
    Streaming = 1,
    Listening = 2,
    Watching = 3,
}

// =========================================================================
// Data structs (fixed-size C structs with char arrays)
// =========================================================================

#[repr(C)]
#[derive(Clone)]
pub struct DiscordActivityTimestamps {
    pub start: i64,
    pub end: i64,
}

#[repr(C)]
#[derive(Clone)]
pub struct DiscordActivityAssets {
    pub large_image: [c_char; 128],
    pub large_text: [c_char; 128],
    pub small_image: [c_char; 128],
    pub small_text: [c_char; 128],
}

#[repr(C)]
#[derive(Clone)]
pub struct DiscordPartySize {
    pub current_size: i32,
    pub max_size: i32,
}

#[repr(C)]
#[derive(Clone)]
pub struct DiscordActivityParty {
    pub id: [c_char; 128],
    pub size: DiscordPartySize,
    pub privacy: i32,
}

#[repr(C)]
#[derive(Clone)]
pub struct DiscordActivitySecrets {
    pub match_: [c_char; 128],
    pub join: [c_char; 128],
    pub spectate: [c_char; 128],
}

#[repr(C)]
#[derive(Clone)]
pub struct DiscordActivity {
    pub type_: EDiscordActivityType,
    pub application_id: i64,
    pub name: [c_char; 128],
    pub state: [c_char; 128],
    pub details: [c_char; 128],
    pub timestamps: DiscordActivityTimestamps,
    pub assets: DiscordActivityAssets,
    pub party: DiscordActivityParty,
    pub secrets: DiscordActivitySecrets,
    pub instance: bool,
    pub supported_platforms: u32,
}

impl DiscordActivity {
    /// Create a zeroed activity.
    pub fn new() -> Self {
        unsafe { std::mem::zeroed() }
    }

    /// Set a fixed-size char field from a Rust string.
    pub fn set_field(field: &mut [c_char; 128], value: &str) {
        let bytes = value.as_bytes();
        let len = bytes.len().min(127);
        for i in 0..len {
            field[i] = bytes[i] as c_char;
        }
        field[len] = 0;
    }
}

// =========================================================================
// Vtable structs (C struct of function pointers)
// =========================================================================

/// IDiscordActivityEvents -- callbacks for activity events.
/// We zero these out since we don't need join/spectate/invite callbacks.
#[repr(C)]
pub struct IDiscordActivityEvents {
    pub on_activity_join: Option<unsafe extern "stdcall" fn(*mut c_void, *const c_char)>,
    pub on_activity_spectate: Option<unsafe extern "stdcall" fn(*mut c_void, *const c_char)>,
    pub on_activity_join_request: Option<unsafe extern "stdcall" fn(*mut c_void, *mut c_void)>,
    pub on_activity_invite:
        Option<unsafe extern "stdcall" fn(*mut c_void, i32, *mut c_void, *mut c_void)>,
}

/// IDiscordActivityManager vtable.
#[repr(C)]
pub struct IDiscordActivityManager {
    pub register_command: Option<
        unsafe extern "stdcall" fn(*mut IDiscordActivityManager, *const c_char) -> EDiscordResult,
    >,
    pub register_steam:
        Option<unsafe extern "stdcall" fn(*mut IDiscordActivityManager, u32) -> EDiscordResult>,
    pub update_activity: Option<
        unsafe extern "stdcall" fn(
            *mut IDiscordActivityManager,
            *mut DiscordActivity,
            *mut c_void,
            Option<unsafe extern "stdcall" fn(*mut c_void, EDiscordResult)>,
        ),
    >,
    pub clear_activity: Option<
        unsafe extern "stdcall" fn(
            *mut IDiscordActivityManager,
            *mut c_void,
            Option<unsafe extern "stdcall" fn(*mut c_void, EDiscordResult)>,
        ),
    >,
    pub send_request_reply: *const c_void,
    pub send_invite: *const c_void,
    pub accept_invite: *const c_void,
}

/// IDiscordOverlayEvents
#[repr(C)]
pub struct IDiscordOverlayEvents {
    pub on_toggle: Option<unsafe extern "stdcall" fn(*mut c_void, bool)>,
}

/// IDiscordCore vtable.
#[repr(C)]
pub struct IDiscordCore {
    pub destroy: Option<unsafe extern "stdcall" fn(*mut IDiscordCore)>,
    pub run_callbacks: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> EDiscordResult>,
    pub set_log_hook: Option<
        unsafe extern "stdcall" fn(
            *mut IDiscordCore,
            EDiscordLogLevel,
            *mut c_void,
            Option<unsafe extern "stdcall" fn(*mut c_void, EDiscordLogLevel, *const c_char)>,
        ),
    >,
    pub get_application_manager:
        Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_user_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_image_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_activity_manager:
        Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut IDiscordActivityManager>,
    pub get_relationship_manager:
        Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_lobby_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_network_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_overlay_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_storage_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_store_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_voice_manager: Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
    pub get_achievement_manager:
        Option<unsafe extern "stdcall" fn(*mut IDiscordCore) -> *mut c_void>,
}

// =========================================================================
// DiscordCreateParams
// =========================================================================

/// Event structs are pointers -- we use *mut c_void for the ones we don't bind.
#[repr(C)]
pub struct DiscordCreateParams {
    pub client_id: i64,
    pub flags: u64,
    pub events: *mut c_void, // IDiscordCoreEvents*
    pub event_data: *mut c_void,
    pub application_events: *mut c_void,
    pub application_version: i32,
    pub user_events: *mut c_void,
    pub user_version: i32,
    pub image_events: *mut c_void,
    pub image_version: i32,
    pub activity_events: *mut IDiscordActivityEvents,
    pub activity_version: i32,
    pub relationship_events: *mut c_void,
    pub relationship_version: i32,
    pub lobby_events: *mut c_void,
    pub lobby_version: i32,
    pub network_events: *mut c_void,
    pub network_version: i32,
    pub overlay_events: *mut IDiscordOverlayEvents,
    pub overlay_version: i32,
    pub storage_events: *mut c_void,
    pub storage_version: i32,
    pub store_events: *mut c_void,
    pub store_version: i32,
    pub voice_events: *mut c_void,
    pub voice_version: i32,
    pub achievement_events: *mut c_void,
    pub achievement_version: i32,
}

impl DiscordCreateParams {
    /// Create params with default version numbers (matching DiscordCreateParamsSetDefault).
    pub fn default_params(client_id: i64) -> Self {
        Self {
            client_id,
            flags: EDiscordCreateFlags::NoRequireDiscord as u64,
            events: ptr::null_mut(),
            event_data: ptr::null_mut(),
            application_events: ptr::null_mut(),
            application_version: DISCORD_APPLICATION_MANAGER_VERSION,
            user_events: ptr::null_mut(),
            user_version: DISCORD_USER_MANAGER_VERSION,
            image_events: ptr::null_mut(),
            image_version: DISCORD_IMAGE_MANAGER_VERSION,
            activity_events: ptr::null_mut(),
            activity_version: DISCORD_ACTIVITY_MANAGER_VERSION,
            relationship_events: ptr::null_mut(),
            relationship_version: DISCORD_RELATIONSHIP_MANAGER_VERSION,
            lobby_events: ptr::null_mut(),
            lobby_version: DISCORD_LOBBY_MANAGER_VERSION,
            network_events: ptr::null_mut(),
            network_version: DISCORD_NETWORK_MANAGER_VERSION,
            overlay_events: ptr::null_mut(),
            overlay_version: 0, // Disable SDK overlay so Discord client uses its own D3D9 hook
            storage_events: ptr::null_mut(),
            storage_version: DISCORD_STORAGE_MANAGER_VERSION,
            store_events: ptr::null_mut(),
            store_version: DISCORD_STORE_MANAGER_VERSION,
            voice_events: ptr::null_mut(),
            voice_version: DISCORD_VOICE_MANAGER_VERSION,
            achievement_events: ptr::null_mut(),
            achievement_version: DISCORD_ACHIEVEMENT_MANAGER_VERSION,
        }
    }
}

// =========================================================================
// DiscordCreate -- dynamically loaded from discord_game_sdk.dll
// =========================================================================

/// Signature: enum EDiscordResult __stdcall DiscordCreate(int version, DiscordCreateParams* params, IDiscordCore** result)
pub type DiscordCreateFn = unsafe extern "stdcall" fn(
    version: i32,
    params: *mut DiscordCreateParams,
    result: *mut *mut IDiscordCore,
) -> EDiscordResult;

// =========================================================================
// High-level wrapper
// =========================================================================

use windows_sys::Win32::Foundation::HMODULE;
use windows_sys::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryA};

/// Wraps the Discord Game SDK lifecycle.
pub struct DiscordSdk {
    core: *mut IDiscordCore,
    activity_events: Box<IDiscordActivityEvents>,
    _dll: HMODULE,
}

// SAFETY: DiscordSdk is used only on a single thread (the background thread).
unsafe impl Send for DiscordSdk {}

impl DiscordSdk {
    /// Initialize the Discord Game SDK.
    pub fn new(client_id: i64) -> Result<Self, &'static str> {
        unsafe {
            // Load the DLL
            let dll_name = b"discord_game_sdk.dll\0";
            let dll = LoadLibraryA(dll_name.as_ptr());
            if dll.is_null() {
                return Err("failed to load discord_game_sdk.dll");
            }

            // Get DiscordCreate
            let proc_name = b"DiscordCreate\0";
            let proc = GetProcAddress(dll, proc_name.as_ptr());
            if proc.is_none() {
                return Err("DiscordCreate not found in discord_game_sdk.dll");
            }
            let discord_create: DiscordCreateFn = std::mem::transmute(proc.unwrap());

            // Set up events (zeroed -- we don't handle join/spectate callbacks)
            let activity_events = Box::new(IDiscordActivityEvents {
                on_activity_join: None,
                on_activity_spectate: None,
                on_activity_join_request: None,
                on_activity_invite: None,
            });

            let mut params = DiscordCreateParams::default_params(client_id);
            params.activity_events = &*activity_events as *const _ as *mut _;

            let mut core: *mut IDiscordCore = ptr::null_mut();
            let result = discord_create(DISCORD_VERSION, &mut params, &mut core);

            if result != EDiscordResult::Ok || core.is_null() {
                return Err("DiscordCreate failed");
            }

            Ok(Self {
                core,
                activity_events,
                _dll: dll,
            })
        }
    }

    /// Run SDK callbacks. Must be called frequently (~every 16ms).
    pub fn run_callbacks(&self) -> bool {
        unsafe {
            if let Some(run) = (*self.core).run_callbacks {
                run(self.core) == EDiscordResult::Ok
            } else {
                false
            }
        }
    }

    /// Update the rich presence activity.
    pub fn update_activity(&self, activity: &mut DiscordActivity) {
        unsafe {
            let mgr = match (*self.core).get_activity_manager {
                Some(f) => f(self.core),
                None => return,
            };
            if mgr.is_null() {
                return;
            }

            if let Some(update) = (*mgr).update_activity {
                update(mgr, activity, ptr::null_mut(), None);
            }
        }
    }

    /// Clear the rich presence activity.
    pub fn clear_activity(&self) {
        unsafe {
            let mgr = match (*self.core).get_activity_manager {
                Some(f) => f(self.core),
                None => return,
            };
            if mgr.is_null() {
                return;
            }

            if let Some(clear) = (*mgr).clear_activity {
                clear(mgr, ptr::null_mut(), None);
            }
        }
    }

    /// Destroy the SDK.
    pub fn destroy(&self) {
        unsafe {
            if let Some(destroy) = (*self.core).destroy {
                destroy(self.core);
            }
        }
    }
}

impl Drop for DiscordSdk {
    fn drop(&mut self) {
        self.destroy();
    }
}
