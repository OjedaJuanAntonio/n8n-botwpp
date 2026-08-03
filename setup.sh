#!/usr/bin/env bash
# ============================================================================
# setup.sh
# Levanta el entorno local de desarrollo (n8n + Postgres) para el bot de
# WhatsApp. Pensado para correr con Git Bash en Windows, pero también
# funciona en macOS/Linux/WSL2.
#
# Qué hace:
#   1. Verifica que Docker y Docker Compose (v2, plugin "docker compose")
#      estén instalados. Si no, muestra instrucciones según el SO detectado.
#   2. Copia .env.example -> .env si todavía no existe (nunca sobreescribe
#      un .env ya existente, para no perder credenciales cargadas a mano).
#   3. Levanta los contenedores con "docker compose up -d".
#   4. Espera (polling) a que n8n responda en el puerto 5678.
#   5. Muestra la URL de acceso y un resumen de próximos pasos.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

N8N_PORT=5678
MAX_WAIT_SECONDS=90
POLL_INTERVAL=2

# ----------------------------------------------------------------------------
# Colores para mensajes (se desactivan solos si la terminal no soporta tty)
# ----------------------------------------------------------------------------
if [ -t 1 ]; then
    C_GREEN="\033[0;32m"
    C_RED="\033[0;31m"
    C_YELLOW="\033[0;33m"
    C_RESET="\033[0m"
else
    C_GREEN=""; C_RED=""; C_YELLOW=""; C_RESET=""
fi

info()    { echo -e "${C_YELLOW}==>${C_RESET} $1"; }
success() { echo -e "${C_GREEN}==>${C_RESET} $1"; }
fail()    { echo -e "${C_RED}ERROR:${C_RESET} $1"; }

# ----------------------------------------------------------------------------
# Detección de sistema operativo (solo para mostrar instrucciones útiles)
# ----------------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows-git-bash" ;;
        Darwin)                echo "macos" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl2"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

print_docker_install_instructions() {
    local os="$1"
    echo ""
    fail "Docker y/o Docker Compose no están disponibles."
    echo ""
    case "$os" in
        windows-git-bash)
            echo "Estás en Windows (Git Bash). Instalá Docker Desktop:"
            echo "  1. Descargalo de: https://www.docker.com/products/docker-desktop/"
            echo "  2. Durante la instalación, dejá tildada la opción de usar el backend WSL2"
            echo "     (o Hyper-V si no tenés WSL2)."
            echo "  3. Reiniciá la PC si te lo pide."
            echo "  4. Abrí Docker Desktop y esperá a que el ícono de la ballena diga \"Running\"."
            echo "  5. Volvé a correr este script desde Git Bash."
            ;;
        wsl2)
            echo "Estás en WSL2. Instalá Docker Desktop en Windows y habilitá la integración con WSL2:"
            echo "  1. Descargalo de: https://www.docker.com/products/docker-desktop/"
            echo "  2. En Docker Desktop: Settings > Resources > WSL Integration > activá tu distro."
            echo "  3. Reabrí la terminal de WSL2 y volvé a correr este script."
            ;;
        macos)
            echo "Estás en macOS. Instalá Docker Desktop:"
            echo "  - Con Homebrew:  brew install --cask docker"
            echo "  - O descargalo de: https://www.docker.com/products/docker-desktop/"
            echo "  Después abrí la app Docker.app al menos una vez y esperá a que arranque."
            ;;
        linux)
            echo "Estás en Linux. Instalá Docker Engine + el plugin de Compose:"
            echo "  curl -fsSL https://get.docker.com | sh"
            echo "  sudo usermod -aG docker \$USER   # y volvé a iniciar sesión"
            echo "  (el plugin 'docker compose' viene incluido en instalaciones recientes;"
            echo "   si no, instalá el paquete 'docker-compose-plugin' con tu gestor de paquetes)"
            ;;
        *)
            echo "No pude detectar tu sistema operativo. Instrucciones generales en:"
            echo "  https://docs.docker.com/get-docker/"
            ;;
    esac
    echo ""
    exit 1
}

check_docker() {
    local os
    os="$(detect_os)"

    if ! command -v docker >/dev/null 2>&1; then
        print_docker_install_instructions "$os"
    fi

    if ! docker info >/dev/null 2>&1; then
        fail "Docker está instalado pero el daemon no está corriendo."
        echo "Abrí Docker Desktop (o iniciá el servicio 'docker' si estás en Linux) y volvé a intentar."
        exit 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        print_docker_install_instructions "$os"
    fi

    success "Docker y Docker Compose detectados correctamente."
}

setup_env_file() {
    if [ -f ".env" ]; then
        info ".env ya existe, no lo piso (así no perdés credenciales ya cargadas)."
    else
        if [ ! -f ".env.example" ]; then
            fail "No se encontró .env.example en $SCRIPT_DIR"
            exit 1
        fi
        cp .env.example .env
        success ".env creado a partir de .env.example. Revisalo y completá las contraseñas antes de seguir."
    fi
}

start_containers() {
    info "Levantando contenedores (docker compose up -d)..."
    docker compose up -d
    success "Contenedores iniciados."
}

wait_for_n8n() {
    info "Esperando a que n8n esté disponible en el puerto $N8N_PORT (máx. ${MAX_WAIT_SECONDS}s)..."
    local elapsed=0
    while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${N8N_PORT}/healthz" 2>/dev/null | grep -qE "^(200|401)$"; then
            return 0
        fi
        # fallback por si /healthz no está disponible en la versión de n8n: probamos la raíz
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${N8N_PORT}/" 2>/dev/null | grep -qE "^(200|401|302)$"; then
            return 0
        fi
        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
        echo -n "."
    done
    echo ""
    return 1
}

main() {
    echo "============================================================"
    echo " Setup del entorno local - Bot de WhatsApp (n8n + Postgres)"
    echo "============================================================"
    echo ""

    check_docker
    setup_env_file
    start_containers

    if wait_for_n8n; then
        echo ""
        success "n8n está listo!"
        echo ""
        # shellcheck disable=SC1091
        source .env 2>/dev/null || true
        echo "  URL local:       http://localhost:${N8N_PORT}"
        echo "  Usuario:         ${N8N_BASIC_AUTH_USER:-<revisar .env>}"
        echo "  Password:        (la que pusiste en N8N_BASIC_AUTH_PASSWORD dentro de .env)"
        echo ""
        echo "  Próximo paso: exponer el puerto $N8N_PORT a internet con HTTPS (ngrok o"
        echo "  Cloudflare Tunnel) para poder configurar el webhook de WhatsApp Cloud API."
        echo "  Ver instrucciones en README.md."
        echo ""
    else
        echo ""
        fail "n8n no respondió dentro de los ${MAX_WAIT_SECONDS}s esperados."
        echo "Revisá los logs con:  docker compose logs -f n8n"
        exit 1
    fi
}

main "$@"
