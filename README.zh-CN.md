[English](README.md) | **简体中文**

Fork 自 [https://github.com/nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline)

对于 Windows PowerShell，将以下代码片段添加到 `setting.json`  

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -File C:/Users/{username}/.claude/statusline.ps1"
  }
}
```

对于 macOS/Ubuntu 终端，将以下代码片段添加到 `setting.json`  

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```
> 请确认脚本具有可执行权限：chmod +x ~/.claude/statusline.sh  
> 该脚本依赖 `jq`；如果尚未安装，请先安装它。

阅读官方文档以了解所有细节：   
https://code.claude.com/docs/en/statusline
