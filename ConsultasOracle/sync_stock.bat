@echo off
REM Sincroniza stock desde Oracle hacia Postgres.
REM Pensado para programarse en el Programador de Tareas de Windows.
REM Usa el mismo Python 32 bits que correr.bat y probar.bat.

cd /d "%~dp0"
C:\Python312-32\python.exe sync_stock.py
