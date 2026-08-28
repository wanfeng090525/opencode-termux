# OpenCode for Termux

把上游 npm 的 `opencode-linux-arm64`（glibc 链接的 Bun 编译产物）用 `bun-termux-loader`
包成一个能在 **Termux（Android / Bionic）** 直接运行的独立二进制，并产出 `.deb` 安装包。

默认构建版本 **1.18.23**，版本可自行选择（见下文"构建"）。

参考实现：[Hope2333/opencode-termux](https://github.com/Hope2333/opencode-termux)

## 原理

上游 `opencode-linux-arm64` 是 glibc 链接的 aarch64 ELF（interpreter `/lib/ld-linux-aarch64.so.1`），
没法直接跑在 Bionic 上。方案是把它整体包进一个 **Bionic wrapper ELF**：

```
┌───────────────────────────────────────────┐
│ Bionic wrapper ELF (~12KB, /system/bin/linker64) │
│  读 /proc/self/exe → 找 BUNWRAP1 元数据       │
│  抽取内嵌 OpenCode(Bun ELF) 到 $TMPDIR 缓存   │
│  userland exec: mmap 加载 glibc ld.so 并跳转   │
├───────────────────────────────────────────┤
│ BUNWRAP1 元数据 (magic + bun_elf_size)       │
├───────────────────────────────────────────┤
│ 原始 OpenCode 二进制 (glibc Bun + JS, ~184MB)│
├───────────────────────────────────────────┤
│ BUNLIBS1 块 (bunfs_shim.so)                 │
├───────────────────────────────────────────┤
│ 内嵌 JS + "---- Bun! ----" trailer (EOF)    │
└───────────────────────────────────────────┘
```

关键点：

- **userland exec** 用 `mmap()` 映射 glibc 的 `ld.so` 后直接跳到其入口，不调用 `execve()`。
  于是 `/proc/self/exe` 仍指向 wrapper 自身，Bun 才能按文件尾部找到 `---- Bun! ----` 标记和内嵌 JS；
  否则会退化成 `bun` CLI 模式（这就是 `grun` 方案会挂的原因）。
- 首次运行会把内嵌 Bun ELF 抽取到 `$TMPDIR/bun-termux-cache/`（约 184MB 写入），之后直接复用，
  同时规避 Android SELinux 禁止 `memfd_create` + `mmap(PROT_EXEC)` 的限制。
- `bunfs_shim.so` 拦截 `dlopen()`，把 `/$bunfs/root/*.so` 重写到已抽取的真实路径。

`build.py` 是**纯二进制拼接**（不编译、不开 QEMU），所以任何 Linux 主机都能产 aarch64 产物，CI 也因此可复现。

## 目录

```
scripts/produce.sh         npm 下载 opencode-linux-arm64@VER + bun-termux-loader 打包
scripts/launcher.sh        TTY/锁清理启动器（deb 里安装为 bin/opencode）
scripts/package_deb.sh     打 .deb（ar + 控制文件，无 dpkg-deb 架构限制）
scripts/verify.py          结构校验（BUNWRAP1/内嵌 ELF/trailer/末尾大小）
Makefile                   wrap / deb / all 目标（VER 可传参）
.github/workflows/build.yml CI 手动构建（可选版本 / 发布）
runtime/opencode-termux    包装后的独立运行二进制（约 184MB，gitignore）
```

## 依赖（Termux 上）

```bash
apt install -y glibc-repo && apt update
apt install -y glibc openssl-glibc bash ncurses
```

## 安装

```bash
dpkg -i opencode_1.18.23_aarch64.deb
opencode --version        # → 1.18.23
opencode run "hi"
```

## 构建（本地，无需 Termux）

版本默认 1.18.23，可自行选择：

```bash
make all                # = produce.sh + package_deb.sh（默认 1.18.23）
make all VER=1.19.0     # 指定版本
./scripts/produce.sh 1.18.23            # 只要 wrapped 二进制
VERSION=1.18.23 ./scripts/package_deb.sh # 只要 .deb（需先有 runtime/opencode-termux）
```

> 上游 CLI 只从 npm 获取（`opencode-linux-arm64@<ver>`），不提供任何"填链接"入口；请勿使用
> `opencode-desktop-*`（桌面 GUI 包，非 Bun CLI 二进制）。

## CI（GitHub Actions）

仓库右上角 **Actions → Build OpenCode for Termux → Run workflow**。输入：

| 输入 | 默认 | 说明 |
|---|---|---|
| `version` | `1.18.23` | npm 发布版本号，可自行选择 |
| `publish` | off | 是否把产物发布到 Release |

产物（`.deb`）以 workflow artifact 形式下载。

## 许可证

MIT。