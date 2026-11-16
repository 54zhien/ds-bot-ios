# 崩溃符号化：`symbolicate.mjs`

一句话：把 `.ips` / `.crash` 里的裸地址换成函数名和源码行。

## 先写结论

- **必须在 macOS 上跑**。`atos` 和 `dwarfdump` 属于 Xcode 命令行工具，Windows 上没有，装也装不来。
- **状态：未验证**。这个脚本一次真实崩溃都没符号化过。解析部分在 Windows 上用伪造样本跑通了（见文末「自测」），符号化那一步没有跑过。
- 我们手上没有 mac，所以它现在是「将来能跑的那台机器」的备件，不是本次验收的产出。谁先拿到 mac，谁把它跑一遍再把这段改成「已验证」。

## 为什么需要它

TestFlight 和 Xcode 导出的 `.ips`，帧上只有 `0x104a4c3a0` 这样的地址。只有**同一次构建**产出的 dSYM 才能换回名字，dSYM 一丢，这份 crash 就永久读不出内容。所以每版 `.xcarchive` 和它的 dSYM 必须留档，这个脚本只是把留档用起来的那一步。

## 用法

```
node docs/qa/symbolicate.mjs CRASH --dsym DIR [--arch arm64] [--all] [--dry-run] [--json]
```

- `CRASH`：`xxx.ips`（iOS 15 及以后）或老的 `xxx.crash` 文本报告
- `--dsym DIR`：装着 `DSBot.app.dSYM` 和各个 `X.framework.dSYM` 的目录，即 `.xcarchive` 里 `dSYMs/` 那层
- `--dry-run`：只解析、只打印 atos 命令，不执行。**Windows 上就用这个**
- `--all`：所有线程，不只崩溃线程
- `--arch`：`arm64`（默认）或 `arm64e`；真机大多是 arm64，选错会全 `????`

## 地址和 base 从哪来（脚本内部做的）

`.ips`（JSON）：

- 镜像表 `usedImages[]` 的下标就是帧里的 `imageIndex`
- `base` = `usedImages[i].base`
- 帧的绝对地址 = `base` + `frames[j].imageOffset`

`.crash`（文本）：

- 帧行长这样：`0   DSBot   0x0000000104a4c3a0 0x1043c0000 + 16470048`
- 第 3 列是绝对地址，第 4 列是该镜像的 load address，最后一个数是偏移
- 镜像的 base 也可以在 `Binary Images:` 表里取（同时给出 UUID 与路径）

两种格式最后都落到同一条命令：

```
atos -arch arm64 -o <DWARF 二进制> -l <base> <绝对地址> [<绝对地址> ...]
```

## dSYM 怎么找

1. 递归扫 `--dsym` 目录，收集每个 `*.dSYM/Contents/Resources/DWARF/` 下的二进制（不往 `.dSYM` 里面继续走）
2. 先用 `dwarfdump --uuid` 比对 UUID，同名多个构建也不会配错
3. 没有 dwarfdump、或 UUID 对不上时退回镜像名匹配（`DSBot.app.dSYM` 里的二进制名就是 `DSBot`）
4. 每个镜像一次 atos，地址按 200 个一批，长栈不会把命令行撑爆

## 输出长什么样

```
crash     docs/qa/symbolicate-samples/app-crash.ips  [.ips]
process   DSBot  0.3.6 (360099) · iPhone OS 18.1.0 (22B83) · arm64
incident  5B0C7A11-3C4D-4E5F-9A10-B2C3D4E5F607
dSYM      2 binaries under docs/qa/symbolicate-samples/dSYM

Thread 775 (crashed)  main
  #  0  0x1043c6024  DSBot               (no symbol)
  #  1  0x1043c61a8  DSBot               (no symbol)
  #  3  0x1050033a4  DeepView            (no symbol)
  #  4  0x19b2c1234  libsystem_kernel.dylib  __pthread_kill
```

有 dSYM 时 `(no symbol)` 会变成 `函数名 (文件:行)`。

## 跑不起来按这个顺序查

1. `atos: command not found` → 没装命令行工具：`xcode-select --install`
2. 全是 `(no symbol)` 且 warning 里有 UUID → dSYM 不是这次构建的，拿 `dwarfdump --uuid` 和 crash 里的 UUID 对一遍
3. 只有系统库没符号（`libsystem_*` 之类）→ 正常。我们没有 Apple 的符号，不用追
4. 解出来是 `????` → arch 不对，`--arch arm64e` 再试
5. `no dSYM under …` → 路径指向了 `.dSYMs` 目录里带 `.app` 的那一层；`.app.dSYM` 是目录，不是 `.app`
6. 一帧都没匹配上 → 看 warning 列出的镜像名，确认那个 `*.framework.dSYM` 是不是漏拷

## 自测（Windows 上真跑过的部分）

夹具在 `docs/qa/symbolicate-samples/`：`app-crash.ips`、`app-legacy.crash` 是伪造的报告（数字对得上、内容不是真的），`dSYM/` 里是两个空文件，只用来让解析器有路径可指。

```
node docs/qa/symbolicate.mjs docs/qa/symbolicate-samples/app-crash.ips --dsym docs/qa/symbolicate-samples/dSYM --dry-run
node docs/qa/symbolicate.mjs docs/qa/symbolicate-samples/app-legacy.crash --dsym docs/qa/symbolicate-samples/dSYM --all --dry-run
```

两次都正确输出了 base、绝对地址与 atos 命令，说明：JSON 与文本两种格式都解析对了，镜像匹配（含架名回退）生效。不加 `--dry-run` 时在 Windows 上会打印同样命令并给出 `atos is not on this machine`，这是预期行为。

没验证的：atos 的真实输出、UUID 精确匹配分支、多架构二进制选片。这三样只能在 mac 上验。
