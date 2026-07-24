# ADR-014：Tree-sitter 可视范围语法高亮

状态：Accepted  
日期：2026-07-24

## 决策

Diff 使用 Tree-sitter C runtime 与 SwiftTreeSitter，在 TextKit 2 的 Unified 和
Side-by-Side 两种展示中提供原生语法高亮。首发语言族固定为：

`Swift、C、C++、Objective-C、JavaScript、TypeScript、Python、Go、Rust、Java、JSON、YAML`。

TSX 作为 TypeScript 语言族的 parser 变体一并提供，因此实际加载 13 个 grammar
入口，但不增加第 13 个产品语言族。

实现遵循这些边界：

- 由 old/new 两份源码投影分别解析，diff gutter、`+`/`-` marker 和 hunk header
  不进入 parser。
- parser 产生的 UTF-16 `NSRange` 通过显式 mapping 转回 TextKit 渲染范围。
- 滚动使用 80 ms debounce，只查询当前可视区并预取相邻 4,000 个 UTF-16 code unit。
- 高亮任务使用 utility priority，可取消，并绑定当前 diff generation；陈旧结果不得写回。
- 最近四份 old/new 源码保留解析树，滚动只重新执行可视区 query，不重新 parse。
- 空文件、二进制、不支持的扩展名和超过 512 KiB UTF-16 的文本自动退化为纯文本。
- 单次 query 最多消费 100,000 个 capture，parser 超时为 250 ms。
- 高亮只改变前景色，不参与 diff、patch、stage 或 selection 的语义。

## 固定依赖与许可证

| 组件 | 固定版本或 revision | 用途 | 许可证 |
|---|---|---|---|
| swift-tree-sitter | 0.25.0 | Swift API、query/highlight、UTF-16 range | BSD-3-Clause |
| tree-sitter | 0.25.10 | C runtime | MIT |
| tree-sitter-swift | `0.7.3-with-generated-files` / `31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5` | Swift | MIT |
| tree-sitter-c | 0.24.2 | C | MIT |
| tree-sitter-cpp | 0.23.4 | C++ | MIT |
| tree-sitter-objc | 3.0.2 | Objective-C | MIT |
| tree-sitter-javascript | 0.23.1 | JavaScript | MIT |
| tree-sitter-typescript | 0.23.2 | TypeScript、TSX | MIT |
| tree-sitter-python | 0.23.6 | Python | MIT |
| tree-sitter-go | 0.25.0 | Go | MIT |
| tree-sitter-rust | 0.24.2 | Rust | MIT |
| tree-sitter-java | 0.23.5 | Java | MIT |
| tree-sitter-json | 0.24.8 | JSON | MIT |
| tree-sitter-yaml | 0.7.0 | YAML | MIT |

JavaScript、Python 和 YAML 使用已验证能在 SwiftPM 依赖模式下编译 external scanner
的稳定 tag；Swift 使用包含生成 parser 文件的不可变 revision。`Package.resolved`
是构建时 SBOM 的权威锁文件。进入打包阶段时，必须把每个组件 checkout 中的完整
`LICENSE` 文本复制进应用的 Third-Party Notices，不允许只保留本表。

## 验证

- 单元测试逐一加载 13 个 parser 入口，要求产生非空且不越界的 UTF-16 capture。
- 单元测试覆盖 12 个语言族的扩展名识别、TSX、可视范围映射、不支持文件和超大文件降级。
- 完整 Swift 测试必须覆盖现有 Git、RepositoryActor、Diff、Graph 和 mutation 回归。
- 原生 QA 使用真实 Swift diff 检查 Unified/Side-by-Side 的 keyword、type、string、
  comment、滚动补齐、切换文件和大文件降级。
- Debug、Release 和最低 macOS GitHub Actions 构建均需通过；包体预算在打包阶段复核。
