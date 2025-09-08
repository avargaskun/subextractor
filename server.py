import os
import subprocess
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

# Path to the subtitle extraction script inside the container
EXTRACT_SCRIPT_PATH = "/scripts/extractor.sh"

class RequestHandler(BaseHTTPRequestHandler):
    """
    A simple HTTP request handler that triggers the subtitle extraction script.
    Handles both GET and POST requests to the /extract endpoint.
    """

    def process_request(self, target_path):
        """
        Shared logic to validate a path and run the extraction script.
        """
        # --- 400 Bad Request: 'path' parameter is missing ---
        if not target_path:
            self.send_response(400)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"Error: 'path' parameter is required in the URL query or JSON body.")
            return

        # --- 400 Bad Request: Path does not exist ---
        if not os.path.exists(target_path):
            self.send_response(400)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            response_text = f"Error: The specified path does not exist inside the container: '{target_path}'"
            self.wfile.write(response_text.encode('utf-8'))
            return

        try:
            # Execute the shell script and capture its output and exit code
            print(f"Executing script for path: {target_path}")
            result = subprocess.run(
                [EXTRACT_SCRIPT_PATH, target_path],
                capture_output=True,
                text=True,
                check=False  # We will check the returncode manually
            )

            print(f"Script stdout:\n{result.stdout}")
            if result.stderr:
                print(f"Script stderr:\n{result.stderr}")

            # --- 200 OK: Script succeeded ---
            if result.returncode == 0:
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                response_body = f"Successfully processed '{target_path}'.\n\n--- SCRIPT OUTPUT ---\n{result.stdout}"
                self.wfile.write(response_body.encode('utf-8'))
            # --- 500 Internal Server Error: Script failed ---
            else:
                self.send_response(500)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                response_body = f"Script failed to process '{target_path}'.\n\n--- SCRIPT ERROR ---\n{result.stderr}\n\n--- SCRIPT OUTPUT ---\n{result.stdout}"
                self.wfile.write(response_body.encode('utf-8'))

        except Exception as e:
            # --- 500 Internal Server Error: Unexpected error ---
            self.send_response(500)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(f"An unexpected server error occurred: {str(e)}".encode('utf-8'))

    def do_GET(self):
        """
        Handles GET requests. Expects an /extract endpoint with a 'path' parameter.
        Example: /extract?path=/data/movie.mkv
        """
        # --- Log request details ---
        print("\n--- New GET Request Received ---")
        print(f"Timestamp: {self.log_date_time_string()}")
        print(f"Request from: {self.client_address[0]}:{self.client_address[1]}")
        print(f"Request line: {self.requestline}")
        
        parsed_path = urlparse(self.path)
        query_params = parse_qs(parsed_path.query)
        
        print(f"Parsed Path: {parsed_path.path}")
        print(f"Query Params: {query_params}")
        # Note: GET requests do not have a body to log.
        print("--------------------------")
        
        if parsed_path.path == '/extract':
            target_path = query_params.get('path', [None])[0]
            self.process_request(target_path)
        else:
            # --- 404 Not Found: For any other endpoint ---
            self.send_response(404)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"Not Found. Please use the /extract endpoint.")

    def do_POST(self):
        """
        Handles POST requests. Expects an /extract endpoint with a JSON body
        containing a 'path' key.
        Example: {"path": "/data/movie.mkv"}
        """
        # --- Log request details ---
        print("\n--- New POST Request Received ---")
        print(f"Timestamp: {self.log_date_time_string()}")
        print(f"Request from: {self.client_address[0]}:{self.client_address[1]}")
        print(f"Request line: {self.requestline}")

        parsed_path = urlparse(self.path)

        if parsed_path.path == '/extract':
            try:
                content_length = int(self.headers['Content-Length'])
                body = self.rfile.read(content_length)
                
                # --- Log the request body ---
                body_str = body.decode('utf-8')
                print(f"Request Body: {body_str}")
                print("--------------------------")

                data = json.loads(body_str)
                target_path = data.get('path')
                self.process_request(target_path)

            except json.JSONDecodeError:
                self.send_response(400)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"Error: Invalid JSON in request body.")
                return
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(f"An unexpected server error occurred while processing POST request: {str(e)}".encode('utf-8'))
        else:
            # --- 404 Not Found: For any other endpoint ---
            self.send_response(404)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"Not Found. Please use the /extract endpoint for POST requests.")


def run_server():
    """
    Starts the HTTP server on the configured port.
    """
    # Get port from environment variable, defaulting to 8080 if not set
    port = int(os.environ.get('LISTEN_PORT', 8080))
    server_address = ('', port)
    httpd = HTTPServer(server_address, RequestHandler)
    
    print(f"Server starting on port {port}...")
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()

