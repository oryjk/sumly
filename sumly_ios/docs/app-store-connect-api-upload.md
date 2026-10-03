# App Store Connect API Key 自动上传

项目使用 App Store Connect API Key 进行命令行上传，不依赖 Xcode GUI 的 Apple Account 会话。

## 固定发布方式与结束条件

发布约定见 [AGENTS.md](../AGENTS.md#ios-发布与-testflight必须遵守)。默认使用本地签名 IPA + JWT API 上传；Xcode 仅负责编译、归档和本地导出。除非用户明确要求更换，不使用 Xcode Organizer、`destination=upload`、`altool` 或 Transporter 上传，也不在网络失败时自动回退到这些工具。

发布前完成必要的代码、签名与离线脚本验证。上传后只核实目标构建：`processingState=VALID`、`internalBuildState=IN_BETA_TESTING`，并确认属于预期内部测试组。达到这些条件后立即向用户报告版本/build，结束发布；不得为了测试恢复流程再次执行上传命令，也不重复联网检查或在成功后继续改上传工具。

## 本机私有配置

优先读取仓库外配置：

`~/.config/sumly/appstore-connect.env`

如果不存在，则读取项目内、但已被 Git 忽略的：

`.appstore-connect.env`

内容：

```bash
ASC_KEY_ID=<Key ID>
ASC_ISSUER_ID=<Issuer ID>
ASC_KEY_PATH=$HOME/.private_keys/AuthKey_<Key ID>.p8
```

私钥放在：

`~/.private_keys/AuthKey_<Key ID>.p8`

建议权限：

```bash
chmod 600 ~/.config/sumly/appstore-connect.env
chmod 600 ~/.private_keys/AuthKey_<Key ID>.p8
```

不要把 `.p8`、Key 内容或本机配置提交到 Git。

## 验证鉴权

在 `sumly_ios` 目录：

```bash
make upload-auth-check
```

这个命令只读取 App Store Connect 的 App 列表，不上传 build。

## 上传

在 `sumly_ios` 目录：

```bash
make upload
```

脚本会：

1. 读取当前 `project.yml` 生成的版本号和 build number。
2. 使用 API Key 进行 Release Archive。
3. 使用本机 Apple Distribution 证书和匹配的 App Store 描述文件本地导出签名 IPA（destination=export）。
4. 用 `upload_signed_ipa.py` 和 API Key 签名 JWT，直接调用 Apple Build Upload API 上传 IPA，并等待 Apple 处理结果。
5. 保持项目中的 build number，不让上传流程自动改号。

入口脚本：`scripts/upload_app_store.sh`。Xcode 仅用于编译与本地导出，不负责网络上传。

如果已有签名 IPA，重试时直接复用，不重新归档：

```bash
bash scripts/upload_app_store.sh --ipa build/ipa-b23-local/Sumly.ipa
```

## 分发签名

当前 API Key 可以管理证书和描述文件，但云签名请求返回 403，因此导出采用本地签名。

- 登录钥匙串已安装 `Apple Distribution: RUI WANG (237PA3LEYJ)`。
- 本机已安装 `Sumly API App Store Distribution` 描述文件，匹配 `com.oryjk.sumly`。
- 证书私钥保存在仓库外 `~/.private_keys/sumly-distribution/`，目录权限 `700`，私钥权限 `600`。
- 证书与描述文件于 2027-09-30 到期；更换证书后需要同步更新 `ExportOptions-upload.plist` 中的证书指纹。

换电脑时需要安装匹配的证书私钥及描述文件；仅复制 API Key 不能完成本地签名。

## 直接 API 上传的网络与恢复

需要 Python 3 与 `cryptography`。API Key 只在内存中生成 JWT，不打印私钥、JWT 或临时存储 URL。

上传版本从 IPA 的 Info.plist 读取，并检查 bundle ID 为 `com.oryjk.sumly`。Apple 上传任务 ID 与 IPA SHA-256 写入同目录的 `.asc-upload-state.json`（权限600），中断后重跑同一 IPA 会复用任务；不要删除这份恢复状态。

创建任务前先保存恢复意图；如果创建响应丢失，重跑只查询并匹配新增任务，不重复创建。查不到或存在多个候选时停止并保留状态，需检查 Apple 上的任务。已经提交的文件不再传输，处理中只查询结果。同一状态文件同时只允许一个上传进程。

默认 `make upload` 发现已有恢复状态时直接复用签名 IPA，不删除归档或导出目录；IPA 的版本和构建号必须与当前项目一致，否则停止并保留原文件。IPA 缺失也停止，不覆盖恢复状态。

默认沿用当前环境代理。如果代理连接异常，可仅让上传进程直连（仍验证 TLS 证书），不改变系统代理：

```bash
SUMLY_UPLOAD_DIRECT=1 bash scripts/upload_app_store.sh --ipa build/ipa-b23-local/Sumly.ipa
```

也可以指定已有任务状态文件：

```bash
python3 scripts/upload_signed_ipa.py build/ipa-b23-local/Sumly.ipa --state /path/to/upload-state.json --direct
```

当前脚本单次网络请求超时45秒；GET/PATCH 和分片 PUT 最多尝试3次，创建任务的 POST 不自动重试。Apple 处理状态查询的等待上限为20分钟，这与网络连接阻塞是两个不同阶段。连接失败要及时报告原因并保留恢复状态，不额外叠加重试循环，不把超时当作重新归档或换上传工具的理由。已经确认发布完成时不再执行这些请求。

测试：`python3 -m unittest discover -s scripts -p 'test_upload_signed_ipa.py'`。

协议来源：[Apple Build Upload API](https://developer.apple.com/documentation/appstoreconnectapi/build-uploads)。本地签名和上传是独立步骤，上传不再依赖 Xcode 的网络上传进程。

2026-10-01：0.1.1（23）已通过直接签名 API 上传并处理完成；Apple 状态为 VALID / IN_BETA_TESTING，内部「测试」组已包含该构建。上传脚本12项离线测试通过，覆盖 JWT 签名、包身份、分片边界、丢失响应、处理中恢复、默认命令保留状态和项目版本匹配。
