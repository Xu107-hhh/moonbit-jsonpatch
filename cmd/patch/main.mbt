///|
/// CLI entry: apply a JSON patch (or merge patch, or compute a diff).
///
/// Usage:
///   moon run cmd/patch -- apply '<doc-json>' '<patch-json>'
///   moon run cmd/patch -- merge '<target-json>' '<merge-patch-json>'
///   moon run cmd/patch -- diff '<original-json>' '<modified-json>'
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
        about="target JSON document as text",
      ),
      @argparse.PositionArg::PositionArg(
        "patch",
        about="patch document (apply/merge) or second document (diff)",
      ),
    ],
    about="RFC 6902 JSON Patch and RFC 7386 JSON Merge Patch",
  )
  let matches = cmd.parse() catch {
    _ => return // argparse has already printed its error/help
  }
  let command = match matches.values.get("command") {
    Some(arr) if arr.length() > 0 => arr[0]
    _ => return
  }
  let document = match matches.values.get("document") {
    Some(arr) if arr.length() > 0 => arr[0]
    _ => return
  }
  let patch = match matches.values.get("patch") {
    Some(arr) if arr.length() > 0 => arr[0]
    _ => return
  }
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
    "diff" =>
      match @lib.diff_text(document, patch) {
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
    _ => {
      println("unknown command: \{command} (expected apply, merge, or diff)")
      abort("bad command")
    }
  }
}
