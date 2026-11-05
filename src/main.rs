// omascope — a keyboard-first process manager for Omarchy.

mod cli;
mod demo;
mod gpu;
mod json;
mod procs;
mod signals;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(cli::run(args));
}
