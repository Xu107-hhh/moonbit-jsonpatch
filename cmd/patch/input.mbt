///|
/// Resolve a CLI document argument to JSON text.
///
/// Every document argument accepts three forms:
///   - `@path` — read the JSON text from a file (`moonbitlang/x/fs`)
///   - `-`     — read all of stdin (supported on the js backend; the wasm
///     backend has no stdin access, see `stdin_wasm.mbt`)
///   - anything else is used as literal JSON text
///
/// `what` names the argument in error messages ("document", "patch", ...).
fn read_input(arg : String, what : String) -> Result[String, String] {
  if arg == "-" {
    read_stdin_internal()
  } else if arg.has_prefix("@") && arg.length() > 1 {
    let path = arg[1:].to_owned()
    let text = @fs.read_file_to_string(path) catch {
      IOError(msg) => return Err("cannot read \{what} file \{path}: \{msg}")
    }
    Ok(text)
  } else {
    Ok(arg)
  }
}
