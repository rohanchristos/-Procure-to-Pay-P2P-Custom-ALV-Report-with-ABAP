# SAP ABAP Custom ALV Purchase Order (P2P) Tracking Report

**Capstone Project | Rohan Ghosh | Roll No: 2328190 | Batch: 2027 SAP (OE)**  
**Specialization: SAP ABAP Backend Development**

---

## Problem Statement

Standard SAP transaction **ME2M** provides a basic list of purchase orders but lacks real-time GR/IR matching, color-coded delivery health indicators, and interactive subtotals that procurement teams need for day-to-day operations.

Finance and purchasing teams need a **single consolidated view** of the entire Procure-to-Pay (P2P) cycle — showing which POs are overdue, how much quantity has been received (GR), how much is still open, and the net value at risk — all in one interactive screen with direct export capability.

This project builds a **Custom ALV (ABAP List Viewer) Report** that retrieves data from `EKKO`, `EKPO`, `LFA1`, and `EKBE`, applies user-defined selection filters, computes real-time open quantities, and presents the result in a feature-rich ALV Grid with color-coded delivery status indicators.

---

## Solution & Features

### Selection Screen

| Parameter | Description |
|-----------|-------------|
| `SO_AEDAT` | PO Creation Date range *(Obligatory)* |
| `SO_EBELN` | Purchase Order Number range |
| `SO_LIFNR` | Vendor Number range |
| `SO_EKGRP` | Purchasing Group |
| `SO_MATNR` | Material Number range |
| `P_WERKS`  | Plant *(default: 1000)* |
| `P_OPEN`   | Show Open POs Only checkbox *(default: checked)* |

---

### Data Retrieval

Optimized `SELECT ... INNER JOIN` across four SAP database tables:

| Table | Description |
|-------|-------------|
| `EKKO` | Purchase Order Header |
| `EKPO` | Purchase Order Item |
| `LFA1` | Vendor Master (General Data) |
| `EKBE` | PO History — used to aggregate Goods Receipt quantities via `SUM(MENGE)` with `GROUP BY` |

A second `FOR ALL ENTRIES IN` query fetches GR data efficiently — avoiding nested loops and N+1 query problems.

---

### Color-Coded Delivery Health

| Color | Condition | ALV Key |
|-------|-----------|---------|
| 🔴 Red | PO delivery date is in the past AND quantity is still open (OVERDUE) | `C610` |
| 🟡 Yellow | Delivery date is within the next 14 days (DUE SOON) | `C510` |
| 🟢 Green | On track / fully received | `C310` |

Color logic is computed at runtime using `SY-DATUM` vs `EINDT` (scheduled delivery date), giving a **live** delivery health dashboard.

---

### ALV Grid Capabilities

- Dynamic field catalog generated at runtime using `REUSE_ALV_FIELDCATALOG_MERGE` — no hard-coding required
- **Subtotals and grand totals** on Net Value (`NETWR`) and Open Quantity (`OPEN_QTY`) grouped by Vendor
- Zebra striping and auto-fit column widths via `LVC_S_LAYO`
- Pre-sorted by Vendor → PO Number with automatic **subtotal break** per vendor
- Saveable ALV layout variants per user (standard SAP variant management)
- Direct export to Excel (`.xlsx`) and PDF from SAP GUI toolbar
- Multi-row selection mode for bulk actions

---

## Tech Stack

| Component | Details |
|-----------|---------|
| SAP Platform | SAP ECC 6.0 / S/4HANA 2022 |
| Language | ABAP Release 7.50+ |
| Development Transaction | SE38 — ABAP Editor |
| Screen | SE51 — Screen Painter (Screen 100 with Custom Container) |
| UI Technology | ALV Grid Control — `CL_GUI_ALV_GRID` |
| Container | `CL_GUI_CUSTOM_CONTAINER` |
| Function Modules | `REUSE_ALV_FIELDCATALOG_MERGE`, `REUSE_ALV_EVENTS_GET` |
| Database Tables | `EKKO`, `EKPO`, `LFA1`, `EKBE` |
| Transport Layer | SAP CTS — Package `ZREPORTS` |
| Testing | SE38 → F8 Execute, ABAP Debugger (ST05 for SQL trace) |

---

## Code Structure

```
SAP-ABAP-Custom-ALV-PO-Tracker/
├── Z_CUSTOM_ALV_PO_TRACKER.abap    ← Full ABAP source code
├── Project_Report.pdf               ← Full project documentation (4–5 pages)
├── Screenshots/
│   ├── Fig1_SE38_Editor.png         ← Source code in SE38 with syntax check
│   ├── Fig2_Selection_Screen.png    ← Parameter input screen
│   ├── Fig3_ALV_Grid_Output.png     ← ALV output with all columns
│   ├── Fig4_Color_Coding.png        ← Red/Yellow/Green rows
│   ├── Fig5_Subtotals.png           ← Net Value and Qty totals per vendor
│   └── Fig6_Export_to_Excel.png     ← Local file export .xlsx
└── README.md
```

---

## Step-by-Step Development Guide

The program is structured in **7 clearly separated steps** — all visible as section comments in the source code:

1. **SE38 Setup** — Create executable report `Z_CUSTOM_ALV_PO_TRACKER` in package `ZREPORTS`. Assign to transport request.

2. **Global Declarations** — Define the `ty_po_tracker` structure including calculated fields (`gr_qty`, `open_qty`, `days_open`, `color`, `status`). Declare ALV object references.

3. **Selection Screen** — User-facing `SELECT-OPTIONS` block with obligatory date range, optional vendor/material filters, and plant parameter.

4. **Data Fetch** — Three-table `INNER JOIN` on `EKKO + EKPO + LFA1`. Followed by a `FOR ALL ENTRIES IN` query on `EKBE` to aggregate GR quantities with `SUM(MENGE) GROUP BY`.

5. **Business Logic** — `LOOP AT it_po_tracker`: compute open quantity (`menge - gr_qty`), calculate `days_open` from `SY-DATUM`, assign row color key based on `EINDT` vs `SY-DATUM`, assign status text. Delete fully received rows if `P_OPEN` flag is set.

6. **Field Catalog** — Call `REUSE_ALV_FIELDCATALOG_MERGE`, then loop and customize: set `KEY`, `DO_SUM`, `NO_OUT`, column texts, output lengths, and currency reference fields.

7. **ALV Display** — Configure `LVC_S_LAYO` (zebra, auto-width, color binding, title), define sort/subtotal criteria on `LIFNR`, create `CL_GUI_CUSTOM_CONTAINER` and `CL_GUI_ALV_GRID`, call `SET_TABLE_FOR_FIRST_DISPLAY`.

---

## Unique Highlights

| Feature | Description |
|---------|-------------|
| **GR/IR Matching at Report Runtime** | Uses `FOR ALL ENTRIES IN` + `SUM(MENGE)` on `EKBE` — no manual BAPI calls needed. Open quantity is computed live. |
| **Business-Logic-Driven Colors** | Row color derived from `EINDT` (delivery date) vs `SY-DATUM` — not a static flag, so it automatically turns red as the clock ticks. |
| **Declarative Subtotals** | `DO_SUM = 'X'` in field catalog plus a sort entry with `SUBTOT = 'X'` produces vendor-wise subtotals with zero manual aggregation code. |
| **Open PO Filter** | `P_OPEN` checkbox removes fully-received lines before display — reducing noise for buyers who only care about outstanding deliveries. |
| **Modular FORM Structure** | `F_BUILD_FCAT` and `F_DISPLAY_ALV` follow SAP ABAP coding standards: single responsibility, no side effects. |
| **SQL Optimization** | `FOR ALL ENTRIES IN` for `EKBE` avoids a full table scan and prevents Cartesian product in the join. |

---

## Screenshots

> Upload SAP GUI screenshots to the `Screenshots/` folder. Recommended captions:

| Fig. | Description |
|------|-------------|
| Fig. 1 | SE38 Editor — source code open, syntax check passed (green bar) |
| Fig. 2 | Selection Screen — date range, Plant, Vendor, Material inputs |
| Fig. 3 | ALV Grid Output — all columns visible with zebra striping |
| Fig. 4 | Color Coding — red overdue POs, yellow due-soon, green on-track |
| Fig. 5 | Subtotals — Net Value and Open Qty aggregated per Vendor |
| Fig. 6 | Export — Local File dialog generating `.xlsx` |

---

## Future Improvements

| Enhancement | Description |
|-------------|-------------|
| **CDS View Migration** | Replace `SELECT` with an ABAP CDS View exposing `@Analytics.dataCategory: #CUBE` for S/4HANA Clean Core compliance |
| **Fiori Analytical List Page** | Expose CDS as OData V4 service and build an ALP in SAP BAS with KPI tiles for overdue PO count and at-risk spend |
| **Automated Email Alerts** | Schedule as background job (SM36) to email the overdue PO list to the purchasing manager every morning at 06:00 |
| **Configurable Thresholds** | Store the "14-day warning" threshold in a custom Z-table (`Z_PO_CONFIG`) so admins can adjust without code changes |
| **Audit Trail Logging** | Log every report execution (user, timestamp, selection criteria, record count) to `Z_PO_AUDIT_LOG` for SOX compliance |
| **BAPI Integration** | Add a custom toolbar button to trigger `BAPI_PO_CHANGE` and close overdue PO items directly from the report |

---

## How to Execute

1. Log into SAP GUI and open **SE38**
2. Enter program name: `Z_CUSTOM_ALV_PO_TRACKER`
3. Press **F8** (Execute)
4. Enter a PO Creation Date range on the selection screen
5. Press **F8** again to run the report
6. Use the ALV toolbar to sort, filter, export to Excel, or save a layout variant

---

## Key SAP Tables Reference

| Table | Description | Key Fields Used |
|-------|-------------|-----------------|
| `EKKO` | PO Header | `EBELN`, `AEDAT`, `LIFNR`, `EKGRP`, `WAERS`, `LOEKZ`, `BSTYP` |
| `EKPO` | PO Item | `EBELN`, `EBELP`, `WERKS`, `MATNR`, `MENGE`, `NETWR`, `EINDT`, `LOEKZ` |
| `LFA1` | Vendor Master | `LIFNR`, `NAME1` |
| `EKBE` | PO History | `EBELN`, `EBELP`, `MENGE`, `VGABE` (GR=1), `SHKZG` (debit=S) |

---

*Submitted as part of the SAP ABAP Capstone Project — April 2026*
