# 记牌器

iPhone 记牌器。牌组共 176 张（4 副，去掉 3、4 和大小王），每人起手 44 张；3 人打底牌 44 张，4 人打底牌 0 张。

## 在 Windows 上安装

1. 代码推送到 GitHub 公开仓库的 `main` 分支。
2. 在 Codemagic 启动 “Build IPA”，完成后在构建页的 Artifacts 下载 `CardCounter.ipa`。GitHub Actions 配置也保留着，但它的 macOS 机器经常分配不到。
3. 在 Windows 上安装 iTunes 和 Sideloadly，连接 iPhone，用 Apple ID 把 IPA 装到手机。
4. 免费 Apple ID 的签名 7 天后失效，到期后重新安装一次。

## 当前状态

- 手动记牌、撤销、新一局和画中画小窗已完成代码编写。
- 牌面识别在 `Shared/TableReader.swift`，模板在 `Shared/GlyphTemplates.swift`，按 2622×1206 的皮皮打筒子 3 人局画面标定。其他分辨率比例和 4 人局还没有适配。
