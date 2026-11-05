//! Made-up processes for screenshots, README images, and trying the interface
//! without reading or signalling anything real. `serve --demo` uses it.

use std::collections::HashSet;

use crate::procs::{now_seconds, Process, Snapshot};

struct Fake {
    pid: i32,
    ppid: i32,
    name: &'static str,
    user: &'static str,
    uid: u32,
    cpu: f64,
    rss: u64,
    threads: u32,
    state: char,
    cmd: &'static str,
}

const FAKES: &[Fake] = &[
    Fake { pid: 1, ppid: 0, name: "systemd", user: "root", uid: 0, cpu: 0.1, rss: 15_400_000, threads: 1, state: 'S', cmd: "/sbin/init splash" },
    Fake { pid: 812, ppid: 1, name: "systemd-journald", user: "root", uid: 0, cpu: 0.4, rss: 48_200_000, threads: 3, state: 'S', cmd: "/usr/lib/systemd/systemd-journald" },
    Fake { pid: 845, ppid: 1, name: "NetworkManager", user: "root", uid: 0, cpu: 0.2, rss: 31_700_000, threads: 3, state: 'S', cmd: "/usr/bin/NetworkManager --no-daemon" },
    Fake { pid: 902, ppid: 1, name: "pipewire", user: "ana", uid: 1000, cpu: 0.6, rss: 12_900_000, threads: 4, state: 'S', cmd: "/usr/bin/pipewire" },
    Fake { pid: 903, ppid: 1, name: "wireplumber", user: "ana", uid: 1000, cpu: 0.3, rss: 9_800_000, threads: 3, state: 'S', cmd: "/usr/bin/wireplumber" },
    Fake { pid: 1201, ppid: 1, name: "Hyprland", user: "ana", uid: 1000, cpu: 4.5, rss: 201_000_000, threads: 14, state: 'R', cmd: "Hyprland --watchdog-fd 4" },
    Fake { pid: 1203, ppid: 1201, name: "hypridle", user: "ana", uid: 1000, cpu: 0.1, rss: 6_100_000, threads: 2, state: 'S', cmd: "hypridle" },
    Fake { pid: 1204, ppid: 1201, name: "waybar", user: "ana", uid: 1000, cpu: 1.1, rss: 84_500_000, threads: 5, state: 'S', cmd: "waybar -c ~/.config/waybar/config.jsonc" },
    Fake { pid: 1220, ppid: 1201, name: "hyprpaper", user: "ana", uid: 1000, cpu: 0.2, rss: 22_400_000, threads: 3, state: 'S', cmd: "hyprpaper" },
    Fake { pid: 4321, ppid: 1201, name: "kitty", user: "ana", uid: 1000, cpu: 1.8, rss: 143_000_000, threads: 6, state: 'S', cmd: "kitty --single-instance" },
    Fake { pid: 4325, ppid: 4321, name: "nvim", user: "ana", uid: 1000, cpu: 2.4, rss: 96_200_000, threads: 4, state: 'R', cmd: "nvim src/procs.rs" },
    Fake { pid: 4330, ppid: 4321, name: "fish", user: "ana", uid: 1000, cpu: 0.0, rss: 8_300_000, threads: 1, state: 'S', cmd: "/usr/bin/fish" },
    Fake { pid: 1500, ppid: 1201, name: "firefox", user: "ana", uid: 1000, cpu: 9.2, rss: 712_000_000, threads: 42, state: 'R', cmd: "/usr/lib/firefox/firefox" },
    Fake { pid: 1510, ppid: 1500, name: "Web Content", user: "ana", uid: 1000, cpu: 6.4, rss: 486_000_000, threads: 31, state: 'S', cmd: "/usr/lib/firefox/firefox -contentproc -childID 3" },
    Fake { pid: 1511, ppid: 1500, name: "Web Content", user: "ana", uid: 1000, cpu: 2.1, rss: 302_000_000, threads: 24, state: 'S', cmd: "/usr/lib/firefox/firefox -contentproc -childID 5" },
    Fake { pid: 1600, ppid: 1201, name: "code", user: "ana", uid: 1000, cpu: 3.7, rss: 388_000_000, threads: 28, state: 'S', cmd: "/usr/share/code/code --ozone-platform=wayland" },
    Fake { pid: 1620, ppid: 1600, name: "extensionHost", user: "ana", uid: 1000, cpu: 1.2, rss: 214_000_000, threads: 12, state: 'S', cmd: "/usr/share/code/code --type=extensionHost" },
    Fake { pid: 1621, ppid: 1600, name: "code", user: "ana", uid: 1000, cpu: 5.9, rss: 344_000_000, threads: 19, state: 'R', cmd: "/usr/share/code/code --type=renderer" },
    Fake { pid: 1700, ppid: 4321, name: "ffmpeg", user: "ana", uid: 1000, cpu: 128.4, rss: 512_000_000, threads: 17, state: 'R', cmd: "ffmpeg -i talk.mp4 -c:v libx264 -crf 22 talk-web.mp4" },
    Fake { pid: 1750, ppid: 1, name: "postgres", user: "postgres", uid: 971, cpu: 1.4, rss: 178_000_000, threads: 9, state: 'S', cmd: "/usr/bin/postgres -D /var/lib/postgres/data" },
    Fake { pid: 1760, ppid: 1750, name: "postgres", user: "postgres", uid: 971, cpu: 0.7, rss: 42_000_000, threads: 1, state: 'S', cmd: "postgres: checkpointer" },
    Fake { pid: 1800, ppid: 1, name: "redis-server", user: "ana", uid: 1000, cpu: 1.2, rss: 13_100_000, threads: 6, state: 'S', cmd: "redis-server *:6379" },
    Fake { pid: 1900, ppid: 1, name: "sshd", user: "root", uid: 0, cpu: 0.0, rss: 5_400_000, threads: 1, state: 'S', cmd: "sshd: /usr/bin/sshd -D [listener]" },
    Fake { pid: 2100, ppid: 1, name: "tailscaled", user: "root", uid: 0, cpu: 0.8, rss: 68_000_000, threads: 14, state: 'S', cmd: "/usr/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state" },
    Fake { pid: 2200, ppid: 1, name: "docker", user: "root", uid: 0, cpu: 0.5, rss: 92_000_000, threads: 21, state: 'S', cmd: "/usr/bin/dockerd -H fd://" },
    Fake { pid: 2400, ppid: 1201, name: "mpv", user: "ana", uid: 1000, cpu: 0.2, rss: 121_000_000, threads: 11, state: 'S', cmd: "mpv --no-border ambient.mp4" },
    Fake { pid: 2600, ppid: 1, name: "pipewire-pulse", user: "ana", uid: 1000, cpu: 0.1, rss: 15_200_000, threads: 3, state: 'S', cmd: "/usr/bin/pipewire-pulse" },
];

pub struct Demo {
    tick: u64,
    killed: HashSet<i32>,
}

impl Demo {
    pub fn new() -> Self {
        Self { tick: 0, killed: HashSet::new() }
    }

    pub fn kill(&mut self, pid: i32) {
        self.killed.insert(pid);
    }

    pub fn sample(&mut self) -> Snapshot {
        self.tick += 1;
        let started = now_seconds().saturating_sub(3600);
        let processes: Vec<Process> = FAKES
            .iter()
            .filter(|fake| !self.killed.contains(&fake.pid))
            .enumerate()
            .map(|(index, fake)| {
                // A slow sine keeps the numbers moving without random noise,
                // so two screenshots of the same tick match.
                let wobble = 1.0 + 0.18 * ((self.tick as f64 * 0.9) + index as f64).sin();
                Process {
                    pid: fake.pid,
                    ppid: fake.ppid,
                    uid: fake.uid,
                    user: fake.user.to_string(),
                    name: fake.name.to_string(),
                    state: fake.state,
                    cpu: ((fake.cpu * wobble) * 10.0).round() / 10.0,
                    rss: fake.rss,
                    threads: fake.threads,
                    started: started + index as u64 * 17,
                    cmd: fake.cmd.to_string(),
                }
            })
            .collect();

        Snapshot {
            time: now_seconds(),
            cores: 8,
            mem_total: 32 * 1024 * 1024 * 1024,
            mem_used: 12_684_000_000,
            load1: 2.4 + 0.4 * (self.tick as f64 * 0.5).sin(),
            processes,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn demo_parents_are_present_so_the_tree_can_be_built() {
        let pids: HashSet<i32> = FAKES.iter().map(|fake| fake.pid).collect();
        for fake in FAKES {
            assert!(fake.ppid == 0 || pids.contains(&fake.ppid), "{} has no parent", fake.name);
        }
    }

    #[test]
    fn a_killed_demo_process_stops_appearing() {
        let mut demo = Demo::new();
        assert!(demo.sample().processes.iter().any(|process| process.pid == 1700));
        demo.kill(1700);
        assert!(!demo.sample().processes.iter().any(|process| process.pid == 1700));
    }

    #[test]
    fn the_picture_has_enough_rows_to_look_like_a_machine() {
        let mut demo = Demo::new();
        let snapshot = demo.sample();
        assert!(snapshot.processes.len() >= 20);
        assert!(snapshot.processes.iter().any(|process| process.state == 'R'));
        assert!(snapshot.processes.iter().any(|process| process.pid == 1));
    }
}
