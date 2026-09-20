///|
/// CLI entry: apply a JSON patch (or merge patch, or compute a diff).
///
/// Usage:
///   moon run cmd/patch -- apply '<doc-json>' '<patch-json>'
///   moon run cmd/patch -- merge '<target-json>' '<merge-patch-json>'
///   moon run cmd/patch -- diff '<original-json>' '<modified-json>'
///
/// Every document argument also accepts `@path` to read from a file, or `-`
/// to read from stdin (js backend only):
///   moon run cmd/patch -- apply @doc.json @patch.json
///   cat patch.json | moon run --target js cmd/patch -- apply doc.json -
///
/// Prints the resulting JSON, or a diagnostic, and exits non-zero on
/// failure.
fn main {
  let cmd = @argparse.Command::Command(
    "moonbit-jsonpatch",
    positionals=[
      @argparse.PositionArg::PositionArg(
        "command",
        about="apply | merge | diff",
      ),
      @argparse.PositionArg::PositionArg(
        "document",
        about="JSON text, @file, or - for stdin",
      ),
      @argparse.PositionArg::PositionArg(
        "patch",
        about="patch document (apply/merge), second document (diff); JSON text, @file, or -",
      ),
    ],
    options=[
      @argparse.OptionArg::OptionArg(
        "key",
        long="key",
        about="diff only: match array items by this member (e.g. id) instead of position",
      ),
    ],
    about="RFC 6902 JSON Patch and RFC 7386 JSON Merge Patch",
  )
  let matches = cmd.parse(argv=cli_args()) catch {
    _ => return // argparse has already printed its error/help
  }
  let command = match matches.values.get("command") {
    Some(arr) if arr.length() > 0 => arr[0]
    _ => return
  }
  fn arg_or_fail(name : String) -> String {
    match matches.values.get(name) {
      Some(arr) if arr.length() > 0 => arr[0]
      _ => abort("missing argument: \{name}")
    }
  }
  fn input_or_fail(name : String, what : String) -> String {
    match read_input(arg_or_fail(name), what) {
      Ok(text) => text
      Err(msg) => {
        println(msg)
        abort("input error")
      }
    }
  }
  let document = input_or_fail("document", "document")
  let patch = input_or_fail("patch", "patch")
  match command {
    "apply" =>
      match @lib.apply(document, patch) {
        Ok(out) => println(out)
        Err(@lib.BadDocumentJson(msg)) => {
          println("document parse error: \{msg}")
          abort("invalid document")
        }
        Err(@lib.BadPatchJson(msg)) => {
          println("patch parse error: \{msg}")
          abort("invalid patch")
        }
        Err(@lib.PatchFailed(e)) => {
          println(
            "patch failed at operation \{e.index} (\{e.op}, path \{e.path}): \{e.message}",
          )
          abort("patch failed")
        }
      }
    "merge" =>
      match @lib.merge(document, patch) {
        Ok(out) => println(out)
        Err(@lib.BadTargetJson(msg)) => {
          println("target parse error: \{msg}")
          abort("invalid target")
        }
        Err(@lib.BadPatchJson(msg)) => {
          println("patch parse error: \{msg}")
          abort("invalid patch")
        }
      }
    "diff" => {
      let keyed = match matches.values.get("key") {
        Some(arr) if arr.length() > 0 => Some(arr[0])
        _ => None
      }
      let result = match keyed {
        Some(key) => @lib.diff_text_keyed(document, patch, key)
        None => @lib.diff_text(document, patch)
      }
      match result {
        Ok(out) => println(out)
        Err(@lib.BadTargetJson(msg)) => {
          println("original parse error: \{msg}")
          abort("invalid original")
        }
        Err(@lib.BadPatchJson(msg)) => {
          println("modified parse error: \{msg}")
          abort("invalid modified")
        }
      }
    }
    _ => {
      println("unknown command: \{command} (expected apply, merge, or diff)")
      abort("bad command")
    }
  }
}
