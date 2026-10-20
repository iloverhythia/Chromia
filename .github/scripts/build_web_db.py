"""Builds the map database mirror the web version of Chromia reads.

Browsers only let the game fetch files from hosts that allow it (CORS), and
two of the map databases (cdn.rhythia.net, savia.nysr.host) don't. This copies
their index.json files into the web-db branch (served by raw.githubusercontent.com,
which allows it) and points each map's download at rhythia.com's archive copy
(static.rhythia.com/rhythia-legacy-<sha256>.sspm, same bytes, allows CORS)
when there is one. File hashes are kept in hashes.json so each map is only
downloaded once.

Usage: build_web_db.py <out_dir>
"""
import concurrent.futures as cf
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

DBS = [
    "https://cdn.rhythia.net/index.json",
    "https://savvyscripter-gh.github.io/savia_db/index.json",
    "https://savia.nysr.host/ranked-maps/index.json",
]
# Hosts browsers can already download from; their links are left as they are.
CORS_OK = ("https://raw.githubusercontent.com/", "https://static.rhythia.com/",
           "https://savvyscripter-gh.github.io/")
ARCHIVE = "https://static.rhythia.com/rhythia-legacy-%s.sspm"
HEADERS = {"User-Agent": "Mozilla/5.0 (Chromia web-db mirror)"}
TIME_BUDGET = 100 * 60  # stop hashing new maps after this; the next run continues


def get(url, timeout=120, method="GET"):
    last = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers=HEADERS, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                if method == "HEAD":
                    return r.status
                if url.endswith(".json"):
                    return r.read()
                h = hashlib.sha256()
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    h.update(chunk)
                return h.hexdigest()
        except urllib.error.HTTPError as e:
            if method == "HEAD" or e.code in (403, 404, 410):
                return e.code if method == "HEAD" else None
            last = e
        except Exception as e:  # network hiccup: retry
            last = e
        time.sleep(2 * (attempt + 1))
    raise RuntimeError("%s: %s" % (url, last))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    hashes_path = os.path.join(out, "hashes.json")
    try:
        with open(hashes_path) as f:
            hashes = json.load(f)  # "url|version" -> {"sha": ..., "archived": bool}
    except Exception:
        hashes = {}

    started = time.time()
    status = {"updated": int(started), "dbs": []}
    for idx, url in enumerate(DBS):
        try:
            raw = get(url, 180)
            maps = json.loads(raw)
        except Exception as e:
            print("db%d: couldn't fetch %s (%s), keeping the previous copy" % (idx, url, e))
            status["dbs"].append({"source": url, "ok": False})
            continue

        todo = []
        for m in maps.values():
            dl = str(m.get("download", ""))
            if dl and not dl.startswith(CORS_OK):
                key = "%s|%s" % (dl, m.get("version", ""))
                if key not in hashes:
                    todo.append(key)

        def work(key):
            sha = get(key.rsplit("|", 1)[0])
            if not sha:
                return key, {"sha": None, "archived": False}
            return key, {"sha": sha, "archived": get(ARCHIVE % sha, 30, "HEAD") == 200}

        print("db%d: %d maps, %d to hash" % (idx, len(maps), len(todo)))
        with cf.ThreadPoolExecutor(12) as pool:
            futures = [pool.submit(work, k) for k in todo]
            for n, fut in enumerate(cf.as_completed(futures)):
                try:
                    k, v = fut.result()
                    hashes[k] = v
                except Exception as e:
                    print("  skipped:", e)
                if n % 100 == 0:
                    print("  %d/%d" % (n, len(todo)))
                if time.time() - started > TIME_BUDGET:
                    print("  out of time, the rest go in the next run")
                    for f in futures:
                        f.cancel()
                    break

        # Hashed maps that weren't archived yet get re-checked (cheap HEAD) once a run.
        keys = set("%s|%s" % (m.get("download", ""), m.get("version", "")) for m in maps.values())
        recheck = [k for k in keys if k in hashes and hashes[k].get("sha") and not hashes[k].get("archived")]

        def recheck_one(key):
            return key, get(ARCHIVE % hashes[key]["sha"], 30, "HEAD") == 200

        with cf.ThreadPoolExecutor(12) as pool:
            for k, ok in pool.map(recheck_one, recheck):
                hashes[k]["archived"] = ok
        mirrored = 0
        blocked = 0
        for m in maps.values():
            dl = str(m.get("download", ""))
            if not dl or dl.startswith(CORS_OK):
                continue
            v = hashes.get("%s|%s" % (dl, m.get("version", "")))
            if v and v.get("sha") and v.get("archived"):
                m["download"] = ARCHIVE % v["sha"]
                mirrored += 1
            else:
                m["web_blocked"] = True
                blocked += 1
        print("db%d: %d links moved to rhythia.com, %d not downloadable in browsers" % (idx, mirrored, blocked))
        with open(os.path.join(out, "db%d.json" % idx), "w") as f:
            json.dump(maps, f, separators=(",", ":"))
        status["dbs"].append({"source": url, "ok": True, "maps": len(maps),
                              "mirrored": mirrored, "blocked": blocked})

    with open(hashes_path, "w") as f:
        json.dump(hashes, f, separators=(",", ":"), sort_keys=True)
    with open(os.path.join(out, "status.json"), "w") as f:
        json.dump(status, f, indent=1)


if __name__ == "__main__":
    main()
