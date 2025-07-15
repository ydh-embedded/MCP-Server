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

# Terminal Client erstellen (HINZUGEFÜGT)
create_terminal_client() {
    log_info "Erstelle Terminal Client..."
    
    cat > terminal_client.py << 'EOF'
#!/usr/bin/env python3
"""
Terminal-Client für Container-MCP-Server
"""

import asyncio
import json
import socket
import subprocess
import datetime
import sys
import os

class MCPTerminalClient:
    def __init__(self):
        self.hostname = socket.gethostname()
        self.welcome_shown = False
        
    def show_welcome(self):
        if not self.welcome_shown:
            print("🚀 MCP Terminal Client")
            print("=" * 50)
            print(f"🐳 Container: {self.hostname}")
            print(f"🕐 Zeit: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"📁 Arbeitsverzeichnis: {os.getcwd()}")
            print("=" * 50)
            print("💡 Verfügbare Befehle:")
            print("  help          - Hilfe anzeigen")
            print("  tools         - Verfügbare Tools auflisten")
            print("  status        - Container-Status")
            print("  time          - Aktuelle Zeit")
            print("  info          - Container-Informationen")
            print("  files [dir]   - Dateien auflisten")
            print("  calc <expr>   - Berechnung durchführen")
            print("  quit/exit     - Beenden")
            print("=" * 50)
            self.welcome_shown = True

    def show_help(self):
        print("\n📋 MCP Terminal Client - Hilfe")
        print("-" * 40)
        print("🔧 System-Befehle:")
        print("  help          - Diese Hilfe anzeigen")
        print("  status        - Container-Status abrufen")
        print("  info          - Container-Informationen")
        print("  time          - Aktuelle Container-Zeit")
        print("  files [dir]   - Dateien in Verzeichnis auflisten")
        print("")
        print("🧮 Berechnungs-Befehle:")
        print("  calc add 5 3      - Zahlen addieren")
        print("  calc mult 4 7     - Zahlen multiplizieren")
        print("  calc sqrt 16      - Quadratwurzel berechnen")
        print("")
        print("🎯 Beispiele:")
        print("  > calc add 10 20")
        print("  > files /app")
        print("  > status")
        print("-" * 40)

    def get_container_status(self):
        try:
            uptime = subprocess.check_output(["uptime"]).decode().strip()
            processes = len([p for p in os.listdir("/proc") if p.isdigit()])
            
            status = {
                "hostname": self.hostname,
                "uptime": uptime,
                "processes": processes,
                "timestamp": datetime.datetime.now().isoformat(),
                "working_dir": os.getcwd(),
                "memory_info": "Verfügbar in /proc/meminfo"
            }
            return status
        except Exception as e:
            return {"error": f"Fehler beim Abrufen des Status: {str(e)}"}

    def get_container_info(self):
        try:
            python_version = subprocess.check_output(["python", "--version"]).decode().strip()
            info = {
                "hostname": self.hostname,
                "working_directory": os.getcwd(),
                "environment": "Container",
                "python_version": python_version,
                "container_id": os.environ.get("HOSTNAME", "unknown"),
                "user": os.environ.get("USER", "unknown"),
                "path": os.environ.get("PATH", "unknown")[:100] + "..."
            }
            return info
        except Exception as e:
            return {"error": f"Fehler: {str(e)}"}

    def list_files(self, directory="/app"):
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

    def calculate(self, operation, *args):
        try:
            if operation == "add" and len(args) == 2:
                return float(args[0]) + float(args[1])
            elif operation == "mult" and len(args) == 2:
                return float(args[0]) * float(args[1])
            elif operation == "sqrt" and len(args) == 1:
                import math
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

    def format_output(self, data):
        if isinstance(data, dict):
            if "error" in data:
                print(f"❌ {data['error']}")
            else:
                print(json.dumps(data, indent=2, ensure_ascii=False))
        elif isinstance(data, (int, float)):
            print(f"📊 Ergebnis: {data}")
        else:
            print(f"📄 {data}")

    def run(self):
        self.show_welcome()
        
        while True:
            try:
                command = input(f"\n🐳 {self.hostname} > ").strip()
                
                if not command:
                    continue
                
                parts = command.split()
                cmd = parts[0].lower()
                
                if cmd in ['quit', 'exit', 'q']:
                    print("👋 Auf Wiedersehen!")
                    break
                elif cmd == 'help':
                    self.show_help()
                elif cmd == 'tools':
                    tools = [
                        "add_numbers", "multiply_numbers", "get_current_time",
                        "get_container_info", "square_root", "list_files", "container_status"
                    ]
                    print("🛠️ Verfügbare MCP-Tools:")
                    for tool in tools:
                        print(f"  • {tool}")
                elif cmd == 'status':
                    result = self.get_container_status()
                    self.format_output(result)
                elif cmd == 'info':
                    result = self.get_container_info()
                    self.format_output(result)
                elif cmd == 'time':
                    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    print(f"🕐 Container-Zeit: {current_time}")
                elif cmd == 'files':
                    directory = parts[1] if len(parts) > 1 else "/app"
                    result = self.list_files(directory)
                    self.format_output(result)
                elif cmd == 'calc':
                    if len(parts) < 2:
                        print("❌ Verwendung: calc <operation> [args...]")
                        print("   Beispiele: calc add 5 3, calc sqrt 16")
                    else:
                        operation = parts[1]
                        args = parts[2:] if len(parts) > 2 else []
                        result = self.calculate(operation, *args)
                        self.format_output(result)
                else:
                    print(f"❌ Unbekannter Befehl: {cmd}")
                    print("💡 Verwenden Sie 'help' für verfügbare Befehle")
                    
            except KeyboardInterrupt:
                print("\n👋 Beende Terminal Client...")
                break
            except EOFError:
                print("\n👋 Auf Wiedersehen!")
                break
            except Exception as e:
                print(f"❌ Fehler: {str(e)}")

if __name__ == "__main__":
    client = MCPTerminalClient()
    client.run()
EOF

    chmod +x terminal_client.py
    log_success "Terminal Client erstellt"
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

# Status-Ausgabe
echo "================================="
echo "✅ Container Services gestartet!"
echo "🔗 MCP Inspector: http://localhost:6247"
echo "🔗 Web Client: http://localhost:8501"
echo "🐳 Container: $(hostname)"
echo "================================="

# Warten auf Services
wait $MCP_PID $STREAMLIT_PID
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

# Login-Script erstellen
create_login_script() {
    log_info "Erstelle Login-Script..."
    
    cat > login.sh << 'EOF'
#!/bin/bash

CONTAINER_NAME="mcp-server"

echo "🔐 Logge in MCP Container ein..."

# Prüfe ob Container läuft
if ! podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ Container '$CONTAINER_NAME' läuft nicht!"
    echo "🚀 Starte Container mit: ./start_container.sh"
    exit 1
fi

# Container-Info anzeigen
echo "🐳 Container: $CONTAINER_NAME"
echo "🔗 MCP Inspector: http://localhost:6247"
echo "🔗 Web Client: http://localhost:8501"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# In Container einloggen
echo "🎯 Logge in Container ein..."
podman exec -it $CONTAINER_NAME /bin/bash

# Nach dem Logout
echo "👋 Logout aus Container abgeschlossen"
EOF

    chmod +x login.sh
    log_success "Login-Script erstellt: login.sh"
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
    create_terminal_client      # HINZUGEFÜGT
    create_streamlit_client
    create_container_services
    create_container_management
    create_login_script
    create_management_script
    create_container_readme
    
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