@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo [1/2] 正在运行 XeLaTeX...
xelatex -synctex=1 -interaction=nonstopmode -file-line-error main.tex
if errorlevel 1 goto :error
echo [2/2] 正在再次运行 XeLaTeX，解析编号与引用...
xelatex -synctex=1 -interaction=nonstopmode -file-line-error main.tex
if errorlevel 1 goto :error
echo.
echo 编译完成：%CD%\main.pdf
pause
exit /b 0
:error
echo.
echo 编译失败。请查看 main.log 中最靠后的错误信息。
pause
exit /b 1
