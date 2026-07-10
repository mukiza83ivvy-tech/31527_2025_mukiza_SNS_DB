/* ============================================================================
   DPR400210 - DATABASE PROGRAMMING WITH ORACLE DATABASE
   FINAL EXAMINATION (CAPSTONE PROJECT) - ACADEMIC YEAR 2025-2026
   UNIVERSITY OF LAY ADVENTISTS OF KIGALI (UNILAK)

   PROJECT : Smart Nkunganire System (SNS) - Anti-Fraud & Soil-Specific
             Subsidy Allocator
   PHASE   : IV - Database Creation  &  V - Table Implementation

   ============================================================================ */


/* ----------------------------------------------------------------------------
   PHASE IV: DATABASE / USER CREATION  (run as SYSDBA / SYSTEM)
   ---------------------------------------------------------------------------- */
ALTER SESSION SET "_ORACLE_SCRIPT" = true;

CREATE USER "31527_2025_mukiza_SNS_DB" IDENTIFIED BY "system123"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;

-- Core privileges required to build and run the capstone project
GRANT CONNECT, RESOURCE TO "31527_2025_mukiza_SNS_DB";
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE, CREATE SYNONYM
      TO "31527_2025_mukiza_SNS_DB";
GRANT UNLIMITED TABLESPACE TO "31527_2025_mukiza_SNS_DB";


/* ----------------------------------------------------------------------------
   PHASE V: TABLE IMPLEMENTATION
   Tables are created in dependency order: reference/lookup tables first,
   then transactional tables, then audit/fraud tables.
   ---------------------------------------------------------------------------- */

-- 1. SECTOR (administrative + RwSIS reference unit)
CREATE TABLE sector (
  sector_id      NUMBER(6)       CONSTRAINT pk_sector PRIMARY KEY,
  sector_name    VARCHAR2(60)    NOT NULL,
  district_name  VARCHAR2(60)    NOT NULL,
  province_name  VARCHAR2(60)    NOT NULL,
  CONSTRAINT uq_sector_name UNIQUE (sector_name, district_name)
);

-- 2. SOIL_PROFILE (RwSIS soil-health / crop norms per sector)
CREATE TABLE soil_profile (
  soil_profile_id             NUMBER(6)      CONSTRAINT pk_soil_profile PRIMARY KEY,
  sector_id                   NUMBER(6)      NOT NULL,
  crop_type                   VARCHAR2(40)   NOT NULL,
  recommended_fertilizer_type VARCHAR2(40)   NOT NULL,
  max_kg_per_hectare          NUMBER(6,2)    NOT NULL,
  soil_ph                     NUMBER(3,1),
  notes                       VARCHAR2(200),
  CONSTRAINT fk_soilprofile_sector FOREIGN KEY (sector_id)
      REFERENCES sector (sector_id),
  CONSTRAINT ck_soilprofile_maxkg CHECK (max_kg_per_hectare > 0),
  CONSTRAINT uq_soilprofile UNIQUE (sector_id, crop_type)
);

-- 3. FERTILIZER_TYPE (catalogue of subsidized inputs)
CREATE TABLE fertilizer_type (
  fertilizer_type_id NUMBER(6)      CONSTRAINT pk_fertilizer_type PRIMARY KEY,
  fertilizer_name     VARCHAR2(60)  NOT NULL UNIQUE,
  unit_price           NUMBER(10,2) NOT NULL,
  unit                  VARCHAR2(10) DEFAULT 'KG' NOT NULL,
  CONSTRAINT ck_fertilizertype_price CHECK (unit_price >= 0)
);

-- 4. FARMER (registered smallholder, one record per National ID)
CREATE TABLE farmer (
  farmer_id           NUMBER(10)     CONSTRAINT pk_farmer PRIMARY KEY,
  national_id         VARCHAR2(16)   NOT NULL UNIQUE,
  first_name           VARCHAR2(40)  NOT NULL,
  last_name            VARCHAR2(40)  NOT NULL,
  phone_number          VARCHAR2(15) NOT NULL,
  sector_id             NUMBER(6)    NOT NULL,
  land_size_hectares    NUMBER(6,2)  NOT NULL,
  registration_date      DATE        DEFAULT SYSDATE NOT NULL,
  CONSTRAINT fk_farmer_sector FOREIGN KEY (sector_id)
      REFERENCES sector (sector_id),
  CONSTRAINT ck_farmer_landsize CHECK (land_size_hectares > 0),
  CONSTRAINT ck_farmer_natid_len CHECK (LENGTH(national_id) = 16)
);

-- 5. AGRO_DEALER (licensed input retailers)
CREATE TABLE agro_dealer (
  dealer_id       NUMBER(10)       CONSTRAINT pk_agro_dealer PRIMARY KEY,
  dealer_name      VARCHAR2(80)    NOT NULL,
  national_id       VARCHAR2(16)   NOT NULL UNIQUE,
  license_number     VARCHAR2(30)  NOT NULL UNIQUE,
  sector_id           NUMBER(6)    NOT NULL,
  phone_number         VARCHAR2(15) NOT NULL,
  status                 VARCHAR2(12) DEFAULT 'ACTIVE' NOT NULL,
  CONSTRAINT fk_dealer_sector FOREIGN KEY (sector_id)
      REFERENCES sector (sector_id),
  CONSTRAINT ck_dealer_status CHECK (status IN ('ACTIVE','SUSPENDED','REVOKED'))
);

-- 6. PUBLIC_HOLIDAY (reference table for the DML-lock business rule)
CREATE TABLE public_holiday (
  holiday_id     NUMBER(6)      CONSTRAINT pk_public_holiday PRIMARY KEY,
  holiday_date   DATE           NOT NULL UNIQUE,
  holiday_name   VARCHAR2(80)   NOT NULL
);

-- 7. SUBSIDY_ALLOCATION (soil-specific allocation ceiling per farmer/season)
CREATE TABLE subsidy_allocation (
  allocation_id        NUMBER(10)     CONSTRAINT pk_subsidy_allocation PRIMARY KEY,
  farmer_id             NUMBER(10)    NOT NULL,
  sector_id              NUMBER(6)    NOT NULL,
  fertilizer_type_id      NUMBER(6)   NOT NULL,
  season                   VARCHAR2(20) NOT NULL,
  max_allowed_kg            NUMBER(8,2) NOT NULL,
  allocated_kg               NUMBER(8,2) DEFAULT 0 NOT NULL,
  allocation_date              DATE     DEFAULT SYSDATE NOT NULL,
  CONSTRAINT fk_alloc_farmer FOREIGN KEY (farmer_id)
      REFERENCES farmer (farmer_id),
  CONSTRAINT fk_alloc_sector FOREIGN KEY (sector_id)
      REFERENCES sector (sector_id),
  CONSTRAINT fk_alloc_fert FOREIGN KEY (fertilizer_type_id)
      REFERENCES fertilizer_type (fertilizer_type_id),
  CONSTRAINT ck_alloc_maxkg CHECK (max_allowed_kg > 0),
  CONSTRAINT ck_alloc_allocated CHECK (allocated_kg >= 0 AND allocated_kg <= max_allowed_kg),
  CONSTRAINT uq_alloc_farmer_season UNIQUE (farmer_id, fertilizer_type_id, season)
);

-- 8. TRANSACTION (actual USSD-confirmed redemption at an agro-dealer)
CREATE TABLE sns_transaction (
  transaction_id      NUMBER(10)      CONSTRAINT pk_transaction PRIMARY KEY,
  allocation_id         NUMBER(10)    NOT NULL,
  dealer_id              NUMBER(10)   NOT NULL,
  farmer_id                NUMBER(10) NOT NULL,
  ussd_reference             VARCHAR2(20) NOT NULL UNIQUE,
  quantity_kg                 NUMBER(8,2) NOT NULL,
  amount_paid                   NUMBER(10,2) NOT NULL,
  transaction_date                 DATE DEFAULT SYSDATE NOT NULL,
  transaction_status                 VARCHAR2(12) DEFAULT 'COMPLETED' NOT NULL,
  CONSTRAINT fk_txn_allocation FOREIGN KEY (allocation_id)
      REFERENCES subsidy_allocation (allocation_id),
  CONSTRAINT fk_txn_dealer FOREIGN KEY (dealer_id)
      REFERENCES agro_dealer (dealer_id),
  CONSTRAINT fk_txn_farmer FOREIGN KEY (farmer_id)
      REFERENCES farmer (farmer_id),
  CONSTRAINT ck_txn_qty CHECK (quantity_kg > 0),
  CONSTRAINT ck_txn_status CHECK (transaction_status IN ('COMPLETED','REVERSED','FLAGGED'))
);

-- 9. FRAUD_ALERT (system/official-raised suspicious activity)
CREATE TABLE fraud_alert (
  alert_id      NUMBER(10)      CONSTRAINT pk_fraud_alert PRIMARY KEY,
  farmer_id       NUMBER(10),
  dealer_id        NUMBER(10),
  alert_type         VARCHAR2(40)  NOT NULL,
  description           VARCHAR2(200),
  alert_date              DATE     DEFAULT SYSDATE NOT NULL,
  status                    VARCHAR2(12) DEFAULT 'OPEN' NOT NULL,
  CONSTRAINT fk_alert_farmer FOREIGN KEY (farmer_id) REFERENCES farmer (farmer_id),
  CONSTRAINT fk_alert_dealer FOREIGN KEY (dealer_id) REFERENCES agro_dealer (dealer_id),
  CONSTRAINT ck_alert_status CHECK (status IN ('OPEN','REVIEWED','CLOSED'))
);

-- 10. AUDIT_LOG (generic audit trail written to by triggers/packages)
CREATE TABLE audit_log (
  audit_id       NUMBER(12)     CONSTRAINT pk_audit_log PRIMARY KEY,
  table_name       VARCHAR2(30) NOT NULL,
  operation_type     VARCHAR2(10) NOT NULL,
  record_id            VARCHAR2(30),
  old_value               VARCHAR2(4000),
  new_value                 VARCHAR2(4000),
  changed_by                  VARCHAR2(30) DEFAULT USER NOT NULL,
  change_date                    DATE     DEFAULT SYSDATE NOT NULL,
  CONSTRAINT ck_audit_op CHECK (operation_type IN ('INSERT','UPDATE','DELETE','BLOCKED'))
);

/* ----------------------------------------------------------------------------
   SEQUENCES for surrogate primary keys
   ---------------------------------------------------------------------------- */
CREATE SEQUENCE seq_sector            START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE seq_soil_profile      START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE seq_fertilizer_type   START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE seq_farmer            START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE seq_agro_dealer       START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE seq_public_holiday    START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE seq_subsidy_alloc     START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE seq_transaction       START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE seq_fraud_alert       START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE seq_audit_log         START WITH 1 INCREMENT BY 1;

COMMIT;