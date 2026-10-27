#!/usr/bin/env python3
"""Run the module and real npm against a local HTTPS JFrog/registry fixture."""

import base64
import hashlib
import http.server
import io
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import tarfile
import tempfile
import threading
import time


MODULE = Path(__file__).resolve().parents[1]


def main():
    for command in ("npm", "node", "jq", "curl", "openssl"):
        if not shutil.which(command):
            raise SystemExit(f"Required command not found: {command}")

    with tempfile.TemporaryDirectory(prefix="jfrog-oidc-test-") as directory:
        root = Path(directory)
        home = root / "home"
        home.mkdir()
        binaries = root / "bin"
        binaries.mkdir()
        identity_calls = root / "identity-calls"
        identity = binaries / "replit"
        identity.write_text(
            "#!/usr/bin/env bash\n"
            '[[ "$*" == "identityv2 create --audience test-jfrog" ]] || exit 1\n'
            f"printf 'mint\\n' >> '{identity_calls}'\n"
            "printf 'fixture-identity'\n"
        )
        identity.chmod(0o700)
        certificate, key = root / "cert.pem", root / "key.pem"
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(key), "-out", str(certificate), "-days", "1",
                "-subj", "/CN=localhost", "-addext",
                "subjectAltName=DNS:localhost,IP:127.0.0.1",
            ],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        package = io.BytesIO()
        with tarfile.open(fileobj=package, mode="w:gz") as archive:
            content = json.dumps({"name": "private-fixture", "version": "1.0.0"}).encode()
            entry = tarfile.TarInfo("package/package.json")
            entry.size = len(content)
            archive.addfile(entry, io.BytesIO(content))
        tarball = package.getvalue()
        state = {"exchanges": 0, "downloads": 0, "failure": None, "requests": []}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                expected = {
                    "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
                    "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
                    "subject_token": "fixture-identity",
                    "provider_name": "replit-test",
                    "project_key": "fixture-project",
                }
                if self.path != "/access/api/v1/oidc/token" or body != expected:
                    self.send_error(400)
                    return
                state["exchanges"] += 1
                if state["failure"] == "http":
                    self.send_error(401)
                    return
                response = {
                    "access_token": "fixture-access",
                    "token_type": "Bearer",
                    "expires_in": 3600,
                }
                if state["failure"] == "expiry":
                    response["expires_in"] = 0
                if state["failure"] == "token":
                    response["access_token"] = "fixture\ninvalid"
                encoded = json.dumps(response).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def do_GET(self):
                state["requests"].append((
                    self.headers.get("Host"), self.path,
                    bool(self.headers.get("Authorization")),
                ))
                if self.path != "/artifactory/api/npm/fixture/private-fixture.tgz":
                    self.send_error(404)
                    return
                if self.headers.get("Authorization") != "Bearer fixture-access":
                    self.send_error(401)
                    return
                state["downloads"] += 1
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(tarball)))
                self.end_headers()
                self.wfile.write(tarball)

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(certificate, key)
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            origin = f"https://localhost:{server.server_port}"
            registry = f"{origin}/artifactory/api/npm/fixture/"
            env = dict(
                os.environ,
                HOME=str(home),
                PATH=f"{binaries}:{os.environ['PATH']}",
                REPLIT_OIDC_STATE_DIR=str(home / ".config/replit-oidc"),
                NPM_CONFIG_USERCONFIG=str(home / ".npmrc"),
                NODE_EXTRA_CA_CERTS=str(certificate),
                CURL_CA_BUNDLE=str(certificate),
            )
            env.pop("REPLIT_JFROG_TOKEN", None)
            project = root / "project"
            project.mkdir()
            npmrc = home / ".npmrc"
            npmrc.write_text("fund=false\n")
            arguments = [
                "bash", str(MODULE / "build.sh"),
                f"--platform-url={origin}", "--provider-name=replit-test",
                "--audience=test-jfrog", f"--registry={registry}",
                "--project-key=fixture-project", "--disable-deps-install",
            ]

            def run(command, success=True):
                result = subprocess.run(
                    command, env=env, cwd=project, capture_output=True, text=True,
                    timeout=60,
                )
                assert (result.returncode == 0) == success, (
                    f"Unexpected exit status {result.returncode} for {command[0]}"
                )
                assert "fixture-access" not in result.stdout + result.stderr
                assert "fixture-identity" not in result.stdout + result.stderr
                return result

            run(arguments)
            run(arguments)
            assert state["exchanges"] == 0 and not identity_calls.exists()
            assert npmrc.read_text().count("# BEGIN replit jfrog-oidc") == 1
            assert "fund=false" in npmrc.read_text()
            assert "${REPLIT_JFROG_TOKEN}" in npmrc.read_text()
            oidc = home / ".config/replit-oidc"
            env["PATH"] = f"{oidc / 'bin'}:{env['PATH']}"
            run(["npm", "--version"])
            assert state["exchanges"] == 0
            (project / "package.json").write_text(json.dumps({
                "name": "fixture-app", "version": "1.0.0",
                "dependencies": {"private-fixture": "1.0.0"},
            }))
            (project / "package-lock.json").write_text(json.dumps({
                "name": "fixture-app", "version": "1.0.0", "lockfileVersion": 3,
                "packages": {
                    "": {"name": "fixture-app", "version": "1.0.0",
                         "dependencies": {"private-fixture": "1.0.0"}},
                    "node_modules/private-fixture": {
                        "version": "1.0.0",
                        "resolved": f"{registry}private-fixture.tgz",
                        "integrity": "sha512-" + base64.b64encode(
                            hashlib.sha512(tarball).digest()
                        ).decode(),
                    },
                },
            }))
            lock_before = (project / "package-lock.json").read_bytes()
            ci = ["npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund",
                  "--fetch-retries=0", "--cache", str(root / "npm-cache")]
            run(ci)
            assert state["exchanges"] == 1 and state["downloads"] == 1
            assert (project / "node_modules/private-fixture/package.json").exists()
            assert (project / "package-lock.json").read_bytes() == lock_before
            assert "fixture-access" not in npmrc.read_text()
            cache = oidc / "jfrog/access-token.json"
            assert cache.stat().st_mode & 0o777 == 0o600
            assert cache.parent.stat().st_mode & 0o777 == 0o700
            run(["npm", "config", "get", "fund"])
            assert state["exchanges"] == 1
            other_origin = f"https://127.0.0.1:{server.server_port}"
            run(["npm", "view", "missing-fixture", f"--registry={other_origin}/other/",
                 "--fetch-retries=0", "--cache", str(root / "npm-cache")],
                success=False)
            other_requests = [authenticated for host, _, authenticated in state["requests"]
                              if host.startswith("127.0.0.1:")]
            assert other_requests and not any(other_requests)
            assert state["exchanges"] == 1
            stale = json.loads(cache.read_text())
            stale["expires_at"] = int(time.time()) + 30
            cache.write_text(json.dumps(stale))
            run(["npm", "config", "get", "fund"])
            assert state["exchanges"] == 2
            for failure in ("http", "expiry", "token"):
                cache.unlink(missing_ok=True)
                state["failure"] = failure
                run(["npm", "config", "get", "fund"], success=False)
                assert not cache.exists()
            state["failure"] = None
            run(arguments + ["--scope=@example"])
            assert f"@example:registry={registry}" in npmrc.read_text()
            for invalid in ("http://example.com", "https://user:pass@example.com",
                            "https://example.com/?token=value"):
                run(arguments + [f"--platform-url={invalid}"], success=False)
                run(arguments + [f"--registry={invalid}"], success=False)
            # A later managed CLI install must not move npm behind its real binary.
            helper_check = (
                f"OIDC_MODULE_NAME=test; MODULE_DIR='{MODULE}'; "
                f"source '{MODULE.parent}/lib/oidc.sh'; "
                f"source '{MODULE.parent}/lib/dependencies.sh'; "
                "oidc_env_prepend_path() { printf '%s\\n' \"$1\" >> \"$HOME/paths\"; }; "
                "oidc_real_cli() { return 1; }; oidc_cli_version() { printf '1.2.3'; }; "
                "oidc_cli_install() { mkdir -p \"$3/bin\"; "
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$3/bin/aws\"; "
                "chmod +x \"$3/bin/aws\"; }; "
                "oidc_dependencies aws 1.2.3"
            )
            run(["bash", "-c", helper_check])
            assert (home / "paths").read_text().splitlines()[-1] == str(oidc / "bin")
            print("PASS: real npm private-package install over HTTPS; lazy auth, cache reuse,")
            print("expiry refresh, safe failures, credential scoping, permissions, idempotency,")
            print("and wrapper priority after another managed CLI installation")
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


if __name__ == "__main__":
    main()
