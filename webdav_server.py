#!/usr/bin/env python3
"""
Simple WebDAV server with basic authentication for testing purposes.
"""

import os
import base64
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import unquote
import json
from datetime import datetime

# Configuration
WEBDAV_ROOT = "/workspaces/WeddingPic/webdav_uploads"
USERNAME = "wedding"
PASSWORD = "photo123"
PORT = 9000

class WebDAVHandler(BaseHTTPRequestHandler):
    def authenticate(self):
        """Check HTTP Basic Authentication"""
        auth_header = self.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Basic '):
            return False
        
        try:
            encoded_credentials = auth_header[6:]  # Remove 'Basic '
            decoded_credentials = base64.b64decode(encoded_credentials).decode('utf-8')
            username, password = decoded_credentials.split(':', 1)
            return username == USERNAME and password == PASSWORD
        except:
            return False
    
    def send_auth_required(self):
        """Send 401 Unauthorized response"""
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="WebDAV"')
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b'Authentication required')
    
    def send_cors_headers(self):
        """Send CORS headers to allow web requests"""
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PROPFIND, MKCOL')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Depth, Content-Length')
        self.send_header('Access-Control-Expose-Headers', 'Content-Length, Last-Modified')
    
    def do_OPTIONS(self):
        """Handle preflight CORS requests"""
        self.send_response(200)
        self.send_cors_headers()
        self.end_headers()
    
    def do_PUT(self):
        """Handle file uploads"""
        if not self.authenticate():
            self.send_auth_required()
            return
        
        # Get file path
        file_path = unquote(self.path[1:])  # Remove leading slash
        full_path = os.path.join(WEBDAV_ROOT, file_path)
        
        # Create directory if it doesn't exist
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        
        try:
            # Get content length
            content_length = int(self.headers.get('Content-Length', 0))
            
            # Read file data
            file_data = self.rfile.read(content_length)
            
            # Write file
            with open(full_path, 'wb') as f:
                f.write(file_data)
            
            print(f"Uploaded: {full_path} ({len(file_data)} bytes)")
            
            # Send success response
            self.send_response(201)  # Created
            self.send_cors_headers()
            self.end_headers()
            
        except Exception as e:
            print(f"Error uploading file: {e}")
            self.send_response(500)
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(f"Error: {str(e)}".encode())
    
    def do_GET(self):
        """Handle file downloads and directory listings"""
        if not self.authenticate():
            self.send_auth_required()
            return
        
        file_path = unquote(self.path[1:])  # Remove leading slash
        full_path = os.path.join(WEBDAV_ROOT, file_path)
        
        try:
            if os.path.isfile(full_path):
                # Serve file
                with open(full_path, 'rb') as f:
                    content = f.read()
                
                self.send_response(200)
                self.send_cors_headers()
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                
            elif os.path.isdir(full_path):
                # List directory
                files = []
                for item in os.listdir(full_path):
                    item_path = os.path.join(full_path, item)
                    is_dir = os.path.isdir(item_path)
                    size = 0 if is_dir else os.path.getsize(item_path)
                    files.append({
                        'name': item,
                        'type': 'directory' if is_dir else 'file',
                        'size': size
                    })
                
                response = json.dumps(files, indent=2)
                self.send_response(200)
                self.send_cors_headers()
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(response)))
                self.end_headers()
                self.wfile.write(response.encode())
                
            else:
                self.send_response(404)
                self.send_cors_headers()
                self.end_headers()
                self.wfile.write(b'File not found')
                
        except Exception as e:
            print(f"Error serving file: {e}")
            self.send_response(500)
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(f"Error: {str(e)}".encode())
    
    def do_PROPFIND(self):
        """Handle WebDAV PROPFIND requests"""
        if not self.authenticate():
            self.send_auth_required()
            return
        
        self.send_response(207)  # Multi-Status
        self.send_cors_headers()
        self.send_header('Content-Type', 'application/xml')
        self.end_headers()
        
        # Simple PROPFIND response
        response = '''<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
    <response>
        <href>/</href>
        <propstat>
            <status>HTTP/1.1 200 OK</status>
        </propstat>
    </response>
</multistatus>'''
        self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        """Override to add timestamp to logs"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] {format % args}")

def main():
    # Create upload directory
    os.makedirs(WEBDAV_ROOT, exist_ok=True)
    
    # Start server
    server = HTTPServer(('0.0.0.0', PORT), WebDAVHandler)
    print(f"WebDAV Server starting on port {PORT}")
    print(f"Upload directory: {WEBDAV_ROOT}")
    print(f"Username: {USERNAME}")
    print(f"Password: {PASSWORD}")
    print(f"WebDAV URL: http://localhost:{PORT}/")
    print("Press Ctrl+C to stop the server")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.shutdown()

if __name__ == '__main__':
    main()
