/* ============================================================================
   PHASE V (continued): MEANINGFUL SAMPLE DATA
   Schema: 31527_2025_Mukiza_SNS_DB  (replace with your own naming convention)
   ============================================================================ */

-- SECTOR (mix of RwSIS potato zone - Musanze, and maize zone - Nyagatare)
INSERT INTO sector VALUES (seq_sector.NEXTVAL, 'Muhoza',   'Musanze',   'Northern');
INSERT INTO sector VALUES (seq_sector.NEXTVAL, 'Cyuve',    'Musanze',   'Northern');
INSERT INTO sector VALUES (seq_sector.NEXTVAL, 'Karangazi','Nyagatare', 'Eastern');
INSERT INTO sector VALUES (seq_sector.NEXTVAL, 'Rukomo',   'Nyagatare', 'Eastern');

-- FERTILIZER_TYPE
INSERT INTO fertilizer_type VALUES (seq_fertilizer_type.NEXTVAL, 'NPK 17-17-17', 850.00, 'KG');
INSERT INTO fertilizer_type VALUES (seq_fertilizer_type.NEXTVAL, 'DAP',          900.00, 'KG');
INSERT INTO fertilizer_type VALUES (seq_fertilizer_type.NEXTVAL, 'Urea',         700.00, 'KG');

-- SOIL_PROFILE (RwSIS norms: potatoes in Musanze vs maize in Nyagatare)
INSERT INTO soil_profile VALUES (seq_soil_profile.NEXTVAL, 100, 'Potato', 'NPK 17-17-17', 250.00, 5.6, 'Volcanic soil, high organic matter');
INSERT INTO soil_profile VALUES (seq_soil_profile.NEXTVAL, 101, 'Potato', 'DAP',          230.00, 5.8, 'Volcanic soil, slightly acidic');
INSERT INTO soil_profile VALUES (seq_soil_profile.NEXTVAL, 102, 'Maize',  'Urea',         150.00, 6.4, 'Savannah loam, semi-arid');
INSERT INTO soil_profile VALUES (seq_soil_profile.NEXTVAL, 103, 'Maize',  'NPK 17-17-17', 160.00, 6.2, 'Savannah loam');

-- PUBLIC_HOLIDAY (Rwanda 2026 sample public holidays used by the DML-lock rule)
INSERT INTO public_holiday VALUES (seq_public_holiday.NEXTVAL, DATE '2026-01-01', 'New Year');
INSERT INTO public_holiday VALUES (seq_public_holiday.NEXTVAL, DATE '2026-02-01', 'Heroes Day');
INSERT INTO public_holiday VALUES (seq_public_holiday.NEXTVAL, DATE '2026-04-07', 'Genocide Memorial Day');
INSERT INTO public_holiday VALUES (seq_public_holiday.NEXTVAL, DATE '2026-07-01', 'Independence Day');
INSERT INTO public_holiday VALUES (seq_public_holiday.NEXTVAL, DATE '2026-07-04', 'Liberation Day');

-- FARMER (16-digit placeholder National IDs)
INSERT INTO farmer VALUES (seq_farmer.NEXTVAL, '1198012345678901', 'Jean',    'Uwimana',  '0788111111', 100, 0.80, DATE '2025-09-01');
INSERT INTO farmer VALUES (seq_farmer.NEXTVAL, '1198212345678902', 'Marie',   'Mukamana', '0788222222', 100, 1.20, DATE '2025-09-02');
INSERT INTO farmer VALUES (seq_farmer.NEXTVAL, '1197512345678903', 'Emmanuel','Habimana', '0788333333', 101, 0.50, DATE '2025-09-03');
INSERT INTO farmer VALUES (seq_farmer.NEXTVAL, '1199012345678904', 'Alice',   'Uwase',    '0788444444', 102, 2.00, DATE '2025-09-05');
INSERT INTO farmer VALUES (seq_farmer.NEXTVAL, '1198812345678905', 'Eric',    'Nkurunziza','0788555555', 103, 1.50, DATE '2025-09-06');

-- AGRO_DEALER (one dealer will be used later to demonstrate fraud detection)
INSERT INTO agro_dealer VALUES (seq_agro_dealer.NEXTVAL, 'Musanze Agro Supplies Ltd', '1197012345670001', 'LIC-MUS-001', 100, '0788666001', 'ACTIVE');
INSERT INTO agro_dealer VALUES (seq_agro_dealer.NEXTVAL, 'Nyagatare Farm Inputs Co.',  '1197012345670002', 'LIC-NYA-001', 102, '0788666002', 'ACTIVE');

-- SUBSIDY_ALLOCATION
-- max_allowed_kg = land_size_hectares * soil_profile.max_kg_per_hectare (RwSIS rule)
INSERT INTO subsidy_allocation VALUES (seq_subsidy_alloc.NEXTVAL, 1000, 100, 100, '2026A', 0.80*250.00, 0, SYSDATE);
INSERT INTO subsidy_allocation VALUES (seq_subsidy_alloc.NEXTVAL, 1001, 100, 100, '2026A', 1.20*250.00, 0, SYSDATE);
INSERT INTO subsidy_allocation VALUES (seq_subsidy_alloc.NEXTVAL, 1002, 101, 101, '2026A', 0.50*230.00, 0, SYSDATE);
INSERT INTO subsidy_allocation VALUES (seq_subsidy_alloc.NEXTVAL, 1003, 102, 102, '2026A', 2.00*150.00, 0, SYSDATE);
INSERT INTO subsidy_allocation VALUES (seq_subsidy_alloc.NEXTVAL, 1003, 102, 102, '2026A', 999.00*160.00, 0, SYSDATE);

COMMIT;

/* Note: SNS_TRANSACTION sample rows (including a deliberate over-allocation /
   ghost-transaction example used to demonstrate fraud detection) are inserted
   through the PL/SQL package in 03_plsql_programs.sql, since each redemption
   must pass through pkg_sns_subsidy.record_transaction so that business rules,
   auditing, and fraud checks fire exactly as they would in production. */
