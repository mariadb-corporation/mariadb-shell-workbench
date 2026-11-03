#!/usr/bin/env python3
"""nginx auth_request target of the multi-user MariaDB Shell Workbench (runs as root).

For each request nginx asks here first. The spawner asks oauth2-proxy who is logged in (forwarding
the request's cookies), then makes sure that user's IDE runs and answers 202 with
X-Workbench-User, which nginx uses to pick /run/mariadb-shell-workbench/<user>/theia.sock:
- a Keycloak user is accepted only under a valid Linux name; a Linux account that exists must be
  in group "workbench" (so "root" or "www-data" never map to a system account), a missing one is
  created (home 0700, no password, ~/workspace);
- the IDE is mariadb-shell-workbench@<user>.service; the spawner waits for its socket;
- an IDE with no connection and no request for WORKBENCH_IDLE_MINUTES (default 90) is stopped;
- the user's sandboxes and REST daemons outlive their IDE: MariaDB Shell starts them detached, but
  they stay in the IDE's cgroup, and stopping the IDE ends its whole cgroup. Every minute, and from
  the IDE's ExecStop ("workbench-spawner.py adopt <user>"), they are moved to a scope of their own
  in workbench-daemons-<user>.slice, which has limits like an IDE's.
Listens on /run/mariadb-shell-workbench/spawner.sock, root:www-data 0660: only nginx can ask.
"""
import grp
import http.client
import http.server
import os
import pwd
import re
import socket
import socketserver
import subprocess
import sys
import threading
import time

OAUTH2_PROXY = ("127.0.0.1", 4180)
RUN_DIR = "/run/mariadb-shell-workbench"
SOCKET = f"{RUN_DIR}/spawner.sock"
GROUP = "workbench"
NAME = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
IDLE_SECONDS = int(os.environ.get("WORKBENCH_IDLE_MINUTES", "90")) * 60
START_TIMEOUT = 120
FORWARD = ("cookie", "authorization", "x-forwarded-for", "x-forwarded-proto",
           "x-forwarded-host", "x-forwarded-uri")
# Accounts get IDs from 10000 on: below that, IDs of the first regular accounts (1000, ...) are
# what container images run as (Keycloak's runs as 1000), and a user with the same ID could
# signal those processes.
ID_RANGE = ["-K", "UID_MIN=10000", "-K", "UID_MAX=59999", "-K", "GID_MIN=10000",
            "-K", "GID_MAX=59999"]
CGROUP_ROOT = "/sys/fs/cgroup/system.slice/system-mariadb\\x2dworkbench.slice"
DAEMONS = ("mariadbd", "mariadb-restd")
DAEMON_LIMITS = ["MemoryHigh=1G", "MemoryMax=1536M", "CPUQuota=150%", "TasksMax=512"]

last_seen = {}       # user -> time of the last request or open connection
ready_until = {}     # user -> time until which the running IDE need not be checked again
user_locks = {}
locks_lock = threading.Lock()


def log(msg):
    print(msg, flush=True)


def lock_for(user):
    with locks_lock:
        return user_locks.setdefault(user, threading.Lock())


def socket_path(user):
    return f"{RUN_DIR}/{user}/theia.sock"


def listening(user):
    """True if the IDE accepts connections. The socket file alone proves nothing: Theia leaves it
    behind when it stops, and the unit's ExecStopPost that removes it may not have run (an IDE
    started from an older unit, a stop cut short)."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        try:
            s.connect(socket_path(user))
            return True
        except OSError:
            return False


def ensure_account(user):
    """True if user is a workbench account (created if missing)."""
    try:
        entry = pwd.getpwnam(user)
    except KeyError:
        subprocess.run(["useradd", "--create-home", "--shell", "/bin/bash", "--groups", GROUP,
                        "-K", "HOME_MODE=0700", *ID_RANGE, user], check=True)
        entry = pwd.getpwnam(user)
        workspace = os.path.join(entry.pw_dir, "workspace")
        os.makedirs(workspace, exist_ok=True)
        os.chown(workspace, entry.pw_uid, entry.pw_gid)
        log(f"created account {user}")
        return True
    group = grp.getgrnam(GROUP)
    return user in group.gr_mem or entry.pw_gid == group.gr_gid


def escape(name):
    return subprocess.run(["systemd-escape", name], capture_output=True, text=True,
                          check=True).stdout.strip()


def adopt_daemons(user):
    """Moves the user's sandboxes and REST daemons out of the IDE's cgroup, each with the
    detached restart loop that runs it (a shell whose parent is gone), into a scope of its own."""
    try:
        with open(f"{CGROUP_ROOT}/mariadb-shell-workbench@{user}.service/cgroup.procs") as f:
            pids = {int(p) for p in f.read().split()}
    except OSError:
        return
    def parent(pid):
        with open(f"/proc/{pid}/stat") as f:
            return int(f.read().rsplit(")", 1)[1].split()[1])
    for pid in sorted(pids):
        try:
            if os.path.basename(os.readlink(f"/proc/{pid}/exe")) not in DAEMONS:
                continue
            group = [pid]
            ppid = parent(pid)
            if (ppid in pids and parent(ppid) == 1 and
                    os.path.basename(os.readlink(f"/proc/{ppid}/exe")) in ("bash", "sh", "dash")):
                group.insert(0, ppid)
        except OSError:
            continue    # exited meanwhile
        # A "-" in a slice name means a child slice: escape the user's.
        slice_ = f"workbench-daemons-{escape(user)}.slice"
        subprocess.run(["systemctl", "set-property", "--runtime", slice_, *DAEMON_LIMITS])
        scope = f"workbench-daemon-{user}-{pid}.scope"
        # A transient scope takes over running processes (systemd-run --scope can only start new
        # ones): StartTransientUnit(name, mode, 3 properties, no auxiliary units).
        result = subprocess.run(
            ["busctl", "call", "org.freedesktop.systemd1", "/org/freedesktop/systemd1",
             "org.freedesktop.systemd1.Manager", "StartTransientUnit", "ssa(sv)a(sa(sv))",
             scope, "fail", "3",
             "PIDs", "au", str(len(group)), *map(str, group),
             "Slice", "s", slice_,
             "Description", "s", f"MariaDB Shell Workbench daemon of {user}",
             "0"],
            capture_output=True, text=True)
        log(f"moved {user}'s daemon {pid} to {scope}" if result.returncode == 0 else
            f"could not move {user}'s daemon {pid}: {result.stderr.strip()}")


def ensure_running(user):
    now = time.time()
    if ready_until.get(user, 0) > now and listening(user):
        return True
    unit = f"mariadb-shell-workbench@{user}.service"
    if subprocess.run(["systemctl", "is-active", "--quiet", unit]).returncode != 0:
        log(f"starting {unit}")
        subprocess.run(["systemctl", "start", unit], check=True)
    deadline = now + START_TIMEOUT
    while time.time() < deadline:
        if listening(user):
            ready_until[user] = time.time() + 10
            return True
        time.sleep(0.5)
    return False


class Handler(http.server.BaseHTTPRequestHandler):
    def address_string(self):
        return "nginx"

    def log_message(self, fmt, *args):
        pass

    def reply(self, status, headers=()):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        conn = http.client.HTTPConnection(*OAUTH2_PROXY, timeout=15)
        conn.request("GET", "/oauth2/auth",
                     headers={k: v for k, v in self.headers.items() if k.lower() in FORWARD})
        resp = conn.getresponse()
        resp.read()
        cookies = [("Set-Cookie", v) for k, v in resp.getheaders() if k.lower() == "set-cookie"]
        if resp.status != 202:
            return self.reply(resp.status, cookies)
        user = resp.getheader("X-Auth-Request-Preferred-Username", "")
        if not NAME.match(user):
            log(f"refused login name {user!r}")
            return self.reply(403, cookies)
        with lock_for(user):
            if not ensure_account(user):
                log(f"refused {user}: existing account not in group {GROUP}")
                return self.reply(403, cookies)
            last_seen[user] = time.time()
            if not ensure_running(user):
                log(f"{user}: IDE did not come up")
                return self.reply(503, cookies)
        self.reply(202, [("X-Workbench-User", user)] + cookies)


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def connected_sockets():
    out = subprocess.run(["ss", "-xHn", "state", "connected"], capture_output=True, text=True).stdout
    return {f for line in out.splitlines() for f in line.split() if f.endswith("/theia.sock")}


def reaper():
    while True:
        time.sleep(60)
        units = subprocess.run(["systemctl", "list-units", "mariadb-shell-workbench@*", "--state=active",
                                "--plain", "--no-legend"], capture_output=True, text=True).stdout
        busy = connected_sockets()
        now = time.time()
        for line in units.splitlines():
            user = line.split()[0][len("mariadb-shell-workbench@"):-len(".service")]
            adopt_daemons(user)
            if socket_path(user) in busy:
                last_seen[user] = now
            elif now - last_seen.setdefault(user, now) > IDLE_SECONDS:
                with lock_for(user):
                    log(f"stopping idle IDE of {user}")
                    ready_until.pop(user, None)
                    subprocess.run(["systemctl", "stop", f"mariadb-shell-workbench@{user}.service"])


def main():
    if os.path.exists(SOCKET):
        os.remove(SOCKET)
    server = Server(SOCKET, Handler)
    os.chown(SOCKET, 0, grp.getgrnam("www-data").gr_gid)
    os.chmod(SOCKET, 0o660)
    threading.Thread(target=reaper, daemon=True).start()
    log(f"listening on {SOCKET}")
    server.serve_forever()


if __name__ == "__main__":
    if sys.argv[1:2] == ["adopt"] and len(sys.argv) == 3 and NAME.match(sys.argv[2]):
        adopt_daemons(sys.argv[2])
    else:
        main()
