-- ============================================================
-- ANÁLISE BOBINAS - MAXWELL CHAT / HELP PORTAL
-- Período: abril/2026 em diante | Sites: MLB, MLA, MLM, MLC
-- ============================================================


-- ------------------------------------------------------------
-- 1. FUNIL MENSAL POR SEGMENTO
--    conversas Maxwell → pedidos realizados × taxa de conversão
-- ------------------------------------------------------------
WITH seg AS (
  SELECT DISTINCT CUS_CUST_ID, SIT_SITE_ID, CUST_SEGMENT_CROSS AS segmento
  FROM `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS`
  WHERE SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
    AND TIM_DATE = '2026-04-01'
    AND SELL_ACTIVE_MTD_FLAG = 1
),
conversas AS (
  SELECT
    FORMAT_DATE('%Y-%m', DATE(c.CONV_CREATE_DATE)) AS mes,
    COALESCE(seg.segmento, 'SEM SEGMENTO') AS segmento,
    COUNT(DISTINCT c.CONVERSATION_ID) AS total_conversas,
    COUNT(DISTINCT CASE WHEN p.user_id IS NULL THEN c.CONVERSATION_ID END) AS bloqueadas
  FROM `meli-bi-data.WHOWNER.BT_CX_MAXWELL_CONVERSATIONS` c
  LEFT JOIN seg ON c.USER_ID = seg.CUS_CUST_ID AND c.SIT_SITE_ID = seg.SIT_SITE_ID
  LEFT JOIN (
    SELECT DISTINCT CAST(SO_CUS_CUST_ID AS INT64) AS user_id, SO_SITE_ID, DATE(SO_REQUEST_DATE) AS dt
    FROM `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER`
    WHERE SO_FLOW_TYPE = 'PAPER_ROLL'
      AND SO_CALL_CENTER IN ('FAQ','PROACTIVO_WIDGET')
      AND SO_SOURCE_CHANNEL = 'MAXWELL_CHAT'
      AND DATE(SO_REQUEST_DATE) >= '2026-04-01'
      AND SO_SITE_ID IN ('MLB','MLA','MLM','MLC')
      AND CAST(SO_CUS_CUST_ID AS INT64) NOT IN (3087698992,3222801111)
  ) p ON c.USER_ID = p.user_id AND c.SIT_SITE_ID = p.SO_SITE_ID AND DATE(c.CONV_CREATE_DATE) = p.dt
  WHERE c.FLAVOR = 'mpcx'
    AND c.SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
    AND c.TYPIFICATION_L3 = 'Coil shipping'
    AND DATE(c.CONV_CREATE_DATE) >= '2026-04-01'
    AND COALESCE(seg.segmento, 'SEM SEGMENTO') != 'BIG SELLERS'
  GROUP BY 1, 2
),
pedidos AS (
  SELECT
    FORMAT_DATE('%Y-%m', DATE(SO_REQUEST_DATE)) AS mes,
    COALESCE(seg.segmento, 'SEM SEGMENTO') AS segmento,
    COUNT(SO_SERVICE_ORDER_ID) AS pedidos_realizados,
    COUNT(DISTINCT CAST(SO_CUS_CUST_ID AS INT64)) AS sellers_pediram
  FROM `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
  LEFT JOIN seg ON CAST(pso.SO_CUS_CUST_ID AS INT64) = seg.CUS_CUST_ID AND pso.SO_SITE_ID = seg.SIT_SITE_ID
  WHERE SO_FLOW_TYPE = 'PAPER_ROLL'
    AND SO_CALL_CENTER IN ('FAQ','PROACTIVO_WIDGET')
    AND SO_SOURCE_CHANNEL = 'MAXWELL_CHAT'
    AND DATE(SO_REQUEST_DATE) >= '2026-04-01'
    AND SO_SITE_ID IN ('MLB','MLA','MLM','MLC')
    AND CAST(SO_CUS_CUST_ID AS INT64) NOT IN (3087698992,3222801111)
    AND COALESCE(seg.segmento, 'SEM SEGMENTO') != 'BIG SELLERS'
  GROUP BY 1, 2
)
SELECT
  c.mes,
  c.segmento,
  c.total_conversas,
  c.bloqueadas,
  c.total_conversas - c.bloqueadas AS conversas_com_pedido,
  COALESCE(p.pedidos_realizados, 0) AS pedidos_realizados,
  COALESCE(p.sellers_pediram, 0) AS sellers_pediram,
  ROUND(COALESCE(p.pedidos_realizados, 0) / NULLIF(c.total_conversas, 0) * 100, 1) AS pct_conversao
FROM conversas c
LEFT JOIN pedidos p USING (mes, segmento)
ORDER BY 1, 2;


-- ------------------------------------------------------------
-- 2. SELLERS QUE CONVERSARAM E PEDIRAM NO MESMO DIA
--    com segmentação: sub_segmento, TPV range, resultado pedido
-- ------------------------------------------------------------
SELECT DISTINCT
  c.USER_ID,
  c.SIT_SITE_ID AS site,
  COALESCE(seg.CUST_SEGMENT_CROSS, 'SEM SEGMENTO') AS segmento,
  COALESCE(seg.CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento,
  seg.TPV_RANGE_POINT,
  CASE WHEN pso.SO_CUS_CUST_ID IS NOT NULL THEN 'Pedido realizado' ELSE 'Sem pedido' END AS resultado_pedido
FROM `meli-bi-data.WHOWNER.BT_CX_MAXWELL_CONVERSATIONS` c
LEFT JOIN `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
  ON CAST(pso.SO_CUS_CUST_ID AS INT64) = c.USER_ID
  AND pso.SO_SITE_ID = c.SIT_SITE_ID
  AND DATE(pso.SO_REQUEST_DATE) = DATE(c.CONV_CREATE_DATE)
  AND pso.SO_FLOW_TYPE = 'PAPER_ROLL'
  AND (
    (pso.SO_CALL_CENTER IN ('FAQ','PROACTIVO_WIDGET') AND pso.SO_SOURCE_CHANNEL = 'MAXWELL_CHAT')
    OR pso.SO_CALL_CENTER = 'PROACTIVO_CX'
  )
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS` seg
  ON c.USER_ID = seg.CUS_CUST_ID
  AND c.SIT_SITE_ID = seg.SIT_SITE_ID
  AND seg.TIM_DATE = '2026-04-01'
  AND seg.SELL_ACTIVE_MTD_FLAG = 1
WHERE c.FLAVOR = 'mpcx'
  AND c.SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
  AND c.TYPIFICATION_L3 = 'Coil shipping'
  AND DATE(c.CONV_CREATE_DATE) >= '2026-04-01'
  AND c.USER_ID NOT IN (3087698992, 3222801111)
ORDER BY 1;


-- ------------------------------------------------------------
-- 3. FUNIL COMPLETO MAXWELL: conversas → pedidos → entregues
--    por sub_segmento (cross-site)
-- ------------------------------------------------------------
SELECT
  COALESCE(seg.CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento,
  COUNT(DISTINCT c.CONVERSATION_ID)                                                        AS total_conversas,
  COUNT(DISTINCT CASE WHEN pso.SO_CUS_CUST_ID IS NOT NULL THEN c.CONVERSATION_ID END)     AS pedidos_realizados,
  COUNT(DISTINCT CASE WHEN UPPER(shp.STATUS) = 'DELIVERED' THEN c.CONVERSATION_ID END)    AS entregues
FROM `meli-bi-data.WHOWNER.BT_CX_MAXWELL_CONVERSATIONS` c
LEFT JOIN `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
  ON CAST(pso.SO_CUS_CUST_ID AS INT64) = c.USER_ID
  AND pso.SO_SITE_ID = c.SIT_SITE_ID
  AND DATE(pso.SO_REQUEST_DATE) = DATE(c.CONV_CREATE_DATE)
  AND pso.SO_FLOW_TYPE = 'PAPER_ROLL'
  AND pso.SO_CALL_CENTER IN ('FAQ','PROACTIVO_WIDGET')
  AND pso.SO_SOURCE_CHANNEL = 'MAXWELL_CHAT'
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_POINT_SERVICE_ORDER_SHIPMENTS` shp
  ON pso.SO_SHIPPING_NUMBER = shp.SHIPPING_NUMBER
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS` seg
  ON c.USER_ID = seg.CUS_CUST_ID
  AND c.SIT_SITE_ID = seg.SIT_SITE_ID
  AND seg.TIM_DATE = '2026-04-01'
  AND seg.SELL_ACTIVE_MTD_FLAG = 1
WHERE c.FLAVOR = 'mpcx'
  AND c.SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
  AND c.TYPIFICATION_L3 = 'Coil shipping'
  AND DATE(c.CONV_CREATE_DATE) >= '2026-04-01'
  AND c.USER_ID NOT IN (3087698992, 3222801111)
GROUP BY 1;


-- ------------------------------------------------------------
-- 4. PEDIDOS HELP_PORTAL: pedidos → entregues por sub_segmento
-- ------------------------------------------------------------
SELECT
  COALESCE(seg.CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento,
  COUNT(pso.SO_SERVICE_ORDER_ID)                        AS total_pedidos,
  COUNTIF(UPPER(shp.STATUS) = 'DELIVERED')              AS entregues,
  ROUND(COUNTIF(UPPER(shp.STATUS) = 'DELIVERED')
        / COUNT(pso.SO_SERVICE_ORDER_ID) * 100, 1)      AS taxa_entrega_pct
FROM `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_POINT_SERVICE_ORDER_SHIPMENTS` shp
  ON pso.SO_SHIPPING_NUMBER = shp.SHIPPING_NUMBER
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS` seg
  ON CAST(pso.SO_CUS_CUST_ID AS INT64) = seg.CUS_CUST_ID
  AND pso.SO_SITE_ID = seg.SIT_SITE_ID
  AND seg.TIM_DATE = '2026-04-01'
  AND seg.SELL_ACTIVE_MTD_FLAG = 1
WHERE pso.SO_FLOW_TYPE = 'PAPER_ROLL'
  AND pso.SO_SOURCE_CHANNEL = 'HELP_PORTAL'
  AND DATE(pso.SO_REQUEST_DATE) >= '2026-04-01'
  AND pso.SO_SITE_ID IN ('MLB','MLA','MLM','MLC')
  AND CAST(pso.SO_CUS_CUST_ID AS INT64) NOT IN (3087698992, 3222801111)
GROUP BY 1;


-- ------------------------------------------------------------
-- 5. TABELA PRINCIPAL MAXWELL
--    sub_segmento | TPV Range | conversas | pedidos | conversão
--    | estoque médio | emergencial CX (qtd + custo USD)
--
--    Agrupamentos aplicados:
--      SMB1 + SMB2 + SMB3 → SMB
--      LM1  + LM2         → LM
--      SEM SEGMENTO        → LOLO
--    Excluídos: BIG SELLERS, IDs internos
-- ------------------------------------------------------------

-- 5a. Funil conversas/pedidos
SELECT
  COALESCE(seg.CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento,
  COUNT(DISTINCT c.CONVERSATION_ID) AS total_conversas,
  COUNT(DISTINCT CASE WHEN pso.SO_CUS_CUST_ID IS NOT NULL THEN c.CONVERSATION_ID END) AS pedidos_realizados
FROM `meli-bi-data.WHOWNER.BT_CX_MAXWELL_CONVERSATIONS` c
LEFT JOIN `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
  ON CAST(pso.SO_CUS_CUST_ID AS INT64) = c.USER_ID AND pso.SO_SITE_ID = c.SIT_SITE_ID
  AND DATE(pso.SO_REQUEST_DATE) = DATE(c.CONV_CREATE_DATE) AND pso.SO_FLOW_TYPE = 'PAPER_ROLL'
  AND pso.SO_CALL_CENTER IN ('FAQ','PROACTIVO_WIDGET') AND pso.SO_SOURCE_CHANNEL = 'MAXWELL_CHAT'
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS` seg
  ON c.USER_ID = seg.CUS_CUST_ID AND c.SIT_SITE_ID = seg.SIT_SITE_ID
  AND seg.TIM_DATE = '2026-04-01' AND seg.SELL_ACTIVE_MTD_FLAG = 1
WHERE c.FLAVOR = 'mpcx' AND c.SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
  AND c.TYPIFICATION_L3 = 'Coil shipping' AND DATE(c.CONV_CREATE_DATE) >= '2026-04-01'
  AND c.USER_ID NOT IN (3087698992, 3222801111)
GROUP BY 1;

-- 5b. Estoque médio no momento do pedido
SELECT
  COALESCE(seg.CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento,
  ROUND(AVG(CAST(bir.stock_percentage_order AS FLOAT64)), 1) AS estoque_medio_pct
FROM `meli-bi-data.WHOWNER.BT_CX_MAXWELL_CONVERSATIONS` c
INNER JOIN `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
  ON CAST(pso.SO_CUS_CUST_ID AS INT64) = c.USER_ID AND pso.SO_SITE_ID = c.SIT_SITE_ID
  AND DATE(pso.SO_REQUEST_DATE) = DATE(c.CONV_CREATE_DATE) AND pso.SO_FLOW_TYPE = 'PAPER_ROLL'
  AND pso.SO_CALL_CENTER IN ('FAQ','PROACTIVO_WIDGET') AND pso.SO_SOURCE_CHANNEL = 'MAXWELL_CHAT'
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS` seg
  ON c.USER_ID = seg.CUS_CUST_ID AND c.SIT_SITE_ID = seg.SIT_SITE_ID
  AND seg.TIM_DATE = '2026-04-01' AND seg.SELL_ACTIVE_MTD_FLAG = 1
LEFT JOIN `meli-bi-data.SBOX_SELLERSGROWTHMP.bobinas_inventory_request` bir
  ON pso.SO_SHIPPING_NUMBER = bir.shipping_number
WHERE c.FLAVOR = 'mpcx' AND c.SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
  AND c.TYPIFICATION_L3 = 'Coil shipping' AND DATE(c.CONV_CREATE_DATE) >= '2026-04-01'
  AND c.USER_ID NOT IN (3087698992, 3222801111)
GROUP BY 1;

-- 5c. Pedidos emergenciais via CX (custo unitário: USD 4,5)
SELECT
  COALESCE(seg.CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento,
  COUNT(pso.SO_SERVICE_ORDER_ID)             AS pedidos_emergenciais_cx,
  COUNT(pso.SO_SERVICE_ORDER_ID) * 4.5       AS custo_emerg_cx_usd
FROM `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS` seg
  ON CAST(pso.SO_CUS_CUST_ID AS INT64) = seg.CUS_CUST_ID AND pso.SO_SITE_ID = seg.SIT_SITE_ID
  AND seg.TIM_DATE = '2026-04-01' AND seg.SELL_ACTIVE_MTD_FLAG = 1
WHERE pso.SO_FLOW_TYPE = 'PAPER_ROLL' AND pso.SO_CALL_CENTER = 'CX'
  AND pso.PRSO_REQUEST_TYPE = 'EMERGENCY' AND DATE(pso.SO_REQUEST_DATE) >= '2026-04-01'
  AND pso.SO_SITE_ID IN ('MLB','MLA','MLM','MLC')
  AND CAST(pso.SO_CUS_CUST_ID AS INT64) NOT IN (3087698992, 3222801111)
GROUP BY 1;

-- 5d. TPV Range (moda, excluindo valor 0)
SELECT
  COALESCE(CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento,
  TPV_RANGE_POINT,
  COUNT(*) AS total
FROM `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS`
WHERE SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
  AND TIM_DATE = '2026-04-01'
  AND SELL_ACTIVE_MTD_FLAG = 1
  AND TPV_RANGE_POINT IS NOT NULL
  AND TPV_RANGE_POINT != '0'
GROUP BY 1, 2
ORDER BY 1, 3 DESC;


-- ------------------------------------------------------------
-- 6. IMPACTO NO TPV: sellers sem pedido em abril
--    TPV médio (USD) em abril vs maio via BT_MP_PAY_PAYMENTS
-- ------------------------------------------------------------
WITH sem_pedido AS (
  SELECT DISTINCT c.USER_ID, c.SIT_SITE_ID,
    COALESCE(seg.CUST_SUB_SEGMENT_CROSS, 'LOLO') AS sub_segmento
  FROM `meli-bi-data.WHOWNER.BT_CX_MAXWELL_CONVERSATIONS` c
  LEFT JOIN `meli-bi-data.WHOWNER.BT_MP_POINT_SERVICE_ORDER` pso
    ON CAST(pso.SO_CUS_CUST_ID AS INT64) = c.USER_ID AND pso.SO_SITE_ID = c.SIT_SITE_ID
    AND DATE(pso.SO_REQUEST_DATE) = DATE(c.CONV_CREATE_DATE) AND pso.SO_FLOW_TYPE = 'PAPER_ROLL'
    AND pso.SO_CALL_CENTER IN ('FAQ','PROACTIVO_WIDGET') AND pso.SO_SOURCE_CHANNEL = 'MAXWELL_CHAT'
  LEFT JOIN `meli-bi-data.WHOWNER.LK_MP_SEGMENTATION_SELLERS` seg
    ON c.USER_ID = seg.CUS_CUST_ID AND c.SIT_SITE_ID = seg.SIT_SITE_ID
    AND seg.TIM_DATE = '2026-04-01' AND seg.SELL_ACTIVE_MTD_FLAG = 1
  WHERE c.FLAVOR = 'mpcx' AND c.SIT_SITE_ID IN ('MLB','MLA','MLM','MLC')
    AND c.TYPIFICATION_L3 = 'Coil shipping'
    AND DATE(c.CONV_CREATE_DATE) >= '2026-04-01'
    AND DATE(c.CONV_CREATE_DATE) <  '2026-05-01'
    AND c.USER_ID NOT IN (3087698992, 3222801111)
    AND pso.SO_CUS_CUST_ID IS NULL
),
tpv_mensal AS (
  SELECT
    CUS_CUST_ID_SEL AS user_id,
    FORMAT_DATE('%Y-%m', DATE(PAY_APPROVED_DATETIME)) AS mes,
    SUM(TPV_DOL_AMT) AS tpv_total
  FROM `meli-bi-data.WHOWNER.BT_MP_PAY_PAYMENTS`
  WHERE DATE(PAY_APPROVED_DATETIME) >= '2026-04-01'
    AND DATE(PAY_APPROVED_DATETIME) <  '2026-06-01'
    AND CUS_CUST_ID_SEL IS NOT NULL
  GROUP BY 1, 2
)
SELECT
  sp.sub_segmento,
  COUNT(DISTINCT sp.USER_ID)                                                                 AS sellers_sem_pedido,
  ROUND(AVG(CASE WHEN tm.mes = '2026-04' THEN tm.tpv_total ELSE NULL END), 2)               AS avg_tpv_abril_usd,
  ROUND(AVG(CASE WHEN tm.mes = '2026-05' THEN tm.tpv_total ELSE NULL END), 2)               AS avg_tpv_maio_usd,
  ROUND(
    (AVG(CASE WHEN tm.mes = '2026-05' THEN tm.tpv_total ELSE NULL END)
   - AVG(CASE WHEN tm.mes = '2026-04' THEN tm.tpv_total ELSE NULL END))
   / NULLIF(AVG(CASE WHEN tm.mes = '2026-04' THEN tm.tpv_total ELSE NULL END), 0) * 100
  , 1)                                                                                        AS variacao_tpv_pct
FROM sem_pedido sp
LEFT JOIN tpv_mensal tm ON sp.USER_ID = tm.user_id
GROUP BY 1
ORDER BY
  CASE sp.sub_segmento
    WHEN 'LM'   THEN 1 WHEN 'CORP' THEN 2 WHEN 'SMB'  THEN 3
    WHEN 'HILO' THEN 4 WHEN 'LOLO' THEN 5 WHEN 'MILO' THEN 6
    ELSE 7
  END;
