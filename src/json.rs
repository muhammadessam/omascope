//! Hand-written JSON for the two seams that need it: the snapshot stream the
//! window reads and the `--json` output agents parse. The shapes are small and
//! fixed, so this is smaller and faster than pulling in a serialiser.

use crate::procs::{Process, Snapshot};

/// Quote a string for JSON. Process names and command lines can contain
/// quotes, backslashes, and control bytes, and a broken line would make the
/// window drop the whole snapshot.
pub fn escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

pub fn process(process: &Process) -> String {
    format!(
        "{{\"pid\":{},\"ppid\":{},\"uid\":{},\"user\":{},\"name\":{},\"state\":{},\"cpu\":{:.1},\"rss\":{},\"threads\":{},\"started\":{},\"cmd\":{}}}",
        process.pid,
        process.ppid,
        process.uid,
        escape(&process.user),
        escape(&process.name),
        escape(&process.state.to_string()),
        process.cpu,
        process.rss,
        process.threads,
        process.started,
        escape(&process.cmd),
    )
}

pub fn snapshot(snapshot: &Snapshot, interval_ms: u64) -> String {
    let mut out = String::with_capacity(64 + snapshot.processes.len() * 160);
    out.push_str(&format!(
        "{{\"type\":\"snapshot\",\"time\":{},\"interval\":{},\"cores\":{},\"cpu\":{:.1},\"memTotal\":{},\"memUsed\":{},\"swapTotal\":{},\"swapUsed\":{},\"load1\":{:.2},",
        snapshot.time,
        interval_ms,
        snapshot.cores,
        snapshot.cpu,
        snapshot.mem_total,
        snapshot.mem_used,
        snapshot.swap_total,
        snapshot.swap_used,
        snapshot.load1
    ));
    match snapshot.temp {
        Some(temp) => out.push_str(&format!("\"temp\":{temp:.1},")),
        None => out.push_str("\"temp\":null,"),
    }
    out.push_str("\"gpus\":[");
    for (index, gpu) in snapshot.gpus.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        out.push_str(&format!(
            "{{\"name\":{},\"util\":{:.1},\"memUsed\":{},\"memTotal\":{},\"temp\":{}}}",
            escape(&gpu.name),
            gpu.util,
            gpu.mem_used,
            gpu.mem_total,
            gpu.temp.map(|value| format!("{value:.1}")).unwrap_or_else(|| "null".into())
        ));
    }
    out.push_str("],\"procs\":[");
    for (index, entry) in snapshot.processes.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        out.push_str(&process(entry));
    }
    out.push_str("]}");
    out
}

pub fn result(ok: bool, pid: i32, signal: &str, message: &str) -> String {
    if ok {
        format!(
            "{{\"type\":\"result\",\"ok\":true,\"pid\":{pid},\"signal\":{}}}",
            escape(signal)
        )
    } else {
        format!(
            "{{\"type\":\"result\",\"ok\":false,\"pid\":{pid},\"signal\":{},\"message\":{}}}",
            escape(signal),
            escape(message)
        )
    }
}

pub fn error(message: &str) -> String {
    format!("{{\"type\":\"error\",\"message\":{}}}", escape(message))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_and_control_bytes_are_escaped() {
        assert_eq!(escape("a\"b"), "\"a\\\"b\"");
        assert_eq!(escape("a\\b"), "\"a\\\\b\"");
        assert_eq!(escape("a\nb"), "\"a\\nb\"");
        assert_eq!(escape("a\u{7}b"), "\"a\\u0007b\"");
    }

    #[test]
    fn a_snapshot_line_parses_back() {
        let snapshot = Snapshot {
            time: 10,
            cores: 4,
            cpu: 22.5,
            mem_total: 1024,
            mem_used: 512,
            swap_total: 2048,
            swap_used: 0,
            temp: Some(48.0),
            load1: 0.25,
            gpus: Vec::new(),
            processes: vec![Process {
                pid: 7,
                ppid: 1,
                uid: 1000,
                user: "ana".into(),
                name: "quote\"d".into(),
                state: 'S',
                cpu: 3.5,
                rss: 2048,
                threads: 2,
                started: 99,
                cmd: "quote\"d --x".into(),
            }],
        };
        let line = snapshot_line(&snapshot);
        assert!(line.contains("\"quote\\\"d\""));
        assert!(line.contains("\"cpu\":3.5"));
        assert!(!line.contains('\n'));
    }

    fn snapshot_line(snapshot: &Snapshot) -> String {
        super::snapshot(snapshot, 1000)
    }
}
