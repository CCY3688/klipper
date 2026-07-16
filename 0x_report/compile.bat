@echo off
setlocal EnableExtensions

cd /d "%~dp0"

set "MAIN=main.tex"
set "OUTDIR=build"
set "PDF=%OUTDIR%\main.pdf"

echo ========================================
echo  Report one-click XeLaTeX build
echo ========================================
echo.

where latexmk >nul 2>nul
if errorlevel 1 (
    echo [ERROR] latexmk was not found in PATH.
    echo Please install TeX Live or MiKTeX, or add latexmk to PATH.
    echo.
    call :wait_if_needed
    exit /b 1
)

if not exist "%MAIN%" (
    echo [ERROR] %MAIN% was not found.
    echo Please put this script in the same folder as %MAIN%.
    echo.
    call :wait_if_needed
    exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo [1/2] Cleaning temporary files...
latexmk -c "%MAIN%" >nul 2>nul
for %%F in (main.aux main.log main.out main.pdf main.synctex.gz main.xdv main.fdb_latexmk main.fls) do (
    if exist "%%F" del /q "%%F" >nul 2>nul
)

echo [2/2] Building PDF...
echo.
latexmk -xelatex -synctex=1 -interaction=nonstopmode "%MAIN%"

if errorlevel 1 (
    echo.
    echo ========================================
    echo  Build failed.
    echo ========================================
    echo Log file: %OUTDIR%\main.log
    echo.
    call :wait_if_needed
    exit /b 1
)

if not exist "%PDF%" (
    echo.
    echo ========================================
    echo  Build finished, but PDF was not found.
    echo ========================================
    echo Expected file: %PDF%
    echo.
    call :wait_if_needed
    exit /b 1
)

echo.
echo ========================================
echo  Build succeeded.
echo ========================================
echo PDF file: %PDF%
echo Open the PDF with VSCode LaTeX Workshop internal viewer.
echo.
call :wait_if_needed
exit /b 0

:wait_if_needed
if /i not "%TERM_PROGRAM%"=="vscode" pause
exit /b 0
