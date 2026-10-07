-- =====================================================================
-- NOTA: las tablas application, bureau y previous_application se cargan
-- desde el notebook notebooks/03_sql_base.ipynb
-- =====================================================================


-- =====================================================================
-- A. CONSULTAS EXPLORATORIAS SOBRE application
-- =====================================================================

-- 1. Tasa general de incumplimiento
SELECT
    COUNT(*) AS total_clientes,
    SUM(TARGET) AS incumplieron,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM application;

-- 2. Tasa de incumplimiento por tipo de contrato
SELECT
    NAME_CONTRACT_TYPE,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM application
GROUP BY NAME_CONTRACT_TYPE
ORDER BY tasa_incumplimiento_pct DESC;

-- 3. Tasa de incumplimiento por tipo de ingreso (grupos de 1,000+ clientes)
SELECT
    NAME_INCOME_TYPE,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM application
WHERE CODE_GENDER IS NOT NULL
GROUP BY NAME_INCOME_TYPE
HAVING COUNT(*) >= 1000
ORDER BY tasa_incumplimiento_pct DESC;

-- 4. Tasa de incumplimiento por rango de edad
SELECT
    RANGO_EDAD,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM application
GROUP BY RANGO_EDAD
ORDER BY RANGO_EDAD;


-- =====================================================================
-- B. BUREAU: exploracion, resumen por cliente y union
-- =====================================================================

-- 5. Cantidad de creditos por cliente en bureau
SELECT
    COUNT(*)                   AS filas,
    COUNT(DISTINCT SK_ID_CURR) AS clientes_distintos,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT SK_ID_CURR), 2) AS creditos_por_cliente
FROM bureau;

-- 6. Estados de los creditos en bureau
SELECT CREDIT_ACTIVE, COUNT(*) AS creditos
FROM bureau
GROUP BY CREDIT_ACTIVE
ORDER BY creditos DESC;

-- 7. Resumen de bureau: una fila por cliente
DROP TABLE IF EXISTS bureau_resumen;
CREATE TABLE bureau_resumen AS
SELECT
    SK_ID_CURR,
    COUNT(*)                                                  AS BUREAU_NUM_CREDITOS,
    SUM(CASE WHEN CREDIT_ACTIVE = 'Active' THEN 1 ELSE 0 END) AS BUREAU_NUM_ACTIVOS,
    SUM(CASE WHEN CREDIT_DAY_OVERDUE > 0 THEN 1 ELSE 0 END)   AS BUREAU_NUM_CON_ATRASO,
    MAX(CREDIT_DAY_OVERDUE)                                   AS BUREAU_MAX_DIAS_ATRASO,
    SUM(AMT_CREDIT_SUM)                                       AS BUREAU_MONTO_TOTAL,
    SUM(AMT_CREDIT_SUM_DEBT)                                  AS BUREAU_DEUDA_TOTAL
FROM bureau
GROUP BY SK_ID_CURR;

-- 8. Verificacion: una fila por cliente (filas = clientes)
SELECT COUNT(*) AS filas, COUNT(DISTINCT SK_ID_CURR) AS clientes
FROM bureau_resumen;

-- 9. Union application + bureau_resumen (LEFT JOIN: se conservan los 307,511)
DROP TABLE IF EXISTS base_unida;
CREATE TABLE base_unida AS
SELECT
    a.*,
    b.BUREAU_NUM_CREDITOS,
    b.BUREAU_NUM_ACTIVOS,
    b.BUREAU_NUM_CON_ATRASO,
    b.BUREAU_MAX_DIAS_ATRASO,
    b.BUREAU_MONTO_TOTAL,
    b.BUREAU_DEUDA_TOTAL,
    CASE WHEN b.SK_ID_CURR IS NULL THEN 1 ELSE 0 END AS BUREAU_SIN_HISTORIAL
FROM application a
LEFT JOIN bureau_resumen b
    ON a.SK_ID_CURR = b.SK_ID_CURR;

-- 10. Verificacion de base_unida (esperado: 307,511 / 307,511 / 44,020)
SELECT
    COUNT(*)                   AS filas,
    COUNT(DISTINCT SK_ID_CURR) AS clientes,
    SUM(BUREAU_SIN_HISTORIAL)  AS sin_historial
FROM base_unida;

-- 11. Tasa de incumplimiento con / sin historial en bureau
SELECT
    BUREAU_SIN_HISTORIAL,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM base_unida
GROUP BY BUREAU_SIN_HISTORIAL;

-- 12. Clientes de bureau que no estan en application (esperado: 42,320)
-- Pertenecen a application_test, archivo fuera del alcance del proyecto
SELECT COUNT(*) AS clientes_bureau_fuera_de_application
FROM bureau_resumen
WHERE SK_ID_CURR NOT IN (SELECT SK_ID_CURR FROM application);


-- =====================================================================
-- C. PREVIOUS_APPLICATION: exploracion, resumen por cliente y union
-- =====================================================================

-- 13. Estados de las solicitudes previas
SELECT NAME_CONTRACT_STATUS, COUNT(*) AS solicitudes
FROM previous_application
GROUP BY NAME_CONTRACT_STATUS
ORDER BY solicitudes DESC;

-- 14. Resumen de previous_application: una fila por cliente
DROP TABLE IF EXISTS previous_resumen;
CREATE TABLE previous_resumen AS
SELECT
    SK_ID_CURR,
    COUNT(*)                                                           AS PREV_NUM_SOLICITUDES,
    SUM(CASE WHEN NAME_CONTRACT_STATUS = 'Approved' THEN 1 ELSE 0 END) AS PREV_NUM_APROBADAS,
    SUM(CASE WHEN NAME_CONTRACT_STATUS = 'Refused'  THEN 1 ELSE 0 END) AS PREV_NUM_RECHAZADAS,
    AVG(AMT_APPLICATION)                                               AS PREV_MONTO_PROMEDIO_SOLICITADO
FROM previous_application
GROUP BY SK_ID_CURR;

-- 15. Verificacion: una fila por cliente (esperado: 338,857 / 338,857)
SELECT COUNT(*) AS filas, COUNT(DISTINCT SK_ID_CURR) AS clientes
FROM previous_resumen;

-- 16. Clientes de application sin historial previo (esperado: 16,454)
SELECT COUNT(*) AS clientes_sin_historial_previo
FROM application
WHERE SK_ID_CURR NOT IN (SELECT SK_ID_CURR FROM previous_resumen);

-- 17. Tabla final: base_unida + previous_resumen (parte de base_unida para
-- conservar las columnas de bureau ya agregadas)
DROP TABLE IF EXISTS base_completa;
CREATE TABLE base_completa AS
SELECT
    u.*,
    p.PREV_NUM_SOLICITUDES,
    p.PREV_NUM_APROBADAS,
    p.PREV_NUM_RECHAZADAS,
    p.PREV_MONTO_PROMEDIO_SOLICITADO,
    CASE WHEN p.SK_ID_CURR IS NULL THEN 1 ELSE 0 END AS PREV_SIN_HISTORIAL
FROM base_unida u
LEFT JOIN previous_resumen p
    ON u.SK_ID_CURR = p.SK_ID_CURR;

-- 18. Tasa de incumplimiento con / sin historial previo
SELECT
    PREV_SIN_HISTORIAL,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM base_completa
GROUP BY PREV_SIN_HISTORIAL;


-- =====================================================================
-- D. TASAS DE INCUMPLIMIENTO POR SEGMENTO (sobre base_completa)
-- =====================================================================

-- 19. Por nivel educativo
SELECT
    NAME_EDUCATION_TYPE,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM base_completa
GROUP BY NAME_EDUCATION_TYPE
HAVING COUNT(*) >= 1000
ORDER BY tasa_incumplimiento_pct DESC;

-- 20. Por rango de edad y tipo de contrato
SELECT
    RANGO_EDAD,
    NAME_CONTRACT_TYPE,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM base_completa
GROUP BY RANGO_EDAD, NAME_CONTRACT_TYPE
HAVING COUNT(*) >= 1000
ORDER BY RANGO_EDAD, NAME_CONTRACT_TYPE;

-- 21. Por cantidad de rechazos previos
SELECT
    CASE
        WHEN PREV_NUM_RECHAZADAS IS NULL THEN 'Sin historial'
        WHEN PREV_NUM_RECHAZADAS = 0     THEN '0 rechazos'
        WHEN PREV_NUM_RECHAZADAS = 1     THEN '1 rechazo'
        ELSE '2 o mas rechazos'
    END AS rechazos_previos,
    COUNT(*) AS clientes,
    ROUND(AVG(TARGET) * 100, 2) AS tasa_incumplimiento_pct
FROM base_completa
GROUP BY rechazos_previos
ORDER BY tasa_incumplimiento_pct DESC;