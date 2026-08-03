# -*- coding: utf-8 -*-
"""
Funciones comunes de conexion a Oracle via ADODB + MSDAORA.
No se usa directamente; lo importan probar_conexion.py y correr.py.
"""
import os
import datetime
import config

# Preparar el entorno para que el cliente Oracle 10g resuelva el alias.
os.environ["ORACLE_HOME"] = config.ORACLE_HOME
os.environ["TNS_ADMIN"] = config.TNS_ADMIN
os.environ["PATH"] = os.path.join(config.ORACLE_HOME, "bin") + ";" + os.environ.get("PATH", "")

import win32com.client  # requiere pywin32 (ya instalado en el Python 32-bit)


def conectar():
    """Devuelve una conexion ADODB abierta a la base."""
    con = win32com.client.Dispatch("ADODB.Connection")
    cs = (f"Provider=MSDAORA;Data Source={config.ALIAS_BASE};"
          f"User Id={config.USUARIO};Password={config.CONTRASENA};")
    con.Open(cs)
    return con


def _a_python(valor):
    """Convierte valores raros de ADO (fechas con zona horaria) a algo que
    openpyxl pueda escribir."""
    if isinstance(valor, datetime.datetime):
        # pywintypes.datetime es tz-aware; openpyxl no lo acepta -> lo dejamos naive
        return valor.replace(tzinfo=None, microsecond=0)
    return valor


def limpiar_sql(sql):
    """Quita comentarios de linea (--...) y el ; final. Deja el SELECT limpio."""
    lineas = []
    for linea in sql.splitlines():
        pos = linea.find("--")
        if pos != -1:
            linea = linea[:pos]
        if linea.strip():
            lineas.append(linea)
    return "\n".join(lineas).strip().rstrip(";")


def ejecutar(con, sql, limite=None):
    """Ejecuta un SELECT y devuelve (columnas, filas)."""
    sql = limpiar_sql(sql)
    rs = con.Execute(sql)[0]
    columnas = [rs.Fields.Item(i).Name for i in range(rs.Fields.Count)]
    filas = []
    n = 0
    while not rs.EOF:
        filas.append([_a_python(rs.Fields.Item(i).Value) for i in range(rs.Fields.Count)])
        n += 1
        rs.MoveNext()
        if limite and n >= limite:
            break
    rs.Close()
    return columnas, filas
