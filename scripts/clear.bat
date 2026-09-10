echo Clearing project directory...

cd /d ../example/xcvu5p/fpga

:: 删除除Makefile以外的所有文件和文件夹
for /f "delims=" %%i in ('dir /b /a') do (
    if /i not "%%i"=="Makefile" (
        if exist "%%i\" (
            echo Deleting folder: %%i
            rmdir /s /q "%%i"
        ) else (
            echo Deleting file: %%i
            del /f /q "%%i"
        )
    )
)

echo Cleanup completed, Makefile preserved.