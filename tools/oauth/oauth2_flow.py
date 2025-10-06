#!/usr/bin/env python3
"""
pCloud OAuth2 - Code Flow mit manuellem Fallback
"""

import os
import sys
import getpass
import webbrowser
import requests
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from pathlib import Path
import threading
import time

try:
    from dotenv import load_dotenv
except ImportError:
    print("python-dotenv nicht installiert. Installiere mit: pip install python-dotenv")
    sys.exit(1)

env_file = Path(".env")
if env_file.exists():
    load_dotenv(env_file)

AUTHORIZE_URL = "https://my.pcloud.com/oauth2/authorize"
PORT = 8000
REDIRECT_URI = f"http://127.0.0.1:{PORT}"

CLIENT_ID = os.getenv("PCLOUD_CLIENT_ID")
CLIENT_SECRET = os.getenv("PCLOUD_CLIENT_SECRET")

if not CLIENT_ID:
    CLIENT_ID = getpass.getpass("Client ID (verborgen): ").strip()
    if not CLIENT_ID:
        print("✗ Client ID erforderlich")
        sys.exit(1)

if not CLIENT_SECRET:
    CLIENT_SECRET = getpass.getpass("Client Secret (verborgen): ").strip()
    if not CLIENT_SECRET:
        print("✗ Client Secret erforderlich")
        sys.exit(1)

auth_code = None
api_hostname = None
server_ready = threading.Event()
shutdown_requested = threading.Event()


class OAuthCallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global auth_code, api_hostname
        
        parsed_url = urlparse(self.path)
        query_params = parse_qs(parsed_url.query)
        
        if "code" in query_params:
            auth_code = query_params["code"][0]
            if "hostname" in query_params:
                api_hostname = query_params["hostname"][0]
            
            print(f"✓ Code vom Server erhalten!")
            
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"<h1>OK</h1>")
            shutdown_requested.set()
            return
        
        self.send_response(400)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(b"<h1>Fehler</h1>")
    
    def log_message(self, format, *args):
        pass


def run_server():
    try:
        server = HTTPServer(("0.0.0.0", PORT), OAuthCallbackHandler)
        server.timeout = 1
        print(f"[Server] Läuft auf {REDIRECT_URI}")
        server_ready.set()
        
        while not shutdown_requested.is_set():
            try:
                server.handle_request()
            except:
                pass
        
        server.server_close()
    except Exception as e:
        print(f"[Server] Fehler: {e}")
        sys.exit(1)


def extract_code_from_url(url):
    """Code aus URL extrahieren (Query-String oder Fragment)"""
    global api_hostname
    
    parsed_url = urlparse(url)
    
    query_params = parse_qs(parsed_url.query)
    if "code" in query_params:
        code = query_params["code"][0]
        if "hostname" in query_params:
            api_hostname = query_params["hostname"][0]
        return code
    
    fragment_params = parse_qs(parsed_url.fragment)
    if "access_token" in fragment_params:
        print("✗ Token Flow nicht unterstützt - nutze Code Flow!")
        return None
    
    return None


def main():
    global auth_code, api_hostname
    
    print("=" * 60)
    print("pCloud OAuth2 - Code Flow")
    print("=" * 60)
    
    print(f"\n[1] Starte lokalen HTTP-Server...")
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    
    if not server_ready.wait(timeout=5):
        print("✗ Server konnte nicht gestartet werden")
        sys.exit(1)
    
    print(f"\n[2] Öffne Browser...")
    auth_url = f"{AUTHORIZE_URL}?client_id={CLIENT_ID}&response_type=code&redirect_uri={REDIRECT_URI}"
    
    print(f"\nAUTHORIZATION URL:")
    print(f"{auth_url}\n")
    
    try:
        webbrowser.open(auth_url)
    except:
        pass
    
    print(f"[3] Warte auf Redirect (60 Sekunden)...")
    start_time = time.time()
    timeout = 60
    
    while not auth_code and (time.time() - start_time) < timeout:
        time.sleep(0.1)
    
    if not auth_code:
        print(f"\n⚠ Kein automatischer Redirect empfangen")
        print(f"Gib die Redirect-URL ein (oder nur den Code):\n")
        
        user_input = input("URL oder Code: ").strip()
        
        if not user_input:
            print("✗ Nichts eingegeben")
            sys.exit(1)
        
        if user_input.startswith("http"):
            auth_code = extract_code_from_url(user_input)
            if not auth_code:
                print("✗ Kein Code in URL gefunden")
                sys.exit(1)
        else:
            auth_code = user_input
    
    print(f"✓ Code: {auth_code[:30]}...")
    if api_hostname:
        print(f"✓ Hostname: {api_hostname}")
    
    print(f"\n[4] Hole Access Token...")
    
    token_url = "https://api.pcloud.com/oauth2_token"
    if api_hostname and api_hostname.startswith("eapi"):
        token_url = f"https://{api_hostname}/oauth2_token"
        print(f"  (EU-Region: nutze {token_url})")
    
    token_params = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "code": auth_code
    }
    
    try:
        response = requests.post(token_url, data=token_params)
        response.raise_for_status()
        
        data = response.json()
        
        if data.get("result") == 0:
            print("✓ Token erfolgreich erhalten!")
            
            access_token = data.get("access_token")
            token_type = data.get("token_type")
            uid = data.get("uid")
            
            print(f"  Token Type: {token_type}")
            print(f"  UID: {uid}")
            
            print(f"\n[5] Speichere Token in token.env...")
            token_file = Path("token.env")
            
            if token_file.exists():
                token_file.unlink()
            
            with open(token_file, "w") as f:
                f.write(f"PCLOUD_ACCESS_TOKEN={access_token}\n")
                f.write(f"PCLOUD_TOKEN_TYPE={token_type}\n")
                if uid:
                    f.write(f"PCLOUD_UID={uid}\n")
                if api_hostname:
                    f.write(f"PCLOUD_HOSTNAME={api_hostname}\n")
                f.write(f"PCLOUD_TOKEN_RESPONSE={json.dumps(data)}\n")
            
            try:
                import stat
                token_file.chmod(0o600)
            except:
                pass
            
            print(f"✓ Token in token.env gespeichert\n")
            print("=" * 60)
            print("✓ Erfolg!")
            print("=" * 60)
        else:
            error = data.get("error", "Unbekannter Fehler")
            print(f"✗ Fehler: {error}")
            sys.exit(1)
    
    except requests.exceptions.RequestException as e:
        print(f"✗ Request Fehler: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
