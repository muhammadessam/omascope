//! GPU readings. NVIDIA exposes utilisation and VRAM through `nvidia-smi`;
//! the kernel's DRM nodes expose neither for the Intel iGPU, so a machine
//! without NVIDIA simply has no GPU row rather than a graph that means
//! nothing. The monitor samples on its own thread so a slow driver cannot
//! stall the one-second process snapshot.

use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Gpu {
    pub name: String,
    pub util: f64,
    pub mem_used: u64,
    pub mem_total: u64,
    pub temp: Option<f64>,
}

const QUERY: &str =
    "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu";
const FORMAT: &str = "--format=csv,noheader,nounits";

/// One reading, or an empty list when there is no NVIDIA driver to ask.
pub fn sample() -> Vec<Gpu> {
    let output = Command::new("nvidia-smi").args([QUERY, FORMAT]).output();
    match output {
        Ok(output) if output.status.success() => {
            parse(&String::from_utf8_lossy(&output.stdout))
        }
        _ => Vec::new(),
    }
}

pub fn parse(raw: &str) -> Vec<Gpu> {
    raw.lines()
        .filter_map(|line| {
            let fields: Vec<&str> = line.split(',').map(str::trim).collect();
            if fields.len() < 4 {
                return None;
            }
            let util = fields[1].parse::<f64>().unwrap_or(0.0);
            let used = fields[2].parse::<f64>().unwrap_or(0.0);
            let total = fields[3].parse::<f64>().unwrap_or(0.0);
            Some(Gpu {
                name: fields[0].to_string(),
                util,
                mem_used: (used * 1024.0 * 1024.0) as u64,
                mem_total: (total * 1024.0 * 1024.0) as u64,
                temp: fields.get(4).and_then(|value| value.parse::<f64>().ok()),
            })
        })
        .collect()
}

/// Keeps the last reading so snapshots never wait on the driver.
pub struct Monitor {
    current: Arc<Mutex<Vec<Gpu>>>,
}

impl Monitor {
    pub fn start() -> Self {
        // One reading before the first snapshot so the GPU card is not empty
        // for the first two seconds of the window's life.
        let current = Arc::new(Mutex::new(sample()));
        if Command::new("nvidia-smi").arg("-L").output().is_err() {
            return Self { current };
        }
        let slot = Arc::clone(&current);
        thread::spawn(move || loop {
            thread::sleep(Duration::from_secs(2));
            let gpus = sample();
            if let Ok(mut guard) = slot.lock() {
                *guard = gpus;
            }
        });
        Self { current }
    }

    pub fn current(&self) -> Vec<Gpu> {
        self.current.lock().map(|gpus| gpus.clone()).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_csv_line_becomes_a_reading() {
        let gpus = parse("NVIDIA GeForce RTX 3060 Laptop GPU, 12, 3485, 6144, 51\n");
        assert_eq!(gpus.len(), 1);
        assert_eq!(gpus[0].name, "NVIDIA GeForce RTX 3060 Laptop GPU");
        assert_eq!(gpus[0].util, 12.0);
        assert_eq!(gpus[0].mem_used, 3485 * 1024 * 1024);
        assert_eq!(gpus[0].temp, Some(51.0));
    }

    #[test]
    fn a_gpu_without_a_temperature_is_still_usable() {
        let gpus = parse("NVIDIA GeForce RTX 3060, 0, 100, 6144, [N/A]\n");
        assert_eq!(gpus.len(), 1);
        assert_eq!(gpus[0].temp, None);
    }

    #[test]
    fn junk_lines_are_skipped_rather_than_panicking() {
        assert!(parse("").is_empty());
        assert!(parse("no fields here").is_empty());
    }
}
