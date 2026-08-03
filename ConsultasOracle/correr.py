# -*- coding: utf-8 -*-
"""
Corre una consulta SQL contra la base Oracle y exporta el resultado a Excel.

USO BASICO (doble clic no: usar el .bat o PowerShell):
    correr.bat consultas_sql\\stock.sql

CON PARAMETROS (los :Deposito, :proveedor que usaba Discoverer):
    correr.bat consultas_sql\\stock.sql --p Deposito=83 --p proveedor=JEMAN

OPCIONES:
    --salida nombre.xlsx   nombre del archivo de salida (por defecto usa el del .sql)
    --csv                  exporta CSV ademas del Excel
    --max N                limita a N filas (util para probar)

El SQL lo sacas de Discoverer:  menu Ver > Inspector de SQL (Show SQL),
copias el texto y lo guardas como un archivo .sql dentro de consultas_sql\\.
"""
import sys
import os
import csv
import argparse
import datetime
import openpyxl
import _oracle_ado as ora

CARPETA = os.path.dirname(os.path.abspath(__file__))
SALIDAS = os.path.join(CARPETA, "salidas")


def comillas_sql(valor):
    if isinstance(valor, (int, float)):
        return str(valor)
    return "'" + str(valor).replace("'", "''") + "'"


def aplicar_parametros(sql, lista):
    """Reemplaza los :nombre del SQL por el valor indicado en --p nombre=valor.
    Pensado para uso interno/confiable (no es una app expuesta a internet)."""
    for item in lista or []:
        if "=" not in item:
            sys.exit(f"ERROR: parametro mal escrito '{item}'. Usa nombre=valor")
        nombre, valor = item.split("=", 1)
        nombre = nombre.strip()
        if valor.isdigit():
            valor = int(valor)
        # Reemplaza :"Nombre" y :Nombre
        sql = sql.replace(f':"{nombre}"', comillas_sql(valor))
        sql = sql.replace(f":{nombre}", comillas_sql(valor))
    return sql


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("sql", help="ruta al archivo .sql")
    ap.add_argument("--p", action="append", default=[], help="parametro nombre=valor (repetible)")
    ap.add_argument("--salida", default=None, help="nombre del .xlsx de salida")
    ap.add_argument("--csv", action="store_true", help="exporta tambien CSV")
    ap.add_argument("--max", type=int, default=None, help="limitar cantidad de filas")
    args = ap.parse_args()

    if not os.path.isfile(args.sql):
        sys.exit(f"ERROR: no existe el archivo {args.sql}")

    with open(args.sql, "r", encoding="utf-8-sig") as f:
        sql = f.read().strip().rstrip(";")
    sql = aplicar_parametros(sql, args.p)

    base = args.salida or (os.path.splitext(os.path.basename(args.sql))[0] +
                           "_" + datetime.datetime.now().strftime("%Y%m%d_%H%M") + ".xlsx")
    if not base.lower().endswith(".xlsx"):
        base += ".xlsx"
    os.makedirs(SALIDAS, exist_ok=True)
    ruta_xlsx = os.path.join(SALIDAS, base)

    print(f"Conectando a '{ora.config.ALIAS_BASE}' ...")
    con = ora.conectar()
    print("Ejecutando consulta ...")
    columnas, filas = ora.ejecutar(con, sql, limite=args.max)
    con.Close()

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Resultado"
    ws.append(columnas)
    for fila in filas:
        ws.append(fila)
    wb.save(ruta_xlsx)
    print(f"OK: {len(filas)} filas  ->  {ruta_xlsx}")

    if args.csv:
        ruta_csv = ruta_xlsx[:-5] + ".csv"
        with open(ruta_csv, "w", newline="", encoding="utf-8-sig") as fcsv:
            w = csv.writer(fcsv, delimiter=";")
            w.writerow(columnas)
            w.writerows(filas)
        print(f"OK: CSV -> {ruta_csv}")


if __name__ == "__main__":
    main()
