# 记牌器

iPhone 记牌器。牌组共 176 张（4 副，去掉 3、4 和大小王），每人起手 44 张；3 人打底牌 44 张，4 人打底牌 0 张。

## 在 Windows 上安装

1. 把本文件夹里的全部内容（包括 `.github`）上传到一个 GitHub 私有仓库的 `main` 分支。
2. 在仓库的 Actions 页面等待 “Build IPA” 完成，下载 `CardCounter-ipa`，解压得到 `CardCounter.ipa`。
3. 在 Windows 上安装 iTunes 和 Sideloadly，连接 iPhone，用 Apple ID 把 IPA 装到手机。
4. 免费 Apple ID 的签名 7 天后失效，到期后重新安装一次。

## 当前状态

- 手动记牌、撤销、新一局和画中画小窗已完成代码编写。
- 屏幕广播通路已接好，牌面识别还是占位实现。适配时替换 `Broadcast/CardRecognizer.swift` 里的 `PendingGameRecognizer`。
