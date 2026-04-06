use std::io;
use std::ptr;

use serde::Serialize;
use serde_json::json;

use windows_sys::Win32::Foundation::{
    CloseHandle, GENERIC_READ, GENERIC_WRITE, HANDLE, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Storage::FileSystem::{CreateFileA, ReadFile, WriteFile, OPEN_EXISTING};
use windows_sys::Win32::System::Pipes::PeekNamedPipe;

#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Opcode {
    Handshake = 0,
    Frame = 1,
    Close = 2,
    Ping = 3,
    Pong = 4,
}

impl Opcode {
    fn from_u32(v: u32) -> Option<Self> {
        match v {
            0 => Some(Self::Handshake),
            1 => Some(Self::Frame),
            2 => Some(Self::Close),
            3 => Some(Self::Ping),
            4 => Some(Self::Pong),
            _ => None,
        }
    }
}

struct OwnedHandle(HANDLE);

impl OwnedHandle {
    fn is_valid(&self) -> bool {
        self.0 != INVALID_HANDLE_VALUE && !self.0.is_null()
    }
    fn raw(&self) -> HANDLE {
        self.0
    }
}

impl Drop for OwnedHandle {
    fn drop(&mut self) {
        if self.is_valid() {
            unsafe { CloseHandle(self.0) };
            self.0 = INVALID_HANDLE_VALUE;
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum State {
    Disconnected,
    Connected,
    Ready,
}

pub struct DiscordIpc {
    pipe: Option<OwnedHandle>,
    state: State,
    client_id: String,
    nonce: u32,
    send_buf: Vec<u8>,
    recv_buf: Vec<u8>,
}

impl DiscordIpc {
    pub fn new(client_id: &str) -> Self {
        Self {
            pipe: None,
            state: State::Disconnected,
            client_id: client_id.to_owned(),
            nonce: 1,
            send_buf: Vec::with_capacity(4096),
            recv_buf: vec![0u8; 4096],
        }
    }

    pub fn is_ready(&self) -> bool {
        self.state == State::Ready && self.pipe.as_ref().map_or(false, |h| h.is_valid())
    }

    pub fn connect(&mut self) -> io::Result<()> {
        if self.state != State::Disconnected {
            return Ok(());
        }
        for i in 0..10 {
            let name = format!("\\\\.\\pipe\\discord-ipc-{}\0", i);
            let handle = unsafe {
                CreateFileA(
                    name.as_ptr(),
                    GENERIC_READ | GENERIC_WRITE,
                    0,
                    ptr::null(),
                    OPEN_EXISTING,
                    0,
                    ptr::null_mut(),
                )
            };
            if handle != INVALID_HANDLE_VALUE {
                self.pipe = Some(OwnedHandle(handle));
                self.state = State::Connected;
                return Ok(());
            }
        }
        Err(io::Error::new(
            io::ErrorKind::NotFound,
            "Discord IPC pipe not found",
        ))
    }

    pub fn disconnect(&mut self) {
        if self.state == State::Ready {
            let _ = self.send_frame(Opcode::Close, b"{}");
        }
        self.pipe = None;
        self.state = State::Disconnected;
    }

    pub fn handshake(&mut self) -> io::Result<()> {
        if self.state != State::Connected {
            return Err(io::Error::new(io::ErrorKind::NotConnected, "not connected"));
        }
        let payload = json!({ "v": 1, "client_id": self.client_id });
        self.send_frame(Opcode::Handshake, payload.to_string().as_bytes())?;

        let (op, response) = self.recv_frame()?;
        if op == Opcode::Frame && response.contains("\"READY\"") {
            self.state = State::Ready;
            Ok(())
        } else {
            Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "handshake did not receive READY",
            ))
        }
    }

    pub fn set_activity(
        &mut self,
        details: &str,
        state: &str,
        large_image: &str,
        large_text: &str,
        small_image: &str,
        small_text: &str,
        start_timestamp: i64,
        party_size: i32,
        party_max: i32,
    ) -> io::Result<()> {
        if self.state != State::Ready {
            return Err(io::Error::new(io::ErrorKind::NotConnected, "not ready"));
        }

        let mut activity = json!({
            "details": details,
            "state": state,
        });

        if start_timestamp > 0 {
            activity["timestamps"] = json!({ "start": start_timestamp });
        }

        let has_large = !large_image.is_empty();
        let has_small = !small_image.is_empty();
        if has_large || has_small {
            let mut assets = serde_json::Map::new();
            if has_large {
                assets.insert("large_image".into(), json!(large_image));
                assets.insert("large_text".into(), json!(large_text));
            }
            if has_small {
                assets.insert("small_image".into(), json!(small_image));
                assets.insert("small_text".into(), json!(small_text));
            }
            activity["assets"] = serde_json::Value::Object(assets);
        }

        if party_size > 0 && party_max > 0 {
            activity["party"] = json!({
                "id": "wow-party",
                "size": [party_size, party_max],
            });
        }

        let payload = json!({
            "cmd": "SET_ACTIVITY",
            "args": {
                "pid": std::process::id(),
                "activity": activity,
            },
            "nonce": self.next_nonce().to_string(),
        });

        self.send_frame(Opcode::Frame, payload.to_string().as_bytes())
    }

    pub fn clear_activity(&mut self) -> io::Result<()> {
        if self.state != State::Ready {
            return Err(io::Error::new(io::ErrorKind::NotConnected, "not ready"));
        }
        let payload = json!({
            "cmd": "SET_ACTIVITY",
            "args": {
                "pid": std::process::id(),
                "activity": null,
            },
            "nonce": self.next_nonce().to_string(),
        });
        self.send_frame(Opcode::Frame, payload.to_string().as_bytes())
    }

    pub fn drain_responses(&mut self) -> io::Result<()> {
        while self.has_data()? {
            let (op, payload) = self.recv_frame()?;
            match op {
                Opcode::Ping => {
                    let _ = self.send_frame(Opcode::Pong, payload.as_bytes());
                }
                Opcode::Close => {
                    self.pipe = None;
                    self.state = State::Disconnected;
                    return Err(io::Error::new(
                        io::ErrorKind::ConnectionAborted,
                        "Discord sent CLOSE",
                    ));
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn pipe_handle(&self) -> io::Result<HANDLE> {
        match &self.pipe {
            Some(h) if h.is_valid() => Ok(h.raw()),
            _ => Err(io::Error::new(io::ErrorKind::NotConnected, "no pipe")),
        }
    }

    fn send_frame(&mut self, opcode: Opcode, payload: &[u8]) -> io::Result<()> {
        let handle = self.pipe_handle()?;
        let len = payload.len() as u32;

        self.send_buf.clear();
        self.send_buf
            .extend_from_slice(&(opcode as u32).to_le_bytes());
        self.send_buf.extend_from_slice(&len.to_le_bytes());
        self.send_buf.extend_from_slice(payload);

        let mut written: u32 = 0;
        let ok = unsafe {
            WriteFile(
                handle,
                self.send_buf.as_ptr(),
                self.send_buf.len() as u32,
                &mut written,
                ptr::null_mut(),
            )
        };
        if ok == 0 || written != self.send_buf.len() as u32 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    fn recv_frame(&mut self) -> io::Result<(Opcode, String)> {
        let handle = self.pipe_handle()?;

        let mut header = [0u8; 8];
        let mut bytes_read: u32 = 0;
        let ok = unsafe {
            ReadFile(
                handle,
                header.as_mut_ptr(),
                8,
                &mut bytes_read,
                ptr::null_mut(),
            )
        };
        if ok == 0 || bytes_read != 8 {
            return Err(io::Error::last_os_error());
        }

        let raw_opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
        let payload_len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;

        let opcode = Opcode::from_u32(raw_opcode)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "unknown opcode"))?;

        if self.recv_buf.len() < payload_len {
            self.recv_buf.resize(payload_len, 0);
        }

        if payload_len > 0 {
            bytes_read = 0;
            let ok = unsafe {
                ReadFile(
                    handle,
                    self.recv_buf.as_mut_ptr(),
                    payload_len as u32,
                    &mut bytes_read,
                    ptr::null_mut(),
                )
            };
            if ok == 0 || (bytes_read as usize) != payload_len {
                return Err(io::Error::last_os_error());
            }
        }

        let payload = String::from_utf8_lossy(&self.recv_buf[..payload_len]).into_owned();
        Ok((opcode, payload))
    }

    fn has_data(&self) -> io::Result<bool> {
        let handle = self.pipe_handle()?;
        let mut available: u32 = 0;
        let ok = unsafe {
            PeekNamedPipe(
                handle,
                ptr::null_mut(),
                0,
                ptr::null_mut(),
                &mut available,
                ptr::null_mut(),
            )
        };
        if ok == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(available > 0)
    }

    fn next_nonce(&mut self) -> u32 {
        let n = self.nonce;
        self.nonce = self.nonce.wrapping_add(1);
        n
    }
}

impl Drop for DiscordIpc {
    fn drop(&mut self) {
        self.disconnect();
    }
}
