# moonbit-jsonpatch

[![CI](https://github.com/Xu107-hhh/moonbit-jsonpatch/actions/workflows/ci.yml/badge.svg)](https://github.com/Xu107-hhh/moonbit-jsonpatch/actions/workflows/ci.yml)

A **standards-compliant JSON Patch (RFC 6902) library** for MoonBit:
apply patches, compute diffs, and apply JSON Merge Patches (RFC 7386),
all addressing locations with JSON Pointers (RFC 6901) and reporting
failures down to the exact operation and path.

moonbit-jsonpatch 是 MoonBit 实现的 **JSON Patch（RFC 6902）工具库**：
应用补丁、计算两个文档的差量（diff）、应用 JSON Merge Patch（RFC 7386，
被 RFC 7396 取代但语义相同），路径寻址遵循 JSON Pointer（RFC 6901），
失败时精确报告到第几个操作、哪个路径。

**官方 [json-patch-tests](https://github.com/json-patch/json-patch-tests) 通过率：108 / 108（100%）** —— 见下文 [Conformance](#conformance--标准符合性)。

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

## Related work / 与既有项目的关系

MoonBit 生态已有的 diff/patch 类库与本项目定位错开：

- [tiye/recollect](https://mooncakes.io/docs/tiye/recollect)（v0.2.1）：面向不可变 UI 框架（Cumulo/Respo）状态同步的**私有格式** diff/patch——补丁是内存中的 `PatchOp`/`PathSegment` 结构体，仅在 recollect 实例之间可用，不读写标准 JSON Patch 文档；数组操作依赖带 `"id"` 的键控数组；其 `Set` 会自动创建缺失的中间节点（RFC 6902 明确将此判定为错误）。
- [moondiff](https://mooncakes.io/docs/moonbit-community/moondiff) / [piediff](https://mooncakes.io/docs/piediff)：文本/源码 diff（difftastic 风格、patience/Myers 算法），处理的是文本行，不是 JSON 文档结构。

moonbit-jsonpatch 是 MoonBit 生态中唯一实现 IETF **标准线格式**（RFC 6902 JSON Patch / RFC 7386 Merge Patch / RFC 6901 JSON Pointer）的库：补丁本身就是标准 JSON 文档，可与任何语言的 RFC 6902 实现、HTTP PATCH 服务、Kubernetes 直接互通；语义严格遵循 RFC（不隐式创建路径、`test`/`copy`/`move` 完整、错误精确到操作与路径），并有官方测试套件 108/108 背书。私有格式方案（如 recollect）如需跨系统传输补丁，序列化为 RFC 6902 后即可与本库互补。

## Conformance / 标准符合性

集成官方 [json-patch-tests](https://github.com/json-patch/json-patch-tests)
（`tests.json` + `spec_tests.json`，已 vendor 到 `suite/fixtures`，其许可为 Apache-2.0）。

| 指标 | 结果 |
|---|---|
| `spec_tests.json`（RFC 6902 正文附录用例） | **16 / 16 通过**（1 例上游标记 `disabled` 未纳入） |
| `tests.json`（社区补充用例） | **92 / 92 通过**（3 例上游标记 `disabled` 未纳入） |
| **合计** | **108 / 108（100%）** |

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

每个文档参数除了内联 JSON，还支持 **`@文件路径`**（读文件）和 **`-`**（读 stdin，js 后端）：

```bash
$ moon run cmd/patch -- apply @doc.json @patch.json
$ cat patch.json | moon run --target js cmd/patch -- apply @doc.json -
```

wasm 后端（`moon run` 默认）可以读文件，但宿主未开放 stdin——此时 `-`
会给出明确报错；stdin 管道请用 `--target js`（需要 Node.js）。

## Performance / 性能

`moon run --release benches` 生成固定种子的确定性文档，测量 apply / diff / merge。
下表为单次调用中位数（Windows 11 · moon 0.1.20260827 · wasm release，2026-09
实测，绝对值随机器浮动，量级与比例可参考）：

| 场景 | n=1,000 | n=10,000 | n=100,000 |
|---|---|---|---|
| apply 对象（100 操作） | 4.2 ms | 216 ms | 2.9 s |
| apply 数组（100 操作） | 14 µs | 1.7 ms | 137 ms |
| diff 对象（~15% 变更） | 6.7 µs | 0.9 ms | 129 ms |
| diff 数组（~20% 变更） | 1.0 µs | 124 µs | 11.8 ms |
| merge 嵌套对象 | 0.1 µs | 13 µs | 2.0 ms |

成本模型与设计选择一致：库采用不可变语义，每个操作重建从根到目标的路径，
因此对象上的 apply 大致线性于「文档大小 × 操作数」（每步复制 Map）；数组应用
因连续内存复制远快于对象；merge patch 只递归变更涉及的分支，开销最小。
热路径上的大文档建议优先 merge patch（RFC 7396）或数组形态。

## Development

Requires the [MoonBit toolchain](https://www.moonbitlang.com/download/) (`moon`).

```bash
moon check             # static checks
moon fmt               # format
moon test              # unit tests + official conformance suite
moon run examples/basic  # runnable example (apply / diff / merge / errors)
moon run cmd/patch --  # run the CLI
moon run --release benches  # benchmarks (apply / diff / merge)
python tools/gen_suite.py  # regenerate suite tests from fixtures
```

## Project layout

- `pointer.mbt` — RFC 6901 JSON Pointer（解析/转义/规范索引）
- `tree.mbt` — 不可变树定位与函数式更新、深度相等
- `apply.mbt` — 补丁文档校验与六种操作的应用
- `merge.mbt` — RFC 7386 JSON Merge Patch
- `diff.mbt` — 差量（补丁）生成
- `cmd/patch` — CLI（apply / merge / diff；参数支持内联 JSON、`@文件`、`-` stdin）
- `examples/basic` — 可运行示例（moon run examples/basic）
- `benches/` — 基准测试（moon run --release benches，固定种子可复现）
- `suite/fixtures` — vendored 官方测试套件（json-patch-tests）
- `suite/gen` — 生成的符合性测试（`tools/gen_suite.py`）
- `demo/` — 浏览器 playground（js target）

## License

Apache-2.0. Test fixtures under `suite/` are from
[json-patch-tests](https://github.com/json-patch/json-patch-tests)
(Apache-2.0).
