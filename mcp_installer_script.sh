#!/bin/bash

# MCP Server Installer für Manjaro/Arch Linux mit Podman Container Support
# Automatische Installation und Einrichtung von Model Context Protocol

set -e  # Exit on error

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Container-Konfiguration
CONTAINER_NAME="mcp-server"
CONTAINER_IMAGE="mcp-server:latest"
CONTAINER_PORT_INSPECTOR="6247"
CONTAINER_PORT_WEB="8501"
CONTAINER_PORT_API="8080"

# Logging Funktionen
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_container() {
    echo -e "${PURPLE}[CONTAINER]${NC} $1"
}

# Banner
show_banner() {
    echo -e "${BLUE}"
    echo "======================================="
    echo "    MCP Server Container Installer v2.0"
    echo "  für Manjaro/Arch Linux + Podman"
    echo "======================================="
    echo -e "${NC}"
}

# Überprüfe ob Script als Root läuft
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Dieses Script sollte NICHT als Root ausgeführt werden!"
        exit 1
    fi
}

# Podman installieren und konfigurieren
install_podman() {
    log_info "Installiere Podman..."
    
    if command -v podman &> /dev/null; then
        log_success "Podman ist bereits installiert"
    else
        # Podman installieren
        sudo pacman -S --needed --noconfirm podman podman-compose slirp4netns || {
            log_error "Fehler beim Installieren von Podman"
            exit 1
        }
        
        # Podman für Rootless-Betrieb konfigurieren
        sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
    fi
    
    # TUN-Module laden für besseres Netzwerk
    log_info "Konfiguriere Netzwerk-Module..."
    sudo modprobe tun || log_warning "TUN-Modul konnte nicht geladen werden"
    
    # Slirp4netns installieren falls nicht vorhanden
    if ! command -v slirp4netns &> /dev/null; then
        sudo pacman -S --needed --noconfirm slirp4netns
    fi
    
    # Podman-Systemd aktivieren
    systemctl --user enable podman.socket
    systemctl --user start podman.socket
    
    # Podman Netzwerk zurücksetzen
    podman system reset --force &> /dev/null || true
    
    log_success "Podman installiert und konfiguriert"
}

# System Updates und Dependencies
install_system_dependencies() {
    log_info "Installiere System-Dependencies..."
    
    # Pacman Updates
    sudo pacman -Syu --noconfirm || log_warning "Pacman Update fehlgeschlagen"
    
    # Basis-Pakete installieren
    sudo pacman -S --needed --noconfirm \
        python python-pip python-virtualenv \
        nodejs npm \
        git curl wget \
        base-devel \
        sqlite \
        podman \
        buildah \
        slirp4netns \
        linux-headers \
        || log_error "Fehler beim Installieren der System-Pakete"
    
    # TUN-Modul laden
    log_info "Lade TUN/TAP Netzwerk-Module..."
    sudo modprobe tun || log_warning "TUN-Modul nicht verfügbar"
    
    # TUN-Modul dauerhaft aktivieren
    echo "tun" | sudo tee -a /etc/modules-load.d/podman.conf &> /dev/null || true
    
    log_success "System-Dependencies installiert"
}

# Dockerfile erstellen
create_dockerfile() {
    log_info "Erstelle Dockerfile..."
    
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Arbeitsverzeichnis setzen
WORKDIR /app

# System-Dependencies installieren
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Python-Dependencies installieren
COPY app.py .

# Python-Dependencies installieren
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install Flask

# MCP-Server Dateien kopieren
COPY mcp_server.py .
COPY streamlit_client.py .
COPY terminal_client.py .
COPY start_container_services.sh .

# Ports freigeben
EXPOSE 6247 8501 8080 5000

# Startscript ausführbar machen
RUN chmod +x start_container_services.sh

# Standardbefehl
CMD ["./start_container_services.sh"]
EOF

    log_success "Dockerfile erstellt"
}

# Requirements.txt erstellen
create_requirements() {
    log_info "Erstelle requirements.txt..."
    
    cat > requirements.txt << 'EOF'
# MCP Core
mcp[cli]>=1.4.0
httpx>=0.24.0

# Web-Framework
fastapi>=0.104.0
uvicorn>=0.24.0
streamlit>=1.28.0

# Utilities
requests>=2.31.0
python-dotenv>=1.0.0
aiofiles>=23.2.0

# Optional LLM Integration
langchain-openai>=0.0.2
mcp-use>=0.1.0
EOF

    log_success "requirements.txt erstellt"
}

# MCP-Server Code erstellen
create_mcp_server() {
    log_info "Erstelle MCP-Server Code..."
    
    cat > mcp_server.py << 'EOF'
#!/usr/bin/env python3
"""
Containerisierter MCP-Server mit erweiterten Funktionen
"""

from mcp.server.fastmcp import FastMCP
import math
import os
import datetime
import json
import subprocess
import socket

# MCP Server initialisieren
mcp = FastMCP("Containerized MCP Server")

@mcp.tool()
def add_numbers(a: float, b: float) -> float:
    """Addiert zwei Zahlen"""
    return a + b

@mcp.tool()
def multiply_numbers(a: float, b: float) -> float:
    """Multipliziert zwei Zahlen"""
    return a * b

@mcp.tool()
def get_current_time() -> str:
    """Gibt die aktuelle Zeit zurück"""
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

@mcp.tool()
def get_container_info() -> dict:
    """Gibt Container-Informationen zurück"""
    return {
        "hostname": socket.gethostname(),
        "working_directory": os.getcwd(),
        "environment": "Container",
        "python_version": subprocess.check_output(["python", "--version"]).decode().strip(),
        "container_id": os.environ.get("HOSTNAME", "unknown")
    }

@mcp.tool()
def square_root(number: float) -> float:
    """Berechnet die Quadratwurzel einer Zahl"""
    if number < 0:
        raise ValueError("Kann keine Quadratwurzel einer negativen Zahl berechnen")
    return math.sqrt(number)

@mcp.tool()
def list_files(directory: str = "/app") -> list:
    """Listet Dateien in einem Verzeichnis auf"""
    try:
        files = []
        for item in os.listdir(directory):
            item_path = os.path.join(directory, item)
            if os.path.isfile(item_path):
                files.append({
                    "name": item,
                    "size": os.path.getsize(item_path),
                    "modified": datetime.datetime.fromtimestamp(os.path.getmtime(item_path)).isoformat()
                })
        return files
    except Exception as e:
        return [{"error": f"Fehler: {str(e)}"}]

@mcp.tool()
def container_status() -> dict:
    """Gibt Container-Status zurück"""
    try:
        # Speicher-Info
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.read()
        
        # CPU-Info
        with open('/proc/cpuinfo', 'r') as f:
            cpuinfo = f.read()
        
        return {
            "status": "running",
            "uptime": subprocess.check_output(["uptime"]).decode().strip(),
            "memory_available": "check /proc/meminfo",
            "processes": len(os.listdir("/proc")) if os.path.exists("/proc") else 0
        }
    except Exception as e:
        return {"error": f"Fehler beim Abrufen des Status: {str(e)}"}

@mcp.resource("container-logs")
def get_container_logs() -> str:
    """Container-Logs Resource"""
    try:
        # Versuche Container-Logs zu lesen
        return f"Container-Logs für {socket.gethostname()} um {datetime.datetime.now()}"
    except Exception as e:
        return f"Fehler beim Abrufen der Logs: {str(e)}"

@mcp.resource("system-info")
def get_system_info() -> str:
    """System-Informationen Resource"""
    return json.dumps({
        "timestamp": datetime.datetime.now().isoformat(),
        "hostname": socket.gethostname(),
        "working_dir": os.getcwd(),
        "python_executable": subprocess.check_output(["which", "python"]).decode().strip(),
        "environment_vars": dict(os.environ)
    }, indent=2)

if __name__ == "__main__":
    print("🚀 Starte MCP-Server im Container...")
    print(f"📍 Hostname: {socket.gethostname()}")
    print(f"🕐 Zeit: {datetime.datetime.now()}")
    mcp.run()
EOF

    chmod +x mcp_server.py
    log_success "MCP-Server Code erstellt"
}

# Terminal Client erstellen
create_terminal_client() {
    log_info "Erstelle Terminal Client..."
    
    cat > terminal_client.py << 'EOF'
#!/usr/bin/env python3
"""
Terminal-Client für Container-MCP-Server (API-kompatibel)
"""

import sys
import json
from datetime import datetime
import os
import subprocess
import math

# --- Tool-Funktionen ---
def get_time():
    return f"🕐 Container-Zeit: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"

def get_info():
    info = {
      "hostname": os.environ.get("HOSTNAME", "unknown"),
      "cwd": os.getcwd(),
      "env": "Container",
      "python_version": subprocess.check_output(["python", "--version"]).decode().strip()
    }
    return f"🐳 Container-Info: {json.dumps(info, indent=2)}"

def list_files(directory="/app"):
    try:
        if not os.path.exists(directory):
            return {"error": f"Verzeichnis {directory} existiert nicht"}
        
        files = []
        for item in os.listdir(directory):
            item_path = os.path.join(directory, item)
            try:
                if os.path.isfile(item_path):
                    size = os.path.getsize(item_path)
                    modified = datetime.datetime.fromtimestamp(os.path.getmtime(item_path))
                    files.append({
                        "name": item,
                        "type": "file",
                        "size": size,
                        "modified": modified.strftime("%Y-%m-%d %H:%M:%S")
                    })
                elif os.path.isdir(item_path):
                    files.append({
                        "name": item,
                        "type": "directory",
                        "size": "-",
                        "modified": "-"
                    })
            except (OSError, PermissionError):
                files.append({
                    "name": item,
                    "type": "unknown",
                    "size": "?",
                    "modified": "?"
                })
        
        return {"directory": directory, "files": files}
    except Exception as e:
        return {"error": f"Fehler: {str(e)}"}

def calculate(operation, *args):
    try:
        if operation == "add" and len(args) == 2:
            return float(args[0]) + float(args[1])
        elif operation == "mult" and len(args) == 2:
            return float(args[0]) * float(args[1])
        elif operation == "sqrt" and len(args) == 1:
            num = float(args[0])
            if num < 0:
                return {"error": "Kann keine Quadratwurzel einer negativen Zahl berechnen"}
            return math.sqrt(num)
        else:
            return {"error": f"Unbekannte Operation oder falsche Anzahl Argumente: {operation}"}
    except ValueError:
        return {"error": "Ungültige Zahlen"}
    except Exception as e:
        return {"error": f"Berechnungsfehler: {str(e)}"}

def get_container_status():
    try:
        uptime = subprocess.check_output(["uptime"]).decode().strip()
        processes = len([p for p in os.listdir("/proc") if p.isdigit()])
        
        status = {
            "hostname": os.environ.get("HOSTNAME", "unknown"),
            "uptime": uptime,
            "processes": processes,
            "timestamp": datetime.datetime.now().isoformat(),
            "working_dir": os.getcwd(),
            "memory_info": "Verfügbar in /proc/meminfo"
        }
        return status
    except Exception as e:
        return {"error": f"Fehler beim Abrufen des Status: {str(e)}"}

# --- Befehls-Mapping ---
COMMANDS = {
    "time": get_time,
    "info": get_info,
    "files": list_files,
    "calc": calculate,
    "status": get_container_status,
}

def print_help():
    help_text = "💡 Verfügbare Befehle:\n"
    for cmd, func in COMMANDS.items():
        help_text += f"  {cmd:<12} - {func.__doc__ or 'Keine Beschreibung'}\n"
    return help_text

COMMANDS["help"] = print_help

# --- Hauptlogik ---
def execute_command(command_line):
    """Führt einen einzelnen Befehl aus und gibt das Ergebnis zurück."""
    if not command_line:
        return ""
        
    parts = command_line.strip().split()
    command = parts[0]
    args = parts[1:] # Für Befehle mit Argumenten

    if command in COMMANDS:
        # Führen Sie die zugehörige Funktion aus
        if command == "files":
            result = COMMANDS[command](*args)
        elif command == "calc":
            result = COMMANDS[command](args[0], *args[1:])
        else:
            result = COMMANDS[command]()
        
        if isinstance(result, dict):
            return json.dumps(result, indent=2, ensure_ascii=False)
        elif isinstance(result, (int, float)):
            return f"📊 Ergebnis: {result}"
        else:
            return str(result)
    else:
        return f"❌ Unbekannter Befehl: {command}\n💡 Verwenden Sie 'help' für verfügbare Befehle"

if __name__ == "__main__":
    # Liest einen einzelnen Befehl von der Kommandozeile (Argumente)
    if len(sys.argv) > 1:
        full_command = " ".join(sys.argv[1:])
        output = execute_command(full_command)
        print(output)
    else:
        # Wenn ohne Argumente aufgerufen, zeige Hilfe
        print("Fehler: Bitte geben Sie einen Befehl an.\n")
        print(print_help())
EOF

    chmod +x terminal_client.py
    log_success "Terminal Client erstellt"
}

# API Server erstellen
create_api_server() {
    log_info "Erstelle API Server..."
    
    cat > app.py << 'EOF'
import subprocess
from flask import Flask, request, jsonify
import os

app = Flask(__name__)

@app.route('/command', methods=['POST'])
def handle_command():
    """
    Nimmt einen Befehl als JSON entgegen, führt ihn im Container-Kontext aus
    und gibt das Ergebnis zurück.
    """
    data = request.json
    if not data or 'command' not in data:
        return jsonify({"error": "Befehl fehlt. Bitte senden Sie ein JSON-Objekt wie {'command': 'your_command'}"}), 400

    command_to_run = data['command']
    
    # Sicherheitshinweis: Wir zerlegen den Befehl, um Injection zu vermeiden.
    # Da wir nur vordefinierte Befehle haben, ist das Risiko gering, aber es ist gute Praxis.
    command_parts = command_to_run.strip().split()

    try:
        # Führe das Client-Skript als separaten Prozess aus
        # Dies stellt sicher, dass jeder API-Aufruf sauber und isoliert ist
        process = subprocess.run(
            ['python', 'terminal_client.py'] + command_parts,
            capture_output=True,
            text=True,
            timeout=10, # Timeout, um Hängenbleiben zu verhindern
            check=True    # Löst eine Ausnahme bei einem Fehler im Skript aus
        )
        
        output = process.stdout.strip()
        
        return jsonify({
            "command": command_to_run,
            "output": output,
            "status": "success"
        })

    except subprocess.CalledProcessError as e:
        return jsonify({
            "command": command_to_run,
            "error": "Fehler bei der Befehlsausführung im Skript.",
            "details": e.stderr.strip(),
            "status": "error"
        }), 500
    except Exception as e:
        return jsonify({
            "command": command_to_run,
            "error": "Ein interner API-Fehler ist aufgetreten.",
            "details": str(e),
            "status": "error"
        }), 500

if __name__ == '__main__':
    # Die API lauscht auf allen Interfaces (0.0.0.0) auf Port 5000
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

    chmod +x app.py
    log_success "API Server erstellt"
}

# Streamlit Client für Container
create_streamlit_client() {
    log_info "Erstelle Streamlit Client..."
    
    cat > streamlit_client.py << 'EOF'
#!/usr/bin/env python3
"""
Streamlit Web-Client für Container-MCP-Server
"""

import streamlit as st
import requests
import json
import socket
import os
import subprocess
import time

st.set_page_config(
    page_title="MCP Container Client", 
    page_icon="🐳",
    layout="wide"
)

# Header
st.title("🐳 MCP Container Web Client")
st.write(f"Running in Container: `{socket.gethostname()}`")

# Sidebar für Container-Info
with st.sidebar:
    st.header("🔧 Container Info")
    
    # Container-Status
    try:
        st.write(f"**Hostname:** {socket.gethostname()}")
        st.write(f"**Working Dir:** {os.getcwd()}")
        st.write(f"**Python:** {subprocess.check_output(['python', '--version']).decode().strip()}")
        
        # MCP-Server Status prüfen
        def check_mcp_server():
            try:
                # Prüfe lokalen MCP-Server
                result = subprocess.run(['pgrep', '-f', 'mcp_server.py'], 
                                       capture_output=True, text=True)
                return len(result.stdout.strip()) > 0
            except:
                return False
        
        if check_mcp_server():
            st.success("✅ MCP-Server läuft")
        else:
            st.error("❌ MCP-Server nicht erreichbar")
            
            if st.button("🚀 Server starten"):
                try:
                    subprocess.Popen(['python', 'mcp_server.py'])
                    st.success("Server gestartet!")
                    time.sleep(2)
                    st.rerun()
                except Exception as e:
                    st.error(f"Fehler: {e}")
    
    except Exception as e:
        st.error(f"Fehler beim Abrufen der Container-Info: {e}")

# Hauptbereich
col1, col2 = st.columns([2, 1])

with col1:
    st.header("💬 Chat Interface")
    
    # Chat History
    if "messages" not in st.session_state:
        st.session_state.messages = []
    
    # Chat Messages anzeigen
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.write(message["content"])
    
    # User Input
    if prompt := st.chat_input("Ihre Nachricht..."):
        # User Message hinzufügen
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.write(prompt)
        
        # Simuliere MCP-Response
        with st.chat_message("assistant"):
            response = f"🐳 Container-MCP Response: '{prompt}' (verarbeitet um {time.strftime('%H:%M:%S')})"
            st.write(response)
            st.session_state.messages.append({"role": "assistant", "content": response})

with col2:
    st.header("🛠️ Tools")
    
    # Verfügbare Tools anzeigen
    st.subheader("📋 Verfügbare MCP-Tools:")
    tools = [
        "➕ add_numbers",
        "✖️ multiply_numbers",
        "🕐 get_current_time",
        "🐳 get_container_info",
        "√ square_root",
        "📁 list_files",
        "📊 container_status"
    ]
    
    for tool in tools:
        st.write(f"• {tool}")
    
    st.divider()
    
    # Quick Actions
    st.subheader("⚡ Quick Actions")
    
    if st.button("🕐 Aktuelle Zeit"):
        current_time = time.strftime('%Y-%m-%d %H:%M:%S')
        st.info(f"Container-Zeit: {current_time}")
    
    if st.button("🐳 Container-Info"):
        info = {
            "hostname": socket.gethostname(),
            "cwd": os.getcwd(),
            "env": "Container"
        }
        st.json(info)

# Footer
st.divider()
st.write("**Container Environment:** MCP-Server läuft in Podman Container")
st.write("**MCP Inspector:** Verfügbar auf Port 6247")
st.write("**Web Client:** Verfügbar auf Port 8501")
EOF

    log_success "Streamlit Client erstellt"
}

# Container-Service-Starter
create_container_services() {
    log_info "Erstelle Container-Service-Starter..."
    
    cat > start_container_services.sh << 'EOF'
#!/bin/bash

echo "🐳 Starte MCP Container Services..."
echo "================================="

# Funktion für parallele Ausführung
run_service() {
    local service_name=$1
    local command=$2
    
    echo "🚀 Starte $service_name..."
    exec $command
}

# Trap für sauberes Herunterfahren
cleanup() {
    echo "🛑 Beende Container Services..."
    pkill -f "mcp_server.py"
    pkill -f "streamlit"
    pkill -f "app.py"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Warte kurz für Initialisierung
sleep 2

# Services im Hintergrund starten
echo "🚀 Starte MCP-Server (Port 6247)..."
python mcp_server.py &
MCP_PID=$!

sleep 3

echo "🚀 Starte Streamlit Web-Client (Port 8501)..."
streamlit run streamlit_client.py --server.port 8501 --server.headless true &
STREAMLIT_PID=$!

sleep 3

echo "🚀 Starte API Server (Port 5000)..."
python app.py &
API_PID=$!

# Status-Ausgabe
echo "================================="
echo "✅ Container Services gestartet!"
echo "🔗 MCP Inspector: http://localhost:6247"
echo "🔗 Web Client: http://localhost:8501"
echo "🔗 API Server: http://localhost:5000"
echo "🐳 Container: $(hostname)"
echo "================================="

# Warten auf Services
wait $MCP_PID $STREAMLIT_PID $API_PID
EOF

    chmod +x start_container_services.sh
    log_success "Container-Service-Starter erstellt"
}

# Container-Management-Scripts
create_container_management() {
    log_info "Erstelle Container-Management-Scripts..."
    
    # Container Build-Script
    cat > build_container.sh << 'EOF'
#!/bin/bash

echo "🔨 Baue MCP Container..."

# Netzwerk-Setup für Build
echo "🔧 Bereite Netzwerk für Build vor..."
sudo modprobe tun || echo "⚠️ TUN-Modul bereits geladen oder nicht verfügbar"

# Podman Netzwerk zurücksetzen falls nötig
podman system reset --force &> /dev/null || true

# Container-Image bauen mit Netzwerk-Fallback
echo "🚀 Starte Container-Build..."

# Versuch 1: Standard Build
podman build -t mcp-server:latest .

if [ $? -ne 0 ]; then
    echo "⚠️ Standard-Build fehlgeschlagen, versuche Host-Netzwerk..."
    
    # Versuch 2: Host-Netzwerk für Build
    podman build --network host -t mcp-server:latest .
    
    if [ $? -ne 0 ]; then
        echo "⚠️ Host-Netzwerk-Build fehlgeschlagen, versuche ohne Netzwerk..."
        
        # Versuch 3: Vereinfachtes Dockerfile ohne apt-get
        echo "🔄 Erstelle vereinfachtes Dockerfile..."
        cp Dockerfile Dockerfile.backup
        cat > Dockerfile.simple << 'SIMPLEEOF'
FROM python:3.11-slim

WORKDIR /app

# Python-Dependencies installieren (ohne apt-get)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# MCP-Server Dateien kopieren
COPY mcp_server.py .
COPY streamlit_client.py .
COPY terminal_client.py .
COPY start_container_services.sh .

# Ports freigeben
EXPOSE 6247 8501 8080

# Startscript ausführbar machen
RUN chmod +x start_container_services.sh

# Standardbefehl
CMD ["./start_container_services.sh"]
SIMPLEEOF
        
        # Build mit vereinfachtem Dockerfile
        podman build -f Dockerfile.simple -t mcp-server:latest .
        
        if [ $? -eq 0 ]; then
            echo "✅ Container mit vereinfachtem Dockerfile erfolgreich gebaut!"
            echo "⚠️ Hinweis: curl ist im Container nicht verfügbar"
            echo "🏷️ Image: mcp-server:latest"
        else
            echo "❌ Alle Build-Versuche fehlgeschlagen!"
            echo ""
            echo "🔧 Troubleshooting-Schritte:"
            echo "1. sudo modprobe tun"
            echo "2. sudo pacman -S linux-headers"
            echo "3. Neustart des Systems"
            echo "4. podman system reset --force"
            exit 1
        fi
    else
        echo "✅ Container mit Host-Netzwerk erfolgreich gebaut!"
        echo "🏷️ Image: mcp-server:latest"
    fi
else
    echo "✅ Container erfolgreich gebaut!"
    echo "🏷️ Image: mcp-server:latest"
fi
EOF

    # Container Start-Script
    cat > start_container.sh << 'EOF'
#!/bin/bash

CONTAINER_NAME="mcp-server"
IMAGE_NAME="mcp-server:latest"

echo "🚀 Starte MCP Container..."

# Prüfe ob Container bereits läuft
if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "⚠️ Container läuft bereits. Stoppe ihn zuerst..."
    podman stop $CONTAINER_NAME
fi

# Entferne alten Container falls vorhanden
if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "🧹 Entferne alten Container..."
    podman rm $CONTAINER_NAME
fi

# Versuche verschiedene Netzwerk-Modi
echo "🔗 Konfiguriere Container-Netzwerk..."

# Versuch 1: Host-Netzwerk (umgeht TUN/TAP Probleme)
echo "🔄 Versuche Host-Netzwerk..."
podman run -d \
    --name $CONTAINER_NAME \
    --network host \
    $IMAGE_NAME

if [ $? -eq 0 ]; then
    echo "✅ Container mit Host-Netzwerk erfolgreich gestartet!"
    echo "🔗 MCP Inspector: http://localhost:6247"
    echo "🔗 Web Client: http://localhost:8501"
    echo "🐳 Container Name: $CONTAINER_NAME"
    echo "🌐 Netzwerk-Modus: Host (direkter Zugriff)"
else
    echo "⚠️ Host-Netzwerk fehlgeschlagen, versuche Standard-Netzwerk..."
    
    # Versuch 2: Standard-Netzwerk mit Port-Mapping
    podman run -d \
        --name $CONTAINER_NAME \
        -p 6247:6247 \
        -p 8501:8501 \
        -p 8080:8080 \
        -p 5000:5000 \
        $IMAGE_NAME
    
    if [ $? -eq 0 ]; then
        echo "✅ Container mit Standard-Netzwerk erfolgreich gestartet!"
        echo "🔗 MCP Inspector: http://localhost:6247"
        echo "🔗 Web Client: http://localhost:8501"
        echo "🐳 Container Name: $CONTAINER_NAME"
        echo "🌐 Netzwerk-Modus: Bridge (Port-Mapping)"
    else
        echo "❌ Fehler beim Starten des Containers"
        echo "🔍 Debugging-Befehle:"
        echo "  podman logs $CONTAINER_NAME"
        echo "  podman system info"
        echo "  sudo modprobe tun"
        exit 1
    fi
fi

echo ""
echo "📋 Nützliche Befehle:"
echo "  ./login.sh              - In Container einloggen"
echo "  ./stop_container.sh     - Container stoppen"
echo "  podman logs $CONTAINER_NAME - Logs anzeigen"
echo "  ./container_status.sh   - Container-Status"
EOF

    # Container Stop-Script
    cat > stop_container.sh << 'EOF'
#!/bin/bash

CONTAINER_NAME="mcp-server"

echo "🛑 Stoppe MCP Container..."

if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    podman stop $CONTAINER_NAME
    echo "✅ Container gestoppt"
else
    echo "⚠️ Container läuft nicht"
fi
EOF

    # Container Status-Script
    cat > container_status.sh << 'EOF'
#!/bin/bash

CONTAINER_NAME="mcp-server"

echo "📊 MCP Container Status"
echo "======================"

# Container-Status prüfen
if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "🟢 Status: RUNNING"
    
    # Container-Details
    echo ""
    echo "📋 Container Details:"
    podman inspect $CONTAINER_NAME --format "{{.State.Status}}"
    
    # Port-Mappings
    echo ""
    echo "🔗 Port-Mappings:"
    podman port $CONTAINER_NAME
    
    # Logs (letzte 10 Zeilen)
    echo ""
    echo "📜 Letzte Logs:"
    podman logs --tail 10 $CONTAINER_NAME
    
else
    echo "🔴 Status: STOPPED"
fi

echo ""
echo "🛠️ Verfügbare Befehle:"
echo "  ./start_container.sh  - Container starten"
echo "  ./stop_container.sh   - Container stoppen"
echo "  ./login.sh           - In Container einloggen"
echo "  ./build_container.sh - Container neu bauen"
EOF

    chmod +x build_container.sh
    chmod +x start_container.sh
    chmod +x stop_container.sh
    chmod +x container_status.sh
    
    log_success "Container-Management-Scripts erstellt"
}

# Erweiterte Login-Funktion für MCP Container
create_login_script() {
    log_info "Erstelle erweitertes Login-Script..."
    
    cat > login.sh << 'EOF'
#!/bin/bash

# Erweiterte Login-Funktion für MCP Container
# Mit besserer Benutzerführung und mehr Optionen

CONTAINER_NAME="mcp-server"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging Funktionen
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner anzeigen
show_banner() {
    echo -e "${CYAN}"
    echo "════════════════════════════════════════"
    echo "      🔐 MCP Container Login v2.0"
    echo "════════════════════════════════════════"
    echo -e "${NC}"
}

# Container-Status prüfen
check_container_status() {
    if ! podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container '$CONTAINER_NAME' läuft nicht!"
        echo ""
        echo -e "${YELLOW}🔧 Verfügbare Optionen:${NC}"
        echo "1. Container starten: ./start_container.sh"
        echo "2. Container bauen: ./build_container.sh"
        echo "3. Status prüfen: ./container_status.sh"
        echo "4. Management: ./manage_mcp.sh"
        echo ""
        
        # Automatischen Start anbieten
        read -p "🚀 Soll der Container automatisch gestartet werden? (j/n): " auto_start
        if [[ $auto_start =~ ^[Jj]$ ]]; then
            if [ -f "./start_container.sh" ]; then
                log_info "Starte Container..."
                ./start_container.sh
                if [ $? -eq 0 ]; then
                    log_success "Container erfolgreich gestartet!"
                    sleep 2
                    return 0
                else
                    log_error "Fehler beim Starten des Containers"
                    return 1
                fi
            else
                log_error "start_container.sh nicht gefunden!"
                return 1
            fi
        else
            return 1
        fi
    fi
    return 0
}

# Container-Informationen anzeigen
show_container_info() {
    echo -e "${PURPLE}🐳 Container-Informationen:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}📦 Container:${NC} $CONTAINER_NAME"
    
    # Container-Status
    container_status=$(podman inspect $CONTAINER_NAME --format "{{.State.Status}}" 2>/dev/null)
    echo -e "${BLUE}📊 Status:${NC} $container_status"
    
    # Uptime
    container_started=$(podman inspect $CONTAINER_NAME --format "{{.State.StartedAt}}" 2>/dev/null)
    echo -e "${BLUE}⏰ Gestartet:${NC} $container_started"
    
    # Port-Mappings
    echo -e "${BLUE}🔗 Ports:${NC}"
    podman port $CONTAINER_NAME 2>/dev/null | while read line; do
        echo "   • $line"
    done
    
    echo ""
    echo -e "${GREEN}🌐 Web-Interfaces:${NC}"
    echo "   • MCP Inspector: http://localhost:6247"
    echo "   • Streamlit Client: http://localhost:8501"
    echo "   • API Server: http://localhost:5000"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Hilfe-Menü anzeigen
show_help_menu() {
    echo -e "${YELLOW}💡 Hilfreiche Befehle im Container:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}🖥️  Terminal-Client:${NC}"
    echo "   python terminal_client.py    # Interaktiver MCP-Client"
    echo ""
    echo -e "${CYAN}🌐 Web-Services:${NC}"
    echo "   python mcp_server.py         # MCP-Server manuell starten"
    echo "   streamlit run streamlit_client.py --server.port 8501 --server.headless true"
    echo ""
    echo -e "${CYAN}📁 Dateisystem:${NC}"
    echo "   ls -la /app/                 # Container-Dateien anzeigen"
    echo "   cat requirements.txt         # Python-Dependencies"
    echo "   ps aux                       # Laufende Prozesse"
    echo ""
    echo -e "${CYAN}🔧 Debugging:${NC}"
    echo "   curl http://localhost:6247   # MCP-Server testen"
    echo "   netstat -tulpn               # Offene Ports prüfen"
    echo "   tail -f /var/log/*.log       # System-Logs"
    echo ""
    echo -e "${CYAN}🚪 Beenden:${NC}"
    echo "   exit                         # Container verlassen"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Login-Optionen anzeigen
show_login_options() {
    echo -e "${YELLOW}🎯 Login-Optionen:${NC}"
    echo "1) 🐚 Standard Bash-Shell"
    echo "2) 🖥️ Direkt zum Terminal-Client"
    echo "3) 🔧 Service-Status prüfen"
    echo "4) 📋 Hilfe anzeigen und dann einloggen"
    echo "5) ❌ Abbrechen"
    echo ""
    read -p "Wählen Sie eine Option (1-5): " login_choice
    
    case $login_choice in
        1)
            return 1  # Standard Login
            ;;
        2)
            return 2  # Terminal Client
            ;;
        3)
            return 3  # Service Status
            ;;
        4)
            show_help_menu
            return 1  # Nach Hilfe Standard Login
            ;;
        5)
            echo "👋 Login abgebrochen"
            exit 0
            ;;
        *)
            log_warning "Ungültige Option, verwende Standard-Login"
            return 1
            ;;
    esac
}

# In Container einloggen
perform_login() {
    local login_type=$1
    
    case $login_type in
        2)
            log_info "Starte Terminal-Client direkt..."
            echo -e "${GREEN}🎯 Terminal-Client wird gestartet...${NC}"
            echo -e "${BLUE}💡 Verwenden Sie 'help' für verfügbare Befehle${NC}"
            echo -e "${BLUE}💡 Verwenden Sie 'quit' um den Client zu beenden${NC}"
            echo ""
            podman exec -it $CONTAINER_NAME python terminal_client.py
            ;;
        3)
            log_info "Prüfe Service-Status..."
            podman exec -it $CONTAINER_NAME /bin/bash -c "
                echo '📊 Container-Services Status:'
                echo '════════════════════════════'
                echo '🔍 Laufende Prozesse:'
                ps aux | grep -E '(mcp_server|streamlit|python)' | grep -v grep
                echo ''
                echo '🌐 Offene Ports:'
                netstat -tulpn 2>/dev/null | grep -E ':(6247|8501|8080)' || echo 'Keine MCP-Ports gefunden'
                echo ''
                echo '📁 Container-Dateien:'
                ls -la /app/
                echo ''
                echo '💾 Speicher-Nutzung:'
                free -h
                echo ''
                echo 'Drücken Sie Enter für Standard-Shell...'
                read
            "
            podman exec -it $CONTAINER_NAME /bin/bash
            ;;
        *)
            log_info "Starte Standard Bash-Shell..."
            echo -e "${GREEN}🎯 Willkommen in Ihrem MCP Container! 🐳${NC}"
            echo -e "${BLUE}💡 Verwenden Sie 'python terminal_client.py' für MCP-Interaktion${NC}"
            echo -e "${BLUE}💡 Verwenden Sie 'exit' um den Container zu verlassen${NC}"
            echo ""
            podman exec -it $CONTAINER_NAME /bin/bash
            ;;
    esac
}

# Post-Login Aktionen
post_login_actions() {
    echo ""
    log_success "Login-Session beendet"
    echo ""
    echo -e "${BLUE}📋 Nützliche Befehle für später:${NC}"
    echo "  ./login.sh               # Erneut einloggen"
    echo "  ./container_status.sh    # Container-Status prüfen"
    echo "  ./manage_mcp.sh          # Management-Interface"
    echo "  ./stop_container.sh      # Container stoppen"
    echo ""
    echo -e "${GREEN}🔗 Web-Interfaces (falls Container läuft):${NC}"
    echo "  http://localhost:6247    # MCP Inspector"
    echo "  http://localhost:8501    # Streamlit Client"
    echo ""
    
    # Frage nach Browser-Öffnung
    if command -v xdg-open &> /dev/null; then
        read -p "🌐 Sollen die Web-Interfaces im Browser geöffnet werden? (j/n): " open_browser
        if [[ $open_browser =~ ^[Jj]$ ]]; then
            log_info "Öffne Web-Interfaces..."
            xdg-open http://localhost:6247 2>/dev/null &
            xdg-open http://localhost:8501 2>/dev/null &
            log_success "Browser-Tabs geöffnet"
        fi
    fi
}

# Hauptfunktion
main() {
    show_banner
    
    # Container-Status prüfen
    if ! check_container_status; then
        exit 1
    fi
    
    # Container-Informationen anzeigen
    show_container_info
    echo ""
    
    # Login-Optionen anzeigen
    show_login_options
    login_type=$?
    
    echo ""
    
    # Login durchführen
    perform_login $login_type
    
    # Post-Login Aktionen
    post_login_actions
}

# Script ausführen
main "$@"
EOF

    chmod +x login.sh
    log_success "Erweitertes Login-Script erstellt: login.sh"
}

# All-in-One Management Script
create_management_script() {
    log_info "Erstelle Management-Script..."
    
    cat > manage_mcp.sh << 'EOF'
#!/bin/bash

CONTAINER_NAME="mcp-server"

show_menu() {
    echo "🐳 MCP Container Management"
    echo "=========================="
    echo "1) 🔨 Container bauen"
    echo "2) 🚀 Container starten"
    echo "3) 🛑 Container stoppen"
    echo "4) 🔐 In Container einloggen"
    echo "5) 📊 Container Status"
    echo "6) 📜 Container Logs"
    echo "7) 🌐 Öffne Web-Interfaces"
    echo "8) 🧹 Container cleanup"
    echo "9) 🔧 Netzwerk-Troubleshooting"
    echo "10) ❌ Beenden"
    echo ""
    read -p "Wählen Sie eine Option (1-10): " choice
}

open_web_interfaces() {
    echo "🌐 Öffne Web-Interfaces..."
    
    # Prüfe ob Container läuft
    if ! podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "❌ Container läuft nicht!"
        return 1
    fi
    
    # Versuche Browser zu öffnen
    if command -v xdg-open &> /dev/null; then
        xdg-open http://localhost:6247 &
        xdg-open http://localhost:8501 &
        echo "✅ Browser-Tabs geöffnet"
    else
        echo "📋 Öffnen Sie manuell:"
        echo "  🔗 MCP Inspector: http://localhost:6247"
        echo "  🔗 Web Client: http://localhost:8501"
    fi
}

cleanup_containers() {
    echo "🧹 Container Cleanup..."
    
    # Stoppe Container
    if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        podman stop $CONTAINER_NAME
    fi
    
    # Entferne Container
    if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        podman rm $CONTAINER_NAME
    fi
    
    # Entferne dangling Images
    podman image prune -f
    
    echo "✅ Cleanup abgeschlossen"
}

network_troubleshooting() {
    echo "🔧 Netzwerk-Troubleshooting"
    echo "=========================="
    
    echo "1. TUN-Modul laden..."
    sudo modprobe tun && echo "✅ TUN-Modul geladen" || echo "❌ TUN-Modul Fehler"
    
    echo "2. Podman Netzwerk zurücksetzen..."
    podman system reset --force && echo "✅ Podman zurückgesetzt" || echo "❌ Reset Fehler"
    
    echo "3. Slirp4netns prüfen..."
    if command -v slirp4netns &> /dev/null; then
        echo "✅ Slirp4netns verfügbar"
    else
        echo "❌ Slirp4netns fehlt - installiere..."
        sudo pacman -S --needed slirp4netns
    fi
    
    echo "4. Podman Info anzeigen..."
    podman system info | grep -A 5 -B 5 network
    
    echo ""
    echo "🔄 Versuchen Sie jetzt erneut: ./start_container.sh"
}

while true; do
    show_menu
    
    case $choice in
        1)
            ./build_container.sh
            ;;
        2)
            ./start_container.sh
            ;;
        3)
            ./stop_container.sh
            ;;
        4)
            ./login.sh
            ;;
        5)
            ./container_status.sh
            ;;
        6)
            echo "📜 Container Logs:"
            podman logs $CONTAINER_NAME
            ;;
        7)
            open_web_interfaces
            ;;
        8)
            cleanup_containers
            ;;
        9)
            network_troubleshooting
            ;;
        10)
            echo "👋 Auf Wiedersehen!"
            exit 0
            ;;
        *)
            echo "❌ Ungültige Option"
            ;;
    esac
    
    echo ""
    read -p "Drücken Sie Enter um fortzufahren..."
    clear
done
EOF

    chmod +x manage_mcp.sh
    log_success "Management-Script erstellt: manage_mcp.sh"
}

# README mit Container-Anweisungen
create_container_readme() {
    log_info "Erstelle Container-Dokumentation..."
    
    cat > README.md << 'EOF'
# 🐳 MCP Server Container Setup

## 🚀 Schnellstart

### 1. Container bauen und starten
```bash
./build_container.sh
./start_container.sh
```

### 2. In Container einloggen
```bash
./login.sh
```

### 3. Management-Interface verwenden
```bash
./manage_mcp.sh
```

## 📁 Container-Struktur

```
/app/
├── mcp_server.py              # MCP-Server
├── streamlit_client.py        # Web-Client
├── terminal_client.py         # Terminal-Client
├── start_container_services.sh # Service-Starter
└── requirements.txt           # Python-Dependencies
```

## 🔧 Container-Management

### Container bauen:
```bash
./build_container.sh
```

### Container starten:
```bash
./start_container.sh
```

### Container stoppen:
```bash
./stop_container.sh
```

### In Container einloggen:
```bash
./login.sh
```

### Container-Status prüfen:
```bash
./container_status.sh
```

## 🌐 Web-Interfaces

Nach dem Container-Start sind verfügbar:

1. **MCP Inspector** - http://localhost:6247
   - Direkte Server-Interaktion
   - Tool-Testing und Debugging

2. **Streamlit Web-Client** - http://localhost:8501
   - Chat-Interface
   - Container-spezifische Informationen

3. **API Server** - http://localhost:5000
   - REST-API für Open Interpreter und andere externe Tools
   - Ermöglicht die Ausführung von Terminal-Client-Befehlen über HTTP/JSON

## 🖥️ Terminal-Client

Im Container ist auch ein Terminal-Client verfügbar:
```bash
# Im Container einloggen
./login.sh

# Terminal-Client starten
python terminal_client.py
```

Der Terminal-Client bietet:
- Interaktive Kommandozeile
- Direkte MCP-Tool-Aufrufe
- Container-System-Informationen
- Berechnungs-Funktionen

## 🛠️ Verfügbare MCP-Tools

Der Container-Server bietet folgende Tools:
- ➕ `add_numbers` - Zahlen addieren
- ✖️ `multiply_numbers` - Zahlen multiplizieren
- 🕐 `get_current_time` - Container-Zeit abrufen
- 🐳 `get_container_info` - Container-Details
- √ `square_root` - Quadratwurzel berechnen
- 📁 `list_files` - Container-Dateien auflisten
- 📊 `container_status` - Container-Status

## 🔍 Debugging

### Container-Logs anzeigen:
```bash
podman logs mcp-server
```

### Container-Prozesse prüfen:
```bash
podman exec -it mcp-server ps aux
```

### Container-Dateisystem untersuchen:
```bash
./login.sh
# Im Container:
ls -la /app/
```

## 🔐 Container-Login

Das `login.sh` Script ermöglicht:
- Interaktive Shell im Container
- Direkten Zugriff auf MCP-Server
- Debugging und Entwicklung
- Manuelle Service-Kontrolle

### Beispiel-Session:
```bash
./login.sh
# Im Container:
python mcp_server.py        # Server manuell starten
streamlit run streamlit_client.py  # Web-Client starten
python terminal_client.py   # Terminal-Client starten
exit                        # Container verlassen
```

## 🐳 Podman-Befehle

### Container-Info:
```bash
podman ps                   # Laufende Container
podman images              # Verfügbare Images
podman inspect mcp-server  # Container-Details
```

### Port-Mappings:
```bash
podman port mcp-server
```

### Container-Ressourcen:
```bash
podman stats mcp-server
```

## 🚨 Troubleshooting

### Container startet nicht:
```bash
podman logs mcp-server
./container_status.sh
```

### Ports sind belegt:
```bash
sudo netstat -tulpn | grep :6247
sudo netstat -tulpn | grep :8501
```

### Container neu bauen:
```bash
./stop_container.sh
./build_container.sh
./start_container.sh
```

## 🔄 Updates

### Container-Image aktualisieren:
```bash
./stop_container.sh
./build_container.sh
./start_container.sh
```

### Python-Dependencies aktualisieren:
```bash
# requirements.txt bearbeiten
./build_container.sh
```

## 🎯 Nächste Schritte

1. **Container starten:** `./start_container.sh`
2. **Web-Interface öffnen:** http://localhost:8501
3. **In Container einloggen:** `./login.sh`
4. **MCP-Server testen:** http://localhost:6247
5. **Terminal-Client nutzen:** `python terminal_client.py`
6. **Entwicklung beginnen:** Container-Code anpassen

## 📞 Support

Bei Problemen:
- Prüfen Sie `./container_status.sh`
- Schauen Sie in `podman logs mcp-server`
- Verwenden Sie `./login.sh` für Debugging
- Nutzen Sie `./manage_mcp.sh` für Management

---

**Viel Spaß mit Ihrem containerisierten MCP-Server! 🐳🤖**
EOF

    log_success "Container-Dokumentation erstellt"
}

# Linux MCP-Client erstellen (funktioniert ohne MCP-Module)
create_linux_mcp_client() {
    log_info "Erstelle Linux MCP-Client..."
    
    cat > linux_mcp_client.py << 'EOF'
#!/usr/bin/env python3
"""
Linux MCP-Client - Funktioniert OHNE MCP-Module!
Direkter Container-Zugriff für alle MCP-ähnlichen Funktionen
"""

import subprocess
import sys

class SimpleLinuxMCPClient:
    def __init__(self):
        self.container_name = "mcp-server"
    
    def show_banner(self):
        print("\n" + "="*50)
        print("🐧 LINUX MCP CLIENT (Direkter Modus)")
        print("="*50)
        print("✅ Funktioniert OHNE MCP-Module!")
        print("🐳 Direkter Container-Zugriff")
        print("="*50)
    
    def check_container(self):
        try:
            result = subprocess.run(
                ["podman", "ps", "--format", "{{.Names}}"],
                capture_output=True, text=True
            )
            return self.container_name in result.stdout
        except:
            return False
    
    def execute_in_container(self, python_code):
        """Führe Python-Code direkt im Container aus"""
        try:
            result = subprocess.run([
                "podman", "exec", self.container_name,
                "python", "-c", python_code
            ], capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            return f"Fehler: {e}"
    
    def run_interactive(self):
        """Interaktive Schleife"""
        self.show_banner()
        
        if not self.check_container():
            print("❌ Container läuft nicht!")
            choice = input("🚀 Container starten? (j/n): ")
            if choice.lower() in ['j', 'y']:
                subprocess.run(["./start_container.sh"])
                if not self.check_container():
                    print("❌ Container-Start fehlgeschlagen")
                    return
            else:
                return
        
        print("\n🚀 Linux MCP-Client bereit!")
        print("💡 Befehle: add 5 3, mult 4 7, sqrt 16, time, info, help, quit")
        
        while True:
            try:
                command = input("\n🐧 MCP > ").strip()
                parts = command.split()
                
                if not parts:
                    continue
                
                cmd = parts[0].lower()
                
                if cmd in ['quit', 'exit', 'q']:
                    break
                elif cmd == 'help':
                    print("\n📋 Verfügbare Befehle:")
                    print("  add 5 3      # Addition")
                    print("  mult 4 7     # Multiplikation")
                    print("  sqrt 16      # Quadratwurzel")
                    print("  time         # Aktuelle Zeit")
                    print("  info         # Container-Info")
                    print("  help         # Diese Hilfe")
                    print("  quit         # Beenden")
                elif cmd == 'time':
                    result = self.execute_in_container("import datetime; print(datetime.datetime.now())")
                    print(f"🕐 Container-Zeit: {result}")
                elif cmd == 'info':
                    result = self.execute_in_container("import socket, os; print(f'Host: {socket.gethostname()}, Dir: {os.getcwd()}')")
                    print(f"🐳 Container-Info: {result}")
                elif cmd == 'add' and len(parts) == 3:
                    try:
                        a, b = float(parts[1]), float(parts[2])
                        result = self.execute_in_container(f"print({a} + {b})")
                        print(f"➕ {a} + {b} = {result}")
                    except ValueError:
                        print("❌ Ungültige Zahlen")
                elif cmd == 'mult' and len(parts) == 3:
                    try:
                        a, b = float(parts[1]), float(parts[2])
                        result = self.execute_in_container(f"print({a} * {b})")
                        print(f"✖️ {a} × {b} = {result}")
                    except ValueError:
                        print("❌ Ungültige Zahlen")
                elif cmd == 'sqrt' and len(parts) == 2:
                    try:
                        num = float(parts[1])
                        result = self.execute_in_container(f"import math; print(math.sqrt({num}))")
                        print(f"√ √{num} = {result}")
                    except ValueError:
                        print("❌ Ungültige Zahl")
                else:
                    print("❌ Unbekannter Befehl. Verwenden Sie 'help' für Hilfe.")
            
            except KeyboardInterrupt:
                print("\n👋 Auf Wiedersehen!")
                break
            except Exception as e:
                print(f"❌ Fehler: {e}")

if __name__ == "__main__":
    client = SimpleLinuxMCPClient()
    client.run_interactive()
EOF

    chmod +x linux_mcp_client.py
    log_success "Linux MCP-Client erstellt"
}

# Browser-Shortcuts erstellen
create_linux_browser_shortcuts() {
    log_info "Erstelle Browser-Shortcuts..."
    
    cat > open_all_interfaces.sh << 'EOF'
#!/bin/bash

echo "🌐 Öffne alle MCP-Interfaces..."

# Container prüfen
if ! podman ps --format "{{.Names}}" | grep -q "^mcp-server$"; then
    echo "❌ Container läuft nicht!"
    read -p "🚀 Container starten? (j/n): " choice
    if [[ $choice =~ ^[Jj]$ ]]; then
        ./start_container.sh
        sleep 3
    else
        exit 1
    fi
fi

# Browser öffnen
echo "🔍 Öffne MCP Inspector..."
if command -v firefox &> /dev/null; then
    firefox http://localhost:6247 2>/dev/null &
elif command -v google-chrome &> /dev/null; then
    google-chrome http://localhost:6247 2>/dev/null &
elif command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:6247 2>/dev/null &
fi

sleep 1

echo "🌐 Öffne Web-Client..."
if command -v firefox &> /dev/null; then
    firefox http://localhost:8501 2>/dev/null &
elif command -v google-chrome &> /dev/null; then
    google-chrome http://localhost:8501 2>/dev/null &
elif command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:8501 2>/dev/null &
fi

echo "✅ Browser-Tabs geöffnet!"
echo "📋 URLs:"
echo "  • MCP Inspector: http://localhost:6247"
echo "  • Web Client: http://localhost:8501"
EOF

    chmod +x open_all_interfaces.sh
    log_success "Browser-Shortcuts erstellt"
}

# Linux Quickstart-Tool erstellen
create_linux_quickstart() {
    log_info "Erstelle Linux Quickstart-Tool..."
    
    cat > linux_quickstart.sh << 'EOF'
#!/bin/bash

echo -e "\033[0;34m🐧 LINUX MCP QUICKSTART\033[0m"
echo "========================"

# Container starten falls nötig
if ! podman ps --format "{{.Names}}" | grep -q "^mcp-server$"; then
    echo "🚀 Starte Container..."
    ./start_container.sh
    sleep 2
fi

echo "✅ Container läuft!"
echo ""
echo "🎯 Was möchten Sie tun?"
echo "1) 🐧 Linux MCP-Client (Terminal)"
echo "2) 🌐 Browser-Interfaces öffnen"
echo "3) 🔐 In Container einloggen"

read -p "Option (1-3): " choice

case $choice in
    1)
        ./linux_mcp_client.py
        ;;
    2)
        ./open_all_interfaces.sh
        ;;
    3)
        ./login.sh
        ;;
    *)
        echo "Starte Standard-Option 1..."
        ./linux_mcp_client.py
        ;;
esac
EOF

    chmod +x linux_quickstart.sh
    log_success "Quickstart-Tool erstellt"
}

# Linux MCP Integration (Hauptfunktion)
install_linux_mcp_integration() {
    log_info "Installiere Linux MCP-Integration..."
    
    # Alle Linux-spezifischen Tools erstellen
    create_linux_mcp_client
    create_linux_browser_shortcuts
    create_linux_quickstart
    
    # Linux-spezifische Dokumentation
    cat > LINUX_MCP_GUIDE.md << 'EOF'
# 🐧 Linux MCP - Kompletter Guide

## 🚀 Sofort loslegen

### Quickstart (Empfohlen)
```bash
./linux_quickstart.sh
```

### Manuell
```bash
# Container starten
./start_container.sh

# Linux MCP-Client starten  
./linux_mcp_client.py

# Browser öffnen
./open_all_interfaces.sh
```

## 🛠️ Linux-spezifische Tools

- `linux_quickstart.sh` - Einfachster Einstieg
- `linux_mcp_client.py` - Terminal-Client (funktioniert OHNE MCP-Module)
- `open_all_interfaces.sh` - Browser-Shortcuts
- `login.sh` - Erweiterte Container-Login

## 💡 Linux-Vorteile

✅ **Funktioniert ohne Claude Desktop**
✅ **Keine MCP Python-Module nötig**
✅ **Native Container-Integration**
✅ **Terminal-Power**
✅ **Browser-Integration**

## 🎯 Empfohlener Workflow

1. `./linux_quickstart.sh`
2. Option 1 wählen (Terminal-Client)
3. Befehle testen: `add 5 3`, `time`, `help`
4. Browser öffnen für Web-Interface

---
**🐧 Linux ist perfekt für MCP!**
EOF

    log_success "Linux MCP-Integration installiert!"
    
    echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}🎉 LINUX MCP INTEGRATION ERFOLGREICH! 🎉${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}🚀 Sofort nutzbar:${NC}"
    echo "  ./linux_quickstart.sh        # Einfachster Start"
    echo "  ./linux_mcp_client.py        # Terminal-Client"
    echo "  ./open_all_interfaces.sh     # Browser öffnen"
    echo ""
    echo -e "${GREEN}🐧 Linux MCP bereit! 🚀${NC}"
}

# Hauptinstallation
main() {
    show_banner
    
    log_info "Starte MCP Container-Installation für Manjaro/Arch Linux..."
    
    check_root
    
    # Projekt-Verzeichnis erstellen
    PROJECT_DIR="$HOME/mcp-container-workspace"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    log_info "Arbeite in: $PROJECT_DIR"
    
    # Installation Steps
    install_system_dependencies
    install_podman
    
    # Container-Dateien erstellen
    create_dockerfile
    create_requirements
    create_mcp_server
    create_terminal_client
    create_api_server
    create_streamlit_client
    create_container_services
    create_container_management
    create_login_script
    create_management_script
    create_container_readme
    install_linux_mcp_integration    # ✅ ===== LINUX MCP INTEGRATION =====
    
    # Container bauen
    log_container "Bereite Container-Build vor..."
    
    # TUN-Modul vor Build laden
    log_info "Lade TUN-Modul für Container-Netzwerk..."
    sudo modprobe tun || log_warning "TUN-Modul konnte nicht geladen werden"
    
    # Podman für Build vorbereiten
    podman system reset --force &> /dev/null || true
    
    log_container "Baue Container-Image..."
    chmod +x build_container.sh
    ./build_container.sh
    
    # Erfolgsmeldung
    echo -e "\n${GREEN}========================================"
    echo "🎉 CONTAINER-INSTALLATION ERFOLGREICH! 🎉"
    echo "=======================================${NC}"
    echo -e "${BLUE}📁 Projekt-Verzeichnis:${NC} $PWD"
    echo -e "${BLUE}🐳 Container-Image:${NC} mcp-server:latest"
    echo -e "${BLUE}🔐 Login-Script:${NC} ./login.sh"
    echo ""
    echo -e "${PURPLE}🚀 Automatischer Start:${NC}"
    echo "• Container wird jetzt gestartet..."
    echo "• Login erfolgt automatisch in 3 Sekunden"
    echo ""
    echo -e "${PURPLE}🌐 Web-Interfaces:${NC}"
    echo "• MCP Inspector: http://localhost:6247"
    echo "• Web Client: http://localhost:8501"
    echo ""
    echo -e "${GREEN}Container bereit für Deployment! 🐳${NC}"
    
    # Automatischer Container-Start
    echo -e "\n${BLUE}🚀 Starte Container automatisch...${NC}"
    chmod +x start_container.sh
    ./start_container.sh
    
    if [ $? -eq 0 ]; then
        log_success "Container erfolgreich gestartet!"
        
        # 5 Sekunden warten damit Container vollständig startet
        echo -e "\n${YELLOW}⏳ Warte 5 Sekunden bis Container vollständig gestartet ist...${NC}"
        for i in 5 4 3 2 1; do
            echo -e "${YELLOW}$i...${NC}"
            sleep 1
        done
        
        # Container-Status prüfen
        echo -e "\n${BLUE}📊 Prüfe Container-Status...${NC}"
        chmod +x container_status.sh
        ./container_status.sh
        
        # Automatischer Login
        echo -e "\n${BLUE}🔐 Starte automatischen Login...${NC}"
        echo -e "${GREEN}✨ Willkommen in Ihrem MCP Container! ✨${NC}"
        echo -e "${BLUE}Verwenden Sie 'exit' um den Container zu verlassen${NC}"
        echo -e "${PURPLE}💡 Tipp: 'python terminal_client.py' für interaktiven MCP-Client${NC}"
        echo ""
        
        chmod +x login.sh
        ./login.sh
        
        # Nach dem Login
        echo -e "\n${GREEN}👋 Login-Session beendet${NC}"
        echo -e "${BLUE}📋 Nützliche Befehle für später:${NC}"
        echo "  ./login.sh             - Erneut einloggen"
        echo "  ./manage_mcp.sh        - Management-Interface"
        echo "  ./container_status.sh  - Container-Status prüfen"
        echo "  ./stop_container.sh    - Container stoppen"
        echo ""
        echo -e "${BLUE}🐧 Linux MCP-Tools:${NC}"
        echo "  ./linux_quickstart.sh  - Einfachster Start"
        echo "  ./linux_mcp_client.py  - Terminal-Client"
        echo "  ./open_all_interfaces.sh - Browser öffnen"
    else
        log_error "Fehler beim automatischen Container-Start!"
        echo -e "${YELLOW}🔧 Troubleshooting-Schritte:${NC}"
        echo "1. sudo modprobe tun"
        echo "2. podman system reset --force"
        echo "3. ./start_container.sh"
        echo -e "${BLUE}Oder versuchen Sie manuell: ./manage_mcp.sh${NC}"
    fi
}

# Script ausführen
main "$@"