#!/usr/bin/env python3
"""Small PixelLab API v2 client used by the art pass (docs/ART_ROADMAP.md, docs/ART_PROMPTS.md).

Auth: the cloud environment's proxy injects the real token for api.pixellab.ai, so the
Authorization header here carries a dummy value. Running this elsewhere needs PIXELLAB_TOKEN.

Every paid call is logged to tools/art_spend.jsonl (one JSON line: time, phase, what, usd,
balance before/after when known), which docs/ART_SPEND.md summarises per phase.

Usage as a library:
    from pixellab import PL
    pl = PL(phase="1")
    cid = pl.create_character("young swordsman ...", size=32, name="Bran A")
    pl.wait_character(cid)
    pl.animate(cid, "swinging a heavy axe", ["south", "east"], frames=6, name="attack")
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.pixellab.ai/v2"
HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "art_spend.jsonl")
DIRS8 = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
DIRS5 = ["south", "south-east", "east", "north-east", "north"]  # the rest are mirrored in game


class PL:
    def __init__(self, phase="?"):
        self.phase = phase
        self.token = os.environ.get("PIXELLAB_TOKEN", "proxy-injected")

    # ------------------------------------------------------------------ http
    def _req(self, method, path, body=None, raw=False, tries=4):
        url = path if path.startswith("http") else API + path
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(tries):
            req = urllib.request.Request(url, data=data, method=method)
            if url.startswith(API):
                req.add_header("Authorization", "Bearer " + self.token)
            if data is not None:
                req.add_header("Content-Type", "application/json")
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    out = r.read()
                    return out if raw else json.loads(out or b"{}")
            except urllib.error.HTTPError as e:
                msg = e.read().decode(errors="replace")
                if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                    time.sleep(4 * (attempt + 1))
                    continue
                raise RuntimeError(f"{method} {path} -> {e.code}: {msg[:800]}")
            except urllib.error.URLError:
                if attempt < tries - 1:
                    time.sleep(4 * (attempt + 1))
                    continue
                raise

    def balance(self):
        return float(self._req("GET", "/balance")["credits"]["usd"])

    def log(self, what, usd, **extra):
        rec = {"t": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "phase": self.phase, "tool": "pixellab",
               "what": what, "usd": round(float(usd or 0), 5)}
        rec.update(extra)
        with open(LEDGER, "a") as f:
            f.write(json.dumps(rec) + "\n")

    # ------------------------------------------------------------------ jobs
    def job(self, job_id):
        return self._req("GET", f"/background-jobs/{job_id}")

    def wait_jobs(self, job_ids, what="job", timeout=900):
        """Polls until every job is done. Returns {job_id: job}. Logs each job's usage."""
        pending = set(job_ids)
        done = {}
        t0 = time.time()
        while pending and time.time() - t0 < timeout:
            for j in list(pending):
                r = self.job(j)
                if r["status"] in ("completed", "failed"):
                    pending.discard(j)
                    done[j] = r
                    usd = (r.get("usage") or {}).get("usd", 0)
                    self.log(what, usd, job=j, status=r["status"])
            if pending:
                time.sleep(6)
        for j in pending:
            done[j] = {"status": "timeout"}
        return done

    # ------------------------------------------------------------ characters
    def create_character(self, description, size=32, name=None, view="high top-down", seed=None,
                         reference_png=None, outline="single color black outline", detail="medium detail"):
        body = {"description": description, "image_size": {"width": size, "height": size}, "view": view,
                "outline": outline, "detail": detail, "no_background": True}
        if name:
            body["name"] = name
        if seed is not None:
            body["seed"] = seed
        if reference_png:
            body["reference_image"] = {"type": "base64", "base64": base64.b64encode(open(reference_png, "rb").read()).decode()}
        r = self._req("POST", "/create-character-v3", body)
        return r["character_id"], r["background_job_id"]

    def character(self, cid):
        return self._req("GET", f"/characters/{cid}")

    def animate(self, cid, action, directions, frames=6, name=None, group=None, keep_first=False, template=None):
        body = {"character_id": cid, "directions": directions}
        if template:
            body.update({"template_animation_id": template, "mode": "template"})
        else:
            body.update({"action_description": action, "mode": "v3", "frame_count": frames,
                         "keep_first_frame": keep_first})
        if name:
            body["animation_name"] = name
        if group:
            body["animation_group_id"] = group
        r = self._req("POST", "/characters/animations", body)
        return r.get("animation_group_id"), r["background_job_ids"]

    def download(self, url, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = self._req("GET", url, raw=True)
        with open(path, "wb") as f:
            f.write(data)
        return path

    def fetch_character(self, cid, out_dir, rename=None, state=None):
        """Downloads a character through the ZIP export (the CDN host is not reachable from the
        cloud sandbox) into out_dir as <dir>.png and <anim>_<dir>_<i>.png. Animation folders are
        named by their display name (lowercased, spaces to _); `rename` maps those to file prefixes."""
        import io
        import re
        import zipfile
        data = self._req("GET", f"/characters/{cid}/zip", raw=True)
        os.makedirs(out_dir, exist_ok=True)
        z = zipfile.ZipFile(io.BytesIO(data))
        for n in z.namelist():
            if not n.endswith(".png"):
                continue
            parts = n.split("/")
            if state and parts[0] != state:
                continue
            if "rotations" in parts:
                dest = f"{parts[-1]}"
            elif "animations" in parts:
                k = parts.index("animations")
                nm = parts[k + 1].lower().replace(" ", "_").replace("-", "_")
                nm = (rename or {}).get(nm, nm)
                d = parts[k + 2]
                i = int(re.search(r"(\d+)", parts[-1]).group(1))
                dest = f"{nm}_{d}_{i}.png"
            else:
                continue
            with open(os.path.join(out_dir, dest), "wb") as f:
                f.write(z.read(n))
        return z.namelist()


# ---------------------------------------------------------------- tiles and props
def create_tileset(pl, lower, upper, transition="", seed=None, size=16, lower_ref=None, **extra):
    body = {"lower_description": lower, "upper_description": upper, "transition_description": transition,
            "tile_size": {"width": size, "height": size}, "view": "high top-down",
            "shading": "basic shading", "detail": "medium detail"}
    if seed is not None:
        body["seed"] = seed
    if lower_ref:
        body["lower_reference_image"] = {"type": "base64", "base64": base64.b64encode(open(lower_ref, "rb").read()).decode()}
    body.update(extra)
    r = pl._req("POST", "/create-tileset", body)
    return r["tileset_id"], r["background_job_id"]


def save_tileset(pl, tileset_id, out_dir):
    """Writes the 16 corner tiles as <NW><NE><SW><SE>.png with L = lower and U = upper terrain."""
    t = pl._req("GET", f"/tilesets/{tileset_id}")["tileset"]
    os.makedirs(out_dir, exist_ok=True)
    keys = []
    for tile in t["tiles"]:
        c = tile.get("corners") or {}
        key = "".join("U" if c.get(k) == "upper" else "L" for k in ("NW", "NE", "SW", "SE"))
        with open(os.path.join(out_dir, key + ".png"), "wb") as f:
            f.write(base64.b64decode(tile["image"]["base64"]))
        keys.append(key)
    return keys


def create_object(pl, description, w, h, **extra):
    body = {"description": description, "image_size": {"width": w, "height": h}, "view": "high top-down",
            "outline": "single color outline", "shading": "medium shading", "detail": "medium detail"}
    body.update(extra)
    r = pl._req("POST", "/map-objects", body)
    return r["object_id"], r["background_job_id"]


def save_object(job, path):
    """A finished map-object job carries its PNG as base64 in last_response.image."""
    img = (job.get("last_response") or {}).get("image")
    if not img:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(base64.b64decode(img))
    return True


# ---------------------------------------------------------------- style-locked images (docs/ART_STYLE.md)
def style_palette():
    return [l.split()[0] for l in open(os.path.join(HERE, "style_palette.hex")) if l.strip() and not l.startswith(";")]


def _ref(path):
    from PIL import Image
    w, h = Image.open(path).size
    return {"image": {"type": "base64", "base64": base64.b64encode(open(path, "rb").read()).decode()}, "size": {"width": w, "height": h}}


def generate_styled(pl, description, size, style_png, refs=(), seed=5):
    """Pro image job anchored to the style target: style_png (a crop in docs/style/) sets the look, the 38-colour
    style palette is enforced, refs (e.g. a building's level 3) guide the subject. Returns the job id; the
    finished job's last_response.images holds several options (9 at 80 px, 25 at 48 px, 64 at 32 px)."""
    body = {"description": description, "image_size": {"width": size[0], "height": size[1]}, "seed": seed,
            "no_background": True, "style_image": _ref(style_png), "style_options": {"color_palette": False},
            "target_palette": {"colors": style_palette()}}
    if refs:
        body["reference_images"] = [_ref(p) for p in refs]
    return pl._req("POST", "/generate-image-v2", body)["background_job_id"]


def save_styled(job, prefix):
    """Writes each option of a finished generate_styled job as <prefix>_<k>.png."""
    out = []
    for k, im in enumerate((job.get("last_response") or {}).get("images") or []):
        data = im["base64"] if isinstance(im, dict) else im
        if data.startswith("data:"):
            data = data.split(",", 1)[1]
        path = f"{prefix}_{k}.png"
        with open(path, "wb") as f:
            f.write(base64.b64decode(data))
        out.append(path)
    return out


def spend_summary():
    """Sum of logged spend per phase."""
    import glob
    tot = {}
    # art_spend.jsonl plus per-thread ledgers (art_spend_<topic>.jsonl), so parallel branches don't edit one file.
    for path in sorted(glob.glob(os.path.join(HERE, "art_spend*.jsonl"))):
        for line in open(path):
            r = json.loads(line)
            key = (r.get("phase"), r.get("tool", "pixellab"))
            tot[key] = tot.get(key, 0) + r.get("usd", 0)
    return tot


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "balance":
        print(PL().balance())
    elif len(sys.argv) > 1 and sys.argv[1] == "spend":
        for (ph, tool), usd in sorted(spend_summary().items()):
            print(f"phase {ph} {tool}: ${usd:.3f}")
    else:
        print(__doc__)
