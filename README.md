# miniserve 快速启动（Windows）

一个「双击就能开」的极简文件服务器：**支持网页上传/下载/删除**、账号密码、日志落盘、浅色美化首页，路径和端口全部写在 `config.txt` 里。

[原服务地址](https://github.com/svenstaro/miniserve)：本项目只是套了一层壳。使用更加的方便、界面更加美观。

---

<img src="assets/image-20261123162153960.png" alt="image-20261123162153960" style="zoom:80%; float:left" />

## 1. 目录结构

```
miniserve/
├─ start.bat              # 启动入口（只是调用 PowerShell 的薄壳）
├─ config.txt             # 配置：端口、目录、上传、下载、认证、日志
├─ messages.txt           # 启动时的中文提示模板（可改文案）
├─ web/
  ├─ serve.ps1           # ★ 启动器主体：读配置、拼参数、部署首页、跑服务
  ├─ home.html           # 根目录美化首页模板（自动部署）
  ├─ deploy.ps1          # 把首页模板部署到共享目录
  └─ guard-upload.ps1    # 上传目录守护（被误删时自动重建）
├─ logs\miniserve.log     # 运行日志（LOG_TO_FILE=1 时自动生成）
└─ miniserve-0.35.0-...exe # miniserve 本体（换版本直接替换）
```

> **为什么用 PowerShell 而不是纯批处理？**
> 批处理处理引号、括号、`!` 延迟展开时非常脆弱（开发过程中反复踩到
> `" was unexpected at this time.`、`%%~nF` 展开失败、多余引号导致整个脚本无法启动等问题）。
> PowerShell 用数组传参、没有这些坑，逻辑全部集中在 `web\serve.ps1`。

---

## 2. 快速开始

1. 记事本打开 `config.txt`，按需改端口 / 目录 / 上传目录。
2. 双击 `start.bat`，浏览器自动打开 `http://localhost:8000/`。
3. 停止服务：窗口里按 `Ctrl+C`。

**局域网访问**：用本机局域网 IP，如 `http://192.168.1.10:8000/`（启动窗口已列出所有可用地址）。
连不上多半是防火墙，首次运行弹窗里勾选「专用网络」，或手动放行：

```powershell
New-NetFirewallRule -DisplayName "miniserve 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
```

---

## 3. 界面结构（重要）

| 位置 | 页面 | 拥有的功能 |
|---|---|---|
| **共享根目录** `/` | 本项目自定义首页 | 拖拽上传、文件列表、**单文件下载**、子目录打包下载按钮、删除按钮、文件名过滤（超过 20 项分批渲染）、**深色模式跟随系统**、**移动端自适应**、**左上角图标点击回到首页** |
| **子目录** `/upload/` 等 | **miniserve 官方列表页**（squirrel 浅色主题） | 官方下载按钮（zip / tar.gz）、拖拽上传、✗ 删除、搜索框、排序、README 渲染 |

> **为什么子目录用官方页？**
> miniserve 的 `?download=zip` 打包下载由官方列表页处理，**而目录里一旦存在 `index.html`，
> actix-files 就会用 index.html 顶替官方列表页**（`?download=` 同时失效）。
> 所以想让每一层都能打包下载，就必须让子目录保持官方列表页。
> `RECURSIVE_INDEX=1` 可让所有子目录都用美化首页，但那时子目录将失去打包下载功能。

---

## 4. config.txt 参数说明

以 `#` 或 `;` 开头的行是注释；路径默认相对 `start.bat` 所在目录。

| 键 | 默认值 | 说明 |
|---|---|---|
| `PORT` | `8000` | 监听端口 |
| `SERVE_DIR` | `.` | 要共享的目录 |
| `UPLOAD_DIR` | `/upload` | 允许上传的虚拟目录（相对 `SERVE_DIR`）。留空 = 任意位置可上传 |
| `MKDIR` | `1` | 是否允许创建目录 |
| `ON_DUPLICATE` | `rename` | 同名文件：`error` / `overwrite` / `rename`（自动加 `-1`） |
| `MEDIA_TYPE` | 空 | 限制上传类型：`image` / `audio` / `video` |
| `HIDDEN` | `0` | 是否显示隐藏文件 |
| `VERBOSE` | `1` | 是否输出访问日志 |
| `OPEN_BROWSER` | `0` | 启动后自动开浏览器 |
| `DISABLE_INDEXING` | `0` | `1` = 关闭目录列表（纯下载服务器） |
| `INDEX` | `index.html` | 根目录首页文件；留空用官方列表页（自定义首页会复用 miniserve 官方 favicon） |
| `RECURSIVE_INDEX` | `0` | `1` = 所有子目录都用美化首页（会失去子目录打包下载） |
| `INDEX_REFRESH` | `0` | `1` = 每次启动覆盖首页（默认保留你自己的修改） |
| `ENABLE_WEBDAV` | `1` | 只读 WebDAV（首页靠它列目录），设 INDEX 时自动开启 |
| `ENABLE_TAR_GZ` | `1` | 官方打包下载 tar.gz（官方页显示下载按钮） |
| `ENABLE_ZIP` | `1` | 官方打包下载 zip |
| `ENABLE_TAR` | `0` | 官方打包下载 tar（不压缩，体积大） |
| `COLOR_SCHEME` | `squirrel` | 官方浅色主题（squirrel 为唯一浅色，其余深色） |
| `COLOR_SCHEME_DARK` | `archlinux` | 官方深色主题 |
| `ALLOW_DELETE` | `1` | 是否允许删除（官方页 ✗ 按钮 + 首页 🗑 按钮） |
| `RM_DIR` | 空 | 允许删除的目录，留空跟随 `UPLOAD_DIR`（**不建议留空**，见下方说明） |
| `GUARD_UPLOAD` | `1` | 上传目录守护：自动重建被误删的上传目录 |
| `COMPRESS` | `0` | 响应压缩，见第 7 节评估 |
| `LOG_TO_FILE` | `1` | 日志写入本地文件 |
| `LOG_FILE` | `logs\miniserve.log` | 日志路径 |
| `LOG_MAX_MB` | `10` | 日志超过此大小自动轮转（`.log.1`、`.log.2`），`0` = 不轮转 |
| `PRETTY_URLS` | `0` | `/about` → `about.html` |
| `SPA` | `0` | 404 时返回 `INDEX` 文件 |
| `SORTING_METHOD` | `name` | `name` / `size` / `date` |
| `SORTING_ORDER` | `desc` | `asc` / `desc` |
| `AUTH` | 空（注释） | 单用户认证 `用户名:密码` |
| `AUTH_FILE` | 空（注释） | 多用户认证文件 |
| `ROUTE_PREFIX` | 空 | 路由前缀，如 `/files` |

**认证示例：**

```ini
AUTH=admin:123456
# 或多用户文件（每行 用户名:密码）
# AUTH_FILE=auth.txt
```

### 返回首页

自定义首页左上角的 📁 图标是链接，点击即回到共享根目录。
在 `RECURSIVE_INDEX=1`（所有子目录都用自定义首页）时，从任意层级都能一键回到首页；
`RECURSIVE_INDEX=0` 时子目录是官方列表页，官方页面自带面包屑导航，同样可以回到上层。

### 大目录性能

首页一次性渲染上万 DOM 节点会导致浏览器卡顿，因此**默认只渲染前 20 项**，
底部有「显示更多」按钮可继续加载（每次 +20），配合顶部搜索框可以快速定位任意文件。

> 注意：miniserve 的 `--index` 机制下，**目录里只要有 `index.html`，
> 官方的列表页 / 搜索 / 打包下载就都不可达**（包括 `?raw=true`、`?search=`、`?download=zip`）。
> 这正是子目录保留官方列表页（`RECURSIVE_INDEX=0`）的原因。

---

## 4.5 上传目录被删掉的问题（重要）

### 问题

miniserve 的删除接口有个特性：允许删除的目录**自身**也能被删。源码（`src/file_op.rs`）：

```rust
let rm_allowed = conf.allowed_rm_dir.is_empty()
    || conf.allowed_rm_dir.iter().any(|s| rm_path.starts_with(s));
```

`Path::starts_with` 按路径组件匹配，`"upload".starts_with("upload")` 为真
→ 于是 `POST /rm?path=upload` 会把**整个上传目录删掉**，之后所有人都传不了文件。

（官方列表页本身不会给出这个按钮——它的删除按钮按"当前所在目录"是否在允许范围内来决定，
根目录不在 `/upload` 范围内，所以官方页不会出现"删除 upload 目录"的入口。
但直接调 API 依然可以删。）

### 本项目的双重保护

1. **前端**：首页的删除按钮会跳过「上传目录本身」和「包含它的上级目录」，
   删除范围也必须是**严格位于** `RM_DIR` 之内（不能等于它）。
2. **守护进程**：`web\guard-upload.ps1` 每秒检查一次上传目录，
   一旦发现被删就自动重建，并把记录写进 `logs\guard.log`。
   守护进程会随 miniserve 退出而自动结束。

### 建议

* `RM_DIR` 一定要**显式指定**成一个具体目录（如 `upload`）。
  如果 `RM_DIR` 和 `UPLOAD_DIR` 都为空，脚本会**直接禁用删除功能**并给出警告——
  因为此时 miniserve 允许删除任意路径，风险太大。
* 想彻底关闭删除：`ALLOW_DELETE=0`。
* 想彻底关闭守护：`GUARD_UPLOAD=0`（不建议）。

---

## 5. 常用方法

### 5.1 发文件给同事

`config.txt`：`PORT=8000` / `SERVE_DIR=./share` / `UPLOAD_DIR=/upload` / `AUTH=admin:123456`

把 `http://<你的局域网IP>:8000/` 发给同事，对方可以浏览、下载、拖拽上传。

### 5.2 下载（三种方式）

1. **官方列表页**：进入子目录，点官方工具栏的 zip / tar.gz 按钮 → 整个目录打包下载。
2. **首页**：根目录美化首页上，每个子目录行有 `⬇ zip` / `⬇ tgz` 按钮；每个文件行有 `⬇ 下载`。
3. **命令行**：
   ```bash
   curl -O "http://127.0.0.1:8000/path/to/file.zip"
   curl -o out.zip "http://127.0.0.1:8000/upload/?download=zip"
   ```

### 5.3 上传（curl）

miniserve 的上传接口是 `POST /upload?path=<目标目录>`：

```bash
# 上传到 /upload 目录
curl -F "file=@./test.zip" "http://127.0.0.1:8000/upload?path=/upload"
# 多文件
curl -F "file=@a.zip" -F "file=@b.zip" "http://127.0.0.1:8000/upload?path=/upload"
# 带认证
curl -u admin:123456 -F "file=@test.zip" "http://127.0.0.1:8000/upload?path=/upload"
```

返回码：`303` 成功、`403` 目录不在允许范围、`401` 需认证。

### 5.4 删除（curl）

```bash
curl -X POST "http://127.0.0.1:8000/rm?path=upload/old.txt"
```

受限目录外的路径返回 `403`。网页上：官方列表页每行有 `✗`，自定义首页每行有 `🗑 删除`。

### 5.5 常用参数速查

| 需求 | 参数 |
|---|---|
| 允许上传 / 指定目录 | `-u` / `-u /upload` |
| 允许创建目录 | `-U` |
| 允许删除 | `-R` 或 `-R /some/dir` |
| 同名覆盖 | `-o overwrite` |
| 账号密码 | `-a user:pass` |
| 随机路径 | `--random-route` |
| 打包下载 | `-r` / `-g` / `-z` |
| README 渲染 | `--readme` |
| 只读 WebDAV | `--enable-webdav` |
| 关闭目录列表 | `-I` |
| 目录优先 / 精确字节 | `-D` / `--size-display exact` |
| 外部直链地址 | `--file-external-url http://dl.example.com` |
| TLS | `--tls-cert cert.pem --tls-key key.pem` |
| 浅色主题 | `--color-scheme squirrel` |

### 5.6 常见问题

| 现象 | 处理 |
|---|---|
| 端口被占用 | 改 `PORT` |
| 别人访问不了 | 防火墙放行；同一网段；`ipconfig` 查 IP |
| 上传 403 | `path=` 指向的目录不在 `UPLOAD_DIR` 内 |
| 子目录没有打包下载 | 正常现象（子目录用官方页，官方页有下载按钮） |
| 首页没生效 | 确认 `INDEX=index.html` 且共享根目录有该文件；`Ctrl+F5` 强刷 |
| 中文乱码 | `web\home.html`、`messages.txt` 存为 **UTF-8 无 BOM** |
| 日志无访问记录 | 需要 `VERBOSE=1` |
| 共享目录是 git 仓库 | 脚本会自动把 `index.html` 写进 `.gitignore` |

---

## 6. 日志

`LOG_TO_FILE=1` 时终端照常显示，同时追加写入 `logs\miniserve.log`（UTF-8）：

```
Sun, 22 Nov 2026 16:20:03 +0000 [INFO] 192.168.99.21 "GET /README.md HTTP/1.1" 200 9238 "-" "Chrome/157.0" 0.000465
Sun, 22 Nov 2026 16:20:05 +0000 [INFO] 127.0.0.1 "POST /upload?path=/upload HTTP/1.1" 303 0 "-" "curl/8.21.0" 0.012345
```

每次启动会写一行 `==== start 时间 ====` 分隔标记。

**自动轮转**：日志超过 `LOG_MAX_MB`（默认 10 MB）时，启动时自动重命名为 `.log.1`，
再旧的变为 `.log.2`（最多保留两份）。这样长期运行也不会撑爆磁盘。

---

## 7. 关于响应压缩 `-C` 的评估（结论：默认关闭）

实测数据（20MB 文件，本机 loopback）：

| 文件类型 | 关闭 `-C` | 开启 `-C` | 结论 |
|---|---|---|---|
| 20MB 纯文本 | 21.2MB / 0.03s | **117 B** / 0.06s | 收益巨大 |
| 20MB 随机二进制 | 21.0MB / 0.03s | 21.0MB / **0.15s** | 纯浪费，CPU 涨 5 倍 |

原因（actix-web 源码 `middleware/compress.rs`）：压缩器只对 `image/*` 和 `video/*` 之外的类型生效，
所以 **zip/gz/mp3/exe 等已压缩格式也会被再压一遍**——既不省流量又吃 CPU。

**建议：**
- 局域网（千兆）内共享大文件 → **保持关闭**，瓶颈是磁盘不是网络。
- 只共享代码/文档、且要走公网或慢速链路 → 可以开启，文本能压到几十分之一。
- 想要「整目录打包下载」→ 用官方的 `?download=zip`，那个才是真正的省流量。

---

## 8. 性能实测（本机）

| 场景 | 结果 |
|---|---|
| 50 并发 × 10MB 下载 | 全部 200，0.83s 完成 |
| 400 次连续请求 | 400/400 成功，无 5xx |
| 30 并发上传 | 30/30 落盘，无丢失、无冲突 |
| 混合压测（50 下载 + 30 上传 + 20 列表） | 1.52s 全部成功，服务存活 |
| 压测后进程状态 | 内存 15MB，句柄 144，CPU 7s（正常） |

---

## 9. 安全建议

1. **开上传 = 允许别人往你磁盘写文件**，务必设 `AUTH`，或把 `UPLOAD_DIR` 限制到独立目录。
2. 别把系统根目录（如 `C:\`）设为共享目录，避免上传的 `.html`/`.js` 被当页面执行。
3. 公网暴露请套 Nginx/Caddy 做 HTTPS，或用 `--tls-cert/--tls-key`。
4. 密码建议哈希：`AUTH=admin:sha256:<hash>`。
5. 用完及时 `Ctrl+C` 停止服务。

---

## 10. 官方资料

* 项目主页：https://github.com/svenstaro/miniserve
* 完整参数：`miniserve.exe --help`
* 打包下载接口：`?download=zip` / `?download=tar.gz` / `?download=tar`
* 搜索：`?search=关键字`
* 排序：`?sort=name&order=asc`
