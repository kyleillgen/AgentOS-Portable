"""Headless, event-driven case checker and worker CLI; independent of the desk."""
import argparse
import contextlib
import json
import pathlib
import sys
import threading
import time
from operations_core import Desk
from operations_events import DirectoryWake, parent_alive


@contextlib.contextmanager
def singleton(registry):
    registry.mkdir(parents=True, exist_ok=True)
    with (registry/'checker.lock').open('a+b') as stream:
        if not stream.tell(): stream.write(b'0'); stream.flush()
        stream.seek(0)
        import msvcrt
        msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        yield


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--registry', required=True)
    parser.add_argument('--snapshot', action='store_true')
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--parent-pid', type=int, default=0)
    parser.add_argument('--stop-after', type=float, default=0)
    parser.add_argument('--claim'); parser.add_argument('--owner')
    parser.add_argument('--fingerprint'); parser.add_argument('--expected-revision', type=int)
    parser.add_argument('--lease-seconds', type=int, default=1800)
    parser.add_argument('--update'); parser.add_argument('--state'); parser.add_argument('--note')
    parser.add_argument('--evidence', action='append', default=[])
    parser.add_argument('--lease-token')
    args = parser.parse_args()
    desk = Desk(args.root, args.registry)
    if args.snapshot: print(json.dumps(desk.snapshot())); return
    if args.claim:
        print(json.dumps(desk.claim(args.claim, args.fingerprint, args.expected_revision, args.owner, args.lease_seconds))); return
    if args.update:
        print(json.dumps(desk.update(args.update, args.fingerprint, args.expected_revision, args.state, args.note, args.evidence, lease_token=args.lease_token))); return
    with singleton(desk.registry):
        if args.once:
            result=desk.run_check(); print(json.dumps(result))
            if result['error']: raise SystemExit(1)
            return
        wake = DirectoryWake([desk.root/'work', desk.registry])
        deadline = time.monotonic()+args.stop_after if args.stop_after else float('inf')
        next_check = 0
        while time.monotonic() < deadline and parent_alive(args.parent_pid):
            if wake.dirty.is_set() or time.monotonic() >= next_check:
                wake.dirty.clear()
                try: desk.run_check()
                except Exception as exc: print('Checker failed: '+str(exc), file=sys.stderr, flush=True)
                next_check = time.monotonic()+300
            time.sleep(.25)


if __name__ == '__main__': main()
