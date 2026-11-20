#!/usr/bin/env python3
"""Write the generated parts of README.md from the pack's own data (run by tools/gen_readme.sh).

Numbers come from the weapon profiles (cfg/addons/<pack>/weapon/**/<id>.yml, the defaults a server overrides) and,
for anything a profile leaves out, from the Workshop defs (weapons/<id>.tres). Words come from
docs/readme/weapons.yml (class and a short description per weapon). Nothing here is typed by hand twice.

Two regions of README.md are replaced, each between its markers (added if missing):
  <!-- gen_readme:summary -->  ... <!-- /gen_readme:summary -->   the lineup table (thumbnail, name, class, damage, rate)
  <!-- gen_readme:weapons -->  ... <!-- /gen_readme:weapons -->   one section per weapon: hero shot, description, stats
Everything else in README.md (pitch, usage, credits) is left exactly as written.

  tools/gen_readme.py [--check]     --check: exit 1 if README.md is out of date (for CI), write nothing
"""
import glob
import os
import re
import subprocess
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG_DIR = "docs/img"


def raw_base():
    url = subprocess.run(["git", "-C", ROOT, "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+)/(.+?)(?:\.git)?$", url)
    if not m:
        sys.exit("gen_readme: origin %r is not a GitHub remote" % url)
    return "https://raw.githubusercontent.com/%s/%s/main/" % (m.group(1), m.group(2))


# ---- weapons/<id>.tres (Godot text resource) ----

def _value(s):
    s = s.strip()
    m = re.match(r'^&?"(.*)"$', s)
    if m:
        return m.group(1)
    if s in ("true", "false"):
        return s == "true"
    m = re.match(r'^(?:Array\[StringName\]\(\[|PackedStringArray\()(.*?)\]?\)$', s, re.S)
    if m:
        return re.findall(r'"([^"]*)"', m.group(1))
    m = re.match(r'^SubResource\("([^"]+)"\)$', s)
    if m:
        return ("sub", m.group(1))
    try:
        return float(s) if re.search(r"[.eE]", s) else int(s)
    except ValueError:
        return s


def read_tres(path):
    """{'resource': {...}, 'tuning': {...}, 'damage_type': {...}, 'params': {...}} with plain values."""
    sections, cur, name = {}, None, None
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        h = re.match(r"^\[(\w+)(.*)\]$", line)
        if h:
            if h.group(1) == "sub_resource":
                name = re.search(r'id="([^"]+)"', h.group(2)).group(1)
            else:
                name = h.group(1)
            cur = sections.setdefault(name, {})
        elif cur is not None and "=" in line:
            k, v = line.split("=", 1)
            k = k.strip()
            if v.strip() == "{":  # a dictionary over several lines
                body = []
                i += 1
                while i < len(lines) and lines[i].strip() != "}":
                    body.append(lines[i])
                    i += 1
                d = {}
                for b in body:
                    m = re.match(r'^\s*&?"([^"]+)":\s*(.*?),?\s*$', b)
                    if m:
                        d[m.group(1)] = _value(m.group(2))
                cur[k] = d
            else:
                cur[k] = _value(v)
        i += 1
    res = sections.get("resource", {})
    out = {"resource": res, "tuning": {}, "damage_type": {}, "params": res.get("params", {}) or {}}
    t = res.get("tuning")
    if isinstance(t, tuple):
        out["tuning"] = sections.get(t[1], {})
        dt = out["tuning"].get("damage_type")
        if isinstance(dt, tuple):
            out["damage_type"] = sections.get(dt[1], {})
    return out


# ---- the profile (cfg/addons/<pack>/weapon/.../<id>.yml) ----

def find_profile(wid, prefix):
    short = wid[len(prefix):] if prefix and wid.startswith(prefix) else wid
    for name in (wid, short):
        for p in sorted(glob.glob(os.path.join(ROOT, "cfg/addons/*/weapon/**/%s.yml" % name), recursive=True)):
            if "/upgrades/" not in p:
                return p
    return None


def read_profile(path):
    if not path:
        return {}
    doc = yaml.safe_load(open(path, encoding="utf-8")) or {}
    flat = {}
    for k, v in doc.items():
        if k not in ("extra", "menu"):
            flat[k] = v
    extra = doc.get("extra") or {}
    for k, v in extra.items():
        if k != "tuning":
            flat[k] = v
    for k, v in (extra.get("tuning") or {}).items():
        flat.setdefault(k, v)
    flat["_menu"] = doc.get("menu") or {}
    flat["_seconds"] = "Durations are seconds" in open(path, encoding="utf-8").readline()
    return flat


# ---- the stats a reader wants, merged ----

def num(v):
    if isinstance(v, bool) or v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def fmt(v, unit="", digits=2):
    if v is None:
        return None
    s = ("%." + str(digits) + "f") % v
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return s + unit


def stats(wid, prefix):
    d = read_tres(os.path.join(ROOT, "weapons", wid + ".tres"))
    r, t, dt, params = d["resource"], d["tuning"], d["damage_type"], d["params"]
    p = read_profile(find_profile(wid, prefix))
    tick = num(p.get("authored_tick_rate")) or num(r.get("authored_tick_rate")) or 64.0

    def get(*keys):
        for k in keys:
            for src in (p, t, r, params):
                if k in src and num(src[k]) is not None:
                    return num(src[k])
        return None

    def secs(sec_key, tick_key):
        v = num(p.get(sec_key))
        if v is not None:
            return v
        v = get(tick_key)
        return v / tick if v is not None else None

    behaviour = str(r.get("behaviour_path", p.get("behaviour", "")))
    kind = "melee" if "melee" in behaviour else "thrown" if "thrown" in behaviour else \
        "projectile" if "projectile" in behaviour else "hitscan"
    tags = r.get("tags") or p.get("tags") or []
    s = {"id": wid, "name": p.get("name") or r.get("display_name") or wid, "kind": kind, "tags": tags,
         "menu": p.get("_menu", {}), "slot": get("slot")}

    rows = []
    def add(label, value):
        if value not in (None, "", "0"):
            rows.append((label, value))

    dmg = get("damage")
    pellets = get("pellets")
    if kind == "thrown" and not dmg:
        dmg = None
    if dmg:
        dstr = fmt(dmg) + (" x %d pellets" % pellets if pellets and pellets > 1 else "")
        if dt.get("display_name"):
            dstr += " (%s)" % str(dt["display_name"]).lower()
        add("Damage", dstr)
    charged = p.get("fire_mode") == "charge" or "charge" in (r.get("fire_modes") or [])
    if kind != "thrown" and charged and get("min_charge_damage") is not None and get("charge_ticks"):
        add("Uncharged damage", fmt(get("min_charge_damage") * 100, " %", 0))
        add("Full charge", fmt(get("charge_ticks") / tick, " s"))
    sd, sr = get("splash_damage"), get("splash_radius")
    if sd:
        add("Splash", "%s within %s" % (fmt(sd), fmt(sr, " m")))
    rpm = get("rpm")
    if rpm is None:
        ui = get("use_interval_ticks")
        rpm = 60.0 * tick / ui if ui else None
    s["rpm"] = rpm
    s["damage"] = dmg if dmg else sd
    s["pellets"] = pellets
    if rpm:
        add("Swing rate" if kind == "melee" else "Throw rate" if kind == "thrown" else "Fire rate", fmt(rpm, " rpm", 0))
    modes = r.get("fire_modes") or p.get("fire_modes") or []
    if isinstance(p.get("fire_mode"), str) and not modes:
        modes = [p["fire_mode"]]
    if modes:
        add("Fire modes", ", ".join(modes))
    burst = get("burst_count")
    if burst and "burst" in modes:
        add("Burst", "%d rounds" % burst)
    mag, res = get("magazine"), get("reserve")
    if kind == "thrown":
        add("Carried", fmt(res) + (" (max %s)" % fmt(get("reserve_max")) if get("reserve_max") else "") if res else None)
    elif mag:
        add("Magazine", "%s + %s reserve" % (fmt(mag), fmt(res)) if res else fmt(mag))
    reload_s = secs("reload_seconds", "reload_ticks")
    per_round = r.get("reload_per_round") or p.get("reload_per_round")
    if reload_s and kind not in ("melee", "thrown"):
        add("Reload", fmt(reload_s, " s per round" if per_round else " s"))
    if kind == "melee":
        add("Reach", fmt(get("reach", "max_range"), " m"))
        add("Swing arc", fmt(get("arc_degrees"), " deg", 0))
    else:
        sp, mv, cr, air = get("spread"), get("spread_moving"), get("spread_crouched"), get("spread_airborne")
        if sp is not None and kind != "thrown" and (sp or mv):
            parts = ["%s deg standing" % fmt(sp)]
            if mv:
                parts.append("%s moving" % fmt(mv))
            if cr is not None and cr != sp:
                parts.append("%s crouched" % fmt(cr))
            if air:
                parts.append("%s airborne" % fmt(air))
            add("Spread", ", ".join(parts))
        b, bm = get("bloom"), get("bloom_max")
        if b:
            add("Bloom", "+%s deg per shot, up to %s" % (fmt(b), fmt(bm)) if bm else "+%s deg per shot" % fmt(b))
        rp, ry = get("recoil_pitch"), get("recoil_yaw")
        if rp:
            add("Recoil", "%s deg up" % fmt(rp) + (", %s deg side" % fmt(ry) if ry else ""))
        rng = get("max_range")
        if kind == "hitscan" and rng:
            fs, fe, ff = num(dt.get("falloff_start")), num(dt.get("falloff_end")), num(dt.get("falloff_floor"))
            r_s = fmt(rng, " m", 0)
            if fs is not None and fe and fs < rng:
                r_s += " (falloff %s-%s m to %s %%)" % (fmt(fs, "", 0), fmt(min(fe, rng), "", 0), fmt((ff or 0) * 100, "", 0))
            add("Range", r_s)
        if kind in ("projectile", "thrown"):
            add("Projectile speed", fmt(get("speed"), " m/s", 0))
        fuse = num(p.get("fuse_seconds"))
        if fuse is None and get("fuse_ticks"):
            fuse = get("fuse_ticks") / tick
        add("Fuse", fmt(fuse, " s"))
    add("Draw time", fmt(secs("deploy_seconds", "deploy_ticks"), " s"))
    add("Weight", fmt(get("weight"), " kg") if get("weight") else None)
    s["rows"] = rows
    return s


# ---- README ----

QUALITY_HEADING = "## Quality and ongoing improvement"
QUALITY_DEFAULT = (
    "The models, textures, sounds and animations in this pack are being improved over time, and some of them are "
    "low quality today. Improvement is driven by the Nightly queue, a work queue where agents pick up items, and by "
    "a visual judge loop that views rendered frames and files defects until each asset passes repeated clean "
    "reviews. Known defects are filed there and fixed in later releases, and the screenshots in this README are "
    "regenerated as the assets improve."
)


def quality_section(words):
    """The 'Quality and ongoing improvement' section. docs/readme/weapons.yml may override it with a `quality:` key."""
    text = " ".join(str(words.get("quality") or QUALITY_DEFAULT).split())
    return QUALITY_HEADING + "\n\n" + text


def load_words():
    path = os.path.join(ROOT, "docs/readme/weapons.yml")
    return yaml.safe_load(open(path, encoding="utf-8")) if os.path.exists(path) else {}


def anchor(name):
    return re.sub(r"[^a-z0-9 -]", "", name.lower()).replace(" ", "-")


def render(words, base):
    prefix = words.get("id_prefix", "")
    ids = sorted(os.path.basename(f)[:-5] for f in glob.glob(os.path.join(ROOT, "weapons/*.tres")))
    order = words.get("order") or []
    ids = [i for i in order if i in ids] + [i for i in ids if i not in order]
    info = words.get("weapons") or {}
    all_stats = [stats(i, prefix) for i in ids]
    missing = [i for i in ids if not os.path.exists(os.path.join(ROOT, IMG_DIR, i + ".webp"))]
    unexpected = [i for i in missing if i not in (words.get("no_image") or [])]
    if unexpected:
        print("gen_readme: no image yet for %s" % ", ".join(unexpected), file=sys.stderr)

    summary = ["| | Weapon | Class | Damage | Rate |", "| --- | --- | --- | --- | --- |"]
    for s in all_stats:
        w = info.get(s["id"], {})
        cls = w.get("class") or str(s["menu"].get("category", s["kind"])).capitalize()
        d = s["damage"]
        dmg = (fmt(d) + (" x %d" % s["pellets"] if s["pellets"] and s["pellets"] > 1 else "")) if d else "-"
        if s["kind"] == "thrown" and d:
            dmg += " splash"
        rate = fmt(s["rpm"], " rpm", 0) if s["rpm"] else "-"
        thumb = '<a href="#%s"><img src="%s%s/%s_thumb.webp" width="160" alt="%s"></a>' % (
            anchor(s["name"]), base, IMG_DIR, s["id"], s["name"]) if s["id"] not in missing else ""
        summary.append('| %s | [%s](#%s) | %s | %s | %s |' % (thumb, s["name"], anchor(s["name"]), cls, dmg, rate))

    body = []
    for s in all_stats:
        w = info.get(s["id"], {})
        cls = w.get("class") or str(s["menu"].get("category", s["kind"])).capitalize()
        body.append("### %s" % s["name"])
        body.append("")
        if s["id"] not in missing:
            body.append('<img src="%s%s/%s.webp" width="1280" alt="%s, studio render">' % (base, IMG_DIR, s["id"], s["name"]))
            body.append("")
        desc = (w.get("blurb") or "").strip()
        body.append("**%s** `%s`%s" % (cls, s["id"], (". " + desc) if desc else ""))
        body.append("")
        body.append("| Default | |")
        body.append("| --- | --- |")
        for label, value in s["rows"]:
            body.append("| %s | %s |" % (label, value))
        body.append("")
    return "\n".join(summary) + "\n", "\n".join(body)


def splice(text, tag, content, before=None):
    start, end = "<!-- gen_readme:%s -->" % tag, "<!-- /gen_readme:%s -->" % tag
    block = "%s\n%s\n%s" % (start, content.rstrip("\n"), end)
    if start in text and end in text:
        return re.sub(re.escape(start) + r".*?" + re.escape(end), lambda _: block, text, flags=re.S)
    if before and before in text:
        i = text.index(before)
        return text[:i] + block + "\n\n" + text[i:]
    return text.rstrip("\n") + "\n\n" + block + "\n"


def main():
    check = "--check" in sys.argv
    words = load_words()
    base = raw_base()
    summary, body = render(words, base)
    path = os.path.join(ROOT, "README.md")
    old = open(path, encoding="utf-8").read()
    new = splice(old, "summary", summary, before=words.get("summary_before", "## Using it"))
    new = splice(new, "weapons", "## The weapons\n\n" + body, before=words.get("weapons_before", "## Credits"))
    if check and "<!-- gen_readme:quality -->" not in old:
        print("gen_readme: README.md has no '%s' section; run tools/gen_readme.sh --text" % QUALITY_HEADING, file=sys.stderr)
        sys.exit(1)
    new = splice(new, "quality", quality_section(words), before=words.get("quality_before", "## Credits"))
    # Owner rule: no repo-name H1 first line (GitHub already shows the name).
    first = new.split("\n", 1)[0]
    if first.startswith("# "):
        if check:
            print("gen_readme: README.md starts with an H1 (%s); remove it" % first, file=sys.stderr)
            sys.exit(1)
        new = new.split("\n", 1)[1].lstrip("\n")
    if check:
        if new != old:
            print("gen_readme: README.md is out of date; run tools/gen_readme.sh --text", file=sys.stderr)
            sys.exit(1)
        return
    if new != old:
        open(path, "w", encoding="utf-8").write(new)
        print("gen_readme: wrote README.md")
    else:
        print("gen_readme: README.md already up to date")


if __name__ == "__main__":
    main()
