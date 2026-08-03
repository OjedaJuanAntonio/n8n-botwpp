# -*- coding: utf-8 -*-
"""
Prueba rapida de conexion.   Ejecutar con:   probar.bat
Confirma que las credenciales de config.py funcionan.
"""
import sys
import _oracle_ado as ora


def main():
    print(f"Conectando a la base '{ora.config.ALIAS_BASE}' como {ora.config.USUARIO} ...")
    try:
        con = ora.conectar()
        cols, filas = ora.ejecutar(con, "SELECT banner FROM v$version")
        print("CONEXION OK\n")
        for f in filas:
            print("  ", f[0])
        con.Close()
    except Exception as e:
        print("FALLO LA CONEXION:")
        print(f"  {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
