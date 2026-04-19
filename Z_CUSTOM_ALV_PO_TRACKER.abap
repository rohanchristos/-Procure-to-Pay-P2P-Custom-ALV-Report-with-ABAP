*&---------------------------------------------------------------------*
*& Report  Z_CUSTOM_ALV_PO_TRACKER
*& Custom ALV Purchase Order (P2P) Tracking Report
*& Author : Rohan Ghosh | Roll No: 2328190 | Batch: 2027 SAP (OE)
*& Specialization: SAP ABAP Backend Development
*& Package: ZREPORTS | Transaction: SE38
*& Created: April 2026
*&---------------------------------------------------------------------*
*&
*& BUSINESS CONTEXT:
*& Standard SAP ME2M lacks real-time GR/IR status visibility and
*& business-rule-driven color flags. This report aggregates data from
*& EKKO (PO Header), EKPO (PO Item), LFA1 (Vendor Master), MARA
*& (Material), and EKBE (PO History / GR records) to provide a
*& consolidated Procure-to-Pay status dashboard for the purchasing team.
*&
*&---------------------------------------------------------------------*

REPORT z_custom_alv_po_tracker LINE-SIZE 280 NO STANDARD PAGE HEADING.

*----------------------------------------------------------------------*
* STEP 1 — Type Pool & Include Declarations
*----------------------------------------------------------------------*

TYPE-POOLS: slis.   " Required for ALV field catalog types

*----------------------------------------------------------------------*
* STEP 2 — Global Data Declarations
*----------------------------------------------------------------------*

"--- Internal structure: one row per PO line item with GR details ------
TYPES: BEGIN OF ty_po_tracker,
         ebeln   TYPE ekko-ebeln,     " Purchase Order Number
         ebelp   TYPE ekpo-ebelp,     " PO Item Number
         aedat   TYPE ekko-aedat,     " PO Creation Date
         lifnr   TYPE ekko-lifnr,     " Vendor Number
         name1   TYPE lfa1-name1,     " Vendor Name
         ekgrp   TYPE ekko-ekgrp,     " Purchasing Group
         werks   TYPE ekpo-werks,     " Plant
         matnr   TYPE ekpo-matnr,     " Material Number
         txz01   TYPE ekpo-txz01,     " Short Text / Material Desc
         menge   TYPE ekpo-menge,     " PO Quantity
         meins   TYPE ekpo-meins,     " Unit of Measure
         netpr   TYPE ekpo-netpr,     " Net Price per Unit
         netwr   TYPE ekpo-netwr,     " Net Order Value
         waers   TYPE ekko-waers,     " Currency
         eindt   TYPE ekpo-eindt,     " Scheduled Delivery Date
         gr_qty  TYPE ekpo-menge,     " Goods Receipt Quantity (from EKBE)
         open_qty TYPE ekpo-menge,    " Open / Pending Quantity
         days_open TYPE i,            " Days since PO creation (calculated)
         status  TYPE c LENGTH 20,    " Status text: Overdue / On Track etc.
         color   TYPE c LENGTH 4,     " ALV Row Color Key (C610/C510/C310)
       END OF ty_po_tracker.

"--- Work areas and internal tables -----
DATA: it_po_tracker TYPE STANDARD TABLE OF ty_po_tracker,
      wa_po_tracker TYPE ty_po_tracker.

"--- GR quantities aggregation helper -----
TYPES: BEGIN OF ty_gr,
         ebeln TYPE ekbe-ebeln,
         ebelp TYPE ekbe-ebelp,
         gr_qty TYPE ekbe-menge,
       END OF ty_gr.

DATA: it_gr     TYPE STANDARD TABLE OF ty_gr,
      wa_gr     TYPE ty_gr.

"--- ALV Object References -----
DATA: go_alv    TYPE REF TO cl_gui_alv_grid,
      go_custom TYPE REF TO cl_gui_custom_container,
      gs_layout TYPE lvc_s_layo,
      it_fcat   TYPE lvc_t_fcat,
      wa_fcat   TYPE lvc_s_fcat.

"--- ALV Event Reference -----
DATA: go_events TYPE REF TO cl_gui_alv_grid.

*----------------------------------------------------------------------*
* STEP 3 — Selection Screen Definition
*----------------------------------------------------------------------*

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS:
    so_ebeln FOR ekko-ebeln,                    " PO Number range
    so_aedat FOR ekko-aedat OBLIGATORY,         " PO Creation Date (REQUIRED)
    so_lifnr FOR ekko-lifnr,                    " Vendor Number range
    so_ekgrp FOR ekko-ekgrp,                    " Purchasing Group
    so_matnr FOR ekpo-matnr.                    " Material Number
  PARAMETERS:
    p_werks  TYPE ekpo-werks DEFAULT '1000',    " Plant (default: 1000)
    p_open   TYPE xfeld DEFAULT 'X'.            " Show OPEN POs only
SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* STEP 4 — Start-of-Selection: Fetch PO Header + Item + Vendor Data
*----------------------------------------------------------------------*

START-OF-SELECTION.

  "--- 4a. Fetch PO Header + Item + Vendor in a single optimized JOIN ---
  SELECT
      ekko~ebeln
      ekko~aedat
      ekko~lifnr
      ekko~ekgrp
      ekko~waers
      lfa1~name1
      ekpo~ebelp
      ekpo~werks
      ekpo~matnr
      ekpo~txz01
      ekpo~menge
      ekpo~meins
      ekpo~netpr
      ekpo~netwr
      ekpo~eindt
    INTO CORRESPONDING FIELDS OF TABLE it_po_tracker
    FROM ekko
    INNER JOIN ekpo ON ekpo~ebeln = ekko~ebeln
    INNER JOIN lfa1 ON lfa1~lifnr = ekko~lifnr
   WHERE ekko~aedat IN so_aedat
     AND ekko~ebeln IN so_ebeln
     AND ekko~lifnr IN so_lifnr
     AND ekko~ekgrp IN so_ekgrp
     AND ekpo~werks  = p_werks
     AND ekpo~matnr IN so_matnr
     AND ekko~loekz  = space            " Exclude logically deleted POs
     AND ekpo~loekz  = space            " Exclude logically deleted items
     AND ekko~bstyp  = 'F'.            " Standard PO document type only

  IF sy-subrc <> 0.
    MESSAGE 'No Purchase Orders found for the selected criteria.' TYPE 'I'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  "--- 4b. Fetch aggregated Goods Receipt quantities from PO History (EKBE) ---
  SELECT ekbe~ebeln
         ekbe~ebelp
         SUM( ekbe~menge ) AS gr_qty
    INTO TABLE it_gr
    FROM ekbe
    FOR ALL ENTRIES IN it_po_tracker
   WHERE ekbe~ebeln = it_po_tracker-ebeln
     AND ekbe~ebelp = it_po_tracker-ebelp
     AND ekbe~vgabe = '1'              " Movement type: Goods Receipt
     AND ekbe~shkzg = 'S'             " Debit posting only
   GROUP BY ekbe~ebeln ekbe~ebelp.

*----------------------------------------------------------------------*
* STEP 5 — Business Logic: GR Qty, Open Qty, Color Coding
*----------------------------------------------------------------------*

  LOOP AT it_po_tracker INTO wa_po_tracker.

    "--- 5a. Find matching GR quantity ---
    READ TABLE it_gr INTO wa_gr
      WITH KEY ebeln = wa_po_tracker-ebeln
               ebelp = wa_po_tracker-ebelp.

    IF sy-subrc = 0.
      wa_po_tracker-gr_qty   = wa_gr-gr_qty.
    ELSE.
      wa_po_tracker-gr_qty   = 0.         " No GR posted yet
    ENDIF.

    "--- 5b. Calculate open quantity ---
    wa_po_tracker-open_qty = wa_po_tracker-menge - wa_po_tracker-gr_qty.

    "--- 5c. Skip fully received POs if 'Open Only' flag is set ---
    IF p_open = 'X' AND wa_po_tracker-open_qty <= 0.
      DELETE it_po_tracker.
      CONTINUE.
    ENDIF.

    "--- 5d. Calculate how many days the PO has been open ---
    wa_po_tracker-days_open = sy-datum - wa_po_tracker-aedat.

    "--- 5e. Color-code rows based on delivery date and open status ---
    IF wa_po_tracker-eindt < sy-datum AND wa_po_tracker-open_qty > 0.
      " Past delivery date with outstanding quantity = OVERDUE
      wa_po_tracker-color  = 'C610'.       " Red
      wa_po_tracker-status = 'OVERDUE'.

    ELSEIF wa_po_tracker-eindt BETWEEN sy-datum AND sy-datum + 14.
      " Delivery due within the next 14 days = APPROACHING
      wa_po_tracker-color  = 'C510'.       " Yellow
      wa_po_tracker-status = 'DUE SOON'.

    ELSEIF wa_po_tracker-gr_qty >= wa_po_tracker-menge.
      " Fully received = COMPLETE
      wa_po_tracker-color  = 'C310'.       " Green
      wa_po_tracker-status = 'COMPLETE'.

    ELSE.
      " Open, delivery date in future = ON TRACK
      wa_po_tracker-color  = 'C310'.       " Green
      wa_po_tracker-status = 'ON TRACK'.

    ENDIF.

    MODIFY it_po_tracker FROM wa_po_tracker.

  ENDLOOP.

*----------------------------------------------------------------------*
* STEP 6 — Build ALV Field Catalog
*----------------------------------------------------------------------*

  PERFORM f_build_fcat.

*----------------------------------------------------------------------*
* STEP 7 — Configure Layout and Display the ALV Grid
*----------------------------------------------------------------------*

  PERFORM f_display_alv.

*----------------------------------------------------------------------*
* FORM Routines
*----------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& FORM f_build_fcat
*& Builds field catalog using REUSE_ALV_FIELDCATALOG_MERGE
*& then customizes key fields for display, aggregation, and sorting
*&---------------------------------------------------------------------*
FORM f_build_fcat.

  "--- 6a. Auto-generate field catalog from the internal table structure ---
  CALL FUNCTION 'REUSE_ALV_FIELDCATALOG_MERGE'
    EXPORTING
      i_program_name     = sy-repid
      i_internal_tabname = 'IT_PO_TRACKER'
      i_inclname         = sy-repid
    CHANGING
      ct_fieldcat        = it_fcat
    EXCEPTIONS
      inconsistent_interface = 1
      program_error          = 2
      OTHERS                 = 3.

  IF sy-subrc <> 0.
    MESSAGE 'Field catalog generation failed. Check table structure.' TYPE 'E'.
    RETURN.
  ENDIF.

  "--- 6b. Customize individual field properties ---
  LOOP AT it_fcat INTO wa_fcat.
    CASE wa_fcat-fieldname.

      WHEN 'EBELN'.
        wa_fcat-key     = 'X'.                 " Sticky key column
        wa_fcat-coltext = 'PO Number'.
        wa_fcat-outputlen = 12.

      WHEN 'EBELP'.
        wa_fcat-coltext = 'Item'.
        wa_fcat-outputlen = 6.

      WHEN 'AEDAT'.
        wa_fcat-coltext = 'PO Date'.
        wa_fcat-outputlen = 10.

      WHEN 'LIFNR'.
        wa_fcat-coltext = 'Vendor No'.
        wa_fcat-outputlen = 12.

      WHEN 'NAME1'.
        wa_fcat-coltext = 'Vendor Name'.
        wa_fcat-outputlen = 30.

      WHEN 'EKGRP'.
        wa_fcat-coltext = 'Purch.Grp'.
        wa_fcat-outputlen = 9.

      WHEN 'WERKS'.
        wa_fcat-coltext = 'Plant'.
        wa_fcat-outputlen = 6.

      WHEN 'MATNR'.
        wa_fcat-coltext = 'Material'.
        wa_fcat-outputlen = 18.

      WHEN 'TXZ01'.
        wa_fcat-coltext = 'Description'.
        wa_fcat-outputlen = 30.

      WHEN 'MENGE'.
        wa_fcat-coltext = 'PO Qty'.
        wa_fcat-outputlen = 13.

      WHEN 'MEINS'.
        wa_fcat-coltext = 'UOM'.
        wa_fcat-outputlen = 6.

      WHEN 'NETPR'.
        wa_fcat-coltext = 'Unit Price'.
        wa_fcat-outputlen = 14.
        wa_fcat-cfieldname = 'WAERS'.        " Link currency reference field

      WHEN 'NETWR'.
        wa_fcat-coltext = 'Net Value'.
        wa_fcat-do_sum  = 'X'.              " Enable subtotals and grand total
        wa_fcat-outputlen = 16.
        wa_fcat-cfieldname = 'WAERS'.

      WHEN 'WAERS'.
        wa_fcat-coltext = 'Curr.'.
        wa_fcat-outputlen = 5.

      WHEN 'EINDT'.
        wa_fcat-coltext = 'Delivery Date'.
        wa_fcat-outputlen = 12.

      WHEN 'GR_QTY'.
        wa_fcat-coltext = 'GR Qty'.
        wa_fcat-outputlen = 13.

      WHEN 'OPEN_QTY'.
        wa_fcat-coltext = 'Open Qty'.
        wa_fcat-do_sum  = 'X'.              " Enable subtotals on open qty
        wa_fcat-outputlen = 13.

      WHEN 'DAYS_OPEN'.
        wa_fcat-coltext = 'Days Open'.
        wa_fcat-outputlen = 10.

      WHEN 'STATUS'.
        wa_fcat-coltext = 'Status'.
        wa_fcat-outputlen = 12.

      WHEN 'COLOR'.
        wa_fcat-no_out  = 'X'.              " Hide color column from display

    ENDCASE.
    MODIFY it_fcat FROM wa_fcat.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM f_display_alv
*& Configures ALV layout (zebra, auto-width, color binding, sort)
*& and displays data using CL_GUI_ALV_GRID
*&---------------------------------------------------------------------*
FORM f_display_alv.

  "--- 7a. Sort criteria: Vendor, then PO Number ascending ---
  DATA: lt_sort TYPE lvc_t_sort,
        wa_sort TYPE lvc_s_sort.

  wa_sort-fieldname = 'LIFNR'.   wa_sort-up = 'X'.  wa_sort-subtot = 'X'.
  APPEND wa_sort TO lt_sort.  CLEAR wa_sort.

  wa_sort-fieldname = 'EBELN'.   wa_sort-up = 'X'.
  APPEND wa_sort TO lt_sort.  CLEAR wa_sort.

  "--- 7b. Layout configuration ---
  gs_layout-zebra      = 'X'.       " Alternating row shading
  gs_layout-cwidth_opt = 'X'.       " Auto-fit column widths to content
  gs_layout-info_fname = 'COLOR'.   " Bind COLOR field for row highlighting
  gs_layout-sel_mode   = 'A'.       " Allow multi-row selection
  gs_layout-grid_title = |P2P Purchase Order Tracking Report | {
                           sy-datum DATE = USER }|.

  "--- 7c. Create ALV container and grid objects ---
  CREATE OBJECT go_custom
    EXPORTING container_name = 'MAIN_CONTAINER'.

  CREATE OBJECT go_alv
    EXPORTING i_parent = go_custom.

  "--- 7d. Display data ---
  go_alv->set_table_for_first_display(
    EXPORTING
      is_layout       = gs_layout
      it_sort         = lt_sort
    CHANGING
      it_outtab       = it_po_tracker
      it_fieldcatalog = it_fcat ).

ENDFORM.

*&---------------------------------------------------------------------*
*& SCREEN 100 — Custom Container Screen Definition
*& Define screen 100 in Screen Painter (SE51) with a Custom Control
*& named 'MAIN_CONTAINER' covering the full screen area
*&---------------------------------------------------------------------*

MODULE status_0100 OUTPUT.
  SET PF-STATUS 'STANDARD'.
  SET TITLEBAR  'TITLE_0100'.
ENDMODULE.

MODULE user_command_0100 INPUT.
  CASE sy-ucomm.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL'.
      LEAVE PROGRAM.
    WHEN 'REFRESH'.
      SUBMIT z_custom_alv_po_tracker.
  ENDCASE.
ENDMODULE.
