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

