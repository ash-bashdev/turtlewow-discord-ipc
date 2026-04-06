//! Discord Rich Presence IPC client.
//!
//! Speaks the Discord RPC protocol over Windows named pipes:
//! - Binary framing: `[opcode: u32][length: u32][json: u8...]`
//! - Handshake (opcode 0) → READY response
//! - SET_ACTIVITY (opcode 1) to update presence
//!
//! Reference: <https://discord.com/developers/docs/topics/rpc>

use std::io;
use std::ptr;

use windows_sys::Win32::Foundation::{
    CloseHandle, GENERIC_READ, GENERIC_WRITE, HANDLE, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Storage::FileSystem::{CreateFileA, ReadFile, WriteFile, OPEN_EXISTING};
use windows_sys::Win32::System::Pipes::PeekNamedPipe;

/// Discord IPC opcodes.
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

/// RAII wrapper for a Windows HANDLE. Closes on drop.
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

/// Discord IPC connection state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum State {
    Disconnected,
    Connected,
    Ready,
}

/// Discord IPC client. Owns the pipe handle and all buffers.
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

    /// Try to connect to Discord's named pipe (tries ipc-0 through ipc-9).
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
            "Discord IPC pipe not found (tried 0-9)",
        ))
    }

    /// Disconnect and release the pipe handle.
    pub fn disconnect(&mut self) {
        // Best-effort close message
        if self.state == State::Ready {
            let _ = self.send_frame(Opcode::Close, b"{}");
        }
        self.pipe = None; // OwnedHandle::drop closes it
        self.state = State::Disconnected;
    }

    /// Perform the Discord RPC handshake.
    pub fn handshake(&mut self) -> io::Result<()> {
        if self.state != State::Connected {
            return Err(io::Error::new(io::ErrorKind::NotConnected, "not connected"));
        }

        let json = format!("{{\"v\":1,\"client_id\":\"{}\"}}", self.client_id);
        self.send_frame(Opcode::Handshake, json.as_bytes())?;

        let (op, payload) = self.recv_frame()?;
        if op == Opcode::Frame && payload.contains("\"READY\"") {
            self.state = State::Ready;
            Ok(())
        } else {
            Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "handshake did not receive READY",
            ))
        }
    }

    /// Send a SET_ACTIVITY command.
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

        let nonce = self.next_nonce();
        let pid = std::process::id();

        let timestamps = if start_timestamp > 0 {
            format!(",\"timestamps\":{{\"start\":{}}}", start_timestamp)
        } else {
            String::new()
        };

        let assets = {
            let has_large = !large_image.is_empty();
            let has_small = !small_image.is_empty();
            if has_large || has_small {
                let mut parts = Vec::new();
                if has_large {
                    parts.push(format!(
                        "\"large_image\":\"{}\",\"large_text\":\"{}\"",
                        json_escape(large_image),
                        json_escape(large_text)
                    ));
                }
                if has_small {
                    parts.push(format!(
                        "\"small_image\":\"{}\",\"small_text\":\"{}\"",
                        json_escape(small_image),
                        json_escape(small_text)
                    ));
                }
                format!(",\"assets\":{{{}}}", parts.join(","))
            } else {
                String::new()
            }
        };

        let party = if party_size > 0 && party_max > 0 {
            format!(
                ",\"party\":{{\"id\":\"wow-party\",\"size\":[{},{}]}}",
                party_size, party_max
            )
        } else {
            String::new()
        };

        let json = format!(
            concat!(
                "{{",
                "\"cmd\":\"SET_ACTIVITY\",",
                "\"args\":{{",
                "\"pid\":{pid},",
                "\"activity\":{{",
                "\"details\":\"{details}\",",
                "\"state\":\"{state}\"",
                "{timestamps}",
                "{assets}",
                "{party}",
                "}}",
                "}},",
                "\"nonce\":\"{nonce}\"",
                "}}"
            ),
            pid = pid,
            details = json_escape(details),
            state = json_escape(state),
            timestamps = timestamps,
            assets = assets,
            party = party,
            nonce = nonce,
        );

        self.send_frame(Opcode::Frame, json.as_bytes())
    }

    /// Clear the rich presence.
    pub fn clear_activity(&mut self) -> io::Result<()> {
        if self.state != State::Ready {
            return Err(io::Error::new(io::ErrorKind::NotConnected, "not ready"));
        }

        let nonce = self.next_nonce();
        let pid = std::process::id();

        let json = format!(
            concat!(
                "{{",
                "\"cmd\":\"SET_ACTIVITY\",",
                "\"args\":{{\"pid\":{pid},\"activity\":null}},",
                "\"nonce\":\"{nonce}\"",
                "}}"
            ),
            pid = pid,
            nonce = nonce,
        );

        self.send_frame(Opcode::Frame, json.as_bytes())
    }

    /// Drain any pending responses from Discord (pings, closes, etc).
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
                _ => {} // FRAME responses to SET_ACTIVITY -- ignore
            }
        }
        Ok(())
    }

    // --- Private helpers ---

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

        // Read 8-byte header
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

        // Read payload, growing buffer if needed
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

/// Escape a string for safe JSON embedding.
fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {} // skip control chars
            c => out.push(c),
        }
    }
    out
}
