# DeepSeek Translate for KOReader

[简体中文](README.zh-CN.md)

An independent KOReader plugin for translating selected text and reading full-page translations with the DeepSeek API. The default target language is Simplified Chinese. Traditional Chinese, English, and Japanese are also available. The plugin menu is currently in Chinese.

- View a selection and its translation together. Optionally send 25, 50, 75, 100, or 200 nearby words on each side as context. The default length is 75 words; sending context is off by default.
- Read page translations in a full-screen view. Swipe vertically to scroll the translation and horizontally to turn the source page. **返回原文** returns to the same page in the original book.
- Reopen cached translations offline. The plugin retains up to 256 entries.

## Install

Tested on the 8th-generation Kindle (Kindle Basic 2) with KOReader `2024.03.1`. The plugin has not been tested on other versions or devices. A scanned PDF needs a readable text layer.

1. Download the repository with **Code → Download ZIP** and extract it. Exit KOReader and copy `deepseektranslate.koplugin` into `koreader/plugins/`.
2. To configure a [DeepSeek API key](https://platform.deepseek.com/api_keys) on Kindle, save it as the only line in a UTF‑8 file named `deepseek-api-key.txt` at the root of the Kindle USB drive. Safely eject, open KOReader, and choose **导入并移除文件** (Import and remove file). The plugin removes the temporary file after verifying the saved key. You can also enter the key manually through **Tools → DeepSeek 翻译 → 设置 API 密钥**.
3. Connect to Wi‑Fi and choose **测试连接** (Test connection). Open a book and choose **翻译当前页** (Translate current page), or select text and choose **DeepSeek 翻译** in the selection menu.

## Data and billing

The plugin sends selected text or current-page text directly to the [DeepSeek API](https://api-docs.deepseek.com/) using `deepseek-flash`. Nearby text is included only when you enable the selection-context setting. API usage is billed by DeepSeek. Testing the connection only requests the model list.

The saved key is stored locally in `koreader/settings/deepseektranslate.key`. Do not publish or share that file, the USB import file, or backups containing either file. The plugin menu includes options to remove the saved key or clear the translation cache.
