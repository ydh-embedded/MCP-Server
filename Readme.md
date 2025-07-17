```ps

┌──────────────────────────┐      HTTP Request       ┌──────────────────────────────────┐
│                          │   (z.B. POST /command)  │                                  │
│     Open Interpreter     ├───────────────────────► │        Host-System (L-10117)     │
│ (läuft auf Ihrem Host)   │                         │                                  │
│                          │                         │  ┌────────────────────────────┐  │
└──────────────────────────┘      HTTP Response      │  │     Podman Container       │  │
      (JSON mit Ausgabe)     ◄───────────────────────┤  │                            │  │
                                                     │  │  ┌──────────┐  ┌─────────┐ │  │
                                                     │  │  │ API (app.py)│MCP-Client │  │
                                                     │  │  └─────┬────┘  └────▲────┘ │  │
                                                     │  │        │             │     │  │
                                                     │  │        └────►Pipes◄──┘     │  │
                                                     │  │      (stdin, stdout)       │  │
                                                     │  └────────────────────────────┘  │
                                                     └──────────────────────────────────┘
                                                     
```                                                 
                                                     
## REST - API

 - Eine REST-API ist hierfür die perfekte Lösung. Wir bauen einen kleinen Webserver (z.B. mit Flask), der neben Ihrem terminal_client.py läuft. Dieser Server nimmt HTTP-Anfragen entgegen, leitet die Befehle an Ihren Client weiter, fängt dessen Ausgabe ab und sendet sie als Antwort zurück.

## Fehlerbehebung

# 🐳 MCP Container Fehlerbehebung - Handout

## 🔍 **Problem-Symptome**
- Container läuft, aber MCP-Server (Port 6247) ist nicht erreichbar
- Streamlit (Port 8501) und Flask API (Port 5000) funktionieren
- Fehlermeldung: `❌ MCP-Server nicht erreichbar`

## 🚨 **Häufigste Container-Diagnose-Befehle**

### **Container-Status prüfen:**
```bash
podman ps -a                    # Alle Container anzeigen
podman inspect mcp-server       # Detaillierte Container-Info
podman stats mcp-server         # Resource-Verbrauch
```

### **Logs analysieren:**
```bash
podman logs mcp-server          # Alle Logs anzeigen
podman logs -f mcp-server       # Live-Logs verfolgen  
podman logs --tail 20 mcp-server # Letzte 20 Zeilen
```

### **Port-Tests:**
```bash
curl -I http://localhost:5000   # Flask API testen
curl -I http://localhost:8501   # Streamlit testen
curl -I http://localhost:6247   # MCP-Server testen
```

## 🐛 **Spezifisches Problem: Pydantic URL-Validierungsfehler**

### **Fehlermeldung in Logs:**
```
pydantic_core._pydantic_core.ValidationError: 1 validation error
Input should be a valid URL, relative URL without a base
[type=url_parsing, input_value='container-logs', input_type=str]
```

### **Root-Cause:**
In `mcp_installer_script.sh` waren **ungültige URL-Formate** definiert:

## 🔧 **Lösung: Script-Reparatur**

### **1. Fehler lokalisieren:**
```bash
grep -n "@mcp.resource" mcp_installer_script.sh
# Ausgabe zeigt:
# 290:@mcp.resource("container-logs")  ❌ FALSCH
# 299:@mcp.resource("system-info")     ❌ FALSCH
```

### **2. URLs korrigieren:**
```bash
# Automatische Reparatur:
sed -i 's/@mcp.resource("container-logs")/@mcp.resource("file:\/\/\/container-logs")/g' mcp_installer_script.sh
sed -i 's/@mcp.resource("system-info")/@mcp.resource("file:\/\/\/system-info")/g' mcp_installer_script.sh
```

### **3. Reparatur verifizieren:**
```bash
grep -n "@mcp.resource" mcp_installer_script.sh
# Sollte zeigen:
# 290:@mcp.resource("file:///container-logs")  ✅ RICHTIG
# 299:@mcp.resource("file:///system-info")     ✅ RICHTIG
```

## 🔄 **Container vollständig neu erstellen**

### **Warum notwendig?**
Podman/Docker verwendet **Build-Caching**. Ohne komplette Löschung wird das alte, defekte Image wiederverwendet.

### **Vollständiger Reset:**
```bash
# 1. Container stoppen und entfernen
podman stop mcp-server
podman rm mcp-server

# 2. WICHTIG: Image löschen (Cache vermeiden)
podman rmi localhost/mcp-server:latest

# 3. Überprüfen, dass Image weg ist
podman images

# 4. Script neu ausführen
./mcp_installer_script.sh
```

## ✅ **Erfolgreiche Lösung verifizieren**

### **Nach dem Neuaufbau testen:**
```bash
# 1. Container-Status prüfen
podman ps

# 2. Logs checken (KEINE Pydantic-Fehler mehr!)
podman logs mcp-server

# 3. Alle Ports testen
curl -I http://localhost:8501  # ✅ Streamlit: 200 OK
curl -I http://localhost:5000  # ✅ Flask API: 404 (normal)
curl -I http://localhost:6247  # ✅ MCP-Server: 200 OK
```

## 🚀 **Erfolgreiches Resultat**

**Alle drei Services laufen:**
- **Port 8501:** Streamlit Web-Client
- **Port 5000:** Flask API Server  
- **Port 6247:** MCP-Server (Inspector)

## 💡 **Wichtige Erkenntnisse**

1. **Container können laufen, aber Services können fehlschlagen**
2. **Logs sind der Schlüssel zur Diagnose** (`podman logs`)
3. **Pydantic erwartet gültige URL-Formate** (nicht nur Strings)
4. **Build-Cache muss bei Code-Änderungen geleert werden**
5. **Vollständiger Reset** ist oft schneller als partielles Debugging

## 🛠️ **Präventive Maßnahmen**

- **Regelmäßig Logs checken:** `podman logs mcp-server`
- **Bei Änderungen immer Cache leeren:** `podman rmi <image>`
- **Port-Tests in Monitoring einbauen**
- **URL-Validierung vor Container-Build**

---
*📝 Dieses Handout dokumentiert die erfolgreiche Lösung eines MCP Container-Problems vom 17.07.2025*