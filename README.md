# Smart Nkunganire System (SNS)
### Anti-Fraud & Soil-Specific Subsidy Allocator

**DPR400210 – Database Programming with Oracle Database**
Final Examination (Capstone Project) | Faculty of Computing and Information Sciences
University of Lay Adventists of Kigali (UNILAK) | Academic Year 2025-2026

**Student:** Mukiza | **Student ID:** 31527
**Database / Schema name:** `31527_2025_mukiza_SNS_DB`
**Instructor:** Eric Maniraguha

---

## 1. About This Project

Rwanda's national **Smart Nkunganire System (SNS)**, run by the Rwanda Agriculture Board (RAB) and BK TecHouse, gives smallholder farmers subsidized seeds and fertilizer through a simple USSD code (`*774#`). This capstone rebuilds the core database behind that system to fix two real problems:

1. **Agro-dealer fraud** — corrupt dealers enter fake or borrowed farmer National ID numbers to create "ghost transactions," hoard subsidized fertilizer, and resell it on the black market at double the price.
2. **Soil over-allocation** — flat subsidy limits ignore Rwanda's Soil Information System (RwSIS), risking soil degradation from over-fertilization. Different sectors need different amounts (e.g. potatoes in Musanze vs. maize in Nyagatare).

This project solves both problems with a normalized Oracle database, PL/SQL business logic, triggers, an audit trail, and a working analytics dashboard.

---

## 2. Repository Structure

```
31527_2025_mukiza_SNS_DB/
├── README.md                          <- you are here
├── docs/
│   └── Final_Capstone_Report.docx     <- full write-up: problem, ERD, 3NF, all phases
├── slides/
│   ├── Phase1_Problem_Statement.pptx  <- 3 slides (Phase I brief)
│   └── Phase8_Final_Presentation.pptx <- 10 slides (final demo)
├── sql/
│   ├── 01_schema_ddl.sql              <- user/schema + 10 tables + constraints + sequences
│   ├── 02_sample_data.sql             <- realistic sample data
│   ├── 03_plsql_programs.sql          <- functions, procedures, package, cursors, exceptions
│   └── 04_triggers_audit_security.sql <- triggers, audit log, DML-lock rule, security role
├── dashboard/
│   └── SNS_Insight_Board.html         <- innovation component: live analytics dashboard
└── screenshots/                       <- add your OEM / SQL Developer execution evidence here
```

---

## 3. Database Design

### Entity-Relationship Diagram (3NF)

`SECTOR → FARMER / AGRO_DEALER / SOIL_PROFILE → SUBSIDY_ALLOCATION → SNS_TRANSACTION`, with `FRAUD_ALERT`, `AUDIT_LOG`, and `PUBLIC_HOLIDAY` as supporting tables. Full diagram and normalization notes are in `docs/Final_Capstone_Report.docx`.

| Table | Purpose |
|---|---|
| `sector` | Administrative sector, linked to RwSIS soil zones |
| `soil_profile` | RwSIS max kg/hectare per crop, per sector |
| `fertilizer_type` | Catalogue of subsidized inputs |
| `farmer` | Registered smallholders (unique National ID) |
| `agro_dealer` | Licensed input retailers |
| `public_holiday` | Reference table for the weekday/holiday DML lock |
| `subsidy_allocation` | Soil-specific fertilizer ceiling per farmer/season |
| `sns_transaction` | Actual USSD-confirmed redemption at a dealer |
| `fraud_alert` | System/official-raised suspicious activity |
| `audit_log` | Generic audit trail for every table |

---

## 4. How to Run This Project

Run the SQL scripts **in order**, connected as a privileged Oracle user (SYSDBA/SYSTEM) for the first step, then as the new schema owner:

```sql
-- Step 1: create the schema (run as SYSDBA/SYSTEM)
@sql/01_schema_ddl.sql

-- Step 2: connect as the schema owner, then load sample data
CONNECT 31527_2025_mukiza_SNS_DB/ChangeMe#2026
@sql/02_sample_data.sql

-- Step 3: create functions, procedures, and the fraud-detection package
@sql/03_plsql_programs.sql

-- Step 4: create triggers, the audit system, and security role
@sql/04_triggers_audit_security.sql
```

> Change the default password (`ChangeMe#2026`) in `01_schema_ddl.sql` before running it in any shared environment.

### View the dashboard
Open `dashboard/SNS_Insight_Board.html` in any browser with an internet connection (it loads Chart.js and fonts from a CDN). It currently runs on sample data shaped exactly like the tables above — swap the mock-data block in the `<script>` tag for a live query when connecting it to Oracle.

---

## 5. Key Features by Exam Phase

| Phase | What was delivered |
|---|---|
| I – Problem Statement | `slides/Phase1_Problem_Statement.pptx`, Section 1 of the report |
| II – Business Process Modeling | Swimlane diagram + explanation, Section 2 of the report |
| III – Logical Database Design | ERD + 3NF normalization, Section 3 of the report |
| IV – Database Creation | `sql/01_schema_ddl.sql` (user, privileges) |
| V – Table Implementation | `sql/01_schema_ddl.sql` (tables/constraints), `sql/02_sample_data.sql` |
| VI – PL/SQL Programming | `sql/03_plsql_programs.sql` |
| VII – Advanced DB Programming | `sql/04_triggers_audit_security.sql` |
| VIII – Documentation & Presentation | This README, `docs/`, `slides/Phase8_Final_Presentation.pptx` |
| Innovation | `dashboard/SNS_Insight_Board.html` |

---

## 6. Anti-Fraud & Business Rule Logic

- **`pkg_sns_subsidy.record_transaction`** — rejects redemptions from suspended dealers, blocks any request exceeding the farmer's remaining soil-specific ceiling, and rejects duplicate USSD references.
- **`pkg_sns_subsidy.fn_dealer_fraud_score`** — scores each dealer on how concentrated their 30-day volume is on a single farmer ID (a hoarding/ghost-farmer signature).
- **`pkg_sns_subsidy.detect_ghost_transactions`** — flags any dealer scoring above 0.6 for RAB review.
- **`trg_allocation_dml_lock`** — blocks INSERT/UPDATE/DELETE on `subsidy_allocation` on weekdays (Mon–Fri) and on any date listed in `public_holiday`, logging every blocked attempt.
- **`trg_farmer_audit` / `trg_transaction_compound`** — full audit trail of every change, at both row and statement level.

---

## 7. Tech Stack

- **Database:** Oracle Database (SQL, PL/SQL)
- **Diagrams:** ERD and swimlane process diagram (see `docs/`)
- **Dashboard:** HTML, CSS, JavaScript, Chart.js
- **Docs & Slides:** Word (.docx), PowerPoint (.pptx)

---

## 8. Academic Integrity

This is an individual capstone submission for DPR400210. All design and code in this repository is original work produced for the Final Examination requirements of UNILAK's Faculty of Computing and Information Sciences.

> *"Whatever you do, work at it with all your heart..."* – Colossians 3:23
