# KOReader 的 DeepSeek 翻译插件

[English](README.md)

独立的 KOReader 插件，支持选段翻译、当前页翻译，以及本次阅读期间的翻页自动翻译。默认译成简体中文，可改为繁體中文、英文或日文。

1. 在 GitHub 上点 **Code → Download ZIP** 并解压。退出 KOReader，将 `deepseektranslate.koplugin` 复制到 `koreader/plugins/`。
2. 在电脑上把自己的 [DeepSeek API 密钥](https://platform.deepseek.com/api_keys) 存为 Kindle 盘根目录的 `deepseek-api-key.txt`。文件使用 UTF‑8，只放一行密钥。
3. 安全弹出 Kindle，启动 KOReader 后点「导入并移除文件」。插件验证密钥已保存后会移除临时文本。若跳过了启动提示，可用「工具 → DeepSeek 翻译 → 从 USB 文本导入密钥」。连上 Wi-Fi 后点「测试连接」。也可以通过「设置 API 密钥」手动输入。
4. 选段时长按文字后点「DeepSeek 翻译」，在同一个窗口上下查看原文和译文。可在工具菜单开启「选段翻译附带附近上下文」，并将「每侧上下文」设为 25、50、75、100 或 200 词，默认 75 词。遇到书的边界或特别长的词，实际发送的上下文可能更少。
5. 点「翻译当前页」进入全屏译文阅读。上下滑动读完本页译文，左右滑动或点「上一页」「下一页」翻动原书并翻译新页。「返回原文」会显示原书的当前页。也可以从工具菜单通过「本书翻页自动翻译」进入译文阅读。

自动翻译和选段上下文默认关闭。翻译时，所选文字或当前页文字直接发给 [DeepSeek API](https://api-docs.deepseek.com/)，请求按 API 用量计费。开启上下文后，附近文字也会发给 DeepSeek，译文仍对应选段。测试连接只查询模型列表。已缓存的译文可离线打开，最多保留 256 条。扫描 PDF 需要已有可读取的文字层。

密钥保存在设备上的 `koreader/settings/deepseektranslate.key`。请勿把这个文件上传到公开仓库，也不要分享包含它的备份。需要清理时可用菜单中的「移除 API 密钥」和「清除翻译缓存」。
