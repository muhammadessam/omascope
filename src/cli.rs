//! The command line. The window is one front end; these are the others, and
//! they are what an agent can drive without a display.

use std::env;
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use crate::demo;
use crate::gpu;
use crate::json;
use crate::procs::{Process, Sampler};
use crate::signals;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const SKILL: &str = include_str!("../resources/agent-skill.md");

pub fn run(args: Vec<String>) -> i32 {
    let Some(command) = args.first().map(String::as_str) else {
        return open();
    };
    let rest = &args[1..];

    match command {
        "open" | "--gui" => open(),
        "serve" => serve(rest),
        "ps" => ps(rest),
        "kill" => kill(rest),
        "skill" => skill(rest),
        "--version" | "-V" | "version" => {
            println!("omascope {VERSION}");
            0
        }
        "--help" | "-h" | "help" => {
            print_help();
            0
        }
        // A bare number is a PID to explain, mirroring `ps`.
        other if other.parse::<i32>().is_ok() => ps(rest),
        other => {
            eprintln!("omascope: unknown command '{other}'");
            print_help();
            1
        }
    }
}

fn print_help() {
    println!(
        "omascope {VERSION} — keyboard-first process manager for Omarchy

Usage:
  omascope                     Open the window
  omascope open                Open the window
  omascope ps [options]        List processes
  omascope kill PID... [opts]  Send a signal to processes
  omascope skill install       Install the bundled agent skill
  omascope serve               Stream snapshots (what the window reads)

ps options:
  --json               Print machine-readable JSON
  --sort cpu|mem|name|pid   Order (default cpu)
  --limit N            Print only the first N rows
  --filter TEXT        Match name, command, user, or PID

kill options:
  --signal NAME        TERM (default), KILL, INT, HUP, QUIT, STOP, CONT, USR1, USR2
  --json               Print machine-readable JSON

Every command exits 0 on success and 1 with a message on stderr otherwise."
    );
}

// ---------------------------------------------------------------- the window

fn open() -> i32 {
    let Some(ui) = ui_directory() else {
        eprintln!("omascope: cannot find the interface. Reinstall the package, or set OMASCOPE_UI.");
        return 1;
    };
    let Some(quickshell) = find_in_path("qs").or_else(|| find_in_path("quickshell")) else {
        eprintln!("omascope: quickshell is not installed. Install it with 'omarchy-pkg-add quickshell'.");
        return 1;
    };
    let binary = env::current_exe().unwrap_or_else(|_| PathBuf::from("omascope"));

    // exec rather than spawn: the window is this process, so closing it ends
    // the command and the terminal keeps the same job.
    use std::os::unix::process::CommandExt;
    let error = Command::new(quickshell)
        .arg("-p")
        .arg(&ui)
        .env("OMASCOPE_BIN", &binary)
        .env("OMASCOPE_UI", &ui)
        .exec();
    eprintln!("omascope: could not start quickshell: {error}");
    1
}

fn ui_directory() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(configured) = env::var_os("OMASCOPE_UI") {
        candidates.push(PathBuf::from(configured));
    }
    if let Ok(exe) = env::current_exe() {
        if let Some(root) = exe.parent().and_then(Path::parent) {
            candidates.push(root.join("share/omascope/ui"));
        }
    }
    candidates.push(PathBuf::from("/usr/share/omascope/ui"));
    candidates.push(PathBuf::from("ui"));
    candidates
        .into_iter()
        .find(|candidate| candidate.join("shell.qml").is_file())
}

fn find_in_path(name: &str) -> Option<PathBuf> {
    env::var_os("PATH").and_then(|paths| {
        env::split_paths(&paths)
            .map(|directory| directory.join(name))
            .find(|candidate| candidate.is_file())
    })
}

// -------------------------------------------------------------------- serve

/// Streams one JSON snapshot per line and answers kill commands with one line
/// each. The window owns the pipe, so a closed stdin means the window is gone
/// and the sampler stops with it.
fn serve(args: &[String]) -> i32 {
    let mut interval_ms = 1000u64;
    let mut once = false;
    let mut demo_mode = false;
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--interval" => {
                interval_ms = args.get(index + 1).and_then(|value| value.parse().ok()).unwrap_or(1000);
                interval_ms = interval_ms.clamp(200, 60_000);
                index += 2;
            }
            "--once" => {
                once = true;
                index += 1;
            }
            "--demo" => {
                demo_mode = true;
                index += 1;
            }
            other => {
                eprintln!("omascope: serve does not take '{other}'");
                return 1;
            }
        }
    }

    let mut sampler = Sampler::new();
    let mut fake = demo::Demo::new();
    let gpus = gpu::Monitor::start();
    let mut stdout = io::stdout();
    let mut emit = |line: String| -> bool {
        writeln!(stdout, "{line}").is_ok() && stdout.flush().is_ok()
    };

    if once {
        let mut snapshot = if demo_mode { fake.sample() } else { sampler.sample() };
        if !demo_mode { snapshot.gpus = gpus.current(); }
        return if emit(json::snapshot(&snapshot, interval_ms)) { 0 } else { 1 };
    }

    if !emit(format!(
        "{{\"type\":\"hello\",\"version\":\"{VERSION}\",\"pid\":{}}}",
        std::process::id()
    )) {
        return 0;
    }

    let (sender, receiver) = mpsc::channel::<Option<String>>();
    thread::spawn(move || {
        let stdin = io::stdin();
        for line in stdin.lock().lines() {
            match line {
                Ok(line) => {
                    if sender.send(Some(line)).is_err() {
                        return;
                    }
                }
                Err(_) => break,
            }
        }
        let _ = sender.send(None);
    });

    let interval = Duration::from_millis(interval_ms);
    let mut interactive = true;
    loop {
        let started = Instant::now();
        let mut snapshot = if demo_mode { fake.sample() } else { sampler.sample() };
        if !demo_mode { snapshot.gpus = gpus.current(); }
        if !emit(json::snapshot(&snapshot, interval_ms)) {
            return 0;
        }

        loop {
            let remaining = interval.saturating_sub(started.elapsed());
            if remaining.is_zero() {
                break;
            }
            if !interactive {
                // Without a writer the window is gone; the write above fails on
                // the next pass and ends the sampler.
                thread::sleep(remaining);
                break;
            }
            match receiver.recv_timeout(remaining) {
                Ok(Some(line)) => {
                    if !handle(&line, if demo_mode { Some(&mut fake) } else { None }, &mut emit) {
                        return 0;
                    }
                    // A kill changes the table now, so take a fresh sample
                    // instead of waiting out the rest of the second.
                    break;
                }
                Ok(None) | Err(mpsc::RecvTimeoutError::Disconnected) => {
                    interactive = false;
                    break;
                }
                Err(mpsc::RecvTimeoutError::Timeout) => break,
            }
        }
    }
}

/// One command from the window. Returns false when the sampler should stop.
fn handle(line: &str, demo: Option<&mut demo::Demo>, emit: &mut impl FnMut(String) -> bool) -> bool {
    let mut fields = line.split_whitespace();
    match fields.next() {
        Some("quit") => false,
        Some("kill") => {
            let Some(pid) = fields.next().and_then(|value| value.parse::<i32>().ok()) else {
                return emit(json::error("kill needs a PID"));
            };
            let signal = fields
                .next()
                .and_then(signals::parse)
                .unwrap_or(signals::TERM);
            let label = signals::label(signal);
            if let Some(fake) = demo {
                // The preview must never touch a real process.
                if signals::refusal(pid).is_none() {
                    fake.kill(pid);
                    return emit(json::result(true, pid, &label, ""));
                }
            }
            match signals::send(pid, signal) {
                Ok(()) => emit(json::result(true, pid, &label, "")),
                Err(message) => emit(json::result(false, pid, &label, &message)),
            }
        }
        Some("refresh") => true,
        Some(other) => emit(json::error(&format!("unknown command '{other}'"))),
        None => true,
    }
}

// ----------------------------------------------------------------------- ps

#[derive(Clone, Copy, PartialEq)]
enum Sort {
    Cpu,
    Memory,
    Name,
    Pid,
}

fn ps(args: &[String]) -> i32 {
    let mut as_json = false;
    let mut sort = Sort::Cpu;
    let mut limit = usize::MAX;
    let mut filter = String::new();
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--json" => as_json = true,
            "--sort" => {
                sort = match args.get(index + 1).map(String::as_str) {
                    Some("cpu") => Sort::Cpu,
                    Some("mem" | "memory") => Sort::Memory,
                    Some("name") => Sort::Name,
                    Some("pid") => Sort::Pid,
                    other => {
                        eprintln!("omascope: unknown sort '{}'; use cpu, mem, name, or pid", other.unwrap_or(""));
                        return 1;
                    }
                };
                index += 1;
            }
            "--limit" => {
                match args.get(index + 1).and_then(|value| value.parse::<usize>().ok()) {
                    Some(value) => limit = value,
                    None => {
                        eprintln!("omascope: --limit needs a number");
                        return 1;
                    }
                }
                index += 1;
            }
            "--filter" => {
                filter = args.get(index + 1).cloned().unwrap_or_default();
                index += 1;
            }
            other => {
                eprintln!("omascope: ps does not take '{other}'");
                return 1;
            }
        }
        index += 1;
    }

    let mut snapshot = Sampler::new().sample();
    let needle = filter.to_lowercase();
    if !needle.is_empty() {
        snapshot.processes.retain(|process| {
            process.name.to_lowercase().contains(&needle)
                || process.cmd.to_lowercase().contains(&needle)
                || process.user.to_lowercase().contains(&needle)
                || process.pid.to_string() == needle
        });
    }
    sort_processes(&mut snapshot.processes, sort);
    snapshot.processes.truncate(limit);

    if as_json {
        snapshot.gpus = gpu::sample();
        println!(
            "{{\"type\":\"processes\",\"time\":{},\"cores\":{},\"cpu\":{:.1},\"gpus\":[{}],\"count\":{},\"procs\":[{}]}}",
            snapshot.time,
            snapshot.cores,
            snapshot.cpu,
            snapshot
                .gpus
                .iter()
                .map(|gpu| format!(
                    "{{\"name\":{},\"util\":{:.1},\"memUsed\":{},\"memTotal\":{},\"temp\":{}}}",
                    json::escape(&gpu.name),
                    gpu.util,
                    gpu.mem_used,
                    gpu.mem_total,
                    gpu.temp.map(|value| format!("{value:.1}")).unwrap_or_else(|| "null".into())
                ))
                .collect::<Vec<_>>()
                .join(","),
            snapshot.processes.len(),
            snapshot
                .processes
                .iter()
                .map(json::process)
                .collect::<Vec<_>>()
                .join(",")
        );
        return 0;
    }

    println!(
        "{:>7}  {:<22} {:>6} {:>8}  {:<12} {}",
        "PID", "NAME", "CPU%", "MEM", "USER", "COMMAND"
    );
    for process in &snapshot.processes {
        println!(
            "{:>7}  {:<22} {:>6.1} {:>8}  {:<12} {}",
            process.pid,
            clip(&process.name, 22),
            process.cpu,
            human_bytes(process.rss),
            clip(&process.user, 12),
            clip(&process.cmd, 110)
        );
    }
    0
}

fn sort_processes(processes: &mut [Process], sort: Sort) {
    match sort {
        Sort::Cpu => processes.sort_by(|a, b| b.cpu.total_cmp(&a.cpu).then(a.pid.cmp(&b.pid))),
        Sort::Memory => processes.sort_by(|a, b| b.rss.cmp(&a.rss).then(a.pid.cmp(&b.pid))),
        Sort::Name => {
            processes.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then(a.pid.cmp(&b.pid)))
        }
        Sort::Pid => processes.sort_by_key(|process| process.pid),
    }
}

fn clip(value: &str, width: usize) -> String {
    if value.chars().count() <= width {
        return value.to_string();
    }
    let mut clipped: String = value.chars().take(width.saturating_sub(1)).collect();
    clipped.push('…');
    clipped
}

fn human_bytes(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "K", "M", "G", "T"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{}{}", bytes, UNITS[unit])
    } else {
        format!("{value:.1}{}", UNITS[unit])
    }
}

// --------------------------------------------------------------------- kill

fn kill(args: &[String]) -> i32 {
    let mut pids = Vec::new();
    let mut signal = signals::TERM;
    let mut as_json = false;
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--json" => as_json = true,
            "--signal" | "-s" => {
                match args.get(index + 1).and_then(|value| signals::parse(value)) {
                    Some(value) => signal = value,
                    None => {
                        eprintln!("omascope: --signal needs a name like TERM or KILL");
                        return 1;
                    }
                }
                index += 1;
            }
            value => match value.parse::<i32>() {
                Ok(pid) => pids.push(pid),
                Err(_) => {
                    eprintln!("omascope: '{value}' is not a PID");
                    return 1;
                }
            },
        }
        index += 1;
    }
    if pids.is_empty() {
        eprintln!("omascope: kill needs at least one PID");
        return 1;
    }

    let label = signals::label(signal);
    let mut results = Vec::new();
    let mut failed = false;
    for pid in pids {
        let outcome = signals::send(pid, signal);
        if outcome.is_err() {
            failed = true;
        }
        results.push((pid, outcome));
    }

    if as_json {
        let body = results
            .iter()
            .map(|(pid, outcome)| match outcome {
                Ok(()) => format!(
                    "{{\"pid\":{pid},\"signal\":{},\"ok\":true}}",
                    json::escape(&label)
                ),
                Err(message) => format!(
                    "{{\"pid\":{pid},\"signal\":{},\"ok\":false,\"message\":{}}}",
                    json::escape(&label),
                    json::escape(message)
                ),
            })
            .collect::<Vec<_>>()
            .join(",");
        println!("{{\"type\":\"kill\",\"results\":[{body}]}}");
    } else {
        for (pid, outcome) in &results {
            match outcome {
                Ok(()) => println!("{pid}: sent {label}"),
                Err(message) => eprintln!("{pid}: {message}"),
            }
        }
    }
    if failed {
        1
    } else {
        0
    }
}

// -------------------------------------------------------------------- skill

fn skill(args: &[String]) -> i32 {
    let Some(action) = args.first().map(String::as_str) else {
        eprintln!("omascope: skill needs 'install'");
        return 1;
    };
    if action != "install" {
        eprintln!("omascope: skill needs 'install'");
        return 1;
    }

    let mut directory: Option<PathBuf> = None;
    let mut as_json = false;
    let mut index = 1;
    while index < args.len() {
        match args[index].as_str() {
            "--json" => as_json = true,
            "--dir" => {
                directory = args.get(index + 1).map(PathBuf::from);
                if directory.is_none() {
                    eprintln!("omascope: --dir needs a path");
                    return 1;
                }
                index += 1;
            }
            other => {
                eprintln!("omascope: skill does not take '{other}'");
                return 1;
            }
        }
        index += 1;
    }

    let directory = directory.unwrap_or_else(default_skill_directory);
    let target = directory.join("omascope").join("SKILL.md");
    if let Some(parent) = target.parent() {
        if let Err(error) = std::fs::create_dir_all(parent) {
            let message = format!("could not create {}: {error}", parent.display());
            return skill_error(&message, as_json);
        }
    }
    if let Err(error) = std::fs::write(&target, SKILL) {
        let message = format!("could not write {}: {error}", target.display());
        return skill_error(&message, as_json);
    }

    if as_json {
        println!(
            "{{\"type\":\"skill\",\"path\":{}}}",
            json::escape(&target.display().to_string())
        );
    } else {
        println!("Installed omascope's agent skill at {}", target.display());
    }
    0
}

fn skill_error(message: &str, as_json: bool) -> i32 {
    if as_json {
        println!("{}", json::error(message));
    } else {
        eprintln!("omascope: {message}");
    }
    1
}

/// Prefer an agent directory the machine already has, so the skill lands
/// where that agent looks rather than in a folder nothing reads.
fn default_skill_directory() -> PathBuf {
    let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let known = [
        home.join(".claude/skills"),
        home.join(".hermes/skills"),
        home.join(".config/opencode/skills"),
        home.join(".codex/skills"),
    ];
    for candidate in known {
        if candidate.is_dir() {
            return candidate;
        }
    }
    home.join(".local/share/omascope/skills")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_sizes_read_like_the_detail_pane() {
        assert_eq!(human_bytes(512), "512B");
        assert_eq!(human_bytes(1536), "1.5K");
        assert_eq!(human_bytes(80 * 1024 * 1024), "80.0M");
    }

    #[test]
    fn clipping_counts_characters_not_bytes() {
        assert_eq!(clip("short", 10), "short");
        assert_eq!(clip("abcdef", 4), "abc…");
        // A multi-byte name must not be cut mid-character.
        assert_eq!(clip("æøåæøå", 4), "æøå…");
    }

    #[test]
    fn sorting_puts_the_heaviest_first_and_breaks_ties_by_pid() {
        let mut processes = vec![
            Process { pid: 5, cpu: 1.0, rss: 10, name: "b".into(), ..Default::default() },
            Process { pid: 2, cpu: 9.0, rss: 40, name: "a".into(), ..Default::default() },
            Process { pid: 8, cpu: 1.0, rss: 20, name: "c".into(), ..Default::default() },
        ];
        sort_processes(&mut processes, Sort::Cpu);
        assert_eq!(processes.iter().map(|p| p.pid).collect::<Vec<_>>(), vec![2, 5, 8]);
        sort_processes(&mut processes, Sort::Memory);
        assert_eq!(processes.iter().map(|p| p.pid).collect::<Vec<_>>(), vec![2, 8, 5]);
        sort_processes(&mut processes, Sort::Name);
        assert_eq!(processes.iter().map(|p| p.pid).collect::<Vec<_>>(), vec![2, 5, 8]);
    }

    #[test]
    fn the_bundled_skill_names_the_commands() {
        assert!(SKILL.contains("omascope ps"));
        assert!(SKILL.contains("omascope kill"));
    }
}
