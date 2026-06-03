**English** | [简体中文](README.zh-CN.md)

Fork form [https://github.com/nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline)

For Windows PowerShell, add the following code snippet to `setting.json`  

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -File C:/Users/{username}/.claude/statusline.ps1"
  }
}
```

For macOS/Ubuntu Terminal, add the following code snippet to `setting.json`  

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```
> Verify your script is executable: chmod +x ~/.claude/statusline.sh  
> The script depends on `jq`; if it is not installed, please install it first.

Read the official documents for all details:   
https://code.claude.com/docs/en/statusline
