# 作品报告 LaTeX 模板

本文件夹已从 `2026嵌入式大赛应用赛道作品报告.docx` 中提取页眉竞赛图标，并配置为 XeLaTeX 工程。

## 文件

- `main.tex`：报告正文入口，已按 Word 模板整理章节占位内容。
- `report-template.tex`：页面、字体、页眉、页脚和标题样式。
- `assets/contest-header.png`：从 Word 页眉提取的竞赛横幅图。
- `.latexmkrc`：`latexmk` 编译配置，输出到 `build/`。

## 编译

```powershell
latexmk -xelatex main.tex
```

也可以直接运行：

```powershell
xelatex main.tex
```

Word 模板页脚使用底部居中的页码字段，LaTeX 中对应为 `\fancyfoot[C]{\thepage}`。
