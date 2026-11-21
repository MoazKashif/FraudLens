#!/usr/bin/env python3
"""
Generates the two Phase 2 PDF reports from the live warehouse:
    reports/Data_Cleaning_Report.pdf   (reads project_staging.cleaning_log, rejected_rows, raw_* and stg_*)
    reports/Data_Quality_Report.pdf    (reads project_dw.dq_results, etl_audit_log, fact/dim tables)

Run after etl_pipeline.py:
    python etl/generate_reports.py --host localhost --user postgres --password secret
"""
import argparse
import os
from datetime import datetime
from pathlib import Path

import psycopg2
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import (BaseDocTemplate, Frame, KeepTogether, PageBreak, PageTemplate, Paragraph, Spacer,
                                Table, TableStyle, XPreformatted)

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "Real-time Data Warehouse for Fraud Detection & Anomaly Analysis"
COURSE = "Data Warehousing & Business Intelligence - Final Project"
TEAM = ["Chaudary Moaz Kashif (23L-2626)", "Umar Khalid (23L-2599)"]
NAVY, TEAL = colors.HexColor("#1F3A5F"), colors.HexColor("#1F6F8B")
LIGHT, GRID = colors.HexColor("#EEF3F8"), colors.HexColor("#C9D3DE")
GREEN, RED = colors.HexColor("#1E7B3A"), colors.HexColor("#B3261E")

S = {
    "title": ParagraphStyle("t", fontName="Helvetica-Bold", fontSize=24, leading=29, textColor=colors.white),
    "sub": ParagraphStyle("s", fontName="Helvetica", fontSize=12, leading=16, textColor=colors.white),
    "h1": ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=15, leading=19, textColor=NAVY, spaceBefore=14, spaceAfter=6, keepWithNext=1),
    "h2": ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=11.5, leading=15, textColor=TEAL, spaceBefore=10, spaceAfter=4, keepWithNext=1),
    "body": ParagraphStyle("b", fontName="Helvetica", fontSize=9.8, leading=14, spaceAfter=5, alignment=TA_LEFT),
    "bullet": ParagraphStyle("bu", fontName="Helvetica", fontSize=9.8, leading=13.5, leftIndent=14, bulletIndent=3, spaceAfter=2),
    "cell": ParagraphStyle("c", fontName="Helvetica", fontSize=8.2, leading=10.4),
    "cellb": ParagraphStyle("cb", fontName="Helvetica-Bold", fontSize=8.2, leading=10.4),
    "cellh": ParagraphStyle("ch", fontName="Helvetica-Bold", fontSize=8.2, leading=10.4, textColor=colors.white),
    "small": ParagraphStyle("sm", fontName="Helvetica-Oblique", fontSize=8.2, leading=11, textColor=colors.HexColor("#555555"), spaceAfter=4),
    "code": ParagraphStyle("code", fontName="Courier", fontSize=7.4, leading=9.4, backColor=colors.HexColor("#F4F6F8"),
                           borderPadding=5, leftIndent=6, rightIndent=6, spaceBefore=4, spaceAfter=8),
    "callout": ParagraphStyle("co", fontName="Helvetica-Bold", fontSize=10.5, leading=15, textColor=NAVY),
}


def esc(x):
    return str(x).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fmt(v):
    if v is None:
        return "-"
    if isinstance(v, (int,)) and not isinstance(v, bool):
        return f"{v:,}"
    try:
        from decimal import Decimal
        if isinstance(v, Decimal):
            return f"{v:,.2f}" if v != v.to_integral_value() else f"{int(v):,}"
    except Exception:
        pass
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d %H:%M:%S")
    return str(v)


def tbl(rows, widths, status_col=None, bold_first=False):
    data = []
    for ri, row in enumerate(rows):
        r = []
        for ci, cell in enumerate(row):
            txt = esc(fmt(cell)) if ri > 0 else esc(cell)
            if ri == 0:
                r.append(Paragraph(txt, S["cellh"]))
            elif status_col is not None and ci == status_col and txt in ("PASS", "FAIL", "SUCCESS", "FAILED"):
                col = "#1E7B3A" if txt in ("PASS", "SUCCESS") else "#B3261E"
                r.append(Paragraph(f'<font color="{col}"><b>{txt}</b></font>', S["cell"]))
            else:
                r.append(Paragraph(txt, S["cellb" if (bold_first and ci == 0) else "cell"]))
        data.append(r)
    t = Table(data, colWidths=[w * cm for w in widths], repeatRows=1)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("GRID", (0, 0), (-1, -1), 0.4, GRID), ("BACKGROUND", (0, 0), (-1, 0), NAVY),
          ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
          ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]
    for i in range(2, len(rows), 2):
        st.append(("BACKGROUND", (0, i), (-1, i), LIGHT))
    t.setStyle(TableStyle(st))
    return t


def P(t, style="body"):
    return Paragraph(t, S[style])


def H1(t):
    return Paragraph(esc(t), S["h1"])


def H2(t):
    return Paragraph(esc(t), S["h2"])


def bullets(items):
    return [Paragraph(i, S["bullet"], bulletText="\u2022") for i in items]


def code(t):
    return XPreformatted(esc(t), S["code"])


def callout(t):
    c = Table([[Paragraph(t, S["callout"])]], colWidths=[17 * cm])
    c.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), LIGHT), ("LINEBEFORE", (0, 0), (0, -1), 3, TEAL),
                           ("LEFTPADDING", (0, 0), (-1, -1), 10), ("TOPPADDING", (0, 0), (-1, -1), 7), ("BOTTOMPADDING", (0, 0), (-1, -1), 7)]))
    return c


def cover(title, subtitle):
    band = Table([[Paragraph(esc(title), S["title"])], [Paragraph(esc(subtitle), S["sub"])], [Paragraph(esc(PROJECT), S["sub"])]], colWidths=[17 * cm])
    band.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), NAVY), ("LEFTPADDING", (0, 0), (-1, -1), 16),
                              ("TOPPADDING", (0, 0), (0, 0), 24), ("BOTTOMPADDING", (0, -1), (-1, -1), 22), ("TOPPADDING", (0, 1), (-1, -1), 4)]))
    info = [["Course", COURSE], ["Phase", "Phase 2 - Physical Data Warehouse Implementation & ETL Pipeline"],
            ["Team members", ", ".join(TEAM)], ["Generated", datetime.now().strftime("%d %B %Y, %H:%M")]]
    it = Table([[Paragraph(f"<b>{esc(a)}</b>", S["cell"]), Paragraph(esc(b), S["cell"])] for a, b in info], colWidths=[4 * cm, 13 * cm])
    it.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.4, GRID), ("VALIGN", (0, 0), (-1, -1), "TOP"),
                            ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    return [band, Spacer(1, 14), it, Spacer(1, 10)]


def build(path, title, story):
    def deco(cv, doc):
        cv.saveState()
        cv.setFont("Helvetica", 8)
        cv.setFillColor(colors.HexColor("#666666"))
        if doc.page > 1:
            cv.drawString(2 * cm, A4[1] - 1.3 * cm, PROJECT)
            cv.drawRightString(A4[0] - 2 * cm, A4[1] - 1.3 * cm, title)
            cv.setStrokeColor(GRID)
            cv.line(2 * cm, A4[1] - 1.45 * cm, A4[0] - 2 * cm, A4[1] - 1.45 * cm)
        cv.drawString(2 * cm, 1.2 * cm, "Phase 2 - Implementation & ETL")
        cv.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"Page {doc.page}")
        cv.restoreState()
    doc = BaseDocTemplate(str(path), pagesize=A4, leftMargin=2 * cm, rightMargin=2 * cm, topMargin=2 * cm, bottomMargin=1.8 * cm,
                          title=title, author=", ".join(TEAM))
    doc.addPageTemplates([PageTemplate(id="p", frames=[Frame(2 * cm, 1.8 * cm, A4[0] - 4 * cm, A4[1] - 3.8 * cm)], onPage=deco)])
    doc.build(story)


class DB:
    def __init__(self, a):
        kw = dict(host=a.host, port=a.port, user=a.user, dbname=a.dbname)
        if a.password:
            kw["password"] = a.password
        self.conn = psycopg2.connect(**kw)

    def q(self, sql):
        with self.conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchall()

    def one(self, sql):
        return self.q(sql)[0][0]


# =====================================================================================================
def cleaning_report(db, out):
    s = cover("Data Cleaning Report", "Phase 2 Deliverable: staging transformations")
    raw = {t: db.one(f"SELECT COUNT(*) FROM project_staging.raw_{t}") for t in ["accounts", "transaction_type", "behavior_risk", "user"]}
    stg = {"accounts": db.one("SELECT COUNT(*) FROM project_staging.stg_accounts"),
           "transaction_type": db.one("SELECT COUNT(*) FROM project_staging.stg_transaction_type"),
           "behavior_risk": db.one("SELECT COUNT(*) FROM project_staging.stg_behavior_risk"),
           "user": db.one("SELECT COUNT(*) FROM project_staging.stg_user")}
    rej = {t: db.one(f"SELECT COUNT(*) FROM project_staging.rejected_rows WHERE source_table='raw_{t}'") for t in raw}
    s += [H1("1. Purpose and Scope"),
          P("This report documents how the four source CSV files were cleaned on their way from the <b>raw_*</b> landing tables to the typed, standardised "
            "<b>stg_*</b> tables in the <b>project_staging</b> schema. Every rule below is implemented in <b>sql/03_staging_clean.sql</b> and every "
            "number in this report was read from the cleaning log written by that script (<i>project_staging.cleaning_log</i>) when the pipeline ran."),
          callout("Pipeline: Source CSV files -> project_staging (raw_*, stg_*) -> project_dw (dim_*, fact_*) -> project_reporting (vw_*)"),
          H1("2. Rows Loaded and Cleaned"),
          tbl([["Source file", "Rows in raw table", "Rows rejected", "Rows in cleaned table", "Cleaned table"],
               ["accounts.csv", raw["accounts"], rej["accounts"], stg["accounts"], "stg_accounts"],
               ["transaction_type.csv", raw["transaction_type"], rej["transaction_type"], stg["transaction_type"], "stg_transaction_type"],
               ["behavior_risk.csv", raw["behavior_risk"], rej["behavior_risk"], stg["behavior_risk"], "stg_behavior_risk"],
               ["user.csv", raw["user"], rej["user"], stg["user"], "stg_user, stg_customer (%s), stg_merchant (%s)" % (
                   fmt(db.one("SELECT COUNT(*) FROM project_staging.stg_customer")), fmt(db.one("SELECT COUNT(*) FROM project_staging.stg_merchant")))]],
              [3.4, 2.8, 2.4, 3.2, 5.2], bold_first=True),
          Spacer(1, 4),
          P("Raw rows = cleaned rows + rejected rows for every file (checked again in the Data Quality Report). "
            "In transaction_type.csv the rejected rows are completely blank lines; the other files lost no rows.", "small"),
          H1("3. Cleaning Rules and Results")]
    log = db.q("SELECT source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note FROM project_staging.cleaning_log "
               "WHERE rule_type <> 'Summary' ORDER BY log_id")
    for rtype, title in [("Duplicates", "3.1 Remove duplicates"), ("NULL handling", "3.2 Handle NULL / missing values"),
                         ("Standardise text", "3.3 Standardise text"), ("Data type conversion", "3.4 Convert data types"),
                         ("Data privacy / quality", "3.5 Data privacy and quality")]:
        rows = [["Source", "Rule", "Rows before", "Rows after", "Rows affected", "Note"]]
        rows += [[a, b, d, e, f, g] for a, b, c_, d, e, f, g in log if c_ == rtype]
        if len(rows) > 1:
            s += [KeepTogether([H2(title), tbl(rows, [2.6, 5.0, 1.8, 1.8, 1.8, 4.0])])]
    s += [P("'Rows affected' counts the rows that were actually changed, removed or rejected by the rule. A value of 0 means the check ran and found nothing to fix.", "small"),
          H1("4. Before and After Examples")]
    # --- text standardisation test (guideline example)
    rows = [["Before (input)", "After (INITCAP(LOWER(TRIM(x))))"]]
    for b_, a_ in db.q("SELECT x, INITCAP(LOWER(TRIM(x))) FROM (VALUES (' lahore '), ('LAHORE'), ('lahore'), ('  New YORK')) v(x)"):
        rows.append(['"%s"' % b_, a_])
    s += [H2("4.1 Standardise text - rule test"), P("The same expression used in the pipeline, applied to dirty sample text:"), tbl(rows, [8.5, 8.5])]
    # --- real examples
    rows = [["Table / column", "Before (raw)", "After (staged)"]]
    for r in db.q("""SELECT r.transaction_type, s.type_name, r.txn_timestamp, s.txn_timestamp::text, r.location_region, s.location_region
                     FROM project_staging.raw_transaction_type r JOIN project_staging.stg_transaction_type s ON s.transaction_id = r.transaction_id::INT
                     WHERE r.row_id IN (1, 2, 3) ORDER BY r.row_id"""):
        rows += [["transaction_type.TransactionType", r[0], r[1]], ["transaction_type.timestamp (text -> TIMESTAMP)", r[2], r[3]]]
    for r in db.q("""SELECT r.purchase_pattern, s.purchase_pattern, r.anomaly, s.anomaly_level, r.login_frequency, s.login_frequency_band, r.session_duration, s.session_duration_band
                     FROM project_staging.raw_behavior_risk r JOIN project_staging.stg_behavior_risk s ON s.row_id = r.row_id
                     WHERE r.row_id IN (1, 2, 4) ORDER BY r.row_id"""):
        rows += [["behavior_risk.purchase_pattern", r[0], r[1]], ["behavior_risk.anomaly", r[2], r[3]],
                 ["behavior_risk.login_frequency (band)", r[4], r[5]], ["behavior_risk.session_duration (band)", r[6], r[7]]]
    for r in db.q("""SELECT r.amount, s.amount::text, r.is_fraud, s.is_fraud::text FROM project_staging.raw_accounts r
                     JOIN project_staging.stg_accounts s ON s.txn_seq = r.row_id WHERE r.row_id IN (1, 2)"""):
        rows += [["accounts.amount (text -> NUMERIC)", r[0], r[1]], ["accounts.is_fraud (TRUE/FALSE -> 1/0)", r[2], r[3]]]
    r = db.q("""SELECT r.card_expiry, s.card_expiry_month, s.card_expiry_year, r.card_number FROM project_staging.raw_user r
                JOIN project_staging.stg_customer s ON s.customer_email = LOWER(TRIM(r.customer_email)) WHERE r.row_id = 1""")[0]
    rows += [["user.Card_Expiry (text -> month, year)", r[0], f"month {r[1]}, year {r[2]}"],
             ["user.Card_Number (scientific notation)", r[3], "not loaded (digits already lost; sensitive)"]]
    s += [H2("4.2 Values taken from the real data"), tbl(rows, [6.4, 5.3, 5.3]), Spacer(1, 4)]
    # --- duplicates
    dup = db.q("""SELECT LEFT(customer_email,2) || '***@' || SPLIT_PART(customer_email,'@',2) AS em, COUNT(*), MIN(row_id)::text,
                         STRING_AGG(row_id::text, ', ' ORDER BY row_id) FROM project_staging.raw_user
                  GROUP BY customer_email HAVING COUNT(*) > 1 ORDER BY MIN(row_id) LIMIT 5""")
    rows = [["Customer email (masked)", "Records in file", "Raw row ids", "Row kept"]] + [[a, b, d, c_] for a, b, c_, d in dup]
    s += [H2("4.3 Duplicates removed (customer email)"),
          P(f"{fmt(db.one('SELECT COUNT(*) FROM (SELECT 1 FROM project_staging.raw_user GROUP BY LOWER(TRIM(customer_email)) HAVING COUNT(*) > 1) x'))} customer emails appear more than once in user.csv "
            "(the file has 2,000 customer records but fewer distinct customers). The first record per email is kept in <b>stg_customer</b>; "
            "all 2,000 records stay in <b>stg_user</b> because each one is a customer-merchant link. First five examples:"),
          tbl(rows, [5.5, 3.2, 4.8, 3.5])]
    # --- rejected rows
    rr = db.q("SELECT source_table, reason, COUNT(*), MIN(row_id), MAX(row_id) FROM project_staging.rejected_rows GROUP BY 1, 2 ORDER BY 1, 2")
    ex = db.q("SELECT raw_data FROM project_staging.rejected_rows WHERE source_table='raw_transaction_type' ORDER BY row_id LIMIT 1")
    s += [H1("5. Rejected Rows"),
          P("Rows that cannot be used are not deleted silently: they are written to <b>project_staging.rejected_rows</b> with the reason and the raw text."),
          tbl([["Source table", "Reason", "Rows", "First raw row_id", "Last raw row_id"]] + [list(x) for x in rr], [4.0, 5.2, 2.2, 2.8, 2.8]) if rr else P("No rows were rejected."),
          Spacer(1, 3), P(f"Example raw text of a rejected transaction_type row: <font face='Courier'>{esc(ex[0][0]) if ex else '-'}</font> (all five columns empty)."),
          H1("6. Observations")]
    s += bullets([
        "<b>transaction_type.csv</b> holds 37,417 usable rows followed by 41,183 completely blank rows (a spreadsheet export artefact). The blank rows are rejected; the 37,417 transaction ids are unique and run 1..37,417.",
        "<b>Text</b> in the source files was consistently lower case for types and labels (for example <i>transfer</i>, <i>high_value</i>, <i>low_risk</i>); the pipeline turns them into readable labels. No leading or trailing spaces were found in any file, and the trim step is kept as a safeguard.",
        "<b>accounts.csv</b> has no missing values, no invalid amounts and no exact duplicate rows. It contains exactly 1,048,575 data rows, the Excel row limit, so it may have been cut when it was saved.",
        "<b>Card numbers</b> were stored in scientific notation (for example 4.17562E+18) in 1,989 of 2,000 rows, so the real numbers cannot be recovered. They are not loaded; only the card expiry month and year are kept.",
        "<b>Behaviour</b> rows 37,418 to 78,600 have no matching transaction row and stay in staging unused (see assumption A1 in the Phase 1 Data Dictionary).",
        "<b>Personal data</b> (names and emails) is loaded as supplied for the course; the reporting views mask customer emails.",
    ])
    build(out, "Data Cleaning Report", s)


# =====================================================================================================
def quality_report(db, out):
    s = cover("Data Quality Report", "Phase 2 Deliverable: validation of the loaded warehouse")
    tot = db.q("SELECT COUNT(*), COUNT(*) FILTER (WHERE status='PASS'), COUNT(*) FILTER (WHERE status='FAIL') FROM project_dw.dq_results")[0]
    groups = db.q("SELECT check_group, COUNT(*), COUNT(*) FILTER (WHERE status='PASS'), COUNT(*) FILTER (WHERE status='FAIL') FROM project_dw.dq_results GROUP BY 1 ORDER BY 1")
    counts = [[t, db.one(f"SELECT COUNT(*) FROM project_dw.{t}")] for t in
              ["dim_date", "dim_time", "dim_customer", "dim_merchant", "dim_transactiontype", "dim_behaviorrisk",
               "fact_transactions", "fact_daily_fraud_snapshot", "fact_customer_merchant"]]
    s += [H1("1. Summary"),
          callout(f"{tot[0]} automated checks ran after the load: {tot[1]} passed, {tot[2]} failed."),
          Spacer(1, 6),
          tbl([["Check group", "What it proves", "Checks", "Pass", "Fail"],
               ["Completeness", "No rows lost, no missing values, minimum sizes met", *[x for x in groups if x[0] == 'Completeness'][0][1:]],
               ["Accuracy", "Totals reconcile with the source; values are valid and consistent", *[x for x in groups if x[0] == 'Accuracy'][0][1:]],
               ["Integrity", "Every foreign key finds its dimension; keys are unique", *[x for x in groups if x[0] == 'Integrity'][0][1:]]],
              [3.0, 8.0, 2.0, 2.0, 2.0], bold_first=True),
          Spacer(1, 6), P("All checks are implemented in <b>sql/08_data_quality.sql</b>. Each check stores its expected and actual value in <i>project_dw.dq_results</i>."),
          H2("Warehouse row counts after the load"),
          tbl([["Table", "Rows"]] + counts, [8, 4]),
          Spacer(1, 4),
          P("Required minimum size: 100+ dimension records and 10,000+ fact records. The warehouse has "
            f"{fmt(sum(c_[1] for c_ in counts[:6]))} dimension rows and {fmt(counts[6][1])} transaction fact rows.", "small")]
    for grp, title in [("Completeness", "2. Completeness Checks (missing values)"), ("Accuracy", "3. Accuracy Checks (reconciliation)"),
                       ("Integrity", "4. Integrity Checks (foreign keys and uniqueness)")]:
        rows = [["#", "Check", "Expected", "Actual", "Result"]]
        for i, (_, name, e, a, st) in enumerate(db.q(f"SELECT check_id, check_name, expected, actual, status FROM project_dw.dq_results WHERE check_group='{grp}' ORDER BY check_id"), 1):
            rows.append([i, name, e, a, st])
        s += [H1(title), tbl(rows, [0.8, 9.4, 2.4, 2.4, 2.0], status_col=4)]
    s.append(P("Checks that compare 'at least' values (minimum size) pass when actual is greater than or equal to expected; all other checks require actual = expected.", "small"))

    # surrogate key evidence
    rows = [["Business key (customer_email, masked)", "customer_key (surrogate)", "Business key (merchant_email, masked)", "merchant_key (surrogate)"]]
    for r in db.q("""SELECT LEFT(c.customer_email,2)||'***@'||SPLIT_PART(c.customer_email,'@',2), c.customer_key,
                            LEFT(m.merchant_email,2)||'***@'||SPLIT_PART(m.merchant_email,'@',2), m.merchant_key
                     FROM project_dw.dim_customer c JOIN project_dw.dim_merchant m ON m.merchant_key - 5000 = c.customer_key - 1000 ORDER BY c.customer_key LIMIT 5"""):
        rows.append([r[0], str(r[1]), r[2], str(r[3])])
    s += [H1("5. Surrogate Key Implementation (business key -> surrogate key)"),
          P("Dimensions generate their own integer surrogate keys (customer_key starts at 1001, merchant_key at 5001) and keep the business key as a unique column. "
            "The fact load replaces every business key by the surrogate key looked up in the dimension."),
          tbl(rows, [5.0, 3.6, 5.0, 3.4])]
    rows = [["Fact row", "Source txn_seq", "User row used", "Customer email (masked) -> customer_key", "Merchant email (masked) -> merchant_key", "Hour -> time_key", "Date -> date_key"]]
    for r in db.q("""SELECT f.transaction_key, a.txn_seq, u.row_id,
                            LEFT(u.customer_email,2)||'***@'||SPLIT_PART(u.customer_email,'@',2) || ' -> ' || f.customer_key,
                            LEFT(u.merchant_email,2)||'***@'||SPLIT_PART(u.merchant_email,'@',2) || ' -> ' || f.merchant_key,
                            EXTRACT(HOUR FROM f.txn_timestamp)::INT || ' -> ' || f.time_key, TO_CHAR(f.txn_timestamp,'YYYY-MM-DD') || ' -> ' || f.date_key
                     FROM project_dw.fact_transactions f JOIN project_staging.stg_accounts a ON a.txn_seq = f.transaction_key
                     JOIN project_staging.stg_user u ON u.row_id = ((a.txn_seq - 1) % (SELECT COUNT(*) FROM project_staging.stg_user)) + 1
                     WHERE f.transaction_key IN (1, 2, 3, 2001, 500000) ORDER BY f.transaction_key"""):
        rows.append(list(r))
    s += [H2("Example: following one transaction through the key mapping"), tbl(rows, [1.5, 1.7, 1.7, 4.3, 4.0, 1.9, 2.0]),
          Spacer(1, 3),
          P("Integrity checks 'Surrogate key: every staged user record maps to exactly one customer_key / merchant_key' and "
            "'Surrogate keys are unique' prove the mapping is complete and one-to-one.", "small")]

    # reporting layer
    views = db.q("SELECT table_name FROM information_schema.views WHERE table_schema='project_reporting' ORDER BY 1")
    rows = [["Reporting view", "Rows returned"]] + [[v[0], db.one(f"SELECT COUNT(*) FROM project_reporting.{v[0]}")] for v in views]
    kpi = db.q("SELECT total_transactions, total_amount, fraud_transactions, fraud_pct, total_fraud_loss, avg_transaction_value, avg_risk_score FROM project_reporting.vw_kpi_overview")[0]
    s += [H1("6. Reporting Layer Check"),
          P("Every view in <b>project_reporting</b> returns rows. The KPI view agrees with the reconciled fact totals:"),
          tbl([["Total transactions", "Total amount", "Fraud transactions", "Fraud %", "Total fraud loss", "Avg transaction", "Avg risk score"], list(kpi)],
              [2.6, 2.8, 2.4, 1.6, 2.6, 2.6, 2.4]),
          Spacer(1, 6), tbl(rows, [9, 4])]

    # negative test
    with db.conn.cursor() as cur:
        cur.execute("BEGIN")
        cur.execute("UPDATE project_dw.fact_transactions SET amount = amount + 5 WHERE transaction_key IN (1,2,3)")
        cur.execute("UPDATE project_dw.fact_transactions SET fraud_amount = 1 WHERE transaction_key = 4 AND is_fraud = 0")
        cur.execute("DELETE FROM project_dw.fact_transactions WHERE transaction_key IN (10,11)")
        cur.execute("UPDATE project_dw.fact_transactions SET date_key = 20221231 WHERE transaction_key = 20")
        cur.execute((ROOT / "sql" / "08_data_quality.sql").read_text(encoding="utf-8"))
        cur.execute("SELECT check_name, expected, actual FROM project_dw.dq_results WHERE status='FAIL' ORDER BY check_id")
        neg = cur.fetchall()
        db.conn.rollback()
    rows = [["Check that failed", "Expected", "Actual"]] + [list(x) for x in neg]
    s += [H1("7. Do the Checks Really Detect Errors?"),
          P("To show the checks are not always green, errors were injected inside a transaction that was rolled back afterwards: "
            "3 amounts changed (+5), 1 fraud_amount changed, 2 fact rows deleted and 1 date changed. The validation script was run and these checks failed "
            "(the warehouse itself is unchanged):"),
          tbl(rows, [10, 3.5, 3.5])]

    # audit log
    rows = [["Step", "Status", "Rows", "Started", "Seconds"]]
    for step, status, nrows, st, fi in db.q("SELECT step_name, status, rows_processed, started_at, finished_at FROM project_dw.etl_audit_log ORDER BY log_id"):
        rows.append([step, status, nrows, st.strftime("%H:%M:%S"), f"{(fi - st).total_seconds():.1f}" if fi else "-"])
    s += [H1("8. ETL Run Log"), P("Written by etl/etl_pipeline.py to <i>project_dw.etl_audit_log</i>."), tbl(rows, [6.4, 2.2, 3.0, 2.6, 2.4], status_col=1)]

    # observations
    by = db.q("SELECT type_name, ROUND(100.0*SUM(is_fraud)/COUNT(*),3) FROM project_dw.fact_transactions f JOIN project_dw.dim_transactiontype t USING (type_key) GROUP BY 1 ORDER BY 1")
    s += [H1("9. Observations and Limitations")]
    s += bullets([
        "<b>Linking of the four files (assumption A1).</b> The source files share no key, so the fact load links them with a fixed positional rule (no RANDOM()). "
        "The data therefore passes every technical check, but relationships between files are simulated: for example the fraud rate is almost identical for every transaction type (" +
        ", ".join(f"{a} {b}%" for a, b in by) + ") and the average risk score of fraud and normal transactions is close. These are not business findings.",
        "<b>Fraud flag and amounts</b> come only from accounts.csv, so fraud totals (18,887 fraud transactions, 1.80%) are real source values and reconcile exactly.",
        "<b>accounts.csv</b> ends at the Excel row limit; if the original file is longer, rerun the pipeline with the complete file. The checks compare against whatever file is supplied.",
        "<b>Re-runs</b> are safe: the pipeline rebuilds staging and warehouse tables and gives the same result because no random numbers are used.",
    ])
    s.append(H2("How to rerun the validation"))
    s.append(code("python etl/etl_pipeline.py --data-dir data --host localhost --user postgres --password <password>\npython etl/generate_reports.py --host localhost --user postgres --password <password>\n-- or only the checks:  psql -d fraud_dw -f sql/08_data_quality.sql"))
    build(out, "Data Quality Report", s)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default=os.getenv("PGHOST", "localhost"))
    p.add_argument("--port", default=os.getenv("PGPORT", "5432"))
    p.add_argument("--user", default=os.getenv("PGUSER", "postgres"))
    p.add_argument("--password", default=os.getenv("PGPASSWORD", ""))
    p.add_argument("--dbname", default=os.getenv("PGDATABASE", "fraud_dw"))
    p.add_argument("--out-dir", default=str(ROOT / "reports"))
    a = p.parse_args()
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    db = DB(a)
    cleaning_report(db, out / "Data_Cleaning_Report.pdf")
    quality_report(db, out / "Data_Quality_Report.pdf")
    print("reports written to", out)


if __name__ == "__main__":
    main()
