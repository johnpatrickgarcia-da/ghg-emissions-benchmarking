"""Export the company workbooks in data/ to load-ready CSVs in data/csv/.

Written with Claude (Anthropic); see the "Use of AI" guideline in the
workbook README sheets.

Usage (from the repository root):
    python scripts/export_csv.py                  # all four companies
    python scripts/export_csv.py toyota           # one or more companies

For each data sheet (emissions, scope3, operations, units, fundamentals) the
rows from every selected workbook are stacked into one CSV:

    data/csv/emissions.csv
    data/csv/scope3.csv
    data/csv/operations.csv
    data/csv/units.csv          (one row per unit; duplicates across workbooks removed)
    data/csv/fundamentals.csv

What the export does, and does not, change:
  * Values are written exactly as stored in the cell, not as displayed.
    Excel number formats (thousands separators, decimals) are ignored.
  * Dates are written as yyyy-mm-dd.
  * "N/A" in a numeric column (value_reported, source_page, conversion_factor)
    is written as an empty field, which PostgreSQL loads as NULL.
    "N/A" in a text column (unit_reported, assurance_status, ...) is kept,
    because there it is a meaningful category.
  * Leading and trailing spaces are trimmed from text, and each trim is reported.
  * Files are UTF-8, so CO₂ and em dashes survive.

Before writing anything, the script checks the workbooks and stops with a list
of problems if any check fails (see validate()).
"""

import csv
import datetime as dt
import sys
from decimal import Decimal
from pathlib import Path

try:
    import openpyxl
except ImportError:
    sys.exit("openpyxl is required: pip install openpyxl")

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = DATA / "csv"

COMPANIES = {"toyota": "TYT", "honda": "HND", "nissan": "NSN", "subaru": "SBR"}
SHEETS = ["emissions", "scope3", "operations", "units", "fundamentals"]

# Columns where "N/A" means "no number" and is exported as an empty field.
NUMERIC = {"value_reported", "source_page", "conversion_factor", "unit_scale", "category_no"}
INTEGER = {"source_page", "category_no"}

ALLOWED = {
    "disclosed": {"Yes", "No"},
    "assurance_status": {"Limited Assurance", "Reasonable Assurance", "No Assurance", "N/A"},
    "boundary_method": {"Operational control", "Equity share", "Financial control", "Not Stated", "N/A"},
    "scope": {"Scope 1", "Scope 2 (market-based)", "Scope 2 (location-based)", "Scope 3 Total"},
    "metric": {"Revenue", "JPY to USD Exchange Rate", "Headcount", "Units sold"},
}
KEYS = {  # columns that must be unique together within a sheet
    "emissions": ("company_id", "fiscal_year_end", "scope"),
    "scope3": ("company_id", "fiscal_year_end", "category_no"),
    "operations": ("company_id", "fiscal_year_end", "metric"),
    "fundamentals": ("company_id",),
}


def read_sheet(path, sheet):
    """Return (header, rows) with rows as dicts of raw cell values; blank rows skipped."""
    ws = openpyxl.load_workbook(path, data_only=True)[sheet]
    rows = list(ws.iter_rows(values_only=True))
    header = [h for h in rows[0] if h is not None]
    out = []
    for r in rows[1:]:
        r = r[: len(header)]
        if all(v is None for v in r):
            continue
        out.append(dict(zip(header, r)))
    return header, out


def clean(col, value, where, log):
    """Convert one cell value to its CSV text."""
    if value is None:
        return ""
    if isinstance(value, str):
        stripped = value.strip()
        if stripped != value:
            log.append(f"trimmed spaces: {where} {col}")
        if col in NUMERIC and stripped == "N/A":
            return ""
        return stripped
    if isinstance(value, dt.datetime):
        return value.date().isoformat()
    if isinstance(value, dt.date):
        return value.isoformat()
    if isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        if col in INTEGER or value.is_integer():
            return str(int(value)) if value.is_integer() else format(Decimal(repr(value)), "f")
        return format(Decimal(repr(value)), "f")  # avoids 1e-06 style output
    return str(value)


def validate(data):
    """Return a list of problems found across the loaded sheets."""
    problems = []
    for sheet, (headers, rows) in data.items():
        if len({tuple(h) for h in headers.values()}) > 1:
            problems.append(f"{sheet}: column headers differ between workbooks: {headers}")
        seen = set()
        for co, i, r in rows:
            where = f"{co}/{sheet} row {i}"
            for col, allowed in ALLOWED.items():
                if col in r and r[col] not in allowed:
                    problems.append(f"{where}: {col} = {r[col]!r} not in {sorted(allowed)}")
            if "company_id" in r and r["company_id"] != COMPANIES[co]:
                problems.append(f"{where}: company_id = {r['company_id']!r}, expected {COMPANIES[co]}")
            if "fiscal_year_end" in r and not isinstance(r["fiscal_year_end"], (dt.date, dt.datetime)):
                problems.append(f"{where}: fiscal_year_end is not a date: {r['fiscal_year_end']!r}")
            v = r.get("value_reported")
            if sheet in ("emissions", "scope3"):
                if r["disclosed"] == "Yes" and not isinstance(v, (int, float)):
                    problems.append(f"{where}: disclosed = Yes but value_reported = {v!r}")
                if r["disclosed"] == "No" and v != "N/A":
                    problems.append(f"{where}: disclosed = No but value_reported = {v!r}")
            elif sheet == "operations" and not isinstance(v, (int, float)):
                problems.append(f"{where}: value_reported is not a number: {v!r}")
            if sheet in KEYS:
                key = tuple(r.get(k) for k in KEYS[sheet])
                if key in seen:
                    problems.append(f"{where}: duplicate {KEYS[sheet]} = {key}")
                seen.add(key)
    # every unit used must exist in that company's units sheet
    units_by_co = {}
    for co, _, r in data["units"][1]:
        units_by_co.setdefault(co, set()).add(r["unit_reported"])
    for sheet in ("emissions", "scope3"):
        for co, i, r in data[sheet][1]:
            if r["unit_reported"] not in units_by_co.get(co, set()):
                problems.append(f"{co}/{sheet} row {i}: unit {r['unit_reported']!r} missing from units sheet")
    return problems


def main(selected):
    data = {}
    for sheet in SHEETS:
        headers, rows = {}, []
        for co in selected:
            path = DATA / f"{co}_raw.xlsx"
            header, sheet_rows = read_sheet(path, sheet)
            headers[co] = header
            rows += [(co, i, r) for i, r in enumerate(sheet_rows, start=2)]
        data[sheet] = (headers, rows)

    problems = validate(data)
    if problems:
        print(f"Stopped: {len(problems)} problem(s) found. Nothing was written.")
        print("\n".join(problems))
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    log = []
    for sheet in SHEETS:
        headers, rows = data[sheet]
        header = next(iter(headers.values()))
        written, unit_seen = [], {}
        for co, i, r in rows:
            line = [clean(c, r.get(c), f"{co}/{sheet} row {i}", log) for c in header]
            if sheet == "units":  # one row per unit across all workbooks
                unit = line[0]
                if unit in unit_seen:
                    if unit_seen[unit][1:3] != line[1:3]:
                        print(f"Stopped: unit {unit!r} has different conversions in different workbooks.")
                        return 1
                    continue
                unit_seen[unit] = line
            written.append(line)
        with open(OUT / f"{sheet}.csv", "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh, lineterminator="\n")
            w.writerow(header)
            w.writerows(written)
        print(f"{sheet}.csv: {len(written)} rows")
    for entry in log:
        print("note:", entry)
    return 0


if __name__ == "__main__":
    args = [a.lower() for a in sys.argv[1:]] or list(COMPANIES)
    unknown = [a for a in args if a not in COMPANIES]
    if unknown:
        sys.exit(f"Unknown company: {', '.join(unknown)}. Choose from {', '.join(COMPANIES)}.")
    sys.exit(main(args))
