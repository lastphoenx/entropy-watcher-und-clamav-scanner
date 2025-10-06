#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
safe_backup.py – Borg-Backup nur, wenn EntropyWatcher "grün" ist".
- Lädt optional .env Dateien (z.B. /opt/entropywatcher/common.env)
- Preflight aus EntropyWatcher-DB (flagged, AV-Events 24h, Scan-Alter, Missing)
- Automatik-Entscheid: full / partial / abort (via Thresholds)
- Partial: Exclude-Datei aus DB (flagged + quarantined)
- Borg create --stats; Stats geparst (Added/Changed/Total, Größen, Dauer)
- Persistenz: backup_runs Tabelle (inkl. Kennzahlen + full JSON)
- Click-CLI: write-schema, preflight, run, report-last
"""

import os, sys, json, re, shlex, subprocess, logging, datetime
from typing import Optional, Tuple, List, Dict, Any, Iterable
import click
import mysql.connector as mariadb
import re as _re

try:
    from dotenv import dotenv_values
except Exception:
    dotenv_values = None  # optional

LOG = logging.getLogger("safe_backup")

# --- Logging Label Helper (fügt [label] in jede Logzeile ein) ---
def _install_label_filter(label: str = "") -> None:
    lbl = (label or os.environ.get("SOURCE_LABEL") or "safe-backup")
    class _LabelFilter(logging.Filter):
        def __init__(self, lbl):
            super().__init__()
            self._lbl = lbl
        def filter(self, record):
            if not hasattr(record, "source_label"):
                record.source_label = self._lbl
            return True

    root = logging.getLogger()
    f = _LabelFilter(lbl)
    # Filter am Root-Logger und an allen vorhandenen Handlern registrieren
    root.addFilter(f)
    for h in root.handlers:
        try:
            h.addFilter(f)
        except Exception:
            pass

# ---------- ENV-Loader (optional) ----------

def _load_env_chain(paths: List[str], override: bool) -> None:
    """Lädt .env Dateien; override=True überschreibt vorhandene Variablen."""
    if not dotenv_values:
        return
    for p in paths:
        p = (p or "").strip()
        if not p or not os.path.exists(p):
            continue
        vals = dotenv_values(p)
        for k, v in (vals or {}).items():
            if v is None:
                continue
            if override or (k not in os.environ):
                os.environ[k] = str(v)

# ---------- Helpers ----------

def now_utc() -> datetime.datetime:
    return datetime.datetime.utcnow().replace(microsecond=0)

def _b2txt(v) -> str:
    if isinstance(v, (bytes, bytearray)):
        return v.decode("utf-8", errors="replace")
    return str(v) if v is not None else ""

def _norm_paths(items: Iterable[str]) -> List[str]:
    seen = set(); out: List[str] = []
    for s in items:
        s = (s or "").strip()
        if not s: continue
        try:
            n = os.path.normpath(s)
        except Exception:
            n = s
        if n not in seen:
            seen.add(n); out.append(n)
    return out

# ---------- DB ----------

def db_conn_from_env():
    return mariadb.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", 3306)),
        database=os.environ.get("DB_NAME", "entropywatcher"),
        user=os.environ.get("DB_USER", "entropyuser"),
        password=os.environ.get("DB_PASS", ""),
        autocommit=False,
    )

def _require_db_conn():
    try:
        return db_conn_from_env()
    except Exception as e:
        LOG.error("DB-Verbindung fehlgeschlagen: %s", e)
        sys.exit(2)

# ---------- Schema (backup_runs) ----------

_BACKUP_SCHEMA_CREATE = """
CREATE TABLE IF NOT EXISTS backup_runs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  started_at DATETIME NOT NULL,
  finished_at DATETIME NULL,
  source VARCHAR(32) NULL,
  mode ENUM('full','partial','abort') NOT NULL,
  policy_reason TEXT NULL,
  repo TEXT NULL,
  archive TEXT NULL,
  status ENUM('success','warning','failed','aborted') NOT NULL,
  rc INT NOT NULL,
  files_added INT NULL,
  files_changed INT NULL,
  files_total INT NULL,
  size_original_bytes BIGINT NULL,
  size_compressed_bytes BIGINT NULL,
  size_dedup_bytes BIGINT NULL,
  duration_seconds INT NULL,
  stats_json JSON NULL,
  note TEXT NULL,
  KEY (source, started_at),
  KEY (status, finished_at)
) ENGINE=InnoDB;
"""

# Falls Tabelle existiert, fehlende Spalten nachziehen (MariaDB: IF NOT EXISTS ist ok)
_BACKUP_SCHEMA_ALTERS = [
    "ALTER TABLE backup_runs MODIFY COLUMN status ENUM('success','warning','failed','aborted') NOT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS files_added INT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS files_changed INT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS files_total INT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS size_original_bytes BIGINT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS size_compressed_bytes BIGINT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS size_dedup_bytes BIGINT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS duration_seconds INT NULL",
    "ALTER TABLE backup_runs ADD COLUMN IF NOT EXISTS stats_json JSON NULL",
]

def ensure_backup_schema(conn) -> None:
    cur = conn.cursor()
    for stmt in [s.strip() for s in _BACKUP_SCHEMA_CREATE.split(";") if s.strip()]:
        cur.execute(stmt)
    for stmt in _BACKUP_SCHEMA_ALTERS:
        try:
            cur.execute(stmt)
        except Exception:
            pass
    conn.commit()
    cur.close()

def write_backup_run(conn,
                     started_at: datetime.datetime,
                     finished_at: Optional[datetime.datetime],
                     source: Optional[str],
                     mode: str,
                     policy_reason: str,
                     repo: Optional[str],
                     archive: Optional[str],
                     status: str,
                     rc: int,
                     files_added: Optional[int],
                     files_changed: Optional[int],
                     files_total: Optional[int],
                     size_original: Optional[int],
                     size_compressed: Optional[int],
                     size_dedup: Optional[int],
                     duration_sec: Optional[int],
                     stats: Optional[dict],
                     note: Optional[str]) -> None:
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO backup_runs
          (started_at, finished_at, source, mode, policy_reason, repo, archive,
           status, rc,
           files_added, files_changed, files_total,
           size_original_bytes, size_compressed_bytes, size_dedup_bytes, duration_seconds,
           stats_json, note)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
    """, (
        started_at, finished_at, (source or None), mode, policy_reason, repo, archive,
        status, int(rc),
        files_added, files_changed, files_total,
        size_original, size_compressed, size_dedup, duration_sec,
        (json.dumps(stats, ensure_ascii=False) if stats else None),
        note
    ))
    conn.commit()
    cur.close()

# ---------- Preflight / Policy ----------

def preflight_status(conn, source: Optional[str], max_age_min: int) -> Dict[str, Any]:
    cur = conn.cursor()
    params = []; src_clause = ""
    if source:
        src_clause = "AND source=%s"; params.append(source)

    cur.execute(f"SELECT COUNT(*) FROM files WHERE flagged=1 {src_clause}", tuple(params))
    flagged = int(cur.fetchone()[0] or 0)

    cur.execute(f"SELECT MAX(last_time) FROM files WHERE 1=1 {src_clause}", tuple(params))
    last_time = cur.fetchone()[0]

    cur.execute(f"SELECT COUNT(*) FROM files WHERE missing_since IS NOT NULL {src_clause}", tuple(params))
    missing = int(cur.fetchone()[0] or 0)

    # AV-Events in den letzten 24h (konservativ)
    if source:
        cur.execute("""
            SELECT COUNT(*) FROM av_events
            WHERE source=%s AND detected_at >= UTC_TIMESTAMP() - INTERVAL 24 HOUR
        """, (source,))
    else:
        cur.execute("""
            SELECT COUNT(*) FROM av_events
            WHERE detected_at >= UTC_TIMESTAMP() - INTERVAL 24 HOUR
        """)
    av_24h = int(cur.fetchone()[0] or 0)

    cur.close()

    too_old = (last_time is None) or ((now_utc() - last_time).total_seconds() > max_age_min * 60)
    return {
        "flagged": flagged,
        "missing": missing,
        "av_24h": av_24h,
        "last_time": last_time,
        "scan_too_old": bool(too_old),
        "max_age_min": max_age_min,
    }

def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)).strip())
    except Exception:
        return default

def decide_action(pf: Dict[str, Any], decision: str) -> Tuple[str, str]:
    """
    decision = 'auto' | 'full' | 'partial' | 'abort'
    ENV-Thresholds (in common.env einstellbar):
      BACKUP_ABORT_FLAGGED_THRESHOLD   (default 5)
      BACKUP_ABORT_AV24H_THRESHOLD     (default 5)
      BACKUP_PARTIAL_ON_MISSING        (default 1: ja)
      BACKUP_MAX_AGE_MIN               (default 30)  -> scan_too_old wenn überschritten
    Logik (auto):
      - wenn flagged >= ABORT_FLAGGED_THRESHOLD oder av_24h >= ABORT_AV24H_THRESHOLD → ABORT
      - sonst wenn flagged>0 oder av_24h>0 → PARTIAL
      - sonst wenn scan_too_old → PARTIAL
      - sonst wenn (MISSING>0 und PARTIAL_ON_MISSING=1) → PARTIAL
      - sonst → FULL
    """
    if decision in ("full", "partial", "abort"):
        rs = []
        if pf["flagged"]>0: rs.append(f"flagged={pf['flagged']}")
        if pf["av_24h"]>0:  rs.append(f"av_24h={pf['av_24h']}")
        if pf["scan_too_old"]: rs.append(f"scan_too_old(max {pf['max_age_min']}m)")
        if pf["missing"]>0: rs.append(f"missing={pf['missing']}")
        return decision, ("forced:" + ",".join(rs) if rs else "forced:ok")

    abort_flagged = _env_int("BACKUP_ABORT_FLAGGED_THRESHOLD", 5)
    abort_av      = _env_int("BACKUP_ABORT_AV24H_THRESHOLD", 5)
    partial_on_missing = _env_int("BACKUP_PARTIAL_ON_MISSING", 1) != 0

    reasons = []
    if pf["flagged"] >= abort_flagged:
        return "abort", f"critical:flagged>={abort_flagged} ({pf['flagged']})"
    if pf["av_24h"] >= abort_av:
        return "abort", f"critical:av_24h>={abort_av} ({pf['av_24h']})"

    if pf["flagged"] > 0 or pf["av_24h"] > 0:
        if pf["flagged"] > 0: reasons.append(f"flagged={pf['flagged']}")
        if pf["av_24h"] > 0: reasons.append(f"av_24h={pf['av_24h']}")
        return "partial", "alerts:" + ",".join(reasons)

    if pf["scan_too_old"]:
        return "partial", f"stale-scan:max{pf['max_age_min']}m"

    if partial_on_missing and pf["missing"] > 0:
        return "partial", f"missing={pf['missing']}"

    return "full", "ok"

# ---------- Exclude-Datei ----------

def build_exclude_file(conn, source: Optional[str], out_path: str) -> Tuple[int, int, int]:
    cur = conn.cursor()
    params = []; src_clause = ""
    if source:
        src_clause = "AND source=%s"; params.append(source)

    cur.execute(f"SELECT path FROM files WHERE flagged=1 {src_clause}", tuple(params))
    flagged = [_b2txt(r[0]) for r in cur.fetchall()]

    if source:
        cur.execute("""
            SELECT quarantine_path FROM av_events
            WHERE action='quarantine' AND source=%s AND quarantine_path IS NOT NULL
        """, (source,))
    else:
        cur.execute("""
            SELECT quarantine_path FROM av_events
            WHERE action='quarantine' AND quarantine_path IS NOT NULL
        """)
    quar = [_b2txt(x[0]) for x in cur.fetchall() if x[0]]
    cur.close()

    lines = _norm_paths(flagged) + _norm_paths(quar)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        for p in lines:
            f.write(p + "\n")

    return len(flagged), len(quar), len(lines)


# ---------- Scan-Summary Helper & State ----------

def get_last_summary(conn, source: Optional[str]) -> Optional[Dict[str, Any]]:
    """
    Liefert die letzte scan_summary-Zeile für source (oder gesamt).
    Rückgabe: dict mit keys: id, finished_at, source, scan_paths
    """
    cur = conn.cursor(dictionary=True)
    if source:
        cur.execute("""
            SELECT id, finished_at, source, scan_paths
            FROM scan_summary
            WHERE source=%s
            ORDER BY finished_at DESC
            LIMIT 1
        """, (source,))
    else:
        cur.execute("""
            SELECT id, finished_at, source, scan_paths
            FROM scan_summary
            ORDER BY finished_at DESC
            LIMIT 1
        """)
    row = cur.fetchone()
    cur.close()
    return row

def _state_path() -> str:
    return os.environ.get("BACKUP_STATE_FILE", "/var/lib/entropywatcher/safe_backup_state.json")

def _read_state() -> Dict[str, Any]:
    p = _state_path()
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def _write_state(d: Dict[str, Any]) -> None:
    p = _state_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2, default=str)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, p)



# ---------- Borg parse/exec ----------

_SIZE_RE = re.compile(r"([0-9]*\.?[0-9]+)\s*(B|kB|MB|GB|TB)", re.I)

def _size_to_bytes(s: str) -> Optional[int]:
    m = _SIZE_RE.search(s or "")
    if not m:
        return None
    val = float(m.group(1))
    unit = m.group(2).upper()
    mul = {"B":1, "KB":1000, "MB":1000**2, "GB":1000**3, "TB":1000**4}[unit]
    return int(val * mul)

def parse_borg_stats(output: str) -> Dict[str, Any]:
    """
    Versucht generisch --stats zu parsen. Unterstützt u.a.:
      Duration: 12.34 seconds
      Number of files: 12345
      Added files: 12
      Changed files: 3
      This archive: Original size, Compressed size, Deduplicated size
    """
    data: Dict[str, Any] = {"raw": output}
    # einfache Key:Value
    kv = {}
    for line in (output or "").splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            kv[k.strip().lower()] = v.strip()
    data["kv"] = kv

    # files
    def _to_int(x):
        try: return int(re.sub(r"[^\d]", "", x))
        except: return None

    data["files_total"]   = _to_int(kv.get("number of files", ""))
    data["files_added"]   = _to_int(kv.get("added files", ""))
    data["files_changed"] = _to_int(kv.get("changed files", ""))

    # Dauer
    dur = kv.get("duration", "")
    if dur.lower().endswith("seconds"):
        try:
            data["duration_seconds"] = int(float(dur.split()[0]))
        except: pass

    # "This archive:" – folgende Zeile mit 3 Spalten Größen
    lines = output.splitlines()
    for i, ln in enumerate(lines):
        if ln.strip().lower().startswith("this archive"):
            # nächste Zeile enthält üblicherweise drei Größen
            if i+1 < len(lines):
                nxt = lines[i+1]
                sizes = re.findall(_SIZE_RE, nxt)
                if len(sizes) >= 3:
                    o = _size_to_bytes("".join(sizes[0]))
                    c = _size_to_bytes("".join(sizes[1]))
                    d = _size_to_bytes("".join(sizes[2]))
                    data["size_original_bytes"]  = o
                    data["size_compressed_bytes"]= c
                    data["size_dedup_bytes"]     = d
            break
    # Fallback: einzelne Keys
    if "original size" in kv:
        data["size_original_bytes"] = _size_to_bytes(kv["original size"])
    if "compressed size" in kv:
        data["size_compressed_bytes"] = _size_to_bytes(kv["compressed size"])
    if "deduplicated size" in kv:
        data["size_dedup_bytes"] = _size_to_bytes(kv["deduplicated size"])

    return data

# ---- Borg-Resultat-Klassifizierung (Warnungen vs. harte Fehler) ----
_WARNING_PATTERNS = [
    re.compile(r"File changed while reading", re.I),
    re.compile(r"Permission denied", re.I),
    re.compile(r"No such file or directory", re.I),
    re.compile(r"Input/output error", re.I),
    re.compile(r"\b(socket|fifo|device):\b", re.I),
    re.compile(r"dangling symlink", re.I),
]

_ERROR_PATTERNS = [
    re.compile(r"Repository.*is locked", re.I),
    re.compile(r"Cache is locked", re.I),
    re.compile(r"Invalid repository", re.I),
    re.compile(r"Object with key .* not found", re.I),
    re.compile(r"Segment checksum mismatch", re.I),
    re.compile(r"No space left on device", re.I),
    re.compile(r"Connection refused", re.I),
    re.compile(r"name resolution", re.I),
    re.compile(r"Passphrase", re.I),
    re.compile(r"encryption key", re.I),
]

def classify_borg_result(output: str, rc: int) -> tuple[str, str]:
    """
    Rückgabe: (status, note)  mit status in {"success","warning","failed"}.
    """
    out = output or ""
    if any(p.search(out) for p in _ERROR_PATTERNS):
        return "failed", "hard-error:repo/infrastructure"
    if rc == 0:
        return "success", "ok"
    if rc == 1:
        warns = [p.pattern for p in _WARNING_PATTERNS if p.search(out)]
        if warns:
            return "warning", "soft-warnings:" + ",".join(warns[:5])
        return "warning", "rc=1"
    return "failed", f"rc={rc}"


def run_borg(borg_repo: str, borg_passphrase: Optional[str],
             archive_name: str, sources: List[str],
             exclude_file: Optional[str], compression: str,
             extra_args: str, dry_run: bool) -> Tuple[int, str]:
    env = os.environ.copy()
    env["BORG_REPO"] = borg_repo
    if borg_passphrase:
        env["BORG_PASSPHRASE"] = borg_passphrase

    cmd = ["borg", "create", "--stats", f"--compression={compression}"]
    if exclude_file and os.path.exists(exclude_file):
        cmd += ["--exclude-from", exclude_file]
    if extra_args:
        cmd += shlex.split(extra_args)
    cmd += [f"::{archive_name}"]
    cmd += sources

    LOG.info("Borg: %s", " ".join(shlex.quote(x) for x in cmd))
    if dry_run:
        LOG.info("Dry-run: borg wird nicht ausgeführt.")
        return 0, ""

    p = subprocess.run(cmd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, (p.stdout or "")

# ---------- Click CLI ----------

@click.group(context_settings=dict(help_option_names=["-h","--help"], max_content_width=100))
@click.option("--env", "env_files", multiple=True,
              help="Zusätzliche .env Dateien (z.B. /opt/entropywatcher/common.env, /opt/entropywatcher/os.env)")
@click.pass_context
def cli(ctx, env_files):
    """
    safe_backup – Borg-Backup mit EntropyWatcher-Preflight.
    Beispiele:
      safe_backup.py write-schema
      safe_backup.py preflight --source os
      safe_backup.py run --source os --borg-repo /mnt/backup/borg --sources "/usr/local,/opt" --decide auto
      safe_backup.py report-last --source os --limit 5
    """
    # .env zuerst laden (damit SOURCE_LABEL & Co. schon da sind)
    if env_files:
        # wie beim Watcher: common zuerst, weitere danach (dürfen überschreiben)
        _load_env_chain(list(env_files), override=True)

    # Logging-Format MIT Label [%(source_label)s]
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(source_label)s] %(message)s"
    )

    # Label-Filter installieren (nimmt jetzt SOURCE_LABEL aus ENV – bereits geladen)
    _install_label_filter()

@cli.command("write-schema")

def write_schema():
    """Legt/aktualisiert die Tabelle backup_runs."""
    conn = _require_db_conn()
    ensure_backup_schema(conn)
    conn.close()
    click.echo("OK: backup_runs Schema vorhanden/aktualisiert.")

@cli.command("preflight")
@click.option("--source", default="", help="files.source / SOURCE_LABEL (z.B. os, nas)")
@click.option("--max-age-min", type=int, default=lambda: int(os.environ.get("BACKUP_MAX_AGE_MIN", 30)))
@click.option("--decide", type=click.Choice(["auto","full","partial","abort"]), default="auto",
              help="Modus erzwingen oder automatisch bestimmen")
def preflight_cmd(source, max_age_min, decide):
    """Zeigt Preflight-Status und die abgeleitete Aktion (full/partial/abort)."""
    _install_label_filter(f"backup-{source or 'all'}")
    conn = _require_db_conn()
    pf = preflight_status(conn, (source or None), int(max_age_min))
    mode, reason = decide_action(pf, decide)
    conn.close()
    click.echo(json.dumps({"preflight": pf, "mode": mode, "reason": reason}, default=str, indent=2, ensure_ascii=False))

@cli.command("run")
@click.option("--source", default="", help="files.source / SOURCE_LABEL (z.B. os, nas)")
@click.option("--max-age-min", type=int, default=lambda: int(os.environ.get("BACKUP_MAX_AGE_MIN", 30)))
@click.option("--decide", type=click.Choice(["auto","full","partial","abort"]), default="auto",
              help="Modus erzwingen oder automatisch bestimmen")
@click.option("--borg-repo", required=True, help="Borg-Repo (z.B. /mnt/backup/borg)")
@click.option("--borg-passphrase", default=lambda: os.environ.get("BORG_PASSPHRASE", ""))
@click.option("--archive", default="{source}-{now:%Y-%m-%d_%H-%M}", help="Archivname-Template")
@click.option("--sources", required=True, help="Kommagetrennte Quellpfade")
@click.option("--exclude-file", default="/opt/entropywatcher/excludes_borg.txt")
@click.option("--compression", default="lz4")
@click.option("--extra-args", default="", help="Zusätzliche Borg-Args (z.B. --one-file-system)")
@click.option("--dry-run", is_flag=True, help="Nur so tun als ob")
@click.option("--note", default="", help="Freitext-Notiz")
def run_cmd(source, max_age_min, decide, borg_repo, borg_passphrase,
            archive, sources, exclude_file, compression, extra_args, dry_run, note):
    """Backup ausführen & in backup_runs protokollieren – inkl. Zähler/Größen/Dauer."""
    _install_label_filter(f"backup-{source or 'all'}")
    started_at = now_utc()
    conn = _require_db_conn()
    ensure_backup_schema(conn)

    try:
        pf = preflight_status(conn, (source or None), int(max_age_min))
        mode, reason = decide_action(pf, decide)

        now_s = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M")
        archive_name = archive.replace("{now:%Y-%m-%d_%H-%M}", now_s).replace("{source}", (source or "all"))

        # abort → nur DB protokollieren
        if mode == "abort":
            write_backup_run(conn,
                             started_at=started_at,
                             finished_at=now_utc(),
                             source=(source or None),
                             mode=mode,
                             policy_reason=reason,
                             repo=borg_repo,
                             archive=archive_name,
                             status="aborted",
                             rc=0,
                             files_added=None, files_changed=None, files_total=None,
                             size_original=None, size_compressed=None, size_dedup=None,
                             duration_sec=None,
                             stats=None,
                             note=(note or ""))
            click.echo(f"ABORT: {reason}")
            return

        # partial → Exclude-Datei erstellen
        exclude_ready = None
        if mode == "partial":
            flagged_n, quar_n, uniq_n = build_exclude_file(conn, (source or None), exclude_file)
            note = (note + f" partial_excludes(flagged={flagged_n}, quarantined={quar_n}, unique={uniq_n})").strip()
            exclude_ready = exclude_file

        srcs = [s.strip() for s in (sources or "").split(",") if s.strip()]
        rc, out = run_borg(
            borg_repo=borg_repo,
            borg_passphrase=(borg_passphrase or None),
            archive_name=archive_name,
            sources=srcs,
            exclude_file=exclude_ready,
            compression=compression,
            extra_args=extra_args,
            dry_run=dry_run
        )
        
        stats = parse_borg_stats(out)
        # Status & Notiz anhand RC + Output klassifizieren
        status, note2 = classify_borg_result(out, rc)
        note = (note + (" " + note2 if note2 else "")).strip()

        files_added   = stats.get("files_added")
        files_changed = stats.get("files_changed")
        files_total   = stats.get("files_total")
        size_original = stats.get("size_original_bytes")
        size_compr    = stats.get("size_compressed_bytes")
        size_dedup    = stats.get("size_dedup_bytes")
        duration_sec  = stats.get("duration_seconds")

        write_backup_run(conn,
                         started_at=started_at,
                         finished_at=now_utc(),
                         source=(source or None),
                         mode=mode,
                         policy_reason=reason,
                         repo=borg_repo,
                         archive=archive_name,
                         status=status,
                         rc=rc,
                         files_added=files_added,
                         files_changed=files_changed,
                         files_total=files_total,
                         size_original=size_original,
                         size_compressed=size_compr,
                         size_dedup=size_dedup,
                         duration_sec=duration_sec,
                         stats=stats,
                         note=note)

        click.echo(json.dumps({
            "mode": mode, "reason": reason, "status": status, "rc": rc,
            "archive": archive_name, "repo": borg_repo, "stats": stats
        }, indent=2, ensure_ascii=False))

    finally:
        conn.close()

@cli.command("run-if-fresh")
@click.option("--source", default="", help="scan_summary.source (z.B. os, nas). Leer = alle")
@click.option("--freshness-sec", type=int, default=600, help="Wie frisch muss die letzte Summary sein (Sekunden)?")
@click.option("--cooldown-sec", type=int, default=1800, help="Mindestabstand zwischen Backups pro Quelle (Sekunden)")
@click.option("--decide", type=click.Choice(["auto","full","partial","abort"]), default="auto")
@click.option("--borg-repo", required=True)
@click.option("--borg-passphrase", default=lambda: os.environ.get("BORG_PASSPHRASE", ""))
@click.option("--archive", default="{source}-{now:%Y-%m-%d_%H-%M}")
@click.option("--sources", default="", help="Kommagetrennt; leer = scan_paths aus summary verwenden")
@click.option("--exclude-file", default="/opt/entropywatcher/excludes_borg.txt")
@click.option("--compression", default="lz4")
@click.option("--extra-args", default="")
@click.option("--dry-run", is_flag=True)
@click.option("--note", default="")
def run_if_fresh(source, freshness_sec, cooldown_sec, decide,
                 borg_repo, borg_passphrase, archive, sources,
                 exclude_file, compression, extra_args, dry_run, note):
    """
    Startet ein Backup, wenn eine neue scan_summary (frisch) vorhanden ist und
    noch kein Backup für diese Summary/Quelle gelaufen ist. Sonst beendet sich der Befehl still.
    """
    _install_label_filter(f"backup-{source or 'all'}")
    conn = _require_db_conn()
    try:
        src = (source or None)
        last = get_last_summary(conn, src)
        if not last:
            LOG.info("Keine scan_summary gefunden (source=%s) – nichts zu tun.", src)
            return

        # Freshness prüfen
        finished = last["finished_at"]
        if not finished:
            LOG.info("Letzte summary ohne finished_at – nichts zu tun.")
            return
        age_sec = int((now_utc() - finished).total_seconds())
        if age_sec > int(freshness_sec):
            LOG.info("Summary zu alt (%ss > %ss) – nichts zu tun.", age_sec, freshness_sec)
            return

        # State prüfen (nicht doppelt)
        st = _read_state()
        key = f"{last.get('source') or 'all'}"
        src_state = st.get(key, {})
        last_id_processed = src_state.get("last_summary_id")
        last_backup_at = src_state.get("last_backup_at")

        if last_id_processed == last["id"]:
            LOG.info("Letzte summary (id=%s) bereits verarbeitet – nichts zu tun.", last["id"])
            return

        if last_backup_at:
            try:
                last_ts = datetime.datetime.fromisoformat(last_backup_at)
                if (now_utc() - last_ts).total_seconds() < int(cooldown_sec):
                    LOG.info("Cooldown aktiv (%ss) – nichts zu tun.", cooldown_sec)
                    return
            except Exception:
                pass

        # Quellen bestimmen: CLI > summary.scan_paths
        if sources.strip():
            srcs = [s.strip() for s in sources.split(",") if s.strip()]
        else:
            sp = (last.get("scan_paths") or "").strip()
            if not sp:
                LOG.warning("Weder --sources noch summary.scan_paths vorhanden – breche ab.")
                return
            srcs = [s.strip() for s in sp.split(",") if s.strip()]
            sources = ",".join(srcs)  # für Übergabe

        # Preflight kurz anzeigen (nice to have)
        pf = preflight_status(conn, src, _env_int("BACKUP_MAX_AGE_MIN", 30))
        mode, reason = decide_action(pf, decide)
        click.echo(json.dumps({"preflight": pf, "mode": mode, "reason": reason,
                               "summary_id": last["id"], "summary_finished_at": finished},
                              default=str, indent=2, ensure_ascii=False))

    finally:
        conn.close()

    # Backup ausführen (bestehende run_cmd wiederverwenden)
    ctx = click.get_current_context()
    ctx.invoke(run_cmd, source=(source or (last.get("source") or "")),
               max_age_min=_env_int("BACKUP_MAX_AGE_MIN", 30), decide=decide,
               borg_repo=borg_repo, borg_passphrase=borg_passphrase,
               archive=archive, sources=sources, exclude_file=exclude_file,
               compression=compression, extra_args=extra_args,
               dry_run=dry_run, note=note)

    # State aktualisieren
    st = _read_state()
    key = f"{last.get('source') or 'all'}"
    st[key] = {
        "last_summary_id": last["id"],
        "last_backup_at": now_utc().isoformat(sep=" "),
    }
    _write_state(st)


@cli.command("preflight-and-run")
@click.option("--source", default="", help="files.source / SOURCE_LABEL (z.B. os, nas)")
@click.option("--max-age-min", type=int, default=lambda: int(os.environ.get("BACKUP_MAX_AGE_MIN", 30)))
@click.option("--decide", type=click.Choice(["auto","full","partial","abort"]), default="auto")
@click.option("--borg-repo", required=True)
@click.option("--borg-passphrase", default=lambda: os.environ.get("BORG_PASSPHRASE", ""))
@click.option("--archive", default="{source}-{now:%Y-%m-%d_%H-%M}")
@click.option("--sources", required=True)
@click.option("--exclude-file", default="/opt/entropywatcher/excludes_borg.txt")
@click.option("--compression", default="lz4")
@click.option("--extra-args", default="")
@click.option("--dry-run", is_flag=True)
@click.option("--note", default="")
def preflight_and_run(source, max_age_min, decide, borg_repo, borg_passphrase,
                      archive, sources, exclude_file, compression, extra_args, dry_run, note):
    """Preflight anzeigen und direkt Backup ausführen."""
    _install_label_filter(f"backup-{source or 'all'}")
    conn = _require_db_conn()
    try:
        pf = preflight_status(conn, (source or None), int(max_age_min))
        mode, reason = decide_action(pf, decide)
        click.echo(json.dumps({"preflight": pf, "mode": mode, "reason": reason},
                              default=str, indent=2, ensure_ascii=False))
    finally:
        conn.close()
    # anschließend vorhandenen run_cmd mit identischen Parametern aufrufen
    ctx = click.get_current_context()
    ctx.invoke(run_cmd, source=source, max_age_min=max_age_min, decide=decide,
               borg_repo=borg_repo, borg_passphrase=borg_passphrase,
               archive=archive, sources=sources, exclude_file=exclude_file,
               compression=compression, extra_args=extra_args,
               dry_run=dry_run, note=note)


@cli.command("report-last")
@click.option("--source", default="", help="Filter nach Quelle (os|nas|…); leer = alle")
@click.option("--limit", type=int, default=10)
def report_last_cmd(source, limit):
    """Zeigt die letzten Backup-Runs (kompakt)."""
    conn = _require_db_conn()
    cur = conn.cursor(dictionary=True)
    if source:
        cur.execute("""
            SELECT started_at, finished_at, source, mode, policy_reason, status, rc,
                   files_added, files_changed, files_total,
                   size_original_bytes, size_compressed_bytes, size_dedup_bytes, duration_seconds,
                   archive, repo
            FROM backup_runs WHERE source=%s
            ORDER BY started_at DESC
            LIMIT %s
        """, (source, limit))
    else:
        cur.execute("""
            SELECT started_at, finished_at, source, mode, policy_reason, status, rc,
                   files_added, files_changed, files_total,
                   size_original_bytes, size_compressed_bytes, size_dedup_bytes, duration_seconds,
                   archive, repo
            FROM backup_runs
            ORDER BY started_at DESC
            LIMIT %s
        """, (limit,))
    rows = cur.fetchall()
    cur.close(); conn.close()
    click.echo(json.dumps(rows, default=str, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    cli()
