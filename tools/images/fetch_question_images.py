"""Descarcă imagini reale, potrivite cu răspunsul, pentru întrebări.

Strategie per gamemode:
 - pixel (desene/filme): pagina Wikipedia a personajului -> imaginea principală;
 - choice (logo firme): căutare pe Wikimedia Commons "<brand> logo" (SVG-urile
   oficiale sunt randate ca PNG prin thumburl);
 - cave (jocuri): pagina Wikipedia a jocului -> cover art;
 - medical: termenul EN din câmpul "imagine_cautare".

Imaginile sunt normalizate la 800x600 (4:3) pentru încadrare bună pe telefon:
foto = crop central; logo/wordmark = letterbox pe fundal alb.

Rulare:  python tools/images/fetch_question_images.py
Reia de unde a rămas (sare peste fișierele deja descărcate).
"""
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from PIL import Image

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

HEADERS = {"User-Agent": "GuessItQuizApp/1.0 (asset fetch script; educational project)"}
TARGET_W, TARGET_H = 800, 600

# (fisier_json, folder_imagini, strategie) — toate intrebarile din fiecare fisier
SOURCES = [
    ("assets/continut/cartoon/intrebari.json", "assets/continut/cartoon/poze", "character"),
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "logo"),
    ("assets/continut/jocuri/intrebari.json", "assets/continut/jocuri/poze", "game"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "custom"),
    ("assets/continut/mecanica/intrebari.json", "assets/continut/mecanica/poze", "custom"),
    ("assets/continut/aplicatii/intrebari.json", "assets/continut/aplicatii/poze", "logo"),
    ("assets/continut/masini/intrebari.json", "assets/continut/masini/poze", "custom"),
    ("assets/continut/celebritati/intrebari.json", "assets/continut/celebritati/poze", "custom"),
    ("assets/continut/sport/intrebari.json", "assets/continut/sport/poze", "custom"),
    ("assets/continut/romania/intrebari.json", "assets/continut/romania/poze", "custom"),
    ("assets/continut/steaguri/intrebari.json", "assets/continut/steaguri/poze", "custom"),
    ("assets/continut/animale/intrebari.json", "assets/continut/animale/poze", "custom"),
    ("assets/continut/monumente/intrebari.json", "assets/continut/monumente/poze", "custom"),
    ("assets/continut/instrumente/intrebari.json", "assets/continut/instrumente/poze", "custom"),
]

# Cooldown adaptiv intre intrebari: pornim lent ca sa nu atingem limita
# Wikimedia; daca totusi primim 429/503 crestem pauza, iar dupa o serie
# de cereri reusite o scadem treptat inapoi (nu tinem scriptul lent degeaba).
DELAY_START, DELAY_MIN, DELAY_MAX = 3.5, 2.0, 15.0
_delay = DELAY_START
_ok_streak = 0


def _on_rate_limited():
    global _delay, _ok_streak
    _delay = min(_delay * 1.6, DELAY_MAX)
    _ok_streak = 0


def _on_request_ok():
    global _delay, _ok_streak
    _ok_streak += 1
    if _ok_streak >= 30 and _delay > DELAY_MIN:
        _delay = max(_delay * 0.85, DELAY_MIN)
        _ok_streak = 0


def _open_with_backoff(url, timeout):
    """Cerere HTTP cu retry pe 429/503 (rate limit Wikimedia)."""
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            resp = urllib.request.urlopen(req, timeout=timeout)
            _on_request_ok()
            return resp
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < 4:
                retry_after = e.headers.get("Retry-After") if e.headers else None
                try:
                    wait = max(int(retry_after), 10) if retry_after else 20 * (attempt + 1)
                except ValueError:
                    wait = 20 * (attempt + 1)
                _on_rate_limited()
                print(f"    rate limit {e.code}, astept {wait}s (pauza intre intrebari: {_delay:.1f}s)...")
                time.sleep(wait)
                continue
            raise


def api_get(url):
    with _open_with_backoff(url, 25) as r:
        return json.loads(r.read().decode("utf-8"))


def wiki_search_title(query):
    url = ("https://en.wikipedia.org/w/api.php?action=query&list=search&format=json"
           "&srlimit=1&srsearch=" + urllib.parse.quote(query))
    data = api_get(url)
    hits = data.get("query", {}).get("search", [])
    return hits[0]["title"] if hits else None


def wiki_page_image(title):
    url = ("https://en.wikipedia.org/w/api.php?action=query&prop=pageimages&format=json"
           "&piprop=thumbnail&pithumbsize=1000&titles=" + urllib.parse.quote(title))
    data = api_get(url)
    for page in data.get("query", {}).get("pages", {}).values():
        thumb = page.get("thumbnail", {})
        if thumb.get("source"):
            return thumb["source"]
    return None


def commons_search_image(query):
    """Caută fișiere pe Commons; SVG-urile sunt acceptate — thumburl le dă ca PNG."""
    url = ("https://commons.wikimedia.org/w/api.php?action=query&format=json"
           "&generator=search&gsrlimit=5&gsrnamespace=6"
           "&prop=imageinfo&iiprop=url|mime&iiurlwidth=1000"
           "&gsrsearch=" + urllib.parse.quote(query))
    data = api_get(url)
    pages = data.get("query", {}).get("pages", {})
    for page in sorted(pages.values(), key=lambda p: p.get("index", 99)):
        for info in page.get("imageinfo", []):
            mime = info.get("mime", "")
            if mime.startswith("image/"):
                return info.get("thumburl") or info.get("url")
    return None


def download_bytes(url):
    with _open_with_backoff(url, 40) as r:
        return r.read()


def normalize(raw, out_path):
    img = Image.open(io.BytesIO(raw))
    img.load()
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        bg = Image.new("RGB", img.size, (255, 255, 255))
        bg.paste(img, mask=img.split()[-1])
        img = bg
    else:
        img = img.convert("RGB")

    w, h = img.size
    ratio = w / h
    target_ratio = TARGET_W / TARGET_H
    if 0.7 <= ratio <= 2.0:
        if ratio > target_ratio:
            new_w = int(h * target_ratio)
            left = (w - new_w) // 2
            img = img.crop((left, 0, left + new_w, h))
        else:
            new_h = int(w / target_ratio)
            top = (h - new_h) // 2
            img = img.crop((0, top, w, top + new_h))
        img = img.resize((TARGET_W, TARGET_H), Image.LANCZOS)
    else:
        img.thumbnail((TARGET_W - 80, TARGET_H - 80), Image.LANCZOS)
        canvas = Image.new("RGB", (TARGET_W, TARGET_H), (255, 255, 255))
        canvas.paste(img, ((TARGET_W - img.width) // 2, (TARGET_H - img.height) // 2))
        img = canvas

    # Formatul iese din extensia ceruta de apelant. Pozele intrebarilor sunt
    # WebP din 2026-08-02 (erau PNG, adica fara pierderi: 589MB pentru 1297 de
    # imagini, peste limita de 200MB a Google Play) — vezi GameMode.imagePath.
    if out_path.lower().endswith(".webp"):
        img.save(out_path, "WEBP", quality=90, method=6)
    else:
        img.save(out_path, "PNG", optimize=True)


def try_wiki(query, out_path):
    title = wiki_search_title(query)
    if not title:
        return None
    img_url = wiki_page_image(title)
    if not img_url:
        return None
    normalize(download_bytes(img_url), out_path)
    return f"wikipedia:{title}"


def try_commons(query, out_path):
    img_url = commons_search_image(query)
    if not img_url:
        return None
    normalize(download_bytes(img_url), out_path)
    return f"commons:{query}"


def fetch_one(answer, strategy, custom_query, out_path):
    name = answer.title()
    if strategy == "character":
        attempts = [("wiki", name), ("wiki", name + " character"), ("commons", name + " character")]
    elif strategy == "logo":
        # aplicatii/logouri au termen custom in "imagine_cautare" (ex: "Gmail app logo")
        attempts = [("commons", custom_query or (name + " logo")), ("commons", name + " logo"),
                    ("commons", name + " wordmark"), ("wiki", name)]
    elif strategy == "game":
        attempts = [("wiki", name + " video game"), ("wiki", name), ("commons", name + " video game")]
    else:  # custom — termen de căutare din "imagine_cautare" (medical, mecanica, premium)
        q = custom_query or name
        attempts = [("wiki", q), ("commons", q), ("wiki", name)]

    for kind, query in attempts:
        try:
            src = try_wiki(query, out_path) if kind == "wiki" else try_commons(query, out_path)
            if src:
                return src
        except Exception as e:
            print(f"    {kind} fail ({query}): {e}")
    return None


def main():
    ok, fail = 0, 0
    failures = []
    for json_path, img_dir, strategy in SOURCES:
        with open(json_path, encoding="utf-8") as f:
            data = json.load(f)
        for cat in data["categorii"].values():
            for item in cat["intrebari"]:
                qid, answer = item["id"], item["raspuns"]
                out_path = os.path.join(img_dir, f"{qid}.webp")
                if os.path.exists(out_path):
                    ok += 1
                    continue
                custom = item.get("imagine_cautare")
                src = fetch_one(answer, strategy, custom, out_path)
                if src:
                    ok += 1
                    print(f"[OK] {qid} ({answer}) <- {src}")
                else:
                    fail += 1
                    failures.append((qid, answer))
                    print(f"[--] {qid} ({answer}) FARA IMAGINE")
                time.sleep(_delay)

    print(f"\nGata: {ok} descarcate/existente, {fail} esuate")
    if failures:
        print("Esuate:")
        for qid, answer in failures:
            print(f"  {qid}: {answer}")


if __name__ == "__main__":
    main()
