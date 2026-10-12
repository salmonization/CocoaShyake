# CocoaShyake — 开发计划

CocoaShyake 是 Shyake 的 macOS 客户端,形态为 **Cocoa/AppKit GUI 程序,Objective-C 编写**,在独立仓库(`CocoaShyake`)开发与发布,版本号独立,协议兼容性以 docs/SPEC.md 为契约。(本文件先在 shyake 仓库起草,新仓库建立后随之迁移。)

**macOS 是 libshyake 的原生平台**,上游本来就在 macOS 构建。因此没有 fork、没有移植、没有加密栈替换——CocoaShyake 直接以 git submodule 引用上游 `shyake` 仓库,编译 `client/src/lib/` 链接使用,零移植成本,也反向验证了"libshyake 之上任何人都能造客户端"的架构宣言。

**设计基线:上游 v0.4.0(`b39766b`,protocol level 3)**。立项时的基线是 2026-07-18 的 `c6bf410`;之后上游的 68 个提交带来的客户端可见变化已并入本文件:回复(§5)、发送失败转草稿、`<动作> failed. <原因>` 的报错约定、`user@domain` 身份显示、草稿的 `enc_reply_to` 字段。签名请求体(level 2)与协议级别协商全在库和服务器里,GUI 无感。

## 1. 定位与目标

- 与 Unix CLI 同级的**另一个参考客户端**,完整实现 docs/SPEC.md 协议。
- 语言 **Objective-C**(已决策,理由记录于第 2 节),UI 为 AppKit 经典三栏。
- 产物 **Universal Binary(arm64 + x86_64)**,单一 `CocoaShyake.app`,zip 分发,免安装。
- 数据模型忠于 Unix 版语义(第 5 节):远端实时视图、显式本地化、手动刷新、无后台轮询。
- 不做安装器、不做自更新、不做版本检查、**不做 Apple 公证**(见第 9 节)。
- macOS 上已有上游 CLI 可用,脚本化场景由 CLI 天然覆盖,CocoaShyake 只面向 GUI 用户。**CLI 的 `~/.config/shyake` 就是 CocoaShyake 的默认 profile,原地使用、不复制**:同一个账号两个客户端,没有副本可以分叉。

## 2. 语言决策:Objective-C 而非 Swift

1. **FFI 零成本**:ObjC 是 C 的严格超集,`#import "shyake.h"` 直接调用,指针与 free 函数的用法和上游 `src/cli/` 完全一致;Swift 侧每个指针都要过 `UnsafeMutablePointer` 仪式。
2. **裸缓冲区可控**(有限的安全论据):C/ObjC 能持有 malloc 缓冲区并 `memset_s` 清零。但要诚实——`NSSecureTextField` 的 `stringValue` 给出的是 `NSString`,同样是堆分配、不可变、写时复制、无法可靠清零,这一点 ObjC 并不优于 Swift。做法是拿到 `stringValue` 后立刻转入 malloc 缓冲区交给 ctx,并接受 `NSString` 那份残留;另外 `setrlimit(RLIMIT_CORE, 0)` 禁掉 core dump,避免崩溃时 passphrase 落盘。
3. **技能栈与气质一致**:三客户端语言谱系为 C / C / ObjC,对 C 程序员学习成本最小;AppKit 经典范式(target-action、delegate)本就定型于 ObjC 时代。

## 3. 依赖与构建

- **libshyake:上游 submodule,不 fork**。本仓库 Makefile 用通配符直接编译 `shyake/client/src/lib/*.c` 与 `vendor/cJSON` 到 `build/libshyake.a`(与上游 Makefile 同一写法,上游新增 .c 自动纳入,源文件清单不存在漂移问题;不调用上游 Makefile,免得在 submodule 里留下构建产物)。上游有协议变更时 bump submodule 即可,无移植成本。
- **草稿:直接编译上游 `client/src/cli/drafts.c`,不重写**。上游把草稿放在 CLI 而不是库里,但这个文件只依赖 libc、cJSON 和公开的 `shyake.h` selfenc 原语,原样编进 `libshyake.a` 即可(已验证可独立编译)。这样 `enc_reply_to`、`O_EXCL` 分配 id、`created`/`modified` 规则全部与 CLI 一字不差,草稿互认由构造保证,不靠测试兜底。NTShyake 当初重写了一份,上游一改就要跟,这里不再重复那条路。
- **liboqs**:静态链接(项目惯例)。Universal Binary 需要 arm64 与 x86_64 各编一份后 `lipo` 合并(CMake 一次配好,脚本化)。
- **libcrypto(OpenSSL)**:macOS 不再自带 OpenSSL 头文件,从 Homebrew 或源码构建,**静态链接**进 app(不能依赖用户机器上的 brew);同样双架构 + lipo。
- **libcurl**:用 **macOS 系统自带的 libcurl**(`/usr/lib/libcurl.4.dylib`,系统 SDK 提供链接桩),免打包、免证书文件(走系统信任库),TLS 由系统 curl 的后端处理。
  - **与 NTShyake 的有意分歧**:NTShyake 打包 `cacert.pem` 且不用系统证书库(XP 的证书库既过时又缺 TLS 1.2 生态);macOS 的系统信任库是持续更新的,信任它是平台惯例且免去了 bundle 过期的维护负担。这是有意决策,不是各自演化的结果。
  - **CA 行为已核实**:上游 `client/src/lib/` 不设置任何 `CURLOPT_CAINFO` / `CURLOPT_SSL_*` 选项,信任链完全交给 curl 后端默认值,即 macOS 系统信任库,不存在选项被后端忽略的问题。仍需对真 instance 打一次 HTTPS 作为冒烟(wrangler 本地只有 HTTP)。
  - 静态 libcrypto 与系统 curl 各自带一套 TLS/crypto 符号,静态库以 `-fvisibility=hidden` 构建避免符号冲突。
- **构建系统:不用 Xcode 工程,clang + make**。一个 Makefile 完成编译上游库、编译 ObjC、手工组装 `.app`(`Contents/MacOS`、`Info.plist`、`Resources/*.lproj`)、`codesign -s -`。只依赖 Command Line Tools,`make` / `make run` / `make test` / `make format`。
  - 代价:没有 Interface Builder,**全部界面用代码搭**(见第 5 节);`.strings` 直接以文本放进 `.lproj`,不需要编译步骤。
  - 开发期链接 brew 的 arm64 静态 `liboqs.a` / `libcrypto.a`。brew bottle 按本机 macOS 版本编译,所以开发产物实际只能跑在本机版本及以上——Makefile 如实以本机版本链接,我们自己的代码仍按 10.13 编译以保留可用性检查。
  - Universal Binary 与 10.13 下限都推迟到 M5:届时用 `deps.sh` 以 `-mmacosx-version-min=10.13` 自建两架构 liboqs/libcrypto 并 `lipo` 合并,Makefile 对每个架构各编一遍再 `lipo` 主程序。

## 4. 数据目录与 profile

```
~/.config/shyake/                        # 上游 CLI 的目录:存在即为第一个 profile,原地读写
~/Library/Application Support/CocoaShyake/
└── profiles/                            # 本 app 新建的其余 profile
    ├── work/                            # 与 ~/.config/shyake/ 内容完全兼容
    │   ├── config
    │   ├── kem_pk.bin / kem_sk.bin / sig_pk.bin / sig_sk.bin
    │   ├── known_hosts
    │   ├── saved/<id>.json
    │   └── drafts/<id>.json
    └── <name>/
```

- **profile 就是一个目录**,以路径为身份。`~/.config/shyake` 按 CLI 的规则解析(`$HOME/.config/shyake`),存在时排第一、显示名为 `~/.config/shyake`;向导新建的放在 Application Support 下,名字是用户自取的短名。已有 CLI 配置的用户启动即进入自己的账号,不走向导。
- CLI 与 GUI 同时用同一目录是安全的:草稿 id 以 `O_EXCL` 分配(上游 `drafts.c`),其余写入都是用户显式动作。
- 目录内容与 `~/.config/shyake/` 互拷兼容是硬性约束,所有格式零特化。
- GUI 状态走 `NSUserDefaults`(标准位置):上次打开的 profile(存路径)、窗口与分栏几何、树的展开状态;profile 目录内只有协议数据。
- **不集成 Keychain**:密码短语只走 scrypt 加密的密钥文件,与其他平台行为一致,保持 profile 可拷贝迁移;Keychain 绑定单机、引入 Apple 依赖,违背项目哲学。
- 单实例由 macOS 天然保证(LaunchServices 同一 app 不二开),无需 mutex。

## 5. GUI 设计

### 主窗口(NSSplitView 三栏)

```
┌────────────────────────────────────────────────────────────┐
│  CocoaShyake   File  Mail  Profile  Help          (系统菜单栏)  │
├──────────┬─────────────────────────────────────────────────┤
│▾ salmon@…│ ID       From        Subject        Date        │
│   Inbox  │ fQBjZ…   flat_white  Coffee?        07-18       │
│   Sent   │          (NSTableView)                          │
│   Saved  ├─────────────────────────────────────────────────┤
│   Drafts │  正文阅读窗格(只读 NSTextView,等宽可选)          │
│▸ work@…  │                                                 │
├──────────┴─────────────────────────────────────────────────┤
│ Profile: default   salmon@shyake.eee.coffee   (状态栏文本)  │
└──────────┴─────────────────────────────────────────────────┘
```

- 界面全部用代码构建(不用 XIB/storyboard——没有 Xcode 工程,也就没有 Interface Builder);布局用 `NSSplitView` 与 autoresizing mask,不依赖可视化编辑器。左栏是 **profile → 信箱的树**(`NSOutlineView`,source list 样式,Sylpheed/Claws Mail 的文件夹树、Mail.app 侧栏同一形态):每个 profile 一个可折叠的根节点,显示为 `user@domain`(未注册则显示 profile 名,悬停显示目录),其下 Inbox/Sent/Saved/Drafts 四个固定子节点;点到哪个 profile 的信箱就切到那个 profile,展开状态按路径持久化。右上 `NSTableView` 列表(列 = `CHECK_COLUMNS`,列宽自动持久化是 AppKit 免费功能),右下只读 `NSTextView` 纯文本(无富文本——Unix 端本就是纯文本邮件),**提供等宽字体开关**(View 菜单,记入 NSUserDefaults;邮件正文常含 base64 与代码,等宽实用)。
- 外观跟随系统:AppKit 控件自动适配浅色/深色模式与强调色,**不硬编码颜色字体**,深色模式无需任何额外工作。

### AppKit 默认行为的强制关闭项

AppKit 有几个默认开启的"贴心"功能会直接违反本项目的硬约束,必须在 M1 显式关掉,不是可选优化:

- **窗口状态恢复**:系统会把可恢复窗口的内容序列化进 `~/Library/Saved Application State/`,`NSTextView` 参与该编码。撰写到一半的正文、阅读窗格里解密后的明文都可能被系统自动写盘,**绕过"Export 是唯一明文落盘途径"这条规则**。主窗口与撰写窗口一律 `restorable = NO`。验收方式:撰写窗口填一半强杀进程,`grep -r` 该目录确认正文不在其中——这条必须实测,不能只信文档。
- **智能标点与文本替换**:`NSTextView` 默认开 `automaticQuoteSubstitution` / `automaticDashSubstitution` / `automaticTextReplacement`,会把用户粘贴的 base64、代码里的 `"` 变成 `""`、`--` 变成 `–`,**静默破坏正文**。撰写视图连同拼写检查、语法检查、data detectors 一并关闭。
- **剪贴板**:阅读窗格复制正文会经 Universal Clipboard 同步到用户的其它 Apple 设备。至少在 README 注明;是否给 pasteboard item 标 `org.nspasteboard.ConcealedType` 待定。

### 操作逻辑:经典邮件客户端的皮,shyake 的骨

布局像传统三栏邮件客户端,但**不引入其"本地信箱 + 后台透明同步"的数据模型**——那与 Shyake"服务器只存密文、本地存储必须是用户显式行为"的威胁模型冲突。规则是把 Unix 版命令语义一对一映射成 GUI 动作:

- **Inbox/Sent 远端实时视图**:⇧⌘N 刷新(`check`),列表只驻内存,退出即失;无已读/未读,无后台同步、无通知。
- **单击看信头,回车/双击 fetch**:fetch 才发网络请求并解密,正文只在内存,切换选中项即清空清零。
- **Save(⌘S,存密文)、Export…(唯一明文落盘途径,NSSavePanel)、Burn(⌘⌫,确认弹窗;与 Mail.app 一致,裸 ⌫ 做菜单快捷键会和文本框抢键)** 全部显式,经 Mail 菜单与右键菜单。
- **Reply(⌘R)**:对应 `reply <id>`,见下文"回复"。
- **断网**:Inbox/Sent 报错于状态栏,Saved/Drafts 照常。
- 快捷键遵循 Mail.app 惯例:⌘N 撰写、**⌘R 回复、⇧⌘N 收取**(刷新)、⌘W 关窗。原计划 ⌘R 刷新,有了回复之后会和 Mail.app 的肌肉记忆冲突,改掉。

### 回复(上游 v0.4.0)

回复不是引用原文,而是带一个密码学引用:`ref` 是原邮件签名的 SHA-256,随回复加密并签名(SPEC §3.2)。GUI 映射:

- **发起**:Mail → Reply。撰写窗口的收件人取 `shyake_reply_recipient()`(对方,或自己发给自己时是自己),**不可编辑**——上游回复草稿就没有 To: 行;主题预填 `Re: <原主题>`;发送走 `shyake_send_reply()`。
- **原文并排只读**:撰写窗口上下分栏,上方只读显示被回复的邮件,下方写正文。这是上游 vim 分屏 / 剪刀线的 GUI 对应物,不把原文拼进正文。原文来自已 fetch 的内存数据,不额外落盘。
- **阅读窗格的 RE 行**:邮件详情有 `reply_ref` 时,信头多一行 `RE:`,经 `shyake_find_ref()` 解析为原邮件 ID、`<id> (saved)` 或 `(unavailable)`;可点击跳转到原邮件。`find_ref` 要查 inbox/sent 列表(走网络),必须在 worker 队列上随 fetch 一起解析。
- **对端不支持**:双方实例都需 protocol level 3。不到时服务器答 `422`,库给出原因,GUI 照常报 `Reply failed. <原因>`,并按下条转存草稿。客户端不做版本探测。

### 发送失败转草稿(上游 v0.2.3)

上游 CLI 在 send/reply 失败时把正文存为加密草稿(`rescue_draft`),因为 stdin/编辑器里的文本否则会丢。GUI 的撰写窗口本来就不会丢字,但为了跨客户端行为一致:**失败即自动存草稿,窗口保持打开并绑定到该草稿 id**——之后 Save Draft 覆盖同一 id,Send 成功则删除它。回复的草稿带 `reply_ref`,从 Drafts 打开时恢复为回复撰写窗口。

### 报错约定(上游 v0.3.0)

库的 `shyake_last_error()` 只给原因("You are blocked by flat_white."),动作由客户端加。GUI:`NSAlert` 的 messageText 是 `Send failed.` 这类动作句,informativeText 是原因;状态栏类的轻提示用同一句式拼成一行。唯一例外与 CLI 相同:`SHYAKE_ERR_KEY_MISMATCH`(对方密钥变了)用 critical 样式,并提供按钮直接打开该用户的 Fingerprint 对话框。

### 撰写窗口(compose / send)

独立 `NSWindow`(可多开):To、Subject 单行 `NSTextField`,正文 `NSTextView`,按钮 Send / Save Draft / Import File…(NSOpenPanel 读 .txt 作正文)。回复时 To 只读、上方多一个只读原文分栏(见"回复")。规则继承:草稿经上游 `drafts.c` 加密落盘、Send 前确认(回复同样确认,上游 v0.4.0 起 reply 也只在确认后发送)、主题 128 字节本地拒、CRLF→LF 归一化、发送/保存后清空控件与缓冲区、永不落明文临时文件——上游 CLI 的编辑器要写 0600 临时文件,GUI 在内存里编辑,天然没有这个问题。

### 对话框与流程

- **首次运行向导**:profiles 为空时的分步 sheet(profile name → instance URL → passphrase → 注册,可跳过注册)。**`USERNAME` 只在注册成功后写入 `config`**(上游 v0.3 起的行为);用户名格式与大小写变体由服务器拒绝,向导只展示库给的原因,不在客户端重复校验规则。
- **`config` 的读写**:上游没有把 config 解析放进库,GUI 自己读写这个 key=value 文件,且**只改自己管的键(`INSTANCE`、`USERNAME`),其余行原样保留**——与 CLI 改写 config 的方式一致,保证互拷后两边都不丢设置。`CHECK_COLUMNS` 决定列表列;`TIME_FORMAT`/`TIME_ZONE`/`NO_COLOR`/`DEFAULT_ACTION`/`EDITOR` 是 CLI 呈现层的设置,GUI 不读(日期按系统区域格式显示),但也不删。
- **身份显示**:状态栏与 Profile 详情一律 `user@domain`(上游 v0.3 起的显示约定)。
- **解锁**:首次进入某个 profile 时 `NSSecureTextField` sheet;取消则未解锁状态,浏览元数据照常,需密钥操作时再弹。**每个打开过的 profile 各持一个 ctx,解锁一次管到退出**(多账号树里每次点另一个账号都重输口令不可用,Mail/Claws 也是如此);退出时所有 ctx 同步 `shyake_free_ctx`,passphrase 由库清零,GUI 侧缓冲区 `memset_s` 清零。
- **Profile 菜单**:切换、New Profile…、详情(whoami + 自指纹)。
- **Fingerprint**(known_hosts 不符时警告 + 带外验证提示,确认后才更新)、**Blocklist**(列表 + Add/Remove)、**Rotate / Destroy**(后果说明 + 输入用户名作确认词)、**enc/dec 文件工具**(File 菜单包装 `shyake_enc_file` / `shyake_dec_file`)。

### 线程模型

- 全部 libshyake 调用排进**一条 serial `dispatch_queue`**(ctx 非线程安全 + libcurl 阻塞),完成后 `dispatch_async` 回主队列刷 UI。
- 请求中:菜单项禁用 + 状态栏文字;失败经 `shyake_last_error` 显示。
- `DEBUG=1` 时 curl verbose 写 `~/Library/Logs/CocoaShyake/debug.log`(mac 惯例位置),默认关闭,文档注明含元数据。

## 6. i18n

- 全部字符串走 `.strings` 文件(`NSLocalizedString`),**en / zh-CN / ja 三语同步**,跟随系统语言。

## 7. 开发环境

- 本机(Apple Silicon Mac)即完整开发环境:Command Line Tools + Homebrew(`liboqs`、`openssl@3`、`clang-format`;M5 自建依赖时再用 cmake)。不需要打开 Xcode。
- x86_64 切片经 **Rosetta 2** 直接实测(`arch -x86_64 ./CocoaShyake.app/Contents/MacOS/CocoaShyake`),无需 Intel 实机。**注意 Rosetta 有保质期**:Apple 已宣布 macOS 27 之后只保留给老游戏的子集。届时 x86_64 要么降级为"只编译不实测",要么留一台 Intel 机——不必现在解决,但别把长期验收押在它上面。
- e2e:本机 `npx wrangler dev --local` + 上游 `tests/e2e_test.sh` 环境齐备,和开发上游 shyake 是同一套流程。

## 8. CI:GitHub Actions

- `macos-latest`(Apple Silicon runner):deps.sh 构建双架构依赖(Actions cache 缓存)→ `make`(Universal)→ ad-hoc 签名 → zip → SHA-256 写入 Release notes。CI 与本地走同一个 Makefile。
- CI 跑上游 `test_crypto`(两架构,x86_64 经 Rosetta)+ wrangler 本地 e2e。**M0 先确认 ARM runner 是否预装 Rosetta**,没有就得先 `softwareupdate --install-rosetta --agree-to-license`。
- GUI 冒烟靠本机手工,CI 不做 UI 测试。

## 9. 分发

- GitHub Releases,单个 `CocoaShyake-<ver>.zip`(Universal Binary),README 写明 SHA-256 校验(`shasum -a 256`)。
- **不做 Apple 公证**(不入开发者计划):Gatekeeper 会拦截。**注意 macOS 15 起"右键 → 打开"这条路已被移除**,README 必须写现行方式:系统设置 → 隐私与安全性 → 仍要打开,或 `xattr -d com.apple.quarantine CocoaShyake.app`。照老写法写会让用户直接卡死。
- **Apple Silicon 强制要求签名,ad-hoc 签名即满足**:`codesign -s -` 零成本。**不要用 `--deep`**,Apple 已明确不推荐,应逐个签嵌套内容。注意 ad-hoc 签名的 app 每次二进制变动后 quarantine 处理要重来,README 一并说明。
- 部署目标 **10.13**,Universal Binary(arm64 + x86_64),系统 libcurl。**不做老系统构建线**(理由见下节)。

## 10. 测试

- 上游 `test_crypto` 双架构通过;与 Unix CLI 跨客户端互发、profile 互拷(本机就能测:`~/.config/shyake/` ↔ CocoaShyake profiles)、草稿互认。
- 手工矩阵:浅色/深色模式 × 系统强调色 × en/zh-CN/ja × arm64/Rosetta。
- 与其他平台客户端各互发一轮作为里程碑验收。

## 11. 里程碑

| 阶段 | 内容 | 完成标准 |
|---|---|---|
| M0 | 建仓;submodule;Makefile(上游库 + ObjC + `.app` 组装 + ad-hoc 签名);clang-format | `make test` 通过;`.app` 启动且 ObjC 侧成功调用 `shyake_init_ctx`;`otool -L` 只见系统库 **(已完成)** |
| M1 | 窗口骨架:三栏布局、菜单、GCD 队列模型、首次向导、解锁 sheet、profile 体系;**关闭状态恢复与智能标点**;`RLIMIT_CORE` 归零 | 向导走通,能注册;与 `~/.config/shyake/` 互拷可用 **(代码完成;库路径与 CLI 双向互通已实测,界面待手工走查)**。Saved Application State 残留检查随 M2 撰写窗口一起验 |
| M2 | 邮件主链路:四箱列表、阅读窗格(含 RE 行)、撰写/发送、**回复**、burn、⇧⌘N 刷新;发送失败转草稿;报错约定 | 与 Unix CLI 互发、**互相回复**,RE 行三种状态(id / saved / unavailable)都能显示;粘贴 base64 与代码后送出,收端字节一致(智能标点未生效);停掉服务器后发送,草稿出现且 `shyake check drafts` 可见 |
| M3 | 本地数据:Drafts 箱(列表/续写/删除,回复草稿恢复为回复窗口)、save/read、Export、enc/dec 文件工具 | 与 Unix CLI 的草稿/saved 双向互认,含回复草稿 |
| M4 | 完善:fingerprint(含 randomart)、blocklist、rotate/destroy、为未注册 profile 补注册(向导中途取消会留下这种 profile)、debug 日志、三语 .strings | 功能面对齐 Unix 版命令集 |
| M5 | Universal 与发布:deps.sh(10.13 下限、两架构自建 liboqs/libcrypto + lipo)、Makefile 双架构 + lipo、CI(确认 runner 的 Rosetta)、SHA-256 自动化、真 instance HTTPS 冒烟 | `make test` 两架构通过;Release 页 zip 可下载,Gatekeeper 绕行文档验证可用 |

## 12. 不做老系统构建线(已决策)

**一条构建线,下限 10.13。** 曾计划一条覆盖 10.6/10.8 的 legacy 线,已放弃,理由记录在此以免重新提案:

- **TLS 是死结**。10.8 及以下的系统 libcurl 握不上现代 instance,必须静态自建 curl + OpenSSL。但现代 OpenSSL 3.x 在那个 SDK/工具链上编不过,退回 1.1.1 就是给一个端到端加密邮件客户端**打包 2023 年 EOL、无安全更新的 TLS 栈**——这比不支持老系统更糟。
- **liboqs 在 Xcode 4/5 时代的 clang 上能否过 C11 那关是纯赌博**,而它是 PQC 的地基,不能退让。
- **"分岔的只是构建管线"这个前提本身不成立**:主线用系统信任库、legacy 要打包 `cacert.pem`,这是 CA 配置的代码级分岔,不是管线分岔。
- 原计划把可行性 spike 排在最后,却要求主线从第一天起遵守"只用 10.8 时代 API"的纪律——**代价前置、验证后置**。NTShyake 的 XP 线正是这个形状:MSYS2 工具链按 pentium4 基线预编译,几周的依赖补丁做完才发现根因在工具链本身、非重建整条交叉工具链不可解。同样的坑不走第二遍。

相应地,主线**不背 API 纪律**:该用什么 AppKit API 就用,不为假想的老系统做弱链接守卫。ObjC + AppKit 本身部署下限就低,真有需求时再评估,但那时是一个全新决策,不是履行今天的承诺。
