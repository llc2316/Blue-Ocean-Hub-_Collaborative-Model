# 第四章数学模型（DC 模型）——VS Code 离线版

本文件夹可直接在 Windows 的 VS Code 中打开，不需要上传 Overleaf，也不需要联网编译。

## 1. 必需软件

- MiKTeX（你当前日志已经表明 XeLaTeX 可用）
- VS Code
- VS Code 扩展：LaTeX Workshop

主文件是 `main.tex`，编译器必须使用 **XeLaTeX**。模板固定采用 Fandol 中文字体，不依赖本机宋体、黑体或楷体文件。

## 2. 最简单的编译方法

在资源管理器中双击：

```text
compile.bat
```

脚本会连续运行两遍 XeLaTeX，以解析公式、表格和章节交叉引用。生成结果为：

```text
main.pdf
```

## 3. 在 VS Code 中编译

1. 在 VS Code 中选择“文件 → 打开文件夹”，打开整个 `vscode_chapter4_dc_model` 文件夹，不要只打开一个 `.tex` 文件。
2. 打开 `main.tex`。
3. 按 `Ctrl+Alt+B`。
4. 项目已预设默认配方为 `XeLaTeX × 2`，会自动执行两遍。
5. 点击右上角 PDF 图标，或按 `Ctrl+Alt+V` 预览。

若 VS Code 没有自动使用预设配方：

1. 按 `Ctrl+Shift+P`；
2. 输入 `LaTeX Workshop: Build with recipe`；
3. 选择 `XeLaTeX × 2`。

## 4. 清理缓存

双击：

```text
clean.bat
```

会删除 `.aux`、`.log`、`.out`、`.toc`、`.synctex.gz` 等临时文件，不会删除 `.tex` 和最终 PDF。

## 5. 章节编号

`chapter4_body.tex` 中使用：

```latex
\setcounter{chapter}{3}
\chapter{数学模型}
```

因此输出为“第四章 数学模型”，节号、公式号和表号均自动变为 `4.x`。

## 6. 合并进团队总稿

团队总稿中直接写：

```latex
\input{chapter4_body}
```

此时通常应删除 `chapter4_body.tex` 里的 `\setcounter{chapter}{3}`，让总稿按前面章节自动编号；若前面恰好已有三章，也可以保留。
