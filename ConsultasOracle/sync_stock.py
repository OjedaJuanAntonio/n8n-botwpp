# -*- coding: utf-8 -*-
"""
Sincroniza la tabla "productos" de Postgres con el stock/precio real de Oracle.

Pensado para correr solo (sin intervencion manual) via el Programador de
Tareas de Windows, una vez por hora. Reutiliza la conexion ya probada de
_oracle_ado.py (no la modifica).

COMO FUNCIONA
-------------
1. Se conecta a Oracle con la misma conexion de siempre (ADODB + MSDAORA).
2. Corre el SQL de  consultas_sql\\stock_sync.sql  (SIN parametros: es una
   foto completa, no una busqueda puntual).
3. Los nombres de columna que devuelva ese SQL (los "AS algo" que vos
   escribas) son EXACTAMENTE los nombres de columna que se van a insertar
   en la tabla "productos" de Postgres. Si en el SELECT alguna columna se
   llama distinto a como se llama en Postgres, el insert va a fallar (a
   proposito: mejor que falle a que inserte en la columna equivocada).
4. Si Oracle falla (conexion caida, SQL con error, etc.), el script CORTA
   ahi mismo y NO TOCA Postgres. La tabla productos se queda con el dato
   de la hora anterior, que es preferible a dejarla vacia.
5. Si Oracle respondio bien, recien ahi se conecta a Postgres y hace, TODO
   dentro de una misma transaccion:
       BEGIN;
       TRUNCATE productos;
       INSERT (todas las filas nuevas, en bloque);
       COMMIT;
   Como es una sola transaccion, el bot de WhatsApp nunca va a ver la
   tabla a mitad de reemplazo: o ve los datos viejos (si consulta justo
   antes del COMMIT) o ve los nuevos (apenas despues). Nunca ve un hueco.
6. Todo queda registrado en logs\\sync_stock.log para poder revisar que
   paso si el Programador de Tareas corrio esto de madrugada y algo fallo.

REQUISITOS
----------
Instalar UNA VEZ en el mismo Python de 32 bits que ya usan correr.bat y
probar.bat (C:\\Python312-32):

    C:\\Python312-32\\python.exe -m pip install psycopg2-binary

Si esa instalacion falla (a veces psycopg2-binary no publica wheel para
Python de 32 bits en versiones muy nuevas), como alternativa pura-Python
que no necesita compilar nada:

    C:\\Python312-32\\python.exe -m pip install pg8000

y avisame para adaptar las 3 lineas que usan psycopg2 a pg8000 (la logica
de todo el resto del script no cambia).

CONFIGURACION
-------------
Agregar a config.py (mismo archivo donde ya estan USUARIO/CONTRASENA de
Oracle) estas variables nuevas, con los mismos valores que pusiste en el
.env del docker-compose de n8n:

    POSTGRES_HOST = "localhost"   # el script corre en la misma maquina
    POSTGRES_PORT = 5432          # el puerto que expusiste en docker-compose
    POSTGRES_DB   = "farmar_bot"
    POSTGRES_USER = "..."
    POSTGRES_PASSWORD = "..."
"""
import os
import sys
import datetime
import logging

import config
import _oracle_ado as ora

CARPETA = os.path.dirname(os.path.abspath(__file__))
SQL_SYNC = os.path.join(CARPETA, "consultas_sql", "stock_sync.sql")
LOGS = os.path.join(CARPETA, "logs")
TABLA_DESTINO = "productos"

os.makedirs(LOGS, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOGS, "sync_stock.log"),
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    encoding="utf-8",
)


def log(msg, nivel="info"):
    print(msg)
    getattr(logging, nivel)(msg)


def validar_nombre_columna(nombre):
    """Defensa extra: solo permitimos nombres de columna con letras,
    numeros y guion bajo. Esto viene del SQL que vos mismo escribiste,
    no de la farmacia, pero no cuesta nada ser estricto."""
    if not nombre or not all(c.isalnum() or c == "_" for c in nombre):
        sys.exit(f"ERROR: nombre de columna invalido devuelto por Oracle: '{nombre}'")
    return nombre


def leer_de_oracle():
    if not os.path.isfile(SQL_SYNC):
        sys.exit(
            f"ERROR: no existe {SQL_SYNC}\n"
            "Sacalo de Discoverer (Ver > Inspector de SQL) y guardalo ahi.\n"
            "Las columnas del SELECT deben tener alias EXACTOS a los "
            "nombres de columna de la tabla 'productos' en Postgres."
        )

    with open(SQL_SYNC, "r", encoding="utf-8-sig") as f:
        sql = f.read()

    log(f"Conectando a Oracle ('{config.ALIAS_BASE}') ...")
    con = ora.conectar()
    try:
        log("Ejecutando consulta de stock ...")
        columnas, filas = ora.ejecutar(con, sql)
    finally:
        con.Close()

    columnas = [validar_nombre_columna(c) for c in columnas]
    log(f"Oracle devolvio {len(filas)} filas, columnas: {columnas}")
    return columnas, filas


def escribir_en_postgres(columnas, filas):
    import pg8000.dbapi as pg8000_dbapi

    log(f"Conectando a Postgres ({config.POSTGRES_HOST}:{config.POSTGRES_PORT}) ...")
    conn = pg8000_dbapi.connect(
        host=config.POSTGRES_HOST,
        port=config.POSTGRES_PORT,
        database=config.POSTGRES_DB,
        user=config.POSTGRES_USER,
        password=config.POSTGRES_PASSWORD,
    )
    try:
        conn.autocommit = False
        # El cursor de pg8000 no soporta "with" (a diferencia del de psycopg2)
        cur = conn.cursor()
        columnas_sql = ", ".join(columnas)
        log(f"Reemplazando tabla '{TABLA_DESTINO}' dentro de una transaccion ...")
        cur.execute(f"TRUNCATE TABLE {TABLA_DESTINO}")
        if filas:
            placeholders = ", ".join(["%s"] * len(columnas))
            query = f"INSERT INTO {TABLA_DESTINO} ({columnas_sql}) VALUES ({placeholders})"
            cur.executemany(query, filas)
        cur.close()
        conn.commit()
        log(f"OK: {len(filas)} filas cargadas en '{TABLA_DESTINO}'.")
    except Exception:
        conn.rollback()
        log("ERROR al escribir en Postgres, se hizo ROLLBACK. La tabla quedo como estaba antes.", "error")
        raise
    finally:
        conn.close()


def main():
    inicio = datetime.datetime.now()
    log("=" * 60)
    log(f"Inicio de sincronizacion: {inicio}")
    try:
        columnas, filas = leer_de_oracle()
    except Exception as e:
        log(f"ERROR conectando/leyendo Oracle: {e}", "error")
        log("Postgres NO fue tocado. Se mantiene el dato de la corrida anterior.")
        sys.exit(1)

    try:
        escribir_en_postgres(columnas, filas)
    except Exception as e:
        log(f"ERROR escribiendo en Postgres: {e}", "error")
        sys.exit(1)

    duracion = (datetime.datetime.now() - inicio).total_seconds()
    log(f"Sincronizacion terminada OK en {duracion:.1f} segundos.")


if __name__ == "__main__":
    main()
