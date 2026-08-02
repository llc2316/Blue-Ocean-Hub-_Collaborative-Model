@echo off
chcp 65001 >nul
cd /d "%~dp0"
del /q *.aux *.log *.out *.toc *.synctex.gz *.fls *.fdb_latexmk *.xdv 2>nul
echo 已清理 LaTeX 临时文件。
pause
