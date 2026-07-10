/* ============================================================================
   PHASE VII: ADVANCED DATABASE PROGRAMMING
   Schema: 31527_2025_Mukiza_SNS_DB  (replace with your own naming convention)

   Contents:
     1. Simple trigger      trg_farmer_audit          (row-level audit)
     2. Simple trigger      trg_dealer_status_check    (data-integrity guard)
     3. Compound trigger     trg_transaction_compound   (statement + row audit)
     4. Business-rule trigger trg_allocation_dml_lock
          Blocks INSERT/UPDATE/DELETE on SUBSIDY_ALLOCATION during:
            - Weekdays (Monday-Friday)
            - Public holidays (from PUBLIC_HOLIDAY reference table)
          Rationale: allocation ceilings are government-set entitlements;
          RAB only allows manual corrections outside business hours
          (weekends, non-holiday) so that no dealer/official can quietly
          inflate a ceiling during active trading hours - the exact window
          when agro-dealer fraud (ghost transactions) occurs.
     5. User activity tracking via AUDIT_LOG (logon trigger)
     6. Security: role-based restriction example
   ============================================================================ */

SET SERVEROUTPUT ON;

/* ----------------------------------------------------------------------------
   1. SIMPLE TRIGGER: trg_farmer_audit
   Logs every INSERT / UPDATE / DELETE on FARMER to AUDIT_LOG.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_farmer_audit
AFTER INSERT OR UPDATE OR DELETE ON farmer
FOR EACH ROW
DECLARE
  v_op   VARCHAR2(10);
BEGIN
  IF INSERTING THEN
    v_op := 'INSERT';
    INSERT INTO audit_log (audit_id, table_name, operation_type, record_id, new_value, changed_by)
    VALUES (seq_audit_log.NEXTVAL, 'FARMER', v_op, :NEW.farmer_id,
            'national_id=' || :NEW.national_id || ', name=' || :NEW.first_name || ' ' || :NEW.last_name,
            USER);
  ELSIF UPDATING THEN
    v_op := 'UPDATE';
    INSERT INTO audit_log (audit_id, table_name, operation_type, record_id, old_value, new_value, changed_by)
    VALUES (seq_audit_log.NEXTVAL, 'FARMER', v_op, :OLD.farmer_id,
            'land_size=' || :OLD.land_size_hectares, 'land_size=' || :NEW.land_size_hectares,
            USER);
  ELSIF DELETING THEN
    v_op := 'DELETE';
    INSERT INTO audit_log (audit_id, table_name, operation_type, record_id, old_value, changed_by)
    VALUES (seq_audit_log.NEXTVAL, 'FARMER', v_op, :OLD.farmer_id,
            'national_id=' || :OLD.national_id, USER);
  END IF;
END trg_farmer_audit;
/


/* ----------------------------------------------------------------------------
   2. SIMPLE TRIGGER: trg_dealer_status_check
   Prevents a SUSPENDED/REVOKED dealer from being silently reactivated
   without going through fn/procedure review (extra guard beyond the CHECK
   constraint already on agro_dealer.status).
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_dealer_status_check
BEFORE UPDATE OF status ON agro_dealer
FOR EACH ROW
BEGIN
  IF :OLD.status = 'REVOKED' AND :NEW.status = 'ACTIVE' THEN
    RAISE_APPLICATION_ERROR(-20030,
      'A REVOKED dealer cannot be reactivated directly; a new license/dealer '
      || 'record must be issued by RAB.');
  END IF;
END trg_dealer_status_check;
/


/* ----------------------------------------------------------------------------
   3. COMPOUND TRIGGER: trg_transaction_compound
   Maintains a running statement-level count of flagged transactions and
   writes one consolidated audit summary row per statement, in addition to
   row-level audit detail - demonstrating the four compound-trigger timing
   points.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_transaction_compound
FOR INSERT ON sns_transaction
COMPOUND TRIGGER

  v_row_count     PLS_INTEGER := 0;
  v_flagged_count PLS_INTEGER := 0;

  BEFORE STATEMENT IS
  BEGIN
    v_row_count := 0;
    v_flagged_count := 0;
  END BEFORE STATEMENT;

  AFTER EACH ROW IS
  BEGIN
    v_row_count := v_row_count + 1;
    IF :NEW.transaction_status = 'FLAGGED' THEN
      v_flagged_count := v_flagged_count + 1;
    END IF;

    INSERT INTO audit_log (audit_id, table_name, operation_type, record_id, new_value, changed_by)
    VALUES (seq_audit_log.NEXTVAL, 'SNS_TRANSACTION', 'INSERT', :NEW.transaction_id,
            'qty_kg=' || :NEW.quantity_kg || ', dealer=' || :NEW.dealer_id
            || ', farmer=' || :NEW.farmer_id, USER);
  END AFTER EACH ROW;

  AFTER STATEMENT IS
  BEGIN
    INSERT INTO audit_log (audit_id, table_name, operation_type, record_id, new_value, changed_by)
    VALUES (seq_audit_log.NEXTVAL, 'SNS_TRANSACTION', 'INSERT', 'STATEMENT_SUMMARY',
            'rows=' || v_row_count || ', flagged=' || v_flagged_count, USER);
  END AFTER STATEMENT;

END trg_transaction_compound;
/


/* ----------------------------------------------------------------------------
   4. BUSINESS-RULE TRIGGER: trg_allocation_dml_lock
   Blocks INSERT, UPDATE, DELETE on SUBSIDY_ALLOCATION during weekdays
   (Monday-Friday) and on any date listed in PUBLIC_HOLIDAY.
   Every blocked attempt is itself written to AUDIT_LOG (operation_type
   'BLOCKED') before the exception is raised, satisfying the auditing
   requirement even for rejected actions.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_allocation_dml_lock
BEFORE INSERT OR UPDATE OR DELETE ON subsidy_allocation
DECLARE
  v_day_name     VARCHAR2(10);
  v_is_holiday   NUMBER := 0;
  v_operation    VARCHAR2(10);
BEGIN
  v_day_name := TRIM(TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH'));

  SELECT COUNT(*) INTO v_is_holiday
    FROM public_holiday
   WHERE holiday_date = TRUNC(SYSDATE);

  IF INSERTING THEN v_operation := 'INSERT';
  ELSIF UPDATING THEN v_operation := 'UPDATE';
  ELSE v_operation := 'DELETE';
  END IF;

  IF v_day_name IN ('MON','TUE','WED','THU','FRI') OR v_is_holiday > 0 THEN
    INSERT INTO audit_log (audit_id, table_name, operation_type, record_id, changed_by)
    VALUES (seq_audit_log.NEXTVAL, 'SUBSIDY_ALLOCATION', 'BLOCKED',
            'attempted_on=' || TO_CHAR(SYSDATE, 'YYYY-MM-DD DY'), USER);
    COMMIT;  -- keep the audit trail even though the triggering DML is rejected

    RAISE_APPLICATION_ERROR(-20040,
      'SUBSIDY_ALLOCATION changes are locked on weekdays and public holidays. '
      || 'Manual corrections are only permitted on weekends outside the holiday '
      || 'calendar, to prevent tampering during active trading hours.');
  END IF;
END trg_allocation_dml_lock;
/


/* ----------------------------------------------------------------------------
   5. USER ACTIVITY TRACKING: logon trigger (schema/database level)
   Requires ADMINISTER DATABASE TRIGGER privilege; run as a privileged user
   if the exam environment restricts DDL triggers for a normal schema owner.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_sns_logon_audit
AFTER LOGON ON SCHEMA
BEGIN
  INSERT INTO audit_log (audit_id, table_name, operation_type, record_id, changed_by)
  VALUES (seq_audit_log.NEXTVAL, 'DATABASE', 'INSERT', 'LOGON', USER);
  COMMIT;
END trg_sns_logon_audit;
/


/* ----------------------------------------------------------------------------
   6. SECURITY: role-based restriction example
   A read-only auditor role that can inspect AUDIT_LOG and FRAUD_ALERT but
   cannot touch transactional tables - supports the "security control"
   marking criterion.
   ---------------------------------------------------------------------------- */
-- CREATE ROLE sns_auditor_role;
-- GRANT SELECT ON audit_log TO sns_auditor_role;
-- GRANT SELECT ON fraud_alert TO sns_auditor_role;
-- GRANT SELECT ON sns_transaction TO sns_auditor_role;
-- REVOKE INSERT, UPDATE, DELETE ON subsidy_allocation FROM sns_auditor_role;
-- -- Example: GRANT sns_auditor_role TO rab_officer_username;

COMMIT;

/* ----------------------------------------------------------------------------
   QUICK TEST of the business-rule lock (run on a weekday to see it fire):
   ---------------------------------------------------------------------------- */
-- BEGIN
--   UPDATE subsidy_allocation SET allocated_kg = allocated_kg WHERE allocation_id = 1000;
-- EXCEPTION
--   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE(SQLERRM);
-- END;
-- /
