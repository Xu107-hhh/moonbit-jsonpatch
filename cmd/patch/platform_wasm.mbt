///|
/// Program arguments with the program path stripped: moonrun passes
/// `[program.wasm, args...]`.
fn cli_args() -> ArrayView[String] {
  @env.args().view(start=1)
}

///|
/// The wasm host API used by `moon run` exposes files but not stdin.
/// Pass a file with `@path` (or literal JSON), or run the CLI on the js
/// backend (`moon run --target js`) to use `-`.
fn read_stdin_internal() -> Result[String, String] {
  Err(
    "reading stdin is not supported on the wasm backend; pass a file with @path, inline JSON, or run with --target js",
  )
}
