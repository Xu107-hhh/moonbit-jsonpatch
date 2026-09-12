# moonbit-jsonpatch

[![CI](https://github.com/Xu107-hhh/moonbit-jsonpatch/actions/workflows/ci.yml/badge.svg)](https://github.com/Xu107-hhh/moonbit-jsonpatch/actions/workflows/ci.yml)

A **standards-compliant JSON Patch (RFC 6902) library** for MoonBit:
apply patches, compute diffs, and apply JSON Merge Patches (RFC 7386),
all addressing locations with JSON Pointers (RFC 6901) and reporting
failures down to the exact operation and path.

moonbit-jsonpatch 是 MoonBit 实现的 **JSON Patch（RFC 6902）工具库**：
应用补丁、计算两个文档的差量（diff）、应用 JSON Merge Patch（RFC 7386），
路径寻址遵循 JSON Pointer（RFC 6901），失败时精确报告到第几个操作、哪个路径。

**官方 [json-patch-tests](https://github.com/json-patch/json-patch-tests) 通过率：见 [Conformance](#conformance--标准符合性)。**

## Try it online / 在线体验

**https://xu107-hhh.github.io/moonbit-jsonpatch/** — 浏览器里实时体验
Apply / Diff / Merge Patch 三种模式（编译为 JavaScript 在页面内运行，无服务器）。

## Install / 安装

```bash
moon add Xu107-hhh/moonbit-jsonpatch
```

文档与 API：https://mooncakes.io/docs/Xu107-hhh/moonbit-jsonpatch

## Why / 为什么做这个

JSON Patch 是 HTTP PATCH、Kubernetes 资源变更、配置同步、协作编辑等场景
的标准差量格式。MoonBit 生态此前没有 RFC 6902 实现 —— 这是 MoonBit 社区
[机会卡 #27](https://github.com/moonbit-community/auto-contrib-workflow/issues/27)
官方扫描 mooncakes.io 后确认的空缺方向。

典型场景：

1. **API 客户端与服务端** —— `PATCH /users/42` 请求体是 JSON Patch，
   服务端逐操作应用并在失败时返回第几个操作、哪条路径出错（400 响应）。
2. **配置与状态同步** —— 用 `diff` 计算两份配置/状态的差异并下发补丁，
   对端 `apply` 原子应用；失败时原文档不受影响（本库不做部分应用）。
3. **Agent / LLM 输出自修正** —— 模型只需返回小补丁而非整份文档，
   `test` 操作先做前置断言，不满足即整体拒绝，避免半新半旧的状态。

与既有 JSON Schema 验证器（校验"文档对不对"）互补，本库解决
"文档怎么从旧版本变成新版本"。

## Conformance / 标准符合性

集成官方 [json-patch-tests](https://github.com/json-patch/json-patch-tests)
（`tests.json` + `spec_tests.json`，已 vendor 到 `suite/fixtures`，其许可为 Apache-2.0）。

<!-- CONFORMANCE_TABLE -->

操作覆盖：`add` / `remove` / `replace` / `move` / `copy` / `test`
全部六种操作，含数组插入与 `-` 追加、`move` 的 remove-then-add 语义、
`move` 禁止移入自身子路径（proper prefix 检查）、`test` 的深度相等比较、
非规范数组索引（前导零）与越界索引的拒绝。

附加能力（超出 RFC 6902 必需范围）：

- `diff` —— 从两份文档生成等价补丁（保证可回放，不保证最小化）；
- RFC 7386 `merge_patch`；
- 不可变语义 —— 所有操作函数式更新，输入文档永不改动，失败零副作用。

## Usage / 用法

```moonbit nocheck
let doc = @json.parse("{\"a\":1,\"list\":[1,2]}")
let patch = @json.parse("[{\"op\":\"add\",\"path\":\"/list/-\",\"value\":3}]")
match @jsonpatch.apply_patch(doc, patch) {
  Ok(result) => // {"a":1,"list":[1,2,3]}
  Err(e) => // e.index / e.op / e.path / e.kind / e.message
}
```

错误精确定位（RFC 6901 路径 + 第几个操作）：

```moonbit nocheck
Err(@jsonpatch.PatchError::{ index: 1, op: "add", path: "/x/9", ... })
// message: "array index is malformed or beyond the end of the array"
```

计算差量与 Merge Patch：

```moonbit nocheck
@jsonpatch.diff(old, new)          // -> RFC 6902 patch (Json)
@jsonpatch.merge_patch(target, p)  // RFC 7386，null 删除成员、对象递归合并
```

文本直入（自动区分解析错误与应用错误）：

```moonbit nocheck
match @jsonpatch.apply(doc_text, patch_text) { ... }
```

CLI：

```bash
$ moon run cmd/patch -- apply '{"a":1,"list":[1,2]}' \
    '[{"op":"add","path":"/list/-","value":3},{"op":"replace","path":"/a","value":9}]'
{"a":9,"list":[1,2,3]}

$ moon run cmd/patch -- diff '{"a":1,"b":2}' '{"a":2,"c":3}'
[{"op":"remove","path":"/b"},{"op":"replace","path":"/a","value":2},{"op":"add","path":"/c","value":3}]

$ moon run cmd/patch -- merge '{"a":{"x":1,"y":2}}' '{"a":{"y":null,"z":3}}'
{"a":{"x":1,"z":3}}
```

## Development

Requires the [MoonBit toolchain](https://www.moonbitlang.com/download/) (`moon`).

```bash
moon check             # static checks
moon fmt               # format
moon test              # unit tests + official conformance suite
moon run cmd/patch --  # run the CLI
python tools/gen_suite.py  # regenerate suite tests from fixtures
```

## Project layout

- `pointer.mbt` — RFC 6901 JSON Pointer（解析/转义/规范索引）
- `tree.mbt` — 不可变树定位与函数式更新、深度相等
- `apply.mbt` — 补丁文档校验与六种操作的应用
- `merge.mbt` — RFC 7386 JSON Merge Patch
- `diff.mbt` — 差量（补丁）生成
- `cmd/patch` — CLI（apply / merge / diff）
- `suite/fixtures` — vendored 官方测试套件（json-patch-tests）
- `suite/gen` — 生成的符合性测试（`tools/gen_suite.py`）
- `demo/` — 浏览器 playground（js target）

## License

Apache-2.0. Test fixtures under `suite/` are from
[json-patch-tests](https://github.com/json-patch/json-patch-tests)
(Apache-2.0).
