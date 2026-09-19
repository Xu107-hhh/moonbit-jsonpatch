///|
/// Program arguments with the interpreter prefix stripped.
///
/// Under the js backend (`moon run --target js`), Node's `process.argv` is
/// `[node, script, args...]`; core's argparse assumes the argv has already
/// been reduced to `[program, args...]` (as moonrun does for wasm), so we
/// normalize here before parsing.
fn cli_args() -> ArrayView[String] {
  @env.args().view(start=2)
}

///|
#external
priv type StdinResult

///|
extern "js" fn StdinResult::is_ok(self : StdinResult) -> Bool =
  #| (res) => res.ok

///|
extern "js" fn StdinResult::content(self : StdinResult) -> Bytes =
  #| (res) => res.content

///|
extern "js" fn StdinResult::error_message(self : StdinResult) -> String =
  #| (res) => res.content

///|
#module("node:fs")
extern "js" fn node_read_fd_sync(fd : Int) -> Bytes = "readFileSync"

///|
extern "js" fn read_stdin_ffi(read_fd : (Int) -> Bytes) -> StdinResult =
  #| function(readFd) {
  #|   try {
  #|     const content = readFd(0);
  #|     return { ok: true, content };
  #|   } catch (error) {
  #|     return { ok: false, content: error.message };
  #|   }
  #| }

///|
/// Read all of stdin as UTF-8 text (js backend, Node.js `fs.readFileSync(0)`).
fn read_stdin_internal() -> Result[String, String] {
  let res = read_stdin_ffi(node_read_fd_sync)
  if res.is_ok() {
    let text = @utf8.decode(res.content()) catch {
      _ => return Err("stdin is not valid UTF-8")
    }
    Ok(text)
  } else {
    Err("failed to read stdin: \{res.error_message()}")
  }
}
