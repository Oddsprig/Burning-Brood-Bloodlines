"""Create v2 workbooks serially. Requires installed Excel for native recalculation.
Run: python -B upgrade_workbooks_v2.py
--check-only builds and checks packages entirely in memory; it never saves files.
Existing originals and existing v2 files are never overwritten.
"""
import argparse
import base64
from copy import deepcopy
from datetime import date
import hashlib
from io import BytesIO
import json
from pathlib import Path
import posixpath
import re
import subprocess
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
CT = "http://schemas.openxmlformats.org/package/2006/content-types"
ET.register_namespace("x", MAIN)
ET.register_namespace("r", REL)
NS = {"x": MAIN}
MONEY = '$#,##0.00;($#,##0.00);"-"'
DATE = "m/d/yyyy"
PERCENT = "0.0%"
EXAMPLE_DATE = date(2026, 10, 17)
BANNED = re.compile(r"\b(?:XLOOKUP|FILTER|SORT|UNIQUE|SEQUENCE)\s*\(", re.I)

def tag(name):
    return "{%s}%s" % (MAIN, name)

def col(number):
    out = ""
    while number:
        number, digit = divmod(number - 1, 26)
        out = chr(65 + digit) + out
    return out

def serial(value):
    return (value - date(1899, 12, 30)).days

class Sheet:
    def __init__(self, book, name, path, root):
        self.book, self.name, self.path, self.root = book, name, path, root
        self.data = root.find(tag("sheetData"))
        self.rows = {int(r.get("r")): r for r in self.data}
        self.cells = {c.get("r"): c for r in self.data for c in r}
        self.dirty = False

    def value(self, address):
        c = self.cells.get(address)
        if c is None:
            return None
        f, v, inline = c.find(tag("f")), c.find(tag("v")), c.find(tag("is"))
        if f is not None:
            return "=" + (f.text or "")
        if inline is not None:
            return "".join(inline.itertext())
        if v is None:
            return None
        if c.get("t") == "s":
            return self.book.strings[int(v.text)]
        if c.get("t") in ("str", "e"):
            return v.text or ""
        try:
            return float(v.text)
        except (TypeError, ValueError):
            return v.text

    def put(self, address, value, style=None):
        r = int(re.search(r"\d+", address).group())
        row = self.rows.get(r)
        if row is None:
            row = ET.Element(tag("row"), r=str(r), ht="25", customHeight="1")
            self.rows[r] = row
            self.data.append(row)
        c = self.cells.get(address)
        if c is None:
            c = ET.SubElement(row, tag("c"), r=address)
            self.cells[address] = c
        c[:] = []
        c.attrib.pop("t", None)
        if style is not None:
            c.set("s", str(style))
        if isinstance(value, date):
            value = serial(value)
        if isinstance(value, str) and value.startswith("="):
            ET.SubElement(c, tag("f")).text = value[1:]
        elif isinstance(value, str):
            c.set("t", "inlineStr")
            ET.SubElement(ET.SubElement(c, tag("is")), tag("t")).text = value
        elif value is not None:
            ET.SubElement(c, tag("v")).text = str(value)
        self.dirty = True

    def formula(self, address, formula, fmt=None):
        self.put(address, formula, self.book.style("calc", fmt))

    def input(self, address, value=None, fmt=None):
        self.put(address, value, self.book.style("input", fmt))

    def row(self, r, values, role="text"):
        for i, v in enumerate(values, 1):
            self.put(col(i) + str(r), v, self.book.style(role))

    def fill(self, column, formula, fmt=None, start=6, end=205):
        for r in range(start, end + 1):
            self.formula(column + str(r), formula.format(r=r), fmt)

    def validation(self, address, options=None, source=None, kind="list",
                   minimum=None, maximum=None):
        validations = self.root.find(tag("dataValidations"))
        if validations is None:
            validations = ET.SubElement(self.root, tag("dataValidations"))
        attrs = dict(type=kind, sqref=address, allowBlank="1",
                     showErrorMessage="1", errorStyle="stop",
                     errorTitle="Check this entry", error="Use a permitted value.")
        if minimum is not None:
            attrs["operator"] = "between" if maximum is not None else "greaterThanOrEqual"
        d = ET.SubElement(validations, tag("dataValidation"), attrs)
        f1 = source if source is not None else (
            '"' + ",".join(map(str, options)) + '"' if options is not None else str(minimum))
        ET.SubElement(d, tag("formula1")).text = f1
        if maximum is not None:
            ET.SubElement(d, tag("formula2")).text = str(maximum)
        validations.set("count", str(len(validations)))
        self.dirty = True

    def width(self, column, width):
        cols = self.root.find(tag("cols"))
        i = 0
        for ch in column:
            i = i * 26 + ord(ch) - 64
        existing = next((c for c in cols if c.get("min") == str(i)
                         and c.get("max") == str(i)), None)
        if existing is None:
            existing = ET.SubElement(cols, tag("col"), min=str(i), max=str(i))
        existing.set("width", str(width))
        existing.set("customWidth", "1")
        self.dirty = True

    def column_format(self, column, fmt, role="input", start=6, end=205):
        style = self.book.style(role, fmt)
        for r in range(start, end + 1):
            a = column + str(r)
            if a not in self.cells:
                self.put(a, None, style)
            else:
                self.cells[a].set("s", str(style))
        self.dirty = True

    def finish(self):
        self.data[:] = sorted(self.rows.values(), key=lambda r: int(r.get("r")))
        for row in self.data:
            row[:] = sorted(row, key=lambda c: (
                len(re.match("[A-Z]+", c.get("r")).group()),
                re.match("[A-Z]+", c.get("r")).group()))
        # Put added elements in SpreadsheetML schema order.
        order = ["sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols",
                 "sheetData", "sheetCalcPr", "sheetProtection", "protectedRanges",
                 "scenarios", "autoFilter", "sortState", "dataConsolidate",
                 "customSheetViews", "mergeCells", "phoneticPr",
                 "conditionalFormatting", "dataValidations", "hyperlinks",
                 "printOptions", "pageMargins", "pageSetup", "headerFooter",
                 "rowBreaks", "colBreaks", "customProperties", "cellWatches",
                 "ignoredErrors", "smartTags", "drawing", "legacyDrawing",
                 "legacyDrawingHF", "picture", "oleObjects", "controls",
                 "webPublishItems", "tableParts", "extLst"]
        self.root[:] = sorted(self.root, key=lambda e: order.index(
            e.tag.rsplit("}", 1)[-1]) if e.tag.rsplit("}", 1)[-1] in order else len(order))
        dim = self.root.find(tag("dimension"))
        if dim is not None:
            # New areas can extend the existing used range.
            dim.set("ref", "A1:%s%d" % (
                max((re.match("[A-Z]+", a).group() for a in self.cells),
                    key=lambda x: (len(x), x)), max(self.rows)))

class Book:
    def __init__(self, path):
        self.path = Path(path)
        raw = self.path.read_bytes()
        self.original_hash = hashlib.sha256(raw).hexdigest()
        with ZipFile(BytesIO(raw)) as z:
            self.parts = {i.filename: z.read(i.filename) for i in z.infolist()}
        self.workbook = ET.fromstring(self.parts["xl/workbook.xml"])
        self.rels = ET.fromstring(self.parts["xl/_rels/workbook.xml.rels"])
        self.types = ET.fromstring(self.parts["[Content_Types].xml"])
        self.styles = ET.fromstring(self.parts["xl/styles.xml"])
        self.strings = []
        if "xl/sharedStrings.xml" in self.parts:
            self.strings = ["".join(s.itertext()) for s in ET.fromstring(
                self.parts["xl/sharedStrings.xml"])]
        targets = {r.get("Id"): r.get("Target") for r in self.rels}
        self.sheets = {}
        for s in self.workbook.find(tag("sheets")):
            target = targets[s.get("{%s}id" % REL)]
            path = target.lstrip("/") if target.startswith("/") else posixpath.normpath(
                posixpath.join("xl", target))
            self.sheets[s.get("name")] = Sheet(self, s.get("name"), path,
                                             ET.fromstring(self.parts[path]))
        self.style_cache = {}
        self.checks, self.cases = [], []

    def __getitem__(self, name):
        return self.sheets[name]

    def style(self, role, fmt=None):
        key = role, fmt
        if key in self.style_cache:
            return self.style_cache[key]
        xfs = self.styles.find(tag("cellXfs"))
        start = self["Start Here"]
        body = next(s for s in self.sheets.values() if s.name != "Start Here")
        fonts = self.styles.find(tag("fonts"))
        def input_style(xf):
            font = fonts[int(xf.get("fontId", "0"))]
            color = font.find(tag("color"))
            return color is not None and color.get("rgb", "").endswith("164A9C")
        if role == "input":
            exemplar = next(i for i, xf in enumerate(xfs) if input_style(xf))
        elif role == "calc":
            exemplar = next(int(c.get("s", "0")) for s in self.sheets.values()
                            for c in s.cells.values() if c.find(tag("f")) is not None)
        else:
            source = start if role in ("text", "title") else body
            address = {"text":"A5", "title":"A2", "note":"A3", "header":"A5"}[role]
            exemplar = int(source.cells[address].get("s", "0"))
        xf = deepcopy(xfs[exemplar])
        xf.set("numFmtId", "0")
        if fmt is not None:
            fmts = self.styles.find(tag("numFmts"))
            if fmts is None:
                fmts = ET.Element(tag("numFmts"), count="0")
                self.styles.insert(0, fmts)
            item = next((n for n in fmts if n.get("formatCode") == fmt), None)
            if item is None:
                num = max([163] + [int(n.get("numFmtId")) for n in fmts]) + 1
                item = ET.SubElement(fmts, tag("numFmt"), numFmtId=str(num), formatCode=fmt)
                fmts.set("count", str(len(fmts)))
            xf.set("numFmtId", item.get("numFmtId"))
            xf.set("applyNumberFormat", "1")
        xfs.append(xf)
        xfs.set("count", str(len(xfs)))
        self.style_cache[key] = len(xfs) - 1
        return len(xfs) - 1

    def new_sheet(self, name, title, headers, widths, note="", rows=205,
                  formulas=()):
        if name in self.sheets:
            raise ValueError("Sheet already exists: " + name)
        index = max([0] + [int(re.search(r"sheet(\d+)\.xml$", p).group(1))
                    for p in self.parts if re.search(r"/sheet\d+\.xml$", p)]) + 1
        while any(s.path == "xl/worksheets/sheet%d.xml" % index for s in self.sheets.values()):
            index += 1
        path = "xl/worksheets/sheet%d.xml" % index
        root = ET.Element(tag("worksheet"))
        prototype = next(iter(self.sheets.values())).root.find(tag("sheetPr"))
        if prototype is not None:
            root.append(deepcopy(prototype))
        views = ET.SubElement(root, tag("sheetViews"))
        view = ET.SubElement(views, tag("sheetView"), showGridLines="0", workbookViewId="0")
        ET.SubElement(view, tag("pane"), ySplit="5", topLeftCell="A6",
                      activePane="bottomLeft", state="frozen")
        ET.SubElement(root, tag("sheetFormatPr"), defaultRowHeight="25")
        ET.SubElement(root, tag("cols"))
        ET.SubElement(root, tag("sheetData"))
        s = Sheet(self, name, path, root)
        self.sheets[name] = s
        rid = "rIdV2_%d" % index
        sheet_id = max(int(s.get("sheetId")) for s in self.workbook.find(tag("sheets"))) + 1
        ET.SubElement(self.workbook.find(tag("sheets")), tag("sheet"),
                      name=name, sheetId=str(sheet_id), attrib={"{%s}id" % REL: rid})
        ET.SubElement(self.rels, "{%s}Relationship" % PKG, Id=rid,
                      Type=REL + "/worksheet", Target="worksheets/sheet%d.xml" % index)
        ET.SubElement(self.types, "{%s}Override" % CT, PartName="/" + path,
                      ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml")
        s.put("A2", title, self.style("title"))
        s.put("A3", note, self.style("note"))
        s.row(5, headers, "header")
        s.rows[5].set("ht", "38")
        for i, width in enumerate(widths, 1):
            s.width(col(i), width)
        for r in range(6, rows + 1):
            for i in range(1, len(headers) + 1):
                c = col(i)
                s.put(c + str(r), None, self.style("calc" if c in formulas else "input"))
        if rows > 20 and len(headers) > 1:
            ET.SubElement(root, tag("autoFilter"), ref="A5:%s%d" % (col(len(headers)), rows))
        return s

    def steps(self, *instructions):
        s = self["Start Here"]
        r = max(int(re.search(r"\d+", a).group()) for a in s.cells if s.value(a) is not None) + 3
        s.put("A%d" % r, "New in v2", self.style("title"))
        for i, text in enumerate(instructions, r + 1):
            s.put("A%d" % i, text, self.style("text"))

    def check(self, sheet, address, expected):
        self.checks.append([sheet, address, expected])

    def case(self, changes, checks):
        self.cases.append({"changes": changes, "checks": checks})

    def package(self):
        for sheet in self.sheets.values():
            if sheet.dirty:
                sheet.finish()
                self.parts[sheet.path] = ET.tostring(sheet.root, encoding="utf-8", xml_declaration=True)
        calc = self.workbook.find(tag("calcPr"))
        if calc is None:
            calc = ET.SubElement(self.workbook, tag("calcPr"))
        calc.set("calcMode", "auto")
        calc.set("fullCalcOnLoad", "1")
        calc.set("forceFullCalc", "1")
        for path, root in [("xl/workbook.xml", self.workbook),
                           ("xl/_rels/workbook.xml.rels", self.rels),
                           ("[Content_Types].xml", self.types),
                           ("xl/styles.xml", self.styles)]:
            self.parts[path] = ET.tostring(root, encoding="utf-8", xml_declaration=True)
        # Keep application metadata consistent with the appended sheets.
        if "docProps/app.xml" in self.parts:
            app = ET.fromstring(self.parts["docProps/app.xml"])
            ep = "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
            vt = "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
            titles = app.find("{%s}TitlesOfParts/{%s}vector" % (ep, vt))
            pairs = app.find("{%s}HeadingPairs/{%s}vector" % (ep, vt))
            if titles is not None:
                titles[:] = []
                titles.set("size", str(len(self.sheets)))
                for name in self.sheets:
                    ET.SubElement(titles, "{%s}lpstr" % vt).text = name
            if pairs is not None:
                variants = list(pairs)
                for i in range(len(variants) - 1):
                    if any(x.text == "Worksheets" for x in variants[i]):
                        for x in variants[i + 1]:
                            x.text = str(len(self.sheets))
            self.parts["docProps/app.xml"] = ET.tostring(app, encoding="utf-8", xml_declaration=True)
        out = BytesIO()
        with ZipFile(out, "w", ZIP_DEFLATED) as z:
            for path, raw in self.parts.items():
                z.writestr(path, raw)
        return out.getvalue()

    def verify(self):
        known = set(self.sheets)
        for s in self.sheets.values():
            for c in s.cells.values():
                f = c.find(tag("f"))
                if f is None:
                    continue
                formula = f.text or ""
                clean = re.sub(r'"(?:[^"]|"")*"|\'(?:[^\']|\'\')*\'', "", formula)
                depth = 0
                for character in clean:
                    depth += (character == "(") - (character == ")")
                    if depth < 0:
                        break
                if depth:
                    raise ValueError("Unbalanced formula: %s!%s" % (s.name,c.get("r")))
                if BANNED.search(formula) or "#REF!" in formula:
                    raise ValueError("Unsupported/broken formula: %s!%s" % (s.name, c.get("r")))
                for name in re.findall(r"'((?:[^']|'')+)'!", formula):
                    if name.replace("''", "'") not in known:
                        raise ValueError("Unknown sheet reference: " + name)
        # Reparse every XML part and verify the generated ZIP CRCs.
        raw = self.package()
        with ZipFile(BytesIO(raw)) as z:
            if z.testzip():
                raise ValueError("ZIP CRC check failed")
            for name in z.namelist():
                if name.endswith(".xml") or name.endswith(".rels"):
                    ET.fromstring(z.read(name))
        return raw

def freelancer(b):
    s = b.new_sheet("Safe to Spend", "Safe to spend",
        ["Measure", "Amount / date", "How to use"], [41, 23, 92],
        "Reserves are money still held in the entered balance. A negative result is a shortfall.",
        rows=15)
    labels = {6:"As of date", 7:"Look-ahead days", 8:"Current spendable balance",
              9:"Tax reserve in this balance", 10:"Savings set-asides in this balance",
              11:"Unpaid bills through horizon", 12:"Safe to spend",
              13:"Bills through", 14:"Undated bills included", 15:"Result"}
    for r, label in labels.items():
        s.put("A%d" % r, label, b.style("text"))
    for r in range(6,16):
        s.put("C%d"%r,None,b.style("text"))
    for addr, value, fmt in [("B6", EXAMPLE_DATE, DATE), ("B7", 30, "0"),
                             ("B8", 2500, MONEY), ("B9", 500, MONEY), ("B10", 200, MONEY)]:
        s.input(addr, value, fmt)
    s.validation("B7", [7,14,30,60,90])
    s.validation("B8:B10", kind="decimal", minimum=0)
    s.formula("B13", '=IF(OR(B6="",B7=""),"",B6+B7)', DATE)
    s.formula("B11", '=IF(B13="","",SUMIFS(\'Bill Planner\'!$F$6:$F$205,'
              '\'Bill Planner\'!$C$6:$C$205,">0",\'Bill Planner\'!$C$6:$C$205,"<"&B13+1)'
              '+SUMIFS(\'Bill Planner\'!$F$6:$F$205,\'Bill Planner\'!$C$6:$C$205,""))', MONEY)
    s.formula("B12", '=IF(OR(B6="",B7="",B8="",B9="",B10=""),"",B8-B11-B9-B10)', MONEY)
    s.formula("B14", '=COUNTIFS(\'Bill Planner\'!$A$6:$A$205,"<>",'
              '\'Bill Planner\'!$C$6:$C$205,"",\'Bill Planner\'!$F$6:$F$205,">0")', "0")
    s.formula("B15", '=IF(B12="","Enter dates, balance and reserves",IF(B12<0,"Shortfall","Available"))')
    notes = {6:"Illustrative date (example). Enter the date of your current balance.",
             7:"Includes overdue bills and the selected number of upcoming days.",
             8:"Illustrative $2,500 (example). Exclude money already transferred to savings.",
             9:"Illustrative $500 (example). Enter only tax money still in the balance.",
             10:"Illustrative $200 (example). Exclude savings already transferred out.",
             11:"Bill Planner balances include partial payments. Undated unpaid bills are also reserved.",
             12:"Balance less unpaid bills, tax reserve and savings set-asides.",
             14:"Add missing due dates in Bill Planner. These balances are reserved conservatively."}
    for r, text in notes.items():
        s.put("C%d" % r, text, b.style("note"))
    b.steps("7. Safe to Spend: enter the cleared balance, as-of date and look-ahead days.",
            "8. Enter tax and savings reserves still in that balance. Do not repeat transferred savings.",
            "9. Keep Bill Planner amounts paid current. Safe to Spend also reserves undated bills.",
            "10. Replace illustrative (example) inputs. Negative safe-to-spend means a shortfall.")
    b.check("Safe to Spend", "B11", 200)
    b.check("Safe to Spend", "B12", 1600)
    b.case([["Safe to Spend","B8",500]], [["Safe to Spend","B12",-400]])
    b.case([["Bill Planner","C8",None]], [["Safe to Spend","B11",200],
                                        ["Safe to Spend","B14",1]])

    b.case([["Safe to Spend","B7",7]],[["Safe to Spend","B11",0],["Safe to Spend","B12",1800]])
    b.case([["Bill Planner","A205","Test bill"],["Bill Planner","C205",serial(date(2026,10,20))],
            ["Bill Planner","D205",100],["Bill Planner","E205",0]],[["Safe to Spend","B12",1500]])

def bakery(b):
    s = b["Pricing"]
    for a, text in {"G5":"Retail margin", "H5":"Retail price / item",
                    "J5":"Wholesale margin", "K5":"Wholesale price / item"}.items():
        s.put(a, text, b.style("header"))
    s.width("J", 20)
    s.width("K", 24)
    for r in range(6, 206):
        s.input("J%d" % r, 0.35 if r <= 8 else None, PERCENT)
    s.fill("K", '=IF(A{r}="","",IF(AND(ISNUMBER(C{r}),ISNUMBER(J{r}),'
           'J{r}>=0,J{r}<1),ROUNDUP(C{r}/(1-J{r}),2),""))', MONEY)
    for column in ("G", "J"):
        s.validation(column+"6:"+column+"205", kind="custom",
                     source='AND(ISNUMBER({0}6),{0}6>=0,{0}6<1)'.format(column))
    af = s.root.find(tag("autoFilter"))
    if af is not None:
        af.set("ref", "A5:K205")
    s.put("A3", "Retail and wholesale prices use the same cost per item. Each margin must be below 100%.",
          b.style("note"))
    o = b.new_sheet("Orders", "Order tracker",
        ["Order ID","Customer","Recipe ID","Item","Qty","Due date","Status",
         "Channel","Suggested unit price","Agreed unit price","Order price","Paid","Balance"],
        [18,27,17,28,10,16,17,16,22,21,19,18,18],
        "Suggested prices update with recipes. Enter the agreed unit price to preserve each customer quote.",
        formulas=("D","I","K","M"))
    o.row(6, ["ORD001","Jordan (example)","R001",None,12,EXAMPLE_DATE,
              "Confirmed","Retail",None,2.50,None,15,None], "input")
    o.column_format("F",DATE)
    for c in ("J","L"):
        o.column_format(c,MONEY)
    o.column_format("E","0")
    o.fill("D", '=IF(C{r}="","",IF(COUNTIFS(\'Batch Costs\'!$A$6:$A$205,C{r})<>1,'
           '"Check recipe ID",INDEX(\'Batch Costs\'!$B$6:$B$205,'
           'MATCH(C{r},\'Batch Costs\'!$A$6:$A$205,0))))')
    o.fill("I", '=IF(C{r}="","",IF(COUNTIFS(\'Pricing\'!$A$6:$A$205,C{r})<>1,'
           '"Check pricing ID",IF(H{r}="Wholesale",IF(ISNUMBER(INDEX(\'Pricing\'!$K$6:$K$205,'
           'MATCH(C{r},\'Pricing\'!$A$6:$A$205,0))),INDEX(\'Pricing\'!$K$6:$K$205,'
           'MATCH(C{r},\'Pricing\'!$A$6:$A$205,0)),"Set wholesale margin"),'
           'IF(H{r}="Retail",IF(ISNUMBER(INDEX(\'Pricing\'!$H$6:$H$205,'
           'MATCH(C{r},\'Pricing\'!$A$6:$A$205,0))),INDEX(\'Pricing\'!$H$6:$H$205,'
           'MATCH(C{r},\'Pricing\'!$A$6:$A$205,0)),"Set retail margin"),"Select channel"))))', MONEY)
    o.fill("K", '=IF(OR(A{r}="",E{r}="",J{r}=""),"",ROUND(E{r}*J{r},2))', MONEY)
    o.fill("M", '=IF(K{r}="","",MAX(0,K{r}-L{r}))', MONEY)
    o.validation("C6:C205", source='INDIRECT("\'Batch Costs\'!$A$6:$A$205")')
    o.validation("G6:G205", ["Inquiry","Confirmed","Baking","Ready","Delivered","Cancelled"])
    o.validation("H6:H205", ["Retail","Wholesale"])
    o.validation("E6:E205", kind="whole", minimum=1)
    o.validation("J6:J205", kind="decimal", minimum=0)
    o.validation("L6:L205", kind="decimal", minimum=0)
    b.steps("7. Pricing: set separate retail (G) and wholesale (J) margins below 100%.",
            "8. Orders: choose the recipe and channel, then enter customer, quantity, due date and status.",
            "9. Review suggested price, enter the agreed unit price, and record the amount paid.",
            "10. Replace the Orders (example) row. Agreed prices stay fixed when recipe costs change.")
    b.check("Orders","D6","Cookies (example)")
    b.check("Orders","K6",30)
    b.check("Orders","M6",15)
    b.case([["Pricing","C6",10]], [["Pricing","H6",25],["Pricing","K6",15.39],
                                 ["Orders","I6",25],["Orders","K6",30]])
    b.case([["Orders","E6",24]], [["Orders","K6",60],["Orders","M6",45]])
    b.case([["Pricing","J6",1]], [["Pricing","K6",""]])

    b.case([["Orders","A205","Test order"],["Orders","E205",2],["Orders","J205",3],
            ["Orders","L205",0]],[["Orders","K205",6],["Orders","M205",6]])

def lawn(b):
    jobs, expenses, invoices = b["Job Schedule"], b["Expense Log"], b["Income Tracker"]
    routes = b.new_sheet("Route Profit", "Profit per route",
        ["Route","Billed revenue","Fuel","Chemicals used","Other costs","Profit","Route status"],
        [27,22,20,22,22,22,25],
        "All logged dates. Revenue is invoiced; chemical cost is use cost. Other costs exclude chemical purchases.",
        formulas=("B","C","D","E","F","G"))
    routes.input("A6","North (example)")
    routes.input("A7","South (example)")
    routes.put("A4","Unassigned rows",b.style("text"))
    for sheet, column in [(jobs,"J"),(expenses,"F")]:
        sheet.put(column+"5","Route",b.style("header"))
        sheet.width(column,27)
        for r in range(6,206):
            sheet.input(column+str(r), "North (example)" if r in (6,7) else
                        ("South (example)" if r==8 else
                         ("North (example)" if sheet is jobs and r==9 else None)))
        sheet.validation(column+"6:"+column+"205",source='INDIRECT("\'Route Profit\'!$A$6:$A$205")')
    for d in expenses.root.findall("x:dataValidations/x:dataValidation",NS):
        if d.get("sqref")=="C6:C205":
            d.find(tag("formula1")).text='"Fuel,Chemicals,Supplies,Equipment,Repairs,Insurance,Marketing,Other"'
    invoices.put("J5","Route",b.style("header"))
    invoices.width("J",27)
    invoices.fill("J", '=IF(A{r}="","",IF(COUNTIFS(\'Job Schedule\'!$A$6:$A$205,C{r})<>1,'
                  '"Check job ID",IF(INDEX(\'Job Schedule\'!$J$6:$J$205,'
                  'MATCH(C{r},\'Job Schedule\'!$A$6:$A$205,0))="","",'
                  'INDEX(\'Job Schedule\'!$J$6:$J$205,MATCH(C{r},\'Job Schedule\'!$A$6:$A$205,0)))))')
    t = b.new_sheet("Treatment Log","Chemical and treatment log",
        ["Date","Client ID","Client","Product / treatment","Amount","Unit","Use cost","Route","Note"],
        [16,17,28,28,14,14,20,27,42],
        "Record actual product use and its cost here. Record purchases as Chemicals in Expense Log.",
        formulas=("C",))
    t.row(6,[date(2026,10,5),"C001",None,"Lawn feed (example)",0.5,"L",5,
             "North (example)","Application (example)"],"input")
    t.column_format("A",DATE)
    t.column_format("E","0.00")
    t.column_format("G",MONEY)
    t.fill("C", '=IF(B{r}="","",IF(COUNTIFS(\'Customers\'!$A$6:$A$205,B{r})<>1,'
           '"Check client ID",INDEX(\'Customers\'!$B$6:$B$205,'
           'MATCH(B{r},\'Customers\'!$A$6:$A$205,0))))')
    t.validation("B6:B205",source='INDIRECT("\'Customers\'!$A$6:$A$205")')
    t.validation("H6:H205",source='INDIRECT("\'Route Profit\'!$A$6:$A$205")')
    t.validation("F6:F205",["mL","L","g","kg","oz","lb","each","Other"])
    t.validation("E6:E205",kind="decimal",minimum=0)
    t.validation("G6:G205",kind="decimal",minimum=0)
    routes.fill("B", '=IF(A{r}="","",SUMIFS(\'Income Tracker\'!$E$6:$E$205,'
                '\'Income Tracker\'!$J$6:$J$205,A{r}))',MONEY)
    routes.fill("C", '=IF(A{r}="","",SUMIFS(\'Expense Log\'!$E$6:$E$205,'
                '\'Expense Log\'!$F$6:$F$205,A{r},\'Expense Log\'!$C$6:$C$205,"Fuel"))',MONEY)
    routes.fill("D", '=IF(A{r}="","",SUMIFS(\'Treatment Log\'!$G$6:$G$205,'
                '\'Treatment Log\'!$H$6:$H$205,A{r}))',MONEY)
    routes.fill("E", '=IF(A{r}="","",SUMIFS(\'Expense Log\'!$E$6:$E$205,'
                '\'Expense Log\'!$F$6:$F$205,A{r},\'Expense Log\'!$C$6:$C$205,"<>Fuel",'
                '\'Expense Log\'!$C$6:$C$205,"<>Chemicals"))',MONEY)
    routes.fill("F", '=IF(A{r}="","",IF(COUNTIFS($A$6:$A$205,A{r})=1,B{r}-C{r}-D{r}-E{r},""))',MONEY)
    routes.fill("G", '=IF(A{r}="","",IF(COUNTIFS($A$6:$A$205,A{r})=1,"Ready","Duplicate route"))')
    routes.formula("B4", '=COUNTIFS(\'Income Tracker\'!$A$6:$A$205,"<>",'
                   '\'Income Tracker\'!$J$6:$J$205,"")+COUNTIFS(\'Expense Log\'!$A$6:$A$205,">0",'
                   '\'Expense Log\'!$F$6:$F$205,"")+COUNTIFS(\'Treatment Log\'!$A$6:$A$205,">0",'
                   '\'Treatment Log\'!$H$6:$H$205,"")',"0")
    for name, helper, start, length in [
            ("Weekly Schedule","K",date(2026,10,12),7),
            ("Monthly Schedule","L",date(2026,10,1),None)]:
        v = b.new_sheet(name,name.lower().capitalize(),
            ["Job ID","Visit date","Customer","Address","Service","Agreed price","Status","Route","Notes"],
            [17,16,28,34,23,20,17,27,40],
            "Choose the period in B4. Jobs appear by visit date; cancelled jobs are omitted.",
            formulas=tuple("ABCDEFGHI"))
        v.put("A4","Week starting Monday" if length else "Month starting",b.style("text"))
        v.input("B4",start,DATE)
        v.put("C4","Illustrative period (example).",b.style("note"))
        v.validation("B4",kind="custom",source="AND(ISNUMBER(B4),WEEKDAY(B4,2)=1)" if length
                     else "AND(ISNUMBER(B4),DAY(B4)=1)")
        begin="'%s'!$B$4" % name
        end=begin+"+7" if length else "EDATE("+begin+",1)"
        jobs.put(helper+"5",name+" position",b.style("header"))
        jobs.width(helper,18)
        jobs.fill(helper, '=IF(AND(A{r}<>"",ISNUMBER(B{r}),B{r}>='+begin+',B{r}<'+end+
                  ',H{r}<>"Cancelled"),COUNTIFS($B$6:$B$205,">="&'+begin+
                  ',$B$6:$B$205,"<"&B{r},$A$6:$A$205,"<>",$H$6:$H$205,"<>Cancelled")'
                  '+COUNTIFS($B$6:B{r},B{r},$A$6:A{r},"<>",$H$6:H{r},"<>Cancelled"),"")',"0")
        v.fill("J", '=IF(COUNTIFS(\'Job Schedule\'!$'+helper+'$6:$'+helper+
               '$205,ROW()-5)=0,"",MATCH(ROW()-5,\'Job Schedule\'!$'+helper+
               '$6:$'+helper+'$205,0))',"0")
        for dest, source in zip("ABCDEFGHI",["A","B","D","E","F","G","H","J","I"]):
            lookup="INDEX('Job Schedule'!$%s$6:$%s$205,$J{r})" % (source,source)
            v.fill(dest, '=IF($J{r}="","",IF('+lookup+'="","",'+lookup+'))',
                   DATE if dest=="B" else MONEY if dest=="F" else None)
        v.width("J",12)
        for sheet, column in [(jobs,helper),(v,"J")]:
            cols=sheet.root.find(tag("cols"))
            next(c for c in cols if c.get("min")==str(sum(
                (ord(ch)-64)*26**i for i,ch in enumerate(column[::-1])))).set("hidden","1")
    for sheet, last in [(jobs,"J"),(expenses,"F"),(invoices,"J")]:
        af=sheet.root.find(tag("autoFilter"))
        if af is not None:
            af.set("ref","A5:"+last+"205")
    b.steps("7. Route Profit: enter unique route names. Assign every job and expense to a route.",
            "8. Weekly Schedule: choose a Monday. Monthly Schedule: choose the first of a month.",
            "9. Treatment Log: record client, product, amount, unit, use cost, date and route.",
            "10. Tag chemical purchases Chemicals in Expense Log. Route profit counts use cost once.",
            "11. Route profit uses all-date billed revenue less fuel, chemical use and other costs.")
    b.check("Route Profit","F6",90)
    b.check("Route Profit","F7",20)
    b.check("Weekly Schedule","A6","J003")
    b.check("Monthly Schedule","A9","J004")
    b.case([["Job Schedule","B9",serial(date(2026,10,3))]],
           [["Monthly Schedule","A6","J004"]])
    b.case([["Job Schedule","H8","Cancelled"]],[["Weekly Schedule","A6",""]])
    b.case([["Treatment Log","G6",10]],[["Route Profit","F6",85]])

    b.case([["Job Schedule","B9",serial(date(2026,11,1))]],[["Monthly Schedule","A9",""]])
    b.case([["Job Schedule","A205","Test visit"],["Job Schedule","B205",serial(date(2026,10,16))],
            ["Job Schedule","C205","C001"],["Job Schedule","H205","Planned"]],
           [["Weekly Schedule","A7","Test visit"]])

def pets(b):
    visits = b["Bookings and Visits"]
    for c, title in zip("LMNOPQ",["Travel cost","Supplies cost","Labor cost",
                                 "Other cost","Total visit cost","Visit profit"]):
        visits.put(c+"5",title,b.style("header"))
        visits.width(c,21)
    for c, values in {"L":[3,2,0,5],"M":[1,1,0,2],
                      "N":[10,8,0,25],"O":[0,0,0,0]}.items():
        for r in range(6,206):
            visits.input(c+str(r),values[r-6] if r<10 else None,MONEY)
        visits.validation(c+"6:"+c+"205",kind="decimal",minimum=0)
    visits.fill("P", '=IF(A{r}="","",IF(AND(ISNUMBER(L{r}),ISNUMBER(M{r}),'
                'ISNUMBER(N{r}),ISNUMBER(O{r})),SUM(L{r}:O{r}),""))',MONEY)
    visits.fill("Q", '=IF(OR(A{r}="",P{r}=""),"",IF(J{r}="Completed",'
                'IF(ISNUMBER(I{r}),I{r}-P{r},""),IF(J{r}="Cancelled",-P{r},"")))',MONEY)
    af=visits.root.find(tag("autoFilter"))
    if af is not None:
        af.set("ref","A5:Q205")
    meds=b.new_sheet("Medication Schedule","Medication schedule per pet",
        ["Entry ID","Pet ID","Pet","Due date","Due time","Medication",
         "Owner / vet instructions","Status","Given at","Notes","Follow-up"],
        [18,17,25,16,16,29,48,17,24,38,29],
        "One row per scheduled dose. Copy the owner's or vet's medication and dose instructions.",
        formulas=("C","K"))
    meds.row(6,["MED001","P001",None,EXAMPLE_DATE,0.375,
                "Owner medication (example)","Copy owner/vet instructions (example)",
                "Pending",None,"Schedule entry (example)",None],"input")
    meds.column_format("D",DATE)
    meds.column_format("E","h:mm AM/PM")
    meds.column_format("I","m/d/yyyy h:mm AM/PM")
    meds.fill("C", '=IF(B{r}="","",IF(COUNTIFS(\'Pet Profiles\'!$A$6:$A$205,B{r})<>1,'
              '"Check pet ID",INDEX(\'Pet Profiles\'!$C$6:$C$205,'
              'MATCH(B{r},\'Pet Profiles\'!$A$6:$A$205,0))))')
    meds.fill("K", '=IF(A{r}="","",IF(OR(B{r}="",D{r}="",E{r}="",F{r}="",G{r}=""),'
              '"Complete schedule",IF(H{r}="Given",IF(I{r}="","Record given time","Recorded"),'
              'IF(H{r}="Cancelled","Cancelled",IF(H{r}="Skipped","Record reason in notes",'
              'IF(D{r}+E{r}<NOW(),"Due / overdue","Scheduled"))))))')
    meds.validation("B6:B205",source='INDIRECT("\'Pet Profiles\'!$A$6:$A$205")')
    meds.validation("H6:H205",["Pending","Given","Skipped","Cancelled"])
    meds.validation("E6:E205",kind="decimal",minimum=0,maximum=0.999999)
    access=b.new_sheet("Key and Access Log","Key and access log",
        ["Record ID","Client ID","Client","Key / tag","Code","Handed over",
         "Returned","Held by","Status","Notes"],
        [18,17,27,29,24,20,20,27,25,42],
        "Use a separate row for each key handover or access arrangement. Codes are stored as text.",
        formulas=("C","I"))
    access.row(6,["KEY001","C001",None,"Blue tag (example)","0000 (example)",
                  date(2026,10,15),None,"Walker (example)",None,
                  "Example access only (example)"],"input")
    for c in ("F","G"):
        access.column_format(c,DATE)
    access.column_format("E","@")
    access.fill("C", '=IF(B{r}="","",IF(COUNTIFS(\'Clients\'!$A$6:$A$205,B{r})<>1,'
                '"Check client ID",INDEX(\'Clients\'!$B$6:$B$205,'
                'MATCH(B{r},\'Clients\'!$A$6:$A$205,0))))')
    access.fill("I", '=IF(A{r}="","",IF(F{r}="","Awaiting handover",IF(G{r}="",'
                '"Held",IF(G{r}<F{r},"Check dates","Returned"))))')
    access.validation("B6:B205",source='INDIRECT("\'Clients\'!$A$6:$A$205")')
    b.steps("7. Medication Schedule: add one row per pet dose, with due date/time and owner/vet instructions.",
            "8. Update dose status and Given at. Check Follow-up for missing records or overdue doses.",
            "9. Key and Access Log: record key, code, holder, handover and return dates by client.",
            "10. Bookings and Visits: enter travel, supplies, labor and other costs. Enter 0 when unused.",
            "11. Visit profit uses completed charges. Cancelled visits show costs as a loss.")
    b.check("Bookings and Visits","Q6",11)
    b.check("Bookings and Visits","Q7",9)
    b.check("Bookings and Visits","Q8","")
    b.check("Medication Schedule","C6","Milo (example)")
    b.check("Key and Access Log","I6","Held")
    b.case([["Bookings and Visits","J6","Cancelled"]],[["Bookings and Visits","Q6",-14]])
    b.case([["Bookings and Visits","L6",None]],[["Bookings and Visits","Q6",""]])
    b.case([["Medication Schedule","H6","Given"]],[["Medication Schedule","K6","Record given time"]])
    b.case([["Key and Access Log","G6",serial(EXAMPLE_DATE)]],[["Key and Access Log","I6","Returned"]])

    b.case([["Medication Schedule","H6","Given"],
            ["Medication Schedule","I6",serial(EXAMPLE_DATE)+0.375]],
           [["Medication Schedule","K6","Recorded"]])
    b.case([["Key and Access Log","G6",serial(date(2026,10,14))]],
           [["Key and Access Log","I6","Check dates"]])

def wedding(b):
    guests=b.new_sheet("Guest List","Guest list and RSVPs",
        ["Guest ID","Guest","Household","RSVP","Meal","Dietary notes","Contact","Notes"],
        [17,28,27,19,21,37,30,38],
        "One row per person, including plus-ones. Replace the (example) rows before using counts.")
    for r, values in enumerate([
            ["G001","Alex (example)","Lane (example)","Accepted","Vegetarian",
             "Confirm requirements (example)","alex@example.invalid","Guest (example)"],
            ["G002","Jamie (example)","Lane (example)","Accepted","Chicken",
             "", "jamie@example.invalid","Guest (example)"],
            ["G003","Morgan (example)","Brook (example)","No response","Not selected",
             "", "morgan@example.invalid","Guest (example)"]],6):
        guests.row(r,values,"input")
    guests.validation("D6:D205",["No response","Accepted","Declined"])
    guests.validation("E6:E205",["Not selected","Chicken","Fish","Beef","Vegetarian","Vegan","Child","Other"])
    guests.put("A4","Accepted",b.style("text"))
    guests.formula("B4",'=COUNTIFS($D$6:$D$205,"Accepted")',"0")
    guests.put("C4","Awaiting RSVP",b.style("text"))
    guests.formula("D4",'=COUNTIFS($A$6:$A$205,"<>",$D$6:$D$205,"No response")'
                   '+COUNTIFS($A$6:$A$205,"<>",$D$6:$D$205,"")',"0")
    seats=b.new_sheet("Seating Plan","Seating plan",
        ["Guest ID","Guest","RSVP","Meal","Table","Seat","Seating status"],
        [17,28,19,21,27,12,30],
        "Assign each accepted guest once. Table and seat combinations must be unique.",
        formulas=("B","C","D","G"))
    for r in (6,7):
        seats.input("A%d"%r,"G00%d"%(r-5))
        seats.input("E%d"%r,"Table 1 (example)")
        seats.input("F%d"%r,r-5,"0")
    for dest,source in [("B","B"),("C","D"),("D","E")]:
        seats.fill(dest,'=IF(A{r}="","",IF(COUNTIFS(\'Guest List\'!$A$6:$A$205,A{r})<>1,'
                   '"Check guest ID",INDEX(\'Guest List\'!$'+source+'$6:$'+source+
                   '$205,MATCH(A{r},\'Guest List\'!$A$6:$A$205,0))))')
    seats.fill("G",'=IF(A{r}="","",IF(COUNTIFS(\'Guest List\'!$A$6:$A$205,A{r})<>1,'
               '"Check guest ID",IF(C{r}<>"Accepted","Check RSVP",'
               'IF(COUNTIFS($A$6:$A$205,A{r})>1,"Guest seated twice",'
               'IF(OR(E{r}="",F{r}=""),"Assign table and seat",'
               'IF(COUNTIFS($E$6:$E$205,E{r},$F$6:$F$205,F{r})>1,"Seat used twice","Seated"))))))')
    seats.validation("A6:A205",source='INDIRECT("\'Guest List\'!$A$6:$A$205")')
    seats.validation("F6:F205",kind="whole",minimum=1)
    seats.column_format("F","0")
    timeline=b.new_sheet("Timeline","Wedding timeline",
        ["Event ID","Date","Start time","End time","Event / task","Location","Owner","Status","Notes"],
        [17,16,16,16,33,29,27,20,40],
        "Enter events in date/time order. Example dates link to the wedding date on Start Here.")
    timeline.column_format("B",DATE)
    for c in ("C","D"):
        timeline.column_format(c,"h:mm AM/PM")
    for r, values in enumerate([
            ["T001",None,0.5,0.5416666667,"Setup (example)","Venue (example)","Planner (example)","Confirmed","Setup details (example)"],
            ["T002",None,0.5833333333,0.625,"Ceremony (example)","Venue (example)","Couple (example)","Confirmed","Ceremony details (example)"],
            ["T003",None,0.6666666667,0.875,"Reception (example)","Venue (example)","Planner (example)","Not started","Reception details (example)"]],6):
        for i,value in enumerate(values,1):
            timeline.input(col(i)+str(r),value,DATE if i==2 else "h:mm AM/PM" if i in (3,4) else None)
        timeline.formula("B%d"%r,"='Start Here'!$B$18",DATE)
    timeline.validation("H6:H205",["Not started","Confirmed","In progress","Done","Cancelled"])
    payers=b.new_sheet("Payers","Totals per payer",
        ["Payer","Planned allocation","Agreed allocation","Paid by payer","Agreed amount left"],
        [30,24,24,24,25],
        "Allocations are responsibilities. Paid by payer uses Payment Log, separate from savings contributions.",
        formulas=("B","C","D","E"))
    payers.put("A4","Unassigned payments",b.style("text"))
    payers.formula("B4",'=COUNTIFS(\'Payment Log\'!$A$6:$A$205,">0",'
                   '\'Payment Log\'!$F$6:$F$205,"")',"0")
    for r,name in enumerate(["Couple (example)","Family A (example)","Family B (example)"],6):
        payers.input("A%d"%r,name)
    split=b.new_sheet("Who Pays","Who pays each budget line",
        ["Budget category","Payer","Share","Planned allocation","Agreed allocation","Split status"],
        [27,30,16,24,24,30],
        "Use multiple rows to split a category. Shares for each Wedding Budget line must total 100%.",
        formulas=("D","E","F"))
    rows=[["Venue","Couple (example)",0.5],["Venue","Family A (example)",0.5],
          ["Catering","Couple (example)",0.5],["Catering","Family B (example)",0.5]]
    rows += [[b["Wedding Budget"].value("A%d"%r),"Couple (example)",1] for r in range(8,14)]
    for r,values in enumerate(rows,6):
        split.row(r,values,"input")
    split.column_format("C",PERCENT)
    split.validation("A6:A205",source='INDIRECT("\'Wedding Budget\'!$A$6:$A$13")')
    split.validation("B6:B205",source='INDIRECT("\'Payers\'!$A$6:$A$205")')
    split.validation("C6:C205",kind="decimal",minimum=0,maximum=1)
    for dest,source in [("D","B"),("E","C")]:
        split.fill(dest,'=IF(A{r}="","",IF(AND(COUNTIFS(\'Wedding Budget\'!$A$6:$A$13,A{r})=1,'
                   'COUNTIFS(\'Payers\'!$A$6:$A$205,B{r})=1,ISNUMBER(C{r}),C{r}>=0,C{r}<=1),'
                   'ROUND(INDEX(\'Wedding Budget\'!$'+source+'$6:$'+source+
                   '$13,MATCH(A{r},\'Wedding Budget\'!$A$6:$A$13,0))*C{r},2),""))',MONEY)
    split.fill("F",'=IF(A{r}="","",IF(COUNTIFS(\'Wedding Budget\'!$A$6:$A$13,A{r})<>1,'
               '"Check category",IF(COUNTIFS(\'Payers\'!$A$6:$A$205,B{r})<>1,"Check payer",'
               'IF(OR(NOT(ISNUMBER(C{r})),C{r}<0,C{r}>1),"Enter valid share",'
               'IF(ABS(SUMIFS($C$6:$C$205,$A$6:$A$205,A{r})-1)>0.000001,"Check category split","Ready")))))')
    budget=b["Wedding Budget"]
    for c,title in [("G","Allocated share"),("H","Unallocated planned"),("I","Split status"),("J","Unallocated agreed")]:
        budget.put(c+"5",title,b.style("header"))
        budget.width(c,24)
    budget.fill("G",'=SUMIFS(\'Who Pays\'!$C$6:$C$205,\'Who Pays\'!$A$6:$A$205,A{r})',PERCENT,end=13)
    budget.fill("H",'=B{r}-SUMIFS(\'Who Pays\'!$D$6:$D$205,\'Who Pays\'!$A$6:$A$205,A{r})',MONEY,end=13)
    budget.fill("J",'=C{r}-SUMIFS(\'Who Pays\'!$E$6:$E$205,\'Who Pays\'!$A$6:$A$205,A{r})',MONEY,end=13)
    budget.fill("I",'=IF(ABS(G{r}-1)>0.000001,IF(G{r}>1,"Overallocated","Allocate balance"),'
                'IF(OR(ABS(H{r})>0.005,ABS(J{r})>0.005),"Check payer / rounding","Allocated"))',end=13)
    payments=b["Payment Log"]
    payments.put("F5","Paid by",b.style("header"))
    payments.width("F",30)
    for r in range(6,206):
        payments.input("F%d"%r,"Family A (example)" if r==6 else
                       ("Couple (example)" if r in (7,8) else None))
    payments.validation("F6:F205",source='INDIRECT("\'Payers\'!$A$6:$A$205")')
    for dest,source in [("B","D"),("C","E")]:
        payers.fill(dest,'=IF(A{r}="","",SUMIFS(\'Who Pays\'!$'+source+'$6:$'+source+
                    '$205,\'Who Pays\'!$B$6:$B$205,A{r}))',MONEY)
    payers.fill("D",'=IF(A{r}="","",SUMIFS(\'Payment Log\'!$D$6:$D$205,'
                '\'Payment Log\'!$F$6:$F$205,A{r}))',MONEY)
    payers.fill("E",'=IF(A{r}="","",C{r}-D{r})',MONEY)
    b.steps("7. Guest List: enter one person per row and update RSVP, meal and dietary notes.",
            "8. Seating Plan: select accepted guests and assign table/seat. Resolve duplicate-seat flags.",
            "9. Timeline: add dates, start/end times, events, locations, owners and progress.",
            "10. Payers: enter unique names. Who Pays: split each budget category into shares totaling 100%.",
            "11. Review Wedding Budget split checks. Payment Log Paid by drives each payer's paid total.",
            "12. Payer allocations are responsibilities. Contributions and savings still track funds received.")
    b.check("Guest List","B4",2)
    b.check("Seating Plan","G6","Seated")
    b.check("Wedding Budget","I6","Allocated")
    b.check("Payers","B7",1500)
    b.check("Payers","D7",1000)
    b.case([["Seating Plan","F7",1]],[["Seating Plan","G6","Seat used twice"]])
    b.case([["Guest List","D6","Declined"]],[["Seating Plan","G6","Check RSVP"]])
    b.case([["Who Pays","C6",0.25]],[["Wedding Budget","H6",750],
                                    ["Wedding Budget","I6","Allocate balance"]])

    b.case([["Who Pays","A205","Venue"],["Who Pays","B205","Family A (example)"],
            ["Who Pays","C205",0.1]],[["Who Pays","D205",300],
                                    ["Wedding Budget","I6","Overallocated"]])
    b.case([["Guest List","A205","G205"],["Guest List","B205","Test guest"],
            ["Guest List","D205","Accepted"],["Guest List","E205","Vegan"],
            ["Seating Plan","A205","G205"],["Seating Plan","E205","Test table"],
            ["Seating Plan","F205",1]],[["Seating Plan","B205","Test guest"],
                                      ["Seating Plan","G205","Seated"]])

EXCEL_SCRIPT = r"""
$ErrorActionPreference = 'Stop'
$spec = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__SPEC__')) | ConvertFrom-Json
$app = $null
$book = $null
function Assert-Cells($checks) {
    foreach ($check in $checks) {
        $value = $book.Worksheets.Item([string]$check[0]).Range([string]$check[1]).Value2
        $expected = $check[2]
        if ($expected -is [string]) {
            if ([string]$value -cne $expected) {
                throw "Unexpected result at $($check[0])!$($check[1]): $value; expected $expected"
            }
        } elseif ($null -eq $value -or [Math]::Abs([double]$value - [double]$expected) -gt 0.000001) {
            throw "Unexpected result at $($check[0])!$($check[1]): $value; expected $expected"
        }
    }
}
try {
    $app = New-Object -ComObject Excel.Application
    $app.Visible = $false
    $app.DisplayAlerts = $false
    $app.EnableEvents = $false
    $app.AskToUpdateLinks = $false
    $app.AutomationSecurity = 3
    $book = $app.Workbooks.Open([string]$spec.path, 0, $false)
    $app.CalculateFullRebuild()
    Assert-Cells $spec.checks
    foreach ($case in $spec.cases) {
        $saved = @()
        try {
            foreach ($change in $case.changes) {
                $cell = $book.Worksheets.Item([string]$change[0]).Range([string]$change[1])
                $saved += ,@($change[0], $change[1], $cell.Formula)
                $cell.Value2 = $change[2]
            }
            $app.CalculateFullRebuild()
            Assert-Cells $case.checks
        } finally {
            foreach ($entry in $saved) {
                $book.Worksheets.Item([string]$entry[0]).Range([string]$entry[1]).Formula = $entry[2]
            }
            $app.CalculateFullRebuild()
        }
    }
    Assert-Cells $spec.checks
    foreach ($sheet in $book.Worksheets) {
        $address = $sheet.UsedRange.Address($false, $false)
        $count = $sheet.Evaluate("SUMPRODUCT(--ISERROR($address))")
        if ($null -eq $count -or [double]$count -ne 0) {
            throw "Formula errors on $($sheet.Name): $count"
        }
    }
    $book.Save()
} finally {
    if ($null -ne $book) {
        $book.Close($false)
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($book)
    }
    if ($null -ne $app) {
        $app.Quit()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
"""

def recalculate_with_excel(path, book):
    spec = json.dumps({"path":str(path.resolve()), "checks":book.checks,
                       "cases":book.cases}, ensure_ascii=True)
    script = EXCEL_SCRIPT.replace("__SPEC__", base64.b64encode(spec.encode()).decode())
    encoded = base64.b64encode(script.encode("utf-16le")).decode()
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive",
                             "-EncodedCommand", encoded],
                            capture_output=True, text=True, timeout=180,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if result.returncode:
        raise RuntimeError("Excel recalculation failed for %s. Stop before the next workbook.\n%s"
                           % (path.name, result.stderr.strip()))
    with ZipFile(path) as z:
        for name in z.namelist():
            if name.startswith("xl/worksheets/") and name.endswith(".xml"):
                root = ET.fromstring(z.read(name))
                bad = [c.get("r") for c in root.findall(".//x:c",NS) if c.get("t")=="e"]
                if bad:
                    raise RuntimeError("Saved formula errors: %s %s" % (name, bad[:5]))

WORKBOOKS = [
    ("Freelancer-Irregular-Income-Budget.xlsx", freelancer),
    ("Home-Bakery-Pricing-Calculator.xlsx", bakery),
    ("Lawn-Care-Business-Tracker.xlsx", lawn),
    ("Pet-Sitting-Dog-Walking-Tracker.xlsx", pets),
    ("Wedding-Budget-Planner.xlsx", wedding),
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder",type=Path,default=Path(__file__).resolve().parent)
    parser.add_argument("--only", choices=[name for name, _ in WORKBOOKS],
                        help="Process one original; useful when resuming after a stopped check.")
    parser.add_argument("--check-only",action="store_true",
                        help="Build and inspect XML/ZIP structures in memory; do not save or start Excel.")
    args = parser.parse_args()
    selected = [(name, build) for name, build in WORKBOOKS if not args.only or name == args.only]
    for name, _ in selected:
        if not (args.folder/name).is_file():
            raise FileNotFoundError(args.folder/name)
        target = args.folder/(Path(name).stem+"-v2.xlsx")
        if not args.check_only and target.exists():
            raise FileExistsError("Refusing to overwrite: "+str(target))
    for name, build in selected:
        source = args.folder/name
        book = Book(source)
        build(book)
        raw = book.verify()
        target = source.with_name(source.stem+"-v2.xlsx")
        if args.check_only:
            print(name+": XML/ZIP and reference checks passed in memory.")
            continue
        # Exclusive creation protects both originals and pre-existing v2 copies.
        with target.open("xb") as handle:
            handle.write(raw)
        recalculate_with_excel(target, book)
        if hashlib.sha256(source.read_bytes()).hexdigest() != book.original_hash:
            raise RuntimeError("Original changed unexpectedly: "+str(source))
        print(target.name+": saved, recalculated and formula checks passed.")
        # Finish saving and checking this copy before opening the next original.

if __name__ == "__main__":
    main()
