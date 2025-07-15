# ============================================================================
# LINUX MCP INTEGRATION FUNCTIONS
# Fügen Sie diese Funktionen zu Ihrem mcp_installer_script.sh hinzu
# ============================================================================

# Linux MCP-Client erstellen
create_linux_mcp_client() {
    log_info "Erstelle Linux MCP-Client..."
    
    cat > linux_mcp_client.py << 'EOF'
#!/usr/bin/env python3
"""
Linux MCP-Client für Container-Server
Vollständige CLI-Integration ohne Claude Desktop
"""

import asyncio
import json
import subprocess
import sys
import os
import signal
from datetime import datetime

class LinuxMCPClient:
    def __init__(self):
        self.container_name = "mcp-server"
        self.running = True
        
        # Signal Handler für sauberes Beenden
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
    
    def signal_handler(self, sig, frame):
        """Signal Handler für Ctrl+C"""
        print("\n\n👋 Linux MCP-Client wird beendet...")
        self.running = False
        sys.exit(0)
    
    def show_banner(self):
        """Zeige Banner"""
        print("\n" + "="*60)
        print("🐧 LINUX MCP CLIENT v2.0")
        print("="*60)
        print(f"🐳 Container: {self.container_name}")
        print(f"🕐 Zeit: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"🌐 MCP Inspector: http://localhost:6247")
        print(f"🎯 Web Client: http://localhost:8501")
        print("="*60)
    
    def check_container(self):
        """Prüfe ob Container läuft"""
        try:
            result = subprocess.run(
                ["podman", "ps", "--format", "{{.Names}}"],
                capture_output=True, text=True, check=True
            )
            return self.container_name in result.stdout
        except:
            return False
    
    def start_container_if_needed(self):
        """Starte Container falls nötig"""
        if not self.check_container():
            print("⚠️ Container läuft nicht!")
            choice = input("🚀 Container automatisch starten? (j/n): ")
            if choice.lower() in ['j', 'ja', 'y', 'yes']:
                print("🔄 Starte Container...")
                try:
                    subprocess.run(["./start_container.sh"], check=True)
                    print("✅ Container gestartet!")
                    return True
                except:
                    print("❌ Fehler beim Container-Start")
                    return False
            return False
        return True
    
    async def connect_to_mcp(self):
        """Verbindung zum MCP-Server im Container"""
        try:
            # Importiere MCP-Module
            from mcp import ClientSession, StdioServerParameters
            from mcp.client.stdio import stdio_client
        except ImportError:
            print("❌ MCP-Module nicht gefunden!")
            print("💡 Installation: pip install mcp")
            return False
        
        server_params = StdioServerParameters(
            command="podman",
            args=["exec", "-i", self.container_name, "python", "mcp_server.py"]
        )
        
        try:
            async with stdio_client(server_params) as (read, write):
                async with ClientSession(read, write) as session:
                    # Server initialisieren
                    await session.initialize()
                    
                    # Verfügbare Tools abrufen
                    tools_response = await session.list_tools()
                    print("\n🛠️ Verfügbare MCP-Tools:")
                    for tool in tools_response.tools:
                        print(f"  • {tool.name}: {tool.description}")
                    
                    # Interaktive Schleife
                    await self.interactive_loop(session)
                    return True
                    
        except Exception as e:
            print(f"❌ MCP-Verbindungsfehler: {e}")
            return False
    
    async def interactive_loop(self, session):
        """Interaktive Command-Loop"""
        print("\n🚀 Linux MCP-Client bereit!")
        print("💡 Befehle: time, add X Y, mult X Y, sqrt X, info, files, status, help, quit")
        
        while self.running:
            try:
                command = input("\n🐧 MCP > ").strip()
                
                if not command:
                    continue
                
                if command.lower() in ['quit', 'exit', 'q']:
                    break
                elif command.lower() == 'help':
                    self.show_help()
                elif command.lower() == 'time':
                    result = await session.call_tool("get_current_time", {})
                    print(f"🕐 Container-Zeit: {result.content[0].text}")
                elif command.lower().startswith('add'):
                    await self.handle_math_command(session, command, "add_numbers", "➕")
                elif command.lower().startswith('mult'):
                    await self.handle_math_command(session, command, "multiply_numbers", "✖️")
                elif command.lower().startswith('sqrt'):
                    parts = command.split()
                    if len(parts) == 2:
                        try:
                            num = float(parts[1])
                            result = await session.call_tool("square_root", {"number": num})
                            print(f"√ √{num} = {result.content[0].text}")
                        except ValueError:
                            print("❌ Ungültige Zahl")
                    else:
                        print("❌ Verwendung: sqrt <zahl>")
                elif command.lower() == 'info':
                    result = await session.call_tool("get_container_info", {})
                    print(f"🐳 Container-Info: {result.content[0].text}")
                elif command.lower() == 'files':
                    result = await session.call_tool("list_files", {})
                    print(f"📁 Dateien: {result.content[0].text}")
                elif command.lower() == 'status':
                    result = await session.call_tool("container_status", {})
                    print(f"📊 Status: {result.content[0].text}")
                else:
                    print("❌ Unbekannter Befehl. Verwenden Sie 'help' für Hilfe.")
            
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"❌ Fehler: {e}")
    
    async def handle_math_command(self, session, command, tool_name, symbol):
        """Handle Math-Befehle"""
        parts = command.split()
        if len(parts) == 3:
            try:
                a, b = float(parts[1]), float(parts[2])
                result = await session.call_tool(tool_name, {"a": a, "b": b})
                print(f"{symbol} {a} {parts[0][:-1] if parts[0].endswith('add') else '×'} {b} = {result.content[0].text}")
            except ValueError:
                print("❌ Ungültige Zahlen")
        else:
            print(f"❌ Verwendung: {parts[0]} <zahl1> <zahl2>")
    
    def show_help(self):
        """Zeige Hilfe"""
        print("\n📋 Linux MCP-Client Hilfe")
        print("-" * 40)
        print("🧮 Berechnungen:")
        print("  add 5 3       # Addition")
        print("  mult 4 7      # Multiplikation")
        print("  sqrt 16       # Quadratwurzel")
        print("")
        print("ℹ️ Informationen:")
        print("  time          # Container-Zeit")
        print("  info          # Container-Details")
        print("  files         # Dateien auflisten")
        print("  status        # Container-Status")
        print("")
        print("🎯 Befehle:")
        print("  help          # Diese Hilfe")
        print("  quit          # Beenden")
        print("-" * 40)
    
    def fallback_mode(self):
        """Fallback ohne MCP-Module"""
        print("\n🔄 Fallback-Modus (ohne MCP-Module)")
        print("Direkte Container-Befehle verfügbar:")
        
        while self.running:
            try:
                command = input("\n🐧 Container > ").strip()
                
                if command.lower() in ['quit', 'exit']:
                    break
                elif command.lower() == 'login':
                    subprocess.run(["./login.sh"])
                elif command.lower() == 'status':
                    subprocess.run(["./container_status.sh"])
                elif command.lower() == 'web':
                    subprocess.run(["firefox", "http://localhost:6247"], stderr=subprocess.DEVNULL)
                    subprocess.run(["firefox", "http://localhost:8501"], stderr=subprocess.DEVNULL)
                else:
                    print("Verfügbare Befehle: login, status, web, quit")
            except KeyboardInterrupt:
                break
    
    def run(self):
        """Hauptfunktion"""
        self.show_banner()
        
        # Container prüfen
        if not self.start_container_if_needed():
            print("❌ Container ist nicht verfügbar")
            return
        
        # MCP-Verbindung versuchen
        try:
            asyncio.run(self.connect_to_mcp())
        except ImportError:
            print("⚠️ MCP-Module nicht verfügbar, starte Fallback-Modus...")
            self.fallback_mode()
        except Exception as e:
            print(f"❌ Fehler: {e}")
            print("🔄 Starte Fallback-Modus...")
            self.fallback_mode()

if __name__ == "__main__":
    client = LinuxMCPClient()
    client.run()
EOF

    chmod +x linux_mcp_client.py
    log_success "Linux MCP-Client erstellt"
}

# Erweiterten Streamlit-Client mit MCP-Integration erstellen  
create_enhanced_streamlit_mcp_client() {
    log_info "Erstelle erweiterten Streamlit MCP-Client..."
    
    cat > enhanced_streamlit_client.py << 'EOF'
#!/usr/bin/env python3
"""
Erweiterter Streamlit Web-Client mit vollständiger MCP-Integration für Linux
"""

import streamlit as st
import asyncio
import subprocess
import json
import socket
import os
import datetime
import time
import sys

st.set_page_config(
    page_title="🐧 Linux MCP Client", 
    page_icon="🐳",
    layout="wide"
)

# MCP-Integration prüfen
def check_mcp_available():
    """Prüfe ob MCP-Module verfügbar sind"""
    try:
        import mcp
        return True
    except ImportError:
        return False

# Container-Status prüfen
def check_container_status():
    """Prüfe Container-Status"""
    try:
        result = subprocess.run(
            ["podman", "ps", "--format", "{{.Names}}"],
            capture_output=True, text=True
        )
        return "mcp-server" in result.stdout
    except:
        return False

# MCP-Tool aufrufen (mit Fallback)
async def call_mcp_tool_async(tool_name, args={}):
    """MCP-Tool über Container aufrufen"""
    if not check_mcp_available():
        return {"error": "MCP-Module nicht verfügbar"}
    
    try:
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.stdio import stdio_client
        
        server_params = StdioServerParameters(
            command="podman",
            args=["exec", "-i", "mcp-server", "python", "mcp_server.py"]
        )
        
        async with stdio_client(server_params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                result = await session.call_tool(tool_name, args)
                return {"result": result.content[0].text}
                
    except Exception as e:
        return {"error": f"MCP-Fehler: {str(e)}"}

def call_mcp_tool(tool_name, args={}):
    """Synchroner Wrapper für MCP-Tool-Aufrufe"""
    return asyncio.run(call_mcp_tool_async(tool_name, args))

# Header
st.title("🐧 Linux MCP Web-Client")
st.write(f"🐳 Container: mcp-server | 🕐 Zeit: {datetime.datetime.now().strftime('%H:%M:%S')}")

# Sidebar
with st.sidebar:
    st.header("🔧 System-Status")
    
    # Container-Status
    container_running = check_container_status()
    if container_running:
        st.success("✅ Container läuft")
    else:
        st.error("❌ Container gestoppt")
        if st.button("🚀 Container starten"):
            with st.spinner("Starte Container..."):
                try:
                    subprocess.run(["./start_container.sh"], check=True)
                    st.success("Container gestartet!")
                    time.sleep(2)
                    st.rerun()
                except:
                    st.error("Fehler beim Container-Start")
    
    # MCP-Status
    mcp_available = check_mcp_available()
    if mcp_available:
        st.success("✅ MCP verfügbar")
    else:
        st.warning("⚠️ MCP-Module fehlen")
        st.code("pip install mcp", language="bash")
    
    st.divider()
    
    # Quick Links
    st.subheader("🔗 Quick Links")
    
    col1, col2 = st.columns(2)
    with col1:
        if st.button("🔍 Inspector"):
            st.markdown("[MCP Inspector](http://localhost:6247)")
    with col2:
        if st.button("🖥️ Terminal"):
            st.info("Verwenden Sie: ./login.sh")
    
    # Container-Management
    st.divider()
    st.subheader("🐳 Container")
    
    if st.button("📊 Status"):
        try:
            result = subprocess.run(["./container_status.sh"], 
                                   capture_output=True, text=True)
            st.text(result.stdout)
        except:
            st.error("Status-Script nicht gefunden")
    
    if st.button("🛑 Stoppen"):
        try:
            subprocess.run(["./stop_container.sh"])
            st.success("Container gestoppt")
        except:
            st.error("Stop-Script nicht gefunden")

# Hauptbereich
tab1, tab2, tab3, tab4 = st.tabs(["🧮 MCP-Tools", "💬 Chat", "📊 Container-Info", "🔧 Management"])

with tab1:
    st.header("🛠️ MCP-Tools")
    
    if not container_running:
        st.error("⚠️ Container muss laufen für MCP-Tools")
    elif not mcp_available:
        st.warning("⚠️ MCP-Module nicht verfügbar")
        st.info("Installation: `pip install mcp`")
    else:
        # Zeit abrufen
        col1, col2 = st.columns(2)
        with col1:
            if st.button("🕐 Container-Zeit"):
                with st.spinner("Rufe Zeit ab..."):
                    result = call_mcp_tool("get_current_time")
                    if "error" in result:
                        st.error(result["error"])
                    else:
                        st.success(f"⏰ {result['result']}")
        
        with col2:
            if st.button("🐳 Container-Info"):
                with st.spinner("Rufe Info ab..."):
                    result = call_mcp_tool("get_container_info")
                    if "error" in result:
                        st.error(result["error"])
                    else:
                        st.json(json.loads(result["result"]))
        
        st.divider()
        
        # Berechnungen
        st.subheader("🧮 Berechnungen")
        
        # Addition
        col1, col2, col3 = st.columns(3)
        with col1:
            a = st.number_input("Erste Zahl", value=5.0, key="add_a")
        with col2:
            b = st.number_input("Zweite Zahl", value=3.0, key="add_b")
        with col3:
            if st.button("➕ Addieren"):
                result = call_mcp_tool("add_numbers", {"a": a, "b": b})
                if "error" in result:
                    st.error(result["error"])
                else:
                    st.success(f"➕ {a} + {b} = {result['result']}")
        
        # Multiplikation
        col1, col2, col3 = st.columns(3)
        with col1:
            c = st.number_input("Erste Zahl", value=4.0, key="mult_a")
        with col2:
            d = st.number_input("Zweite Zahl", value=7.0, key="mult_b")
        with col3:
            if st.button("✖️ Multiplizieren"):
                result = call_mcp_tool("multiply_numbers", {"a": c, "b": d})
                if "error" in result:
                    st.error(result["error"])
                else:
                    st.success(f"✖️ {c} × {d} = {result['result']}")
        
        # Quadratwurzel
        col1, col2 = st.columns(2)
        with col1:
            num = st.number_input("Zahl für Quadratwurzel", value=16.0, min_value=0.0)
        with col2:
            if st.button("√ Quadratwurzel"):
                result = call_mcp_tool("square_root", {"number": num})
                if "error" in result:
                    st.error(result["error"])
                else:
                    st.success(f"√ √{num} = {result['result']}")

with tab2:
    st.header("💬 MCP-Chat Simulator")
    
    # Chat-Nachrichten
    if "messages" not in st.session_state:
        st.session_state.messages = [
            {"role": "assistant", "content": "🐧 Willkommen! Ich kann MCP-Tools in Ihrem Container verwenden."}
        ]
    
    # Chat-Historie anzeigen
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.write(message["content"])
    
    # Chat-Input
    if prompt := st.chat_input("Ihre Nachricht..."):
        # User-Message hinzufügen
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.write(prompt)
        
        # Simulierte Assistant-Response
        with st.chat_message("assistant"):
            response = f"🤖 Verarbeite Ihre Anfrage: '{prompt}'"
            
            # Einfache Keyword-Detection für MCP-Tools
            if "zeit" in prompt.lower():
                if container_running and mcp_available:
                    result = call_mcp_tool("get_current_time")
                    if "error" not in result:
                        response = f"🕐 Die aktuelle Container-Zeit ist: {result['result']}"
            elif "info" in prompt.lower():
                if container_running and mcp_available:
                    result = call_mcp_tool("get_container_info")
                    if "error" not in result:
                        response = f"🐳 Container-Informationen: {result['result']}"
            elif any(word in prompt.lower() for word in ["addier", "plus", "+"]):
                response = "➕ Verwenden Sie das MCP-Tools Tab für Berechnungen!"
            else:
                response += f" (Container: {'✅' if container_running else '❌'}, MCP: {'✅' if mcp_available else '❌'})"
            
            st.write(response)
            st.session_state.messages.append({"role": "assistant", "content": response})

with tab3:
    st.header("📊 Container-Informationen")
    
    if container_running:
        # Container-Details
        try:
            # Podman inspect für Details
            result = subprocess.run(
                ["podman", "inspect", "mcp-server"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                inspect_data = json.loads(result.stdout)[0]
                
                col1, col2 = st.columns(2)
                with col1:
                    st.subheader("🏷️ Container-Details")
                    st.write(f"**Name:** {inspect_data.get('Name', 'N/A')}")
                    st.write(f"**Status:** {inspect_data['State']['Status']}")
                    st.write(f"**Gestartet:** {inspect_data['State']['StartedAt'][:19]}")
                    st.write(f"**Image:** {inspect_data['Config']['Image']}")
                
                with col2:
                    st.subheader("🔗 Port-Mappings")
                    ports = inspect_data.get('NetworkSettings', {}).get('Ports', {})
                    for port, mappings in ports.items():
                        if mappings:
                            host_port = mappings[0]['HostPort']
                            st.write(f"**{port}** → localhost:{host_port}")
        except:
            st.error("Fehler beim Abrufen der Container-Details")
        
        # Live-Status
        if st.button("🔄 Status aktualisieren"):
            st.rerun()
            
    else:
        st.warning("⚠️ Container läuft nicht")

with tab4:
    st.header("🔧 Management")
    
    # Script-Buttons
    col1, col2, col3 = st.columns(3)
    
    with col1:
        st.subheader("🐳 Container")
        if st.button("🚀 Starten", key="mgmt_start"):
            subprocess.run(["./start_container.sh"])
            st.success("Start-Befehl ausgeführt")
        
        if st.button("🛑 Stoppen", key="mgmt_stop"):
            subprocess.run(["./stop_container.sh"])
            st.success("Stop-Befehl ausgeführt")
        
        if st.button("🔄 Neustart", key="mgmt_restart"):
            subprocess.run(["./stop_container.sh"])
            time.sleep(2)
            subprocess.run(["./start_container.sh"])
            st.success("Neustart-Befehle ausgeführt")
    
    with col2:
        st.subheader("🔧 Tools")
        if st.button("🖥️ Terminal öffnen"):
            st.info("Führen Sie aus: `./login.sh`")
        
        if st.button("🔍 MCP Inspector"):
            st.markdown("[→ MCP Inspector öffnen](http://localhost:6247)")
        
        if st.button("📋 Logs anzeigen"):
            try:
                result = subprocess.run(
                    ["podman", "logs", "--tail", "20", "mcp-server"],
                    capture_output=True, text=True
                )
                st.text_area("Container-Logs", result.stdout, height=200)
            except:
                st.error("Fehler beim Abrufen der Logs")
    
    with col3:
        st.subheader("🌐 Web-Links")
        st.markdown("**MCP Inspector:**")
        st.markdown("http://localhost:6247")
        
        st.markdown("**Aktueller Client:**")
        st.markdown("http://localhost:8501")
        
        if st.button("🌐 Browser öffnen"):
            try:
                subprocess.run(["xdg-open", "http://localhost:6247"], 
                              stderr=subprocess.DEVNULL)
                st.success("Browser geöffnet")
            except:
                st.error("Browser konnte nicht geöffnet werden")

# Footer
st.divider()
col1, col2, col3 = st.columns(3)
with col1:
    st.write("🐧 **Linux MCP Client**")
with col2:
    st.write(f"🐳 Container: {'✅' if container_running else '❌'}")
with col3:
    st.write(f"🛠️ MCP: {'✅' if mcp_available else '❌'}")
EOF

    log_success "Erweiterter Streamlit MCP-Client erstellt"
}

# Browser-Shortcuts erstellen
create_browser_shortcuts() {
    log_info "Erstelle Browser-Shortcuts..."
    
    # MCP Inspector Shortcut
    cat > open_mcp_inspector.sh << 'EOF'
#!/bin/bash

echo "🔍 Öffne MCP Inspector..."

# Container-Status prüfen
if ! podman ps --format "{{.Names}}" | grep -q "^mcp-server$"; then
    echo "❌ Container läuft nicht!"
    echo "🚀 Starte Container mit: ./start_container.sh"
    exit 1
fi

# Browser öffnen
if command -v firefox &> /dev/null; then
    firefox http://localhost:6247 &
    echo "✅ Firefox geöffnet: http://localhost:6247"
elif command -v google-chrome &> /dev/null; then
    google-chrome http://localhost:6247 &
    echo "✅ Chrome geöffnet: http://localhost:6247"
elif command -v chromium &> /dev/null; then
    chromium http://localhost:6247 &
    echo "✅ Chromium geöffnet: http://localhost:6247"
else
    echo "⚠️ Kein unterstützter Browser gefunden"
    echo "📋 Öffnen Sie manuell: http://localhost:6247"
fi
EOF

    # Web-Client Shortcut  
    cat > open_web_client.sh << 'EOF'
#!/bin/bash

echo "🌐 Öffne Web-Client..."

# Container-Status prüfen
if ! podman ps --format "{{.Names}}" | grep -q "^mcp-server$"; then
    echo "❌ Container läuft nicht!"
    echo "🚀 Starte Container mit: ./start_container.sh"
    exit 1
fi

# Browser öffnen
if command -v firefox &> /dev/null; then
    firefox http://localhost:8501 &
    echo "✅ Firefox geöffnet: http://localhost:8501"
elif command -v google-chrome &> /dev/null; then
    google-chrome http://localhost:8501 &
    echo "✅ Chrome geöffnet: http://localhost:8501"
elif command -v chromium &> /dev/null; then
    chromium http://localhost:8501 &
    echo "✅ Chromium geöffnet: http://localhost:8501"
else
    echo "⚠️ Kein unterstützter Browser gefunden"
    echo "📋 Öffnen Sie manuell: http://localhost:8501"
fi
EOF

    # Alle Browser öffnen
    cat > open_all_interfaces.sh << 'EOF'
#!/bin/bash

echo "🌐 Öffne alle MCP-Interfaces..."

# Container-Status prüfen
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

echo "🔍 Öffne MCP Inspector..."
if command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:6247 2>/dev/null &
else
    firefox http://localhost:6247 2>/dev/null &
fi

sleep 1

echo "🌐 Öffne Web-Client..."
if command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:8501 2>/dev/null &
else
    firefox http://localhost:8501 2>/dev/null &
fi

echo "✅ Browser-Tabs geöffnet!"
echo "📋 URLs:"
echo "  • MCP Inspector: http://localhost:6247"
echo "  • Web Client: http://localhost:8501"
EOF

    chmod +x open_mcp_inspector.sh
    chmod +x open_web_client.sh
    chmod +x open_all_interfaces.sh
    
    log_success "Browser-Shortcuts erstellt"
}

# Linux MCP Management-Tool
create_linux_mcp_management() {
    log_info "Erstelle Linux MCP Management-Tool..."
    
    cat > linux_mcp_manager.sh << 'EOF'
#!/bin/bash

# Linux MCP Management Tool
# Zentrale Verwaltung aller MCP-Komponenten

CONTAINER_NAME="mcp-server"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                  🐧 LINUX MCP MANAGER v2.0                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BLUE}🐳 Container:${NC} $CONTAINER_NAME"
    echo -e "${BLUE}🕐 Zeit:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

check_dependencies() {
    echo -e "${YELLOW}🔍 Prüfe Abhängigkeiten...${NC}"
    
    # Podman
    if command -v podman &> /dev/null; then
        echo -e "${GREEN}✅ Podman verfügbar${NC}"
    else
        echo -e "${RED}❌ Podman fehlt${NC}"
        return 1
    fi
    
    # Python
    if command -v python &> /dev/null; then
        echo -e "${GREEN}✅ Python verfügbar${NC}"
    else
        echo -e "${RED}❌ Python fehlt${NC}"
        return 1
    fi
    
    # MCP Python-Module
    if python -c "import mcp" 2>/dev/null; then
        echo -e "${GREEN}✅ MCP-Module verfügbar${NC}"
    else
        echo -e "${YELLOW}⚠️ MCP-Module fehlen${NC}"
        echo -e "${BLUE}💡 Installation: pip install mcp${NC}"
    fi
    
    return 0
}

show_status() {
    echo -e "${PURPLE}📊 System-Status${NC}"
    echo "─────────────────────────────────────────────────────"
    
    # Container-Status
    if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${GREEN}🐳 Container: RUNNING${NC}"
        
        # Port-Status
        echo -e "${BLUE}🔗 Ports:${NC}"
        podman port $CONTAINER_NAME 2>/dev/null | while read line; do
            echo "   • $line"
        done
        
        # Service-Status im Container
        echo -e "${BLUE}🛠️ Services:${NC}"
        if podman exec $CONTAINER_NAME pgrep -f "mcp_server.py" &>/dev/null; then
            echo -e "   • MCP-Server: ${GREEN}✅ RUNNING${NC}"
        else
            echo -e "   • MCP-Server: ${RED}❌ STOPPED${NC}"
        fi
        
        if podman exec $CONTAINER_NAME pgrep -f "streamlit" &>/dev/null; then
            echo -e "   • Streamlit: ${GREEN}✅ RUNNING${NC}"
        else
            echo -e "   • Streamlit: ${RED}❌ STOPPED${NC}"
        fi
        
    else
        echo -e "${RED}🐳 Container: STOPPED${NC}"
    fi
    
    echo "─────────────────────────────────────────────────────"
}

show_menu() {
    echo -e "${YELLOW}📋 Verfügbare Aktionen:${NC}"
    echo ""
    echo -e "${CYAN}🐳 Container-Management:${NC}"
    echo "  1) 🚀 Container starten"
    echo "  2) 🛑 Container stoppen"  
    echo "  3) 🔄 Container neustarten"
    echo "  4) 🔨 Container neu bauen"
    echo ""
    echo -e "${CYAN}🖥️ Client-Tools:${NC}"
    echo "  5) 🐧 Linux MCP-Client starten"
    echo "  6) 🔐 Container-Login"
    echo "  7) 🖥️ Terminal-Client (im Container)"
    echo ""
    echo -e "${CYAN}🌐 Web-Interfaces:${NC}"
    echo "  8) 🔍 MCP Inspector öffnen"
    echo "  9) 🌐 Web-Client öffnen"
    echo "  10) 🚀 Alle Browser-Interfaces öffnen"
    echo ""
    echo -e "${CYAN}🔧 System:${NC}"
    echo "  11) 📊 Detaillierter Status"
    echo "  12) 📜 Container-Logs anzeigen"
    echo "  13) 🧹 Cleanup (Container + Images)"
    echo "  14) ⚙️ Abhängigkeiten installieren"
    echo ""
    echo -e "${CYAN}❌ Beenden:${NC}"
    echo "  15) ❌ Manager beenden"
    echo ""
}

install_dependencies() {
    echo -e "${YELLOW}⚙️ Installiere Abhängigkeiten...${NC}"
    
    # MCP-Module installieren
    echo "📦 Installiere MCP Python-Module..."
    pip install mcp[cli] || {
        echo -e "${RED}❌ Fehler bei MCP-Installation${NC}"
        return 1
    }
    
    # Zusätzliche Module
    echo "📦 Installiere zusätzliche Module..."
    pip install streamlit httpx fastapi uvicorn || {
        echo -e "${YELLOW}⚠️ Einige Module konnten nicht installiert werden${NC}"
    }
    
    echo -e "${GREEN}✅ Abhängigkeiten installiert${NC}"
}

detailed_status() {
    echo -e "${PURPLE}📊 Detaillierter System-Status${NC}"
    echo "═════════════════════════════════════════════════════"
    
    # Container-Details
    if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${GREEN}🐳 Container läuft${NC}"
        
        # Uptime
        started=$(podman inspect $CONTAINER_NAME --format "{{.State.StartedAt}}")
        echo -e "${BLUE}⏰ Gestartet:${NC} $started"
        
        # Ressourcen
        echo -e "${BLUE}💾 Ressourcen:${NC}"
        podman stats --no-stream $CONTAINER_NAME
        
        # Prozesse im Container
        echo -e "${BLUE}🔍 Container-Prozesse:${NC}"
        podman exec $CONTAINER_NAME ps aux
        
        # Netzwerk-Status
        echo -e "${BLUE}🌐 Netzwerk-Tests:${NC}"
        if curl -s http://localhost:6247 >/dev/null; then
            echo -e "   • Port 6247: ${GREEN}✅ ERREICHBAR${NC}"
        else
            echo -e "   • Port 6247: ${RED}❌ NICHT ERREICHBAR${NC}"
        fi
        
        if curl -s http://localhost:8501 >/dev/null; then
            echo -e "   • Port 8501: ${GREEN}✅ ERREICHBAR${NC}"
        else
            echo -e "   • Port 8501: ${RED}❌ NICHT ERREICHBAR${NC}"
        fi
    else
        echo -e "${RED}🐳 Container gestoppt${NC}"
    fi
    
    echo "═════════════════════════════════════════════════════"
}

cleanup_system() {
    echo -e "${YELLOW}🧹 System-Cleanup...${NC}"
    
    read -p "⚠️ Alle Container und Images löschen? (j/n): " confirm
    if [[ $confirm =~ ^[Jj]$ ]]; then
        # Container stoppen und entfernen
        podman stop $CONTAINER_NAME 2>/dev/null
        podman rm $CONTAINER_NAME 2>/dev/null
        
        # Images aufräumen
        podman image prune -f
        podman system prune -f
        
        echo -e "${GREEN}✅ Cleanup abgeschlossen${NC}"
    else
        echo "❌ Cleanup abgebrochen"
    fi
}

handle_choice() {
    local choice=$1
    
    case $choice in
        1)
            echo -e "${BLUE}🚀 Starte Container...${NC}"
            ./start_container.sh
            ;;
        2)
            echo -e "${BLUE}🛑 Stoppe Container...${NC}"
            ./stop_container.sh
            ;;
        3)
            echo -e "${BLUE}🔄 Starte Container neu...${NC}"
            ./stop_container.sh
            sleep 2
            ./start_container.sh
            ;;
        4)
            echo -e "${BLUE}🔨 Baue Container neu...${NC}"
            ./build_container.sh
            ;;
        5)
            echo -e "${BLUE}🐧 Starte Linux MCP-Client...${NC}"
            ./linux_mcp_client.py
            ;;
        6)
            echo -e "${BLUE}🔐 Container-Login...${NC}"
            ./login.sh
            ;;
        7)
            echo -e "${BLUE}🖥️ Terminal-Client im Container...${NC}"
            podman exec -it $CONTAINER_NAME python terminal_client.py
            ;;
        8)
            echo -e "${BLUE}🔍 MCP Inspector...${NC}"
            ./open_mcp_inspector.sh
            ;;
        9)
            echo -e "${BLUE}🌐 Web-Client...${NC}"
            ./open_web_client.sh
            ;;
        10)
            echo -e "${BLUE}🚀 Alle Browser-Interfaces...${NC}"
            ./open_all_interfaces.sh
            ;;
        11)
            detailed_status
            ;;
        12)
            echo -e "${BLUE}📜 Container-Logs:${NC}"
            podman logs $CONTAINER_NAME
            ;;
        13)
            cleanup_system
            ;;
        14)
            install_dependencies
            ;;
        15)
            echo -e "${GREEN}👋 Linux MCP Manager beendet${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Ungültige Option${NC}"
            ;;
    esac
}

main() {
    while true; do
        show_banner
        check_dependencies || {
            echo -e "${RED}❌ Abhängigkeits-Probleme erkannt${NC}"
            echo -e "${BLUE}💡 Option 14 wählen für automatische Installation${NC}"
        }
        echo ""
        show_status
        echo ""
        show_menu
        
        read -p "Wählen Sie eine Option (1-15): " choice
        echo ""
        
        handle_choice $choice
        
        echo ""
        read -p "Drücken Sie Enter um fortzufahren..."
    done
}

main "$@"
EOF

    chmod +x linux_mcp_manager.sh
    log_success "Linux MCP Management-Tool erstellt"
}

# Erweiterte Container-Management für Linux
update_container_management_for_linux() {
    log_info "Erweitere Container-Management für Linux..."
    
    # Neues Streamlit-Interface als Ersatz für das alte
    log_info "Ersetze Standard-Streamlit-Client..."
    mv streamlit_client.py streamlit_client_basic.py 2>/dev/null
    mv enhanced_streamlit_client.py streamlit_client.py
    
    # Management-Script erweitern
    cat >> manage_mcp.sh << 'LINUX_EXTEND'

# ===== LINUX MCP ERWEITERUNGEN =====

linux_mcp_menu() {
    echo "🐧 Linux MCP Optionen"
    echo "====================="
    echo "16) 🐧 Linux MCP-Client starten"
    echo "17) 🔍 MCP Inspector im Browser"
    echo "18) 🌐 Alle Browser-Interfaces öffnen"
    echo "19) 📦 MCP-Module installieren"
    echo ""
}

handle_linux_choice() {
    case $choice in
        16)
            if [ -f "./linux_mcp_client.py" ]; then
                ./linux_mcp_client.py
            else
                echo "❌ Linux MCP-Client nicht gefunden"
            fi
            ;;
        17)
            if [ -f "./open_mcp_inspector.sh" ]; then
                ./open_mcp_inspector.sh
            else
                echo "🔍 Öffne MCP Inspector..."
                xdg-open http://localhost:6247 2>/dev/null &
            fi
            ;;
        18)
            if [ -f "./open_all_interfaces.sh" ]; then
                ./open_all_interfaces.sh
            else
                echo "🌐 Öffne alle Interfaces..."
                xdg-open http://localhost:6247 2>/dev/null &
                xdg-open http://localhost:8501 2>/dev/null &
            fi
            ;;
        19)
            echo "📦 Installiere MCP-Module..."
            pip install mcp[cli] streamlit httpx fastapi uvicorn
            echo "✅ Installation abgeschlossen"
            ;;
    esac
}

# Erweitere das bestehende Menü
original_show_menu() {
    # ... bestehende Menü-Funktion ...
    linux_mcp_menu
}
LINUX_EXTEND

    log_success "Container-Management für Linux erweitert"
}

# Installationsroutine für Linux MCP
install_linux_mcp_integration() {
    log_info "Installiere Linux MCP-Integration..."
    
    # Alle Komponenten erstellen
    create_linux_mcp_client
    create_enhanced_streamlit_mcp_client  
    create_browser_shortcuts
    create_linux_mcp_management
    update_container_management_for_linux
    
    # Finale Zusammenfassung
    cat > LINUX_MCP_README.md << 'EOF'
# 🐧 Linux MCP Integration

## 🚀 Schnellstart für Linux

### 1. Container starten
```bash
./start_container.sh
```

### 2. Linux MCP-Tools nutzen
```bash
# Zentrales Management-Tool
./linux_mcp_manager.sh

# Direkter MCP-Client  
./linux_mcp_client.py

# Browser-Interfaces
./open_all_interfaces.sh
```

## 🛠️ Verfügbare Tools

### 📋 Management-Tools
- `linux_mcp_manager.sh` - Zentrales Management-Interface
- `linux_mcp_client.py` - Python MCP-Client für Terminal
- `enhanced_streamlit_client.py` - Erweiterte Web-Oberfläche

### 🌐 Browser-Shortcuts
- `open_mcp_inspector.sh` - MCP Inspector (http://localhost:6247)
- `open_web_client.sh` - Web-Client (http://localhost:8501)
- `open_all_interfaces.sh` - Alle Interfaces auf einmal

### 🔧 Container-Integration
- Nahtlose Container-Interaktion
- Automatische Service-Erkennung
- Intelligente Fehlerbehandlung

## 💡 Linux-Vorteile

✅ **Native Container-Integration**
✅ **Terminal-basierte MCP-Clients**  
✅ **Browser-basierte Interfaces**
✅ **Python-Erweiterbarkeit**
✅ **Bessere Automatisierung**

## 🎯 Empfohlener Workflow

1. **Starten:** `./linux_mcp_manager.sh`
2. **Container:** Option 1 (Container starten)
3. **Client:** Option 5 (Linux MCP-Client)
4. **Web:** Option 10 (Alle Browser-Interfaces)

---
**🐧 Linux ist die beste Plattform für MCP-Development!**
EOF

    log_success "Linux MCP-Integration installiert!"
    
    # Abschlussmeldung
    echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}🎉 LINUX MCP INTEGRATION ERFOLGREICH! 🎉${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}📁 Neue Tools verfügbar:${NC}"
    echo "  • linux_mcp_manager.sh      - Zentrales Management"
    echo "  • linux_mcp_client.py       - Python MCP-Client"
    echo "  • open_all_interfaces.sh    - Browser-Shortcuts"
    echo "  • enhanced_streamlit_client.py - Erweiterte Web-UI"
    echo ""
    echo -e "${PURPLE}🚀 Schnellstart:${NC}"
    echo "  ./linux_mcp_manager.sh       # Zentrales Tool"
    echo "  ./linux_mcp_client.py        # Direkter Client"
    echo "  ./open_all_interfaces.sh     # Browser öffnen"
    echo ""
    echo -e "${GREEN}🐧 Linux MCP bereit für Einsatz! 🚀${NC}"
}

# ============================================================================
# INTEGRATION IN HAUPT-INSTALLER
# Fügen Sie diese Zeile zur main() Funktion hinzu, nach create_container_readme
# ============================================================================

# Nach create_container_readme() hinzufügen:
# install_linux_mcp_integration