#!/usr/bin/env python3
import argparse, json, hashlib, time
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from xml.etree import ElementTree as ET

UA = "ai-dev-exp-control/1.0 (+rss collector)"
TIMEOUT = 20

def fetch(url: str) -> bytes:
    req = Request(url, headers={"User-Agent": UA})
    with urlopen(req, timeout=TIMEOUT) as r:
        return r.read()

def sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:16]

def text(el, path, default=""):
    found = el.find(path)
    return (found.text or "").strip() if found is not None else default

def parse_rss(xml_bytes: bytes):
    root = ET.fromstring(xml_bytes)
    channel = root.find("channel")
    if channel is None:
        return []
    items = []
    for item in channel.findall("item"):
        title = text(item, "title")
        link = text(item, "link")
        pub = text(item, "pubDate")
        items.append({"title": title, "url": link, "published_raw": pub})
    return items

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", required=True)
    ap.add_argument("--out-json", required=True)
    ap.add_argument("--out-jsonl", required=True)
    ap.add_argument("--out-md", required=True)
    args = ap.parse_args()

    sources = json.load(open(args.sources, "r", encoding="utf-8"))
    now = datetime.now(timezone.utc).isoformat()

    seen = set()
    normalized = []

    for src in sources:
        try:
            raw = fetch(src["url"])
            items = parse_rss(raw)[:40]
            for it in items:
                url = (it.get("url") or "").strip()
                title = (it.get("title") or "").strip()
                if not url or not title:
                    continue
                key = sha1(url)
                if key in seen:
                    continue
                seen.add(key)

                normalized.append({
                    "id": key,
                    "source": src["name"],
                    "url": url,
                    "title": title,
                    "tags": src.get("tags", []),
                    "weight": float(src.get("weight", 0.5)),
                    "collected_at": now,
                })
        except Exception as e:
            normalized.append({
                "id": sha1(src.get("name","src") + str(time.time())),
                "source": src.get("name","unknown"),
                "url": src.get("url",""),
                "title": f"[collector error] {src.get('name','unknown')}: {e}",
                "tags": ["collector_error"],
                "weight": 0.0,
                "collected_at": now,
            })

    normalized.sort(key=lambda x: (x["weight"], x["collected_at"]), reverse=True)

    json.dump({"generated_at": now, "items": normalized},
              open(args.out_json, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)

    with open(args.out_jsonl, "w", encoding="utf-8") as f:
        for x in normalized:
            f.write(json.dumps(x, ensure_ascii=False) + "\n")

    top = [x for x in normalized if "collector_error" not in (x.get("tags") or [])][:30]
    lines = []
    lines.append(f"# SIGNALS (generated_at: {now})")
    lines.append("")
    lines.append("上位シグナル（暫定: weight順。shortlist注入に使う）")
    lines.append("")
    for x in top:
        lines.append(f"- [{x['source']}] {x['title']} ({x['url']})")
    open(args.out_md, "w", encoding="utf-8").write("\n".join(lines))

if __name__ == "__main__":
    main()
