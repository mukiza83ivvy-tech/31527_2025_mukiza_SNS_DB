  
   /* ============================================================================
   PHASE VI: PL/SQL PROGRAMMING
   Schema: 31527_2025_mukiza_SNS_DB 

   Contents:
     1. Standalone FUNCTION  fn_calc_max_allocation
     2. Standalone PROCEDURE sp_create_allocation
     3. PACKAGE pkg_sns_subsidy (spec + body)
          - record_transaction   (procedure, parameterized, DML + TCL)
          - fn_dealer_fraud_score (function, explicit cursor)
          - detect_ghost_transactions (procedure, cursor loop, exception handling)
     4. Custom exceptions, RAISE_APPLICATION_ERROR usage
     5. COMMIT / ROLLBACK transaction control demonstration
   ============================================================================ */

SET SERVEROUTPUT ON;

/* ----------------------------------------------------------------------------
   1. FUNCTION: fn_calc_max_allocation
   Soil-specific ceiling = farmer's land size x RwSIS max_kg_per_hectare for
   the crop/fertilizer grown in that farmer's sector.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION fn_calc_max_allocation (
  p_farmer_id  IN farmer.farmer_id%TYPE,
  p_fert_id    IN fertilizer_type.fertilizer_type_id%TYPE
) RETURN NUMBER
IS
  v_land_size   farmer.land_size_hectares%TYPE;
  v_sector_id   farmer.sector_id%TYPE;
  v_max_per_ha  soil_profile.max_kg_per_hectare%TYPE;
  e_no_soil_profile EXCEPTION;
BEGIN
  SELECT land_size_hectares, sector_id
    INTO v_land_size, v_sector_id
    FROM farmer
   WHERE farmer_id = p_farmer_id;

  BEGIN
    SELECT sp.max_kg_per_hectare
      INTO v_max_per_ha
      FROM soil_profile sp
      JOIN fertilizer_type ft ON ft.fertilizer_type_id = p_fert_id
     WHERE sp.sector_id = v_sector_id
       AND sp.recommended_fertilizer_type = ft.fertilizer_name;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE e_no_soil_profile;
  END;

  RETURN ROUND(v_land_size * v_max_per_ha, 2);

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20001, 'fn_calc_max_allocation: farmer '
      || p_farmer_id || ' not found.');
  WHEN e_no_soil_profile THEN
    RAISE_APPLICATION_ERROR(-20002, 'fn_calc_max_allocation: no RwSIS soil '
      || 'profile matches fertilizer type ' || p_fert_id
      || ' for this farmer''s sector.');
END fn_calc_max_allocation;
/


/* ----------------------------------------------------------------------------
   2. PROCEDURE: sp_create_allocation
   Parameterized procedure that opens a new season allocation for a farmer,
   using the soil-specific ceiling computed above.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE sp_create_allocation (
  p_farmer_id  IN farmer.farmer_id%TYPE,
  p_fert_id    IN fertilizer_type.fertilizer_type_id%TYPE,
  p_season     IN subsidy_allocation.season%TYPE
)
IS
  v_sector_id   farmer.sector_id%TYPE;
  v_max_kg      NUMBER;
  e_duplicate_allocation EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_duplicate_allocation, -00001);
BEGIN
  SELECT sector_id INTO v_sector_id FROM farmer WHERE farmer_id = p_farmer_id;

  v_max_kg := fn_calc_max_allocation(p_farmer_id, p_fert_id);

  INSERT INTO subsidy_allocation (
    allocation_id, farmer_id, sector_id, fertilizer_type_id,
    season, max_allowed_kg, allocated_kg, allocation_date
  ) VALUES (
    seq_subsidy_alloc.NEXTVAL, p_farmer_id, v_sector_id, p_fert_id,
    p_season, v_max_kg, 0, SYSDATE
  );

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Allocation created for farmer ' || p_farmer_id
    || ' - ceiling ' || v_max_kg || ' kg.');

EXCEPTION
  WHEN e_duplicate_allocation THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20003, 'sp_create_allocation: an allocation for '
      || 'this farmer/fertilizer/season already exists.');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20099, 'sp_create_allocation: unexpected error - '
      || SQLERRM);
END sp_create_allocation;
/


/* ----------------------------------------------------------------------------
   3. PACKAGE: pkg_sns_subsidy
   Groups the anti-fraud transaction logic used by every dealer redemption.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE PACKAGE pkg_sns_subsidy AS

  e_over_allocation   EXCEPTION;
  e_dealer_suspended  EXCEPTION;
  e_duplicate_ussd    EXCEPTION;

  PROCEDURE record_transaction (
    p_allocation_id IN subsidy_allocation.allocation_id%TYPE,
    p_dealer_id     IN agro_dealer.dealer_id%TYPE,
    p_farmer_id     IN farmer.farmer_id%TYPE,
    p_ussd_ref      IN sns_transaction.ussd_reference%TYPE,
    p_qty_kg        IN sns_transaction.quantity_kg%TYPE,
    p_unit_price    IN NUMBER
  );

  FUNCTION fn_dealer_fraud_score (
    p_dealer_id IN agro_dealer.dealer_id%TYPE
  ) RETURN NUMBER;

  PROCEDURE detect_ghost_transactions;

END pkg_sns_subsidy;
/


CREATE OR REPLACE PACKAGE BODY pkg_sns_subsidy AS

  /* ---- record_transaction ---------------------------------------------- */
  PROCEDURE record_transaction (
    p_allocation_id IN subsidy_allocation.allocation_id%TYPE,
    p_dealer_id     IN agro_dealer.dealer_id%TYPE,
    p_farmer_id     IN farmer.farmer_id%TYPE,
    p_ussd_ref      IN sns_transaction.ussd_reference%TYPE,
    p_qty_kg        IN sns_transaction.quantity_kg%TYPE,
    p_unit_price    IN NUMBER
  )
  IS
    v_dealer_status   agro_dealer.status%TYPE;
    v_remaining_kg     NUMBER;
  BEGIN
    -- Rule 1: dealer must be ACTIVE
    SELECT status INTO v_dealer_status
      FROM agro_dealer WHERE dealer_id = p_dealer_id;

    IF v_dealer_status <> 'ACTIVE' THEN
      RAISE e_dealer_suspended;
    END IF;

    -- Rule 2: remaining allocation must cover the requested quantity
    SELECT max_allowed_kg - allocated_kg INTO v_remaining_kg
      FROM subsidy_allocation
     WHERE allocation_id = p_allocation_id
       AND farmer_id = p_farmer_id
       FOR UPDATE;                     -- lock the row against concurrent fraud

    IF p_qty_kg > v_remaining_kg THEN
      RAISE e_over_allocation;
    END IF;

    -- Rule 3: insert the transaction (UNIQUE constraint blocks duplicate USSD refs)
    INSERT INTO sns_transaction (
      transaction_id, allocation_id, dealer_id, farmer_id, ussd_reference,
      quantity_kg, amount_paid, transaction_date, transaction_status
    ) VALUES (
      seq_transaction.NEXTVAL, p_allocation_id, p_dealer_id, p_farmer_id, p_ussd_ref,
      p_qty_kg, p_qty_kg * p_unit_price, SYSDATE, 'COMPLETED'
    );

    UPDATE subsidy_allocation
       SET allocated_kg = allocated_kg + p_qty_kg
     WHERE allocation_id = p_allocation_id;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Transaction ' || p_ussd_ref || ' recorded: '
      || p_qty_kg || ' kg for farmer ' || p_farmer_id);

  EXCEPTION
    WHEN e_dealer_suspended THEN
      ROLLBACK;
      INSERT INTO fraud_alert (alert_id, farmer_id, dealer_id, alert_type, description)
      VALUES (seq_fraud_alert.NEXTVAL, p_farmer_id, p_dealer_id, 'SUSPENDED_DEALER_ATTEMPT',
              'Attempted redemption via a non-active dealer.');
      COMMIT;
      RAISE_APPLICATION_ERROR(-20010, 'record_transaction: dealer ' || p_dealer_id
        || ' is not ACTIVE - transaction rejected and flagged.');

    WHEN e_over_allocation THEN
      ROLLBACK;
      INSERT INTO fraud_alert (alert_id, farmer_id, dealer_id, alert_type, description)
      VALUES (seq_fraud_alert.NEXTVAL, p_farmer_id, p_dealer_id, 'OVER_ALLOCATION_ATTEMPT',
              'Requested quantity exceeds remaining soil-specific ceiling.');
      COMMIT;
      RAISE_APPLICATION_ERROR(-20011, 'record_transaction: quantity requested exceeds '
        || 'the farmer''s remaining soil-specific allocation - possible fraud, flagged.');

    WHEN DUP_VAL_ON_INDEX THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20012, 'record_transaction: USSD reference '
        || p_ussd_ref || ' already used - duplicate/ghost transaction rejected.');

    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20013, 'record_transaction: dealer or allocation not found.');

    WHEN OTHERS THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20099, 'record_transaction: unexpected error - ' || SQLERRM);
  END record_transaction;


  /* ---- fn_dealer_fraud_score --------------------------------------------
     Explicit cursor scores a dealer: proportion of transactions concentrated
     on very few farmers (a hoarding/ghost-farmer signature) in the last 30 days.
     Score 0 = no concern, 1 = maximum concern (all volume via one farmer ID).
     ------------------------------------------------------------------------ */
  FUNCTION fn_dealer_fraud_score (
    p_dealer_id IN agro_dealer.dealer_id%TYPE
  ) RETURN NUMBER
  IS
    CURSOR c_dealer_txn IS
      SELECT farmer_id, quantity_kg
        FROM sns_transaction
       WHERE dealer_id = p_dealer_id
         AND transaction_date >= SYSDATE - 30;

    TYPE t_farmer_totals IS TABLE OF NUMBER INDEX BY VARCHAR2(20);
    v_totals       t_farmer_totals;
    v_farmer_key   VARCHAR2(20);
    v_total_kg     NUMBER := 0;
    v_max_farmer_kg NUMBER := 0;
    v_score        NUMBER := 0;
  BEGIN
    FOR r_txn IN c_dealer_txn LOOP
      v_farmer_key := TO_CHAR(r_txn.farmer_id);
      IF v_totals.EXISTS(v_farmer_key) THEN
        v_totals(v_farmer_key) := v_totals(v_farmer_key) + r_txn.quantity_kg;
      ELSE
        v_totals(v_farmer_key) := r_txn.quantity_kg;
      END IF;
      v_total_kg := v_total_kg + r_txn.quantity_kg;
    END LOOP;

    IF v_total_kg = 0 THEN
      RETURN 0;
    END IF;

    v_farmer_key := v_totals.FIRST;
    WHILE v_farmer_key IS NOT NULL LOOP
      IF v_totals(v_farmer_key) > v_max_farmer_kg THEN
        v_max_farmer_kg := v_totals(v_farmer_key);
      END IF;
      v_farmer_key := v_totals.NEXT(v_farmer_key);
    END LOOP;

    v_score := ROUND(v_max_farmer_kg / v_total_kg, 2);
    RETURN v_score;

  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20020, 'fn_dealer_fraud_score: ' || SQLERRM);
  END fn_dealer_fraud_score;


  /* ---- detect_ghost_transactions -----------------------------------------
     Cursor loop across all active dealers; any dealer whose fraud score
     exceeds 0.6 (i.e. more than 60% of a dealer's 30-day volume traces to a
     single farmer ID) is written to FRAUD_ALERT for RAB review.
     ------------------------------------------------------------------------ */
  PROCEDURE detect_ghost_transactions
  IS
    CURSOR c_dealers IS
      SELECT dealer_id FROM agro_dealer WHERE status = 'ACTIVE';
    v_score NUMBER;
    v_count NUMBER := 0;
  BEGIN
    FOR r_dealer IN c_dealers LOOP
      v_score := fn_dealer_fraud_score(r_dealer.dealer_id);
      IF v_score > 0.6 THEN
        INSERT INTO fraud_alert (alert_id, dealer_id, alert_type, description)
        VALUES (seq_fraud_alert.NEXTVAL, r_dealer.dealer_id, 'HOARDING_PATTERN',
                'Fraud score ' || v_score || ' - volume concentrated on a single '
                || 'farmer ID over the last 30 days.');
        v_count := v_count + 1;
      END IF;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE(v_count || ' dealer(s) flagged for hoarding pattern.');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20021, 'detect_ghost_transactions: ' || SQLERRM);
  END detect_ghost_transactions;

END pkg_sns_subsidy;
/


/* ----------------------------------------------------------------------------
   4. DEMONSTRATION: create allocations, then run legitimate + fraudulent
      transactions to show exception handling and transaction control.
   ---------------------------------------------------------------------------- */

-- Legitimate redemptions (well within each farmer's soil-specific ceiling)
BEGIN
  pkg_sns_subsidy.record_transaction(1000, 1000, 1000, 'USSD-REF-0001', 100, 850.00);
  pkg_sns_subsidy.record_transaction(1001, 1000, 1001, 'USSD-REF-0002', 150, 850.00);
  pkg_sns_subsidy.record_transaction(1003, 1001, 1003, 'USSD-REF-0003', 200, 700.00);
END;
/

-- Fraud simulation: same dealer (1000) funnels a large share of volume
-- through a single farmer ID (1000) to hoard stock - triggers the fraud score
BEGIN
  pkg_sns_subsidy.record_transaction(1000, 1000, 1000, 'USSD-REF-0004', 130, 850.00);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Expected rejection (over-allocation): ' || SQLERRM);
END;
/

-- Run the ghost-transaction detector
BEGIN
  pkg_sns_subsidy.detect_ghost_transactions;
END;
/

COMMIT;
