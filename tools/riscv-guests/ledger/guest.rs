//! A freestanding Rust guest for gno.land: no std, no alloc, no runtime.
//!
//! It reads a little ledger script from the call input, applies it, and writes
//! the resulting balances back. Three syscalls, one allocation-free parser, and
//! nothing about it knows what a realm is.
//!
//!   mint alice 100
//!   mint bob 50
//!   send alice bob 30
//!
//! prints
//!
//!   alice 70
//!   bob 80
//!
//! An unknown command, an unknown name or an overdraft is a refusal: the line
//! is reported and the program exits non-zero, which the host reports as halted
//! rather than trapped, because the program said no and the VM did not break.

#![no_std]
#![no_main]

const SYS_READ: usize = 63;
const SYS_WRITE: usize = 64;
const SYS_EXIT: usize = 93;

#[inline(always)]
unsafe fn syscall3(n: usize, a0: usize, a1: usize, a2: usize) -> isize {
    let ret: isize;
    core::arch::asm!(
        "ecall",
        in("a7") n,
        inlateout("a0") a0 as isize => ret,
        in("a1") a1,
        in("a2") a2,
        options(nostack),
    );
    ret
}

fn write(buf: &[u8]) {
    unsafe { syscall3(SYS_WRITE, 1, buf.as_ptr() as usize, buf.len()) };
}

fn exit(code: usize) -> ! {
    unsafe { syscall3(SYS_EXIT, code, 0, 0) };
    loop {}
}

/// A panic here is a bug in this program, not a refusal, so it exits with a
/// distinct code instead of pretending the ledger balanced.
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    write(b"panic\n");
    exit(2)
}

const MAX_ACCOUNTS: usize = 16;
const MAX_NAME: usize = 24;

struct Ledger {
    names: [[u8; MAX_NAME]; MAX_ACCOUNTS],
    lens: [u8; MAX_ACCOUNTS],
    balances: [i64; MAX_ACCOUNTS],
    count: usize,
}

impl Ledger {
    const fn new() -> Self {
        Ledger {
            names: [[0; MAX_NAME]; MAX_ACCOUNTS],
            lens: [0; MAX_ACCOUNTS],
            balances: [0; MAX_ACCOUNTS],
            count: 0,
        }
    }

    fn find(&self, name: &[u8]) -> Option<usize> {
        for i in 0..self.count {
            let n = self.lens[i] as usize;
            if n == name.len() && self.names[i][..n] == *name {
                return Some(i);
            }
        }
        None
    }

    /// intern returns the slot for a name, creating it at zero if the ledger
    /// has room. A full ledger is a refusal, not a silent overwrite.
    fn intern(&mut self, name: &[u8]) -> Option<usize> {
        if let Some(i) = self.find(name) {
            return Some(i);
        }
        if self.count == MAX_ACCOUNTS || name.is_empty() || name.len() > MAX_NAME {
            return None;
        }
        let i = self.count;
        for (k, b) in name.iter().enumerate() {
            self.names[i][k] = *b;
        }
        self.lens[i] = name.len() as u8;
        self.count += 1;
        Some(i)
    }
}

static mut LEDGER: Ledger = Ledger::new();
static mut INPUT: [u8; 1024] = [0; 1024];
static mut OUT: [u8; 512] = [0; 512];

fn is_space(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r'
}

/// field splits off the next whitespace-delimited token, returning it and the
/// rest. No allocation and no iterator adaptors that would drag in formatting
/// machinery.
fn field(s: &[u8]) -> (&[u8], &[u8]) {
    let mut i = 0;
    while i < s.len() && is_space(s[i]) {
        i += 1;
    }
    let start = i;
    while i < s.len() && !is_space(s[i]) {
        i += 1;
    }
    (&s[start..i], &s[i..])
}

fn parse_u32(s: &[u8]) -> Option<i64> {
    if s.is_empty() || s.len() > 9 {
        return None;
    }
    let mut v: i64 = 0;
    for c in s {
        if *c < b'0' || *c > b'9' {
            return None;
        }
        v = v * 10 + (*c - b'0') as i64;
    }
    Some(v)
}

struct Out {
    n: usize,
}

impl Out {
    fn push(&mut self, b: &[u8]) {
        let buf = unsafe { &mut *core::ptr::addr_of_mut!(OUT) };
        for c in b {
            if self.n < buf.len() {
                buf[self.n] = *c;
                self.n += 1;
            }
        }
    }

    fn push_num(&mut self, mut v: i64) {
        if v == 0 {
            self.push(b"0");
            return;
        }
        let mut tmp = [0u8; 20];
        let mut i = tmp.len();
        while v > 0 {
            i -= 1;
            tmp[i] = b'0' + (v % 10) as u8;
            v /= 10;
        }
        self.push(&tmp[i..]);
    }

    fn flush(&self) {
        let buf = unsafe { &*core::ptr::addr_of!(OUT) };
        write(&buf[..self.n]);
    }
}

/// apply runs one line. Err(reason) is a refusal, and it names the reason.
fn apply(line: &[u8], led: &mut Ledger) -> Result<(), &'static str> {
    let (cmd, rest) = field(line);
    if cmd.is_empty() {
        return Ok(()); // a blank line is not an error
    }
    match cmd {
        b"mint" => {
            let (who, rest) = field(rest);
            let (amount, _) = field(rest);
            let n = parse_u32(amount).ok_or("bad amount")?;
            let i = led.intern(who).ok_or("ledger full or bad name")?;
            led.balances[i] += n;
            Ok(())
        }
        b"send" => {
            let (from, rest) = field(rest);
            let (to, rest) = field(rest);
            let (amount, _) = field(rest);
            let n = parse_u32(amount).ok_or("bad amount")?;
            let fi = led.find(from).ok_or("unknown sender")?;
            if led.balances[fi] < n {
                return Err("insufficient balance");
            }
            let ti = led.intern(to).ok_or("ledger full or bad name")?;
            led.balances[fi] -= n;
            led.balances[ti] += n;
            Ok(())
        }
        b"burn" => {
            let (who, rest) = field(rest);
            let (amount, _) = field(rest);
            let n = parse_u32(amount).ok_or("bad amount")?;
            let i = led.find(who).ok_or("unknown account")?;
            if led.balances[i] < n {
                return Err("insufficient balance");
            }
            led.balances[i] -= n;
            Ok(())
        }
        _ => Err("unknown command"),
    }
}

#[no_mangle]
pub extern "C" fn _start() -> ! {
    let input = unsafe { &mut *core::ptr::addr_of_mut!(INPUT) };
    let n = unsafe { syscall3(SYS_READ, 0, input.as_mut_ptr() as usize, input.len()) };
    let n = if n < 0 { 0 } else { n as usize };

    let led = unsafe { &mut *core::ptr::addr_of_mut!(LEDGER) };
    let mut out = Out { n: 0 };

    let mut start = 0;
    let mut lineno = 0;
    while start <= n {
        let mut end = start;
        while end < n && input[end] != b'\n' {
            end += 1;
        }
        if end > start {
            lineno += 1;
            if let Err(why) = apply(&input[start..end], led) {
                out.push(b"line ");
                out.push_num(lineno);
                out.push(b": ");
                out.push(why.as_bytes());
                out.push(b"\n");
                out.flush();
                exit(1);
            }
        }
        if end >= n {
            break;
        }
        start = end + 1;
    }

    for i in 0..led.count {
        let l = led.lens[i] as usize;
        out.push(&led.names[i][..l]);
        out.push(b" ");
        out.push_num(led.balances[i]);
        out.push(b"\n");
    }
    out.flush();
    exit(0)
}
