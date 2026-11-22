use nix::libc;
use nix::poll::{poll, PollFd, PollFlags, PollTimeout};
use nix::pty::{openpty, Winsize};
use nix::sys::signal::{sigaction, SaFlags, SigAction, SigHandler, SigSet, Signal};
use nix::sys::termios::{cfmakeraw, tcgetattr, tcsetattr, SetArg, Termios};
use nix::sys::wait::{waitpid, WaitStatus};
use nix::unistd::{dup2, execvp, fork, pipe, read, setsid, write, ForkResult};
use serde::Serialize;
use std::collections::VecDeque;
use std::env;
use std::ffi::CString;
use std::io::Write;
use std::os::fd::{AsFd, AsRawFd, BorrowedFd, OwnedFd, RawFd};
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use vte::{Params, Parser, Perform};

const MAX_ENTRIES: usize = 20;
const MAX_OUTPUT_BYTES: usize = 512 * 1024;
const MAX_INPUT_BYTES: usize = 16 * 1024;

static SIGWINCH_WRITE_FD: AtomicI32 = AtomicI32::new(-1);

extern "C" fn handle_sigwinch(_sig: libc::c_int) {
    let fd = SIGWINCH_WRITE_FD.load(Ordering::Relaxed);
    if fd >= 0 {
        let b: [u8; 1] = [1];
        unsafe {
            libc::write(fd, b.as_ptr() as *const libc::c_void, 1);
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Idle,
    Input,
    Output,
}

#[derive(Clone)]
struct RawEntry {
    command: String,
    exit_code: Option<i32>,
    output_bytes: Vec<u8>,
    cols: u16,
    rows: u16,
}

#[derive(Serialize)]
struct RenderedEntry {
    command: String,
    exit_code: Option<i32>,
    output: Vec<String>,
}

struct RingState {
    phase: Phase,
    in_alt_screen: bool,
    pending_cmd: Option<String>,
    input_bytes: Vec<u8>,
    output_bytes: Vec<u8>,
    cols: u16,
    rows: u16,
    entries: VecDeque<RawEntry>,
}

impl RingState {
    fn new(cols: u16, rows: u16) -> Self {
        Self {
            phase: Phase::Idle,
            in_alt_screen: false,
            pending_cmd: None,
            input_bytes: Vec::new(),
            output_bytes: Vec::new(),
            cols,
            rows,
            entries: VecDeque::with_capacity(MAX_ENTRIES),
        }
    }

    fn record_byte(&mut self, b: u8) {
        if self.in_alt_screen {
            return;
        }
        match self.phase {
            Phase::Input => {
                if self.input_bytes.len() < MAX_INPUT_BYTES {
                    self.input_bytes.push(b);
                }
            }
            Phase::Output => {
                if self.output_bytes.len() < MAX_OUTPUT_BYTES {
                    self.output_bytes.push(b);
                }
            }
            Phase::Idle => {}
        }
    }

    fn rendered(&self) -> Vec<RenderedEntry> {
        self.entries
            .iter()
            .map(|e| RenderedEntry {
                command: e.command.clone(),
                exit_code: e.exit_code,
                output: render_vt_lines(&e.output_bytes, e.rows, e.cols),
            })
            .collect()
    }
}

impl Perform for RingState {
    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], _ignore: bool, action: char) {
        if intermediates == b"?" && (action == 'h' || action == 'l') {
            let entering = action == 'h';
            for p in params.iter() {
                if matches!(p, [1049] | [1047] | [47]) {
                    self.in_alt_screen = entering;
                }
            }
        }
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        if params.first().copied() == Some(b"777")
            && params.get(1).copied() == Some(b"pty-ring-cmd")
        {
            if let Some(hex) = params.get(2) {
                if let Some(decoded) = decode_hex(hex) {
                    self.pending_cmd = Some(decoded);
                }
            }
            return;
        }

        if params.first().copied() != Some(b"133") {
            return;
        }
        let Some(kind) = params.get(1).copied() else {
            return;
        };
        match kind {
            b"A" => {
                self.phase = Phase::Idle;
                self.pending_cmd = None;
                self.input_bytes.clear();
            }
            b"B" => {
                self.phase = Phase::Input;
                self.input_bytes.clear();
            }
            b"C" => {
                self.phase = Phase::Output;
                self.output_bytes.clear();
            }
            b"D" => {
                if self.phase == Phase::Output {
                    let exit_code = params
                        .get(2)
                        .and_then(|b| std::str::from_utf8(b).ok())
                        .and_then(|s| s.parse::<i32>().ok());
                    let cmd = self
                        .pending_cmd
                        .take()
                        .unwrap_or_else(|| {
                            render_vt_lines(&self.input_bytes, 4, self.cols)
                                .join(" ")
                                .trim()
                                .to_string()
                        });
                    let is_out_cmd = cmd.split_whitespace().next() == Some("out");
                    if !is_out_cmd && (!cmd.is_empty() || !self.output_bytes.is_empty()) {
                        if self.entries.len() >= MAX_ENTRIES {
                            self.entries.pop_front();
                        }
                        self.entries.push_back(RawEntry {
                            command: cmd,
                            exit_code,
                            output_bytes: std::mem::take(&mut self.output_bytes),
                            cols: self.cols,
                            rows: self.rows,
                        });
                    } else {
                        self.output_bytes.clear();
                    }
                }
                self.phase = Phase::Idle;
                self.pending_cmd = None;
                self.input_bytes.clear();
            }
            _ => {}
        }
    }
}

fn decode_hex(bytes: &[u8]) -> Option<String> {
    let s = std::str::from_utf8(bytes).ok()?;
    if s.len() % 2 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(s.len() / 2);
    for chunk in s.as_bytes().chunks_exact(2) {
        let hex_str = std::str::from_utf8(chunk).ok()?;
        let val = u8::from_str_radix(hex_str, 16).ok()?;
        out.push(val);
    }
    String::from_utf8(out).ok()
}

fn render_vt_lines(raw: &[u8], rows: u16, cols: u16) -> Vec<String> {
    if raw.is_empty() {
        return Vec::new();
    }
    let mut parser = vt100::Parser::new(rows.max(24), cols.max(120), 10_000);
    parser.process(raw);
    let screen = parser.screen();
    let contents = screen.contents();
    let mut lines: Vec<String> = contents.lines().map(|l| l.trim_end().to_string()).collect();
    while lines.first().is_some_and(|l| l.is_empty()) {
        lines.remove(0);
    }
    while lines.last().is_some_and(|l| l.is_empty()) {
        lines.pop();
    }
    lines
}

struct TermiosGuard {
    fd: RawFd,
    orig: Termios,
}

impl Drop for TermiosGuard {
    fn drop(&mut self) {
        let borrowed = unsafe { BorrowedFd::borrow_raw(self.fd) };
        let _ = tcsetattr(borrowed, SetArg::TCSANOW, &self.orig);
    }
}

struct SocketGuard(PathBuf);

impl Drop for SocketGuard {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

fn get_winsize(fd: RawFd) -> Winsize {
    let mut ws = Winsize {
        ws_row: 24,
        ws_col: 80,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    unsafe {
        libc::ioctl(fd, libc::TIOCGWINSZ, &mut ws);
    }
    if ws.ws_row == 0 {
        ws.ws_row = 24;
    }
    if ws.ws_col == 0 {
        ws.ws_col = 80;
    }
    ws
}

fn set_winsize(fd: RawFd, ws: &Winsize) {
    unsafe {
        libc::ioctl(fd, libc::TIOCSWINSZ, ws);
    }
}

fn write_all_fd(fd: BorrowedFd<'_>, mut buf: &[u8]) -> std::io::Result<()> {
    while !buf.is_empty() {
        match write(fd, buf) {
            Ok(0) => break,
            Ok(n) => buf = &buf[n..],
            Err(nix::errno::Errno::EINTR | nix::errno::Errno::EAGAIN) => continue,
            Err(e) => return Err(std::io::Error::from_raw_os_error(e as i32)),
        }
    }
    Ok(())
}

fn make_socket_path() -> PathBuf {
    let pid = std::process::id();
    let base = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|p| p.is_dir())
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join(format!("pty-ring-{pid}.sock"))
}

fn spawn_socket_server(sock_path: &Path, state: Arc<Mutex<RingState>>) -> std::io::Result<()> {
    let _ = std::fs::remove_file(sock_path);
    let listener = UnixListener::bind(sock_path)?;
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut conn) = stream else { break };
            let payload = {
                let guard = state.lock().unwrap();
                serde_json::to_vec(&guard.rendered()).unwrap_or_else(|_| b"[]".to_vec())
            };
            let _ = conn.write_all(&payload);
            let _ = conn.write_all(b"\n");
        }
    });
    Ok(())
}

fn main() {
    let mut args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        args.push(env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string()));
    }

    let stdin_fd = libc::STDIN_FILENO;
    let stdout_fd = libc::STDOUT_FILENO;
    let stdin_borrowed = unsafe { BorrowedFd::borrow_raw(stdin_fd) };
    let stdout_borrowed = unsafe { BorrowedFd::borrow_raw(stdout_fd) };

    let orig_termios = tcgetattr(stdin_borrowed).ok();
    let ws = get_winsize(stdin_fd);

    let pty = openpty(Some(&ws), None).expect("openpty failed");
    let sock_path = make_socket_path();
    let state = Arc::new(Mutex::new(RingState::new(ws.ws_col, ws.ws_row)));
    let _sock_guard = SocketGuard(sock_path.clone());
    let _ = spawn_socket_server(&sock_path, Arc::clone(&state));

    match unsafe { fork() }.expect("fork failed") {
        ForkResult::Child => {
            drop(pty.master);
            let _ = setsid();
            unsafe {
                libc::ioctl(pty.slave.as_raw_fd(), libc::TIOCSCTTY as _, 0);
            }
            let slave_raw = pty.slave.as_raw_fd();
            let _ = dup2(slave_raw, libc::STDIN_FILENO);
            let _ = dup2(slave_raw, libc::STDOUT_FILENO);
            let _ = dup2(slave_raw, libc::STDERR_FILENO);
            if slave_raw > libc::STDERR_FILENO {
                drop(pty.slave);
            }
            env::set_var("PTY_RING_SOCK", &sock_path);

            let prog = CString::new(args[0].as_str()).unwrap();
            let cargs: Vec<CString> = args.iter().map(|a| CString::new(a.as_str()).unwrap()).collect();
            let _ = execvp(&prog, &cargs);
            std::process::exit(127);
        }
        ForkResult::Parent { child } => {
            drop(pty.slave);

            let _termios_guard = orig_termios.map(|orig| {
                let mut raw = orig.clone();
                cfmakeraw(&mut raw);
                let _ = tcsetattr(stdin_borrowed, SetArg::TCSANOW, &raw);
                TermiosGuard { fd: stdin_fd, orig }
            });

            let (winch_r, winch_w): (OwnedFd, OwnedFd) = pipe().expect("pipe failed");
            SIGWINCH_WRITE_FD.store(winch_w.as_raw_fd(), Ordering::Relaxed);
            let sig_action = SigAction::new(
                SigHandler::Handler(handle_sigwinch),
                SaFlags::SA_RESTART,
                SigSet::empty(),
            );
            unsafe {
                let _ = sigaction(Signal::SIGWINCH, &sig_action);
            }

            let mut vte_parser = Parser::new();
            let mut buf = [0u8; 8192];
            let mut stdin_open = true;

            loop {
                let mut fds = Vec::with_capacity(3);
                fds.push(PollFd::new(pty.master.as_fd(), PollFlags::POLLIN));
                fds.push(PollFd::new(winch_r.as_fd(), PollFlags::POLLIN));
                if stdin_open {
                    fds.push(PollFd::new(stdin_borrowed, PollFlags::POLLIN));
                }

                match poll(&mut fds, PollTimeout::NONE) {
                    Ok(_) => {}
                    Err(nix::errno::Errno::EINTR) => continue,
                    Err(_) => break,
                }

                let master_rev = fds[0].revents().unwrap_or(PollFlags::empty());
                if master_rev.contains(PollFlags::POLLIN) {
                    match read(pty.master.as_raw_fd(), &mut buf) {
                        Ok(0) | Err(_) => break,
                        Ok(n) => {
                            let chunk = &buf[..n];
                            let _ = write_all_fd(stdout_borrowed, chunk);
                            let mut guard = state.lock().unwrap();
                            for &b in chunk {
                                vte_parser.advance(&mut *guard, &[b]);
                                guard.record_byte(b);
                            }
                        }
                    }
                } else if master_rev.intersects(PollFlags::POLLHUP | PollFlags::POLLERR) {
                    break;
                }

                let winch_rev = fds[1].revents().unwrap_or(PollFlags::empty());
                if winch_rev.contains(PollFlags::POLLIN) {
                    let mut drain = [0u8; 64];
                    let _ = read(winch_r.as_raw_fd(), &mut drain);
                    let new_ws = get_winsize(stdin_fd);
                    set_winsize(pty.master.as_raw_fd(), &new_ws);
                    let mut guard = state.lock().unwrap();
                    guard.cols = new_ws.ws_col;
                    guard.rows = new_ws.ws_row;
                }

                if stdin_open && fds.len() > 2 {
                    let stdin_rev = fds[2].revents().unwrap_or(PollFlags::empty());
                    if stdin_rev.contains(PollFlags::POLLIN) {
                        match read(stdin_fd, &mut buf) {
                            Ok(0) | Err(_) => stdin_open = false,
                            Ok(n) => {
                                let _ = write_all_fd(pty.master.as_fd(), &buf[..n]);
                            }
                        }
                    } else if stdin_rev.intersects(PollFlags::POLLHUP | PollFlags::POLLERR) {
                        stdin_open = false;
                    }
                }
            }

            drop(pty.master);
            let exit_code = match waitpid(child, None) {
                Ok(WaitStatus::Exited(_, code)) => code,
                Ok(WaitStatus::Signaled(_, sig, _)) => 128 + sig as i32,
                _ => 0,
            };
            drop(_termios_guard);
            drop(_sock_guard);
            std::process::exit(exit_code);
        }
    }
}
