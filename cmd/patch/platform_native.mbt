///|
/// Program arguments with the program path stripped: the native runtime
/// passes `[program, args...]`.
fn cli_args() -> ArrayView[String] {
  @env.args().view(start=1)
}

///|
/// Stdin on the native backend would go through C stdio; not wired up yet.
fn read_stdin_internal() -> Result[String, String] {
  Err(
    "reading stdin is not supported on the native backend yet; pass a file with @path or inline JSON",
  )
}
