//! Reading `/proc` into the one snapshot the window draws.
//!
//! Everything here is plain files: a process manager does not need a helper
//! library, and avoiding one keeps the build a single `cargo build` with no
//! network and no C dependency.

use std::collections::HashMap;
use std::fs;
use std::os::unix::fs::MetadataExt;

/// The kernel reports `/proc` CPU times in `USER_HZ`, which is fixed at 100
/// on Linux regardless of the architecture or the configured tick rate.
pub const USER_HZ: u64 = 100;

/// The architectures Omarchy installs on use 4 KiB pages, and `/proc/<pid>/stat`
/// counts RSS in pages.
const PAGE_SIZE: u64 = 4096;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Process {
    pub pid: i32,
    pub ppid: i32,
    pub uid: u32,
    pub user: String,
    pub name: String,
    pub state: char,
    pub cpu: f64,
    pub rss: u64,
    pub threads: u32,
    pub started: u64,
    pub cmd: String,
}

#[derive(Clone, Debug, Default)]
pub struct Snapshot {
    pub time: u64,
    pub cores: u32,
    pub mem_total: u64,
    pub mem_used: u64,
    pub load1: f64,
    pub processes: Vec<Process>,
}

/// The parsed pieces of one `/proc/<pid>/stat` line, before CPU time is
/// turned into a percentage.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Stat {
    pub pid: i32,
    pub comm: String,
    pub state: char,
    pub ppid: i32,
    pub ticks: u64,
    pub threads: u32,
    pub starttime: u64,
    pub rss_pages: u64,
}

#[derive(Default)]
pub struct Sampler {
    previous: HashMap<i32, (u64, u64)>,
    previous_total: u64,
    users: HashMap<u32, String>,
}

impl Sampler {
    pub fn new() -> Self {
        Self::default()
    }

    /// One sweep of the process table. CPU percentages come from the change
    /// since the previous sweep, so the first one reports each process's
    /// lifetime average, the same number `ps` shows, rather than zero.
    pub fn sample(&mut self) -> Snapshot {
        let total_ticks = total_cpu_ticks().unwrap_or(0);
        let cores = cores().unwrap_or(1);
        let uptime = uptime_seconds().unwrap_or(0.0);
        let boot = boot_time().unwrap_or(0);

        let total_delta = total_ticks.saturating_sub(self.previous_total);
        let first = self.previous_total == 0 || total_delta == 0;

        let (mem_total, mem_used) = memory().unwrap_or((0, 0));
        let mut processes = Vec::new();
        let mut current = HashMap::new();

        if let Ok(entries) = fs::read_dir("/proc") {
            for entry in entries.flatten() {
                let file_name = entry.file_name();
                let Some(pid) = file_name.to_str().and_then(|name| name.parse::<i32>().ok()) else {
                    continue;
                };
                if pid <= 0 {
                    continue;
                }
                let Some(stat) = read_stat(pid) else { continue };
                let uid = entry.metadata().map(|m| m.uid()).unwrap_or(0);
                let user = self.user(uid).to_string();

                let ticks = stat.ticks;
                let cpu = if first {
                    lifetime_cpu(ticks, stat.starttime, uptime, cores)
                } else {
                    let previous = self.previous.get(&pid).copied().unwrap_or((0, 0));
                    // A recycled PID starts its counters again, so a shrink
                    // means "new process" rather than negative CPU time.
                    if ticks < previous.0 || stat.starttime != previous.1 {
                        lifetime_cpu(ticks, stat.starttime, uptime, cores)
                    } else {
                        let delta = ticks - previous.0;
                        delta as f64 / total_delta as f64 * 100.0 * cores as f64
                    }
                };

                let cmd = read_cmdline(pid).unwrap_or_else(|| format!("[{}]", stat.comm));
                current.insert(pid, (ticks, stat.starttime));
                processes.push(Process {
                    pid,
                    ppid: stat.ppid,
                    uid,
                    user,
                    name: stat.comm.clone(),
                    state: stat.state,
                    cpu: (cpu * 10.0).round() / 10.0,
                    rss: stat.rss_pages * PAGE_SIZE,
                    threads: stat.threads,
                    started: boot + stat.starttime / USER_HZ,
                    cmd,
                });
            }
        }

        processes.sort_by_key(|process| process.pid);

        self.previous = current;
        self.previous_total = total_ticks;

        Snapshot {
            time: now_seconds(),
            cores,
            mem_total,
            mem_used,
            load1: load_average(),
            processes,
        }
    }

    fn user(&mut self, uid: u32) -> &str {
        if !self.users.contains_key(&uid) {
            self.users.insert(uid, lookup_user(uid));
        }
        self.users.get(&uid).map(String::as_str).unwrap_or("?")
    }
}

fn lifetime_cpu(ticks: u64, starttime: u64, uptime: f64, cores: u32) -> f64 {
    // Divide by the time this process has existed, not by system uptime:
    // a one-second-old busy process is at 100%, not at a rounding error.
    // This is the number `ps` prints as %CPU, in top's units where 100 is one
    // core and every core adds another 100.
    let elapsed_ticks = uptime * USER_HZ as f64 - starttime as f64;
    if elapsed_ticks <= 0.0 {
        return 0.0;
    }
    let percent = ticks as f64 / elapsed_ticks * 100.0;
    percent.clamp(0.0, 100.0 * cores as f64)
}

fn lookup_user(uid: u32) -> String {
    // /etc/passwd is the local registry; a directory-service user (sssd, ldap)
    // that is not there shows the number instead of pretending to know.
    // Fields are name:password:uid:gid:gecos:home:shell.
    if let Ok(passwd) = fs::read_to_string("/etc/passwd") {
        for line in passwd.lines() {
            let mut fields = line.split(':');
            let name = fields.next();
            let _password = fields.next();
            if fields.next().and_then(|value| value.parse::<u32>().ok()) == Some(uid) {
                if let Some(name) = name {
                    return name.to_string();
                }
            }
        }
    }
    uid.to_string()
}

/// Parse a `/proc/<pid>/stat` line. The command name is wrapped in
/// parentheses and may itself contain spaces and parentheses, so the fields
/// begin after the *last* `)`.
pub fn parse_stat(line: &str) -> Option<Stat> {
    let open = line.find('(')?;
    let close = line.rfind(')')?;
    if close < open {
        return None;
    }
    let pid = line[..open].trim().parse::<i32>().ok()?;
    let comm = line[open + 1..close].to_string();
    let fields: Vec<&str> = line[close + 1..].split_whitespace().collect();
    // state is field 3 of the proc(5) list, so index 0 here.
    let state = fields.first()?.chars().next()?;
    Some(Stat {
        pid,
        comm,
        state,
        ppid: fields.get(1)?.parse().ok()?,
        ticks: fields.get(11)?.parse::<u64>().ok()? + fields.get(12)?.parse::<u64>().ok()?,
        threads: fields.get(17)?.parse().ok()?,
        starttime: fields.get(19)?.parse().ok()?,
        rss_pages: fields.get(21)?.parse().ok()?,
    })
}

fn read_stat(pid: i32) -> Option<Stat> {
    parse_stat(&fs::read_to_string(format!("/proc/{pid}/stat")).ok()?)
}

fn read_cmdline(pid: i32) -> Option<String> {
    let raw = fs::read(format!("/proc/{pid}/cmdline")).ok()?;
    if raw.is_empty() {
        return None;
    }
    let parts: Vec<String> = raw
        .split(|byte| *byte == 0)
        .filter(|part| !part.is_empty())
        .map(|part| String::from_utf8_lossy(part).into_owned())
        .collect();
    if parts.is_empty() {
        return None;
    }
    Some(parts.join(" "))
}

fn total_cpu_ticks() -> Option<u64> {
    let stat = fs::read_to_string("/proc/stat").ok()?;
    let line = stat.lines().next()?;
    let values: Vec<u64> = line
        .split_whitespace()
        .skip(1)
        .filter_map(|value| value.parse::<u64>().ok())
        .take(8)
        .collect();
    if values.is_empty() {
        None
    } else {
        Some(values.iter().sum())
    }
}

fn cores() -> Option<u32> {
    let stat = fs::read_to_string("/proc/stat").ok()?;
    let count = stat
        .lines()
        .filter(|line| line.starts_with("cpu") && !line.starts_with("cpu "))
        .count();
    (count > 0).then_some(count as u32)
}

fn uptime_seconds() -> Option<f64> {
    fs::read_to_string("/proc/uptime")
        .ok()?
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

fn boot_time() -> Option<u64> {
    fs::read_to_string("/proc/stat")
        .ok()?
        .lines()
        .find_map(|line| line.strip_prefix("btime "))
        .and_then(|value| value.trim().parse().ok())
}

fn memory() -> Option<(u64, u64)> {
    let meminfo = fs::read_to_string("/proc/meminfo").ok()?;
    let mut total = 0;
    let mut available = 0;
    for line in meminfo.lines() {
        let mut fields = line.split_whitespace();
        match fields.next() {
            Some("MemTotal:") => total = fields.next()?.parse::<u64>().ok()? * 1024,
            Some("MemAvailable:") => available = fields.next()?.parse::<u64>().ok()? * 1024,
            _ => {}
        }
    }
    (total > 0).then_some((total, total.saturating_sub(available)))
}

fn load_average() -> f64 {
    fs::read_to_string("/proc/loadavg")
        .ok()
        .and_then(|raw| raw.split_whitespace().next()?.parse().ok())
        .unwrap_or(0.0)
}

pub fn now_seconds() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_line_with_parens_in_the_name_parses() {
        // The kernel wraps a name containing spaces and parentheses without
        // escaping it, so only the last ')' can end the field.
        let line = "4242 (web (thing) worker) S 1 4242 4242 0 -1 4194560 120 0 0 0 12 34 0 0 20 0 7 0 900 1000 2048 0";
        let stat = parse_stat(line).expect("line parses");
        assert_eq!(stat.pid, 4242);
        assert_eq!(stat.comm, "web (thing) worker");
        assert_eq!(stat.state, 'S');
        assert_eq!(stat.ppid, 1);
        assert_eq!(stat.ticks, 46);
        assert_eq!(stat.threads, 7);
        assert_eq!(stat.starttime, 900);
        assert_eq!(stat.rss_pages, 2048);
    }

    #[test]
    fn a_short_stat_line_is_rejected_rather_than_guessed() {
        assert!(parse_stat("12 (only) S 1 2").is_none());
        assert!(parse_stat("garbage").is_none());
    }

    #[test]
    fn lifetime_cpu_is_a_share_of_one_core() {
        // A process born with the system, 100 ticks over 1 second of uptime,
        // is one whole core.
        let value = lifetime_cpu(100, 0, 1.0, 8);
        assert!((value - 100.0).abs() < 0.001, "got {value}");
        // One started half a second ago with half a second of CPU is also one
        // whole core; dividing by system uptime would have said 50%.
        let value = lifetime_cpu(50, 50, 1.0, 8);
        assert!((value - 100.0).abs() < 0.001, "got {value}");
        // 8 cores busy for a second is 800% in top's units.
        let value = lifetime_cpu(800, 0, 1.0, 8);
        assert!((value - 800.0).abs() < 0.001, "got {value}");
    }

    #[test]
    fn root_resolves_to_a_name_not_a_number() {
        // UID 0 is on every machine, so this pins the passwd field order
        // without depending on the user running the test.
        assert_eq!(lookup_user(0), "root");
    }

    #[test]
    fn sampling_twice_reports_the_kernel_tables() {
        let mut sampler = Sampler::new();
        let snapshot = sampler.sample();
        assert!(!snapshot.processes.is_empty());
        assert!(snapshot.cores >= 1);
        assert!(snapshot.mem_total > 0);
        assert!(snapshot.processes.iter().any(|p| p.pid == std::process::id() as i32));
        // The second sweep has a previous sample to compare against.
        let second = sampler.sample();
        assert!(second.processes.iter().all(|p| p.cpu >= 0.0));
    }
}
