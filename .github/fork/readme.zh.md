## 关于此 Fork

本仓库是 [Xitaoyou/VeneraX](https://github.com/Xitaoyou/VeneraX)，基于 [Kyosee/VeneraX](https://github.com/Kyosee/VeneraX) 的个人 iOS 增强版；更早的原始项目为 [venera-app/venera](https://github.com/venera-app/venera)。感谢上游开发者，本 Fork 保留原项目许可与署名。以下内容仅说明本 Fork 的改动，上游功能说明保留在后文。

### 本 Fork 的新增与修复

| 项目 | 行为与兼容规则 |
| --- | --- |
| 漫画阅读器下滑返回 | iOS 左右翻页、横向连续阅读均支持，包含从左到右和从右到左；上下翻页或纵向连续阅读时自动停用，不弹提示。 |
| 图片预览下滑返回 | 漫画封面、图片收藏等全屏预览支持下滑返回。 |
| 返回动画 | 阅读器图片与工具栏作为整页一起缩放、淡出，底层页面保持原位；封面及收藏图片优先回到可见的原缩略图，没有合适目标时使用整页收起动画。未达到返回条件时回弹，兼容系统减少动态效果设置。 |
| 收藏与缩放手势 | 开启滑动收藏时停用下滑返回，并在设置中提示冲突；图片放大后拖动用于平移，多指缩放、翻页、长按和原有边缘返回继续保留。 |
| 搜索及漫画列表右滑返回 | 收起状态的漫画卡片支持从封面或文字区域右滑返回，已收藏漫画也适用；左滑收藏保留，已展开的侧滑操作栏右滑时先收起。 |
| 上游控件兼容 | 为自定义动画路由补齐 Material 容器，兼容上游新版阅读进度滑条。 |
| 本仓库更新源 | 手动检查更新、启动时自动检查更新均指向本 Fork，包含自己的 Release 与 AltStore / SideStore 更新源；同一上游版本的不同 Fork 构建也会比较构建号。 |

以上手势增强仅在 iOS 启用。自动化回归覆盖阅读方向、真实图片控件、缩放、收藏冲突、列表卡片和返回动画；实际设备效果仍以安装后测试为准。

### 下载与安装

- **本 Fork 的 iOS IPA：** [最新发布](https://github.com/Xitaoyou/VeneraX/releases/latest)。构建保留上游版本号，并使用独立递增的构建号，发布标签为 `v版本号+构建号`。
- **AltStore / SideStore 更新源：** [altstore-source.json](https://github.com/Xitaoyou/VeneraX/releases/latest/download/altstore-source.json)。
- IPA 为未签名包，需使用自己的签名工具安装。iOS 应用内更新会打开本仓库的发布页，不会静默安装 IPA；签名工具可通过上述更新源检查更新。
- Android、Windows、macOS、Linux 的上游安装包请前往 [Kyosee/VeneraX Releases](https://github.com/Kyosee/VeneraX/releases)。本 Fork 的专用发布流程面向 iOS。

### 上游同步与自动发布

[**Fork iOS 工作流**](https://github.com/Xitaoyou/VeneraX/actions/workflows/fork-ios.yml) 每六小时尝试同步上游 `master`，也支持手动运行。合并冲突会停止同步；静态检查、手势回归测试及 IPA 构建全部通过后才发布新版本，失败时保留此前已发布的安装包。

Fork 主页说明单独保存并与上游 README 正文自动组合，互不覆盖；翻译仅在条目互不冲突时按键合并。应用代码或同一翻译条目的冲突会停止，并在 Actions 摘要列出。构建失败后会在后续定时任务中重试未发布的应用改动。

仅 README、更新日志、安装清单等元数据变化时仍同步，但跳过 IPA 打包；应用代码、内置资源、依赖和构建配置变化才触发打包，手动运行可强制构建。Fork 自有 CI 配置单独保留，上游工作流更新需要人工评估。自动合并不能保证未来所有上游改动均兼容。

实现与兼容策略见 [Fork 设计说明](.github/fork/DESIGN.md)。下方为保留的上游介绍与通用构建说明；本 Fork 的下载、更新源和 iOS 发布规则以本节为准。

---

## 上游项目说明
