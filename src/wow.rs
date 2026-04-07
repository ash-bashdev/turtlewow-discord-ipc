use std::ffi::{c_char, c_int, c_void, CStr};
use std::sync::OnceLock;

pub type LuaState = *mut c_void;
pub type LuaCFunction = unsafe extern "fastcall" fn(LuaState) -> c_int;

type LuaGettopFn = unsafe extern "fastcall" fn(LuaState) -> c_int;
type LuaTypeFn = unsafe extern "fastcall" fn(LuaState, c_int) -> c_int;
type LuaTonumberFn = unsafe extern "fastcall" fn(LuaState, c_int) -> f64;
type LuaTostringFn = unsafe extern "fastcall" fn(LuaState, c_int) -> *const c_char;
type LuaPushnumberFn = unsafe extern "fastcall" fn(LuaState, f64);
type LuaPushstringFn = unsafe extern "fastcall" fn(LuaState, *const c_char);
type LuaPushnilFn = unsafe extern "fastcall" fn(LuaState);
type GetLuaContextFn = unsafe extern "fastcall" fn() -> LuaState;
type RegisterFunctionFn = unsafe extern "fastcall" fn(*const c_char, *const c_void);

pub struct WowApi {
    gettop: LuaGettopFn,
    lua_type: LuaTypeFn,
    tonumber: LuaTonumberFn,
    tostring: LuaTostringFn,
    pushnumber: LuaPushnumberFn,
    pushstring: LuaPushstringFn,
    pushnil: LuaPushnilFn,
    get_context: GetLuaContextFn,
    register_function: RegisterFunctionFn,
}

unsafe impl Send for WowApi {}
unsafe impl Sync for WowApi {}

impl WowApi {
    #[inline]
    pub unsafe fn get_state(&self) -> LuaState {
        (self.get_context)()
    }

    #[inline]
    pub unsafe fn gettop(&self, l: LuaState) -> i32 {
        (self.gettop)(l)
    }

    #[inline]
    pub unsafe fn tonumber(&self, l: LuaState, idx: i32) -> f64 {
        (self.tonumber)(l, idx)
    }

    pub unsafe fn tostring(&self, l: LuaState, idx: i32) -> Option<String> {
        let ptr = (self.tostring)(l, idx);
        if ptr.is_null() {
            return None;
        }
        Some(CStr::from_ptr(ptr).to_string_lossy().into_owned())
    }

    #[inline]
    pub unsafe fn pushnumber(&self, l: LuaState, n: f64) {
        (self.pushnumber)(l, n);
    }

    #[inline]
    pub unsafe fn pushstring(&self, l: LuaState, s: *const c_char) {
        (self.pushstring)(l, s);
    }

    #[inline]
    pub unsafe fn pushnil(&self, l: LuaState) {
        (self.pushnil)(l);
    }

    pub unsafe fn register_function(&self, name: *const c_char, func: *const c_void) {
        (self.register_function)(name, func);
    }
}

mod offsets {
    pub const SYS_MSG_INITIALIZE: usize = 0x0044CD10;
    pub const LOAD_SCRIPT_FUNCTIONS: usize = 0x00490250;
    pub const LUA_GETTOP: usize = 0x006F3070;
    pub const LUA_TYPE: usize = 0x006F3460;
    pub const LUA_TONUMBER: usize = 0x006F3620;
    pub const LUA_TOSTRING: usize = 0x006F3690;
    pub const LUA_PUSHNIL: usize = 0x006F37F0;
    pub const LUA_PUSHNUMBER: usize = 0x006F3810;
    pub const LUA_PUSHSTRING: usize = 0x006F3890;
    pub const GET_LUA_CONTEXT: usize = 0x007040D0;
    pub const FRAMESCRIPT_REGISTER: usize = 0x00704120;
}

pub type SysMsgInitializeFn = extern "fastcall" fn();
pub type LoadScriptFunctionsFn = extern "stdcall" fn();

pub fn sys_msg_initialize_addr() -> usize {
    offsets::SYS_MSG_INITIALIZE
}

pub fn load_script_functions_addr() -> usize {
    offsets::LOAD_SCRIPT_FUNCTIONS
}

static API: OnceLock<WowApi> = OnceLock::new();

fn is_valid_code_addr(addr: usize) -> bool {
    (0x00401000..0x00900000).contains(&addr)
}

pub unsafe fn init() -> bool {
    let addrs = [
        offsets::LUA_GETTOP,
        offsets::LUA_TYPE,
        offsets::LUA_TONUMBER,
        offsets::LUA_TOSTRING,
        offsets::LUA_PUSHNIL,
        offsets::LUA_PUSHNUMBER,
        offsets::LUA_PUSHSTRING,
        offsets::GET_LUA_CONTEXT,
        offsets::FRAMESCRIPT_REGISTER,
    ];

    for &addr in &addrs {
        if !is_valid_code_addr(addr) {
            return false;
        }
    }

    let api = WowApi {
        gettop: std::mem::transmute(offsets::LUA_GETTOP),
        lua_type: std::mem::transmute(offsets::LUA_TYPE),
        tonumber: std::mem::transmute(offsets::LUA_TONUMBER),
        tostring: std::mem::transmute(offsets::LUA_TOSTRING),
        pushnil: std::mem::transmute(offsets::LUA_PUSHNIL),
        pushnumber: std::mem::transmute(offsets::LUA_PUSHNUMBER),
        pushstring: std::mem::transmute(offsets::LUA_PUSHSTRING),
        get_context: std::mem::transmute(offsets::GET_LUA_CONTEXT),
        register_function: std::mem::transmute(offsets::FRAMESCRIPT_REGISTER),
    };

    let _ = API.set(api);
    true
}

pub fn api() -> Option<&'static WowApi> {
    API.get()
}
