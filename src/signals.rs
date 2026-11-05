//! Signals by name, and the one syscall the app needs beyond the standard
//! library. `libc` is declared here rather than added as a dependency.

use std::io;

extern "C" {
    fn kill(pid: i32, signal: i32) -> i32;
}

pub const TERM: i32 = 15;
pub const KILL: i32 = 9;
pub const INT: i32 = 2;
pub const HUP: i32 = 1;
pub const QUIT: i32 = 3;
pub const STOP: i32 = 19;
pub const CONT: i32 = 18;
pub const USR1: i32 = 10;
pub const USR2: i32 = 12;

/// Signals a process manager offers by name, in menu order.
pub const NAMED: &[(&str, i32)] = &[
    ("TERM", TERM),
    ("KILL", KILL),
    ("INT", INT),
    ("HUP", HUP),
    ("QUIT", QUIT),
    ("STOP", STOP),
    ("CONT", CONT),
    ("USR1", USR1),
    ("USR2", USR2),
];

/// Resolve `TERM`, `SIGTERM`, `term`, or a number to a signal number.
pub fn parse(name: &str) -> Option<i32> {
    let upper = name.trim().to_ascii_uppercase();
    let bare = upper.strip_prefix("SIG").unwrap_or(&upper);
    if let Some((_, number)) = NAMED.iter().find(|(label, _)| *label == bare) {
        return Some(*number);
    }
    let number = bare.parse::<i32>().ok()?;
    (1..=64).contains(&number).then_some(number)
}

/// The name to show for a signal number, for status lines and JSON.
pub fn label(number: i32) -> String {
    NAMED
        .iter()
        .find(|(_, value)| *value == number)
        .map(|(label, _)| (*label).to_string())
        .unwrap_or_else(|| number.to_string())
}

/// Why a signal would be refused before it is sent. These are the mistakes
/// worth naming in the window rather than translating an errno later.
pub fn refusal(pid: i32) -> Option<String> {
    if pid <= 1 {
        return Some("Process 1 is the init system and cannot be signalled from here.".into());
    }
    if pid == std::process::id() as i32 {
        return Some("That is omascope itself.".into());
    }
    None
}

/// Send one signal, with the kernel's own reason when it refuses.
pub fn send(pid: i32, signal: i32) -> Result<(), String> {
    if let Some(reason) = refusal(pid) {
        return Err(reason);
    }
    let status = unsafe { kill(pid, signal) };
    if status == 0 {
        return Ok(());
    }
    Err(describe(io::Error::last_os_error()))
}

fn describe(error: io::Error) -> String {
    match error.raw_os_error() {
        Some(1) => "Permission denied. That process belongs to another user.".into(),
        Some(3) => "No such process. It may have exited already.".into(),
        Some(22) => "That signal is not valid here.".into(),
        _ => error.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_and_numbers_resolve() {
        assert_eq!(parse("TERM"), Some(15));
        assert_eq!(parse("sigkill"), Some(9));
        assert_eq!(parse("2"), Some(2));
        assert_eq!(parse("nonsense"), None);
        assert_eq!(parse("0"), None);
        assert_eq!(parse("99"), None);
        assert_eq!(label(9), "KILL");
        assert_eq!(label(40), "40");
    }

    #[test]
    fn init_and_self_are_refused_before_the_syscall() {
        assert!(refusal(1).is_some());
        assert!(refusal(std::process::id() as i32).is_some());
        assert!(refusal(4242).is_none());
    }

    #[test]
    fn a_missing_process_is_named_not_raw_errno() {
        let message = send(2_147_000_000, TERM).unwrap_err();
        assert!(message.contains("No such process"), "got {message}");
    }
}
