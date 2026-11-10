# Run a command in a new pty. Send the answer when the prompt shows. Print all output.
import os, pty, sys, select
answer = sys.argv[1].encode()
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
buf = b""; sent = False
while True:
    try:
        r, _, _ = select.select([fd], [], [], 10)
        if not r: break
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data: break
    buf += data
    if not sent and b"[y/N]" in buf:
        os.write(fd, answer + b"\n"); sent = True
_, st = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
sys.stdout.write("\nRC=%d\n" % os.waitstatus_to_exitcode(st))
