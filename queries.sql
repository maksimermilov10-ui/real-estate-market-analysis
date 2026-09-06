-- =============================================================
-- Проект: Анализ данных для агентства недвижимости
-- Схема: real_estate (Яндекс Недвижимость — СПб и Ленобласть)
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- Знакомство с данными
-- ─────────────────────────────────────────────────────────────

-- Период выгрузки объявлений
SELECT
  MIN(first_day_exposition) AS min_date,
  MAX(first_day_exposition) AS max_date
FROM real_estate.advertisement;

-- Количество городов и объявлений по типу населённого пункта
SELECT
  t.type AS locality_type,
  COUNT(DISTINCT c.city_id) AS cities_cnt,
  COUNT(a.id) AS ads_cnt
FROM real_estate.advertisement a
JOIN real_estate.flats f ON f.id = a.id
JOIN real_estate.city  c ON c.city_id = f.city_id
JOIN real_estate.type  t ON t.type_id = f.type_id
GROUP BY t.type
ORDER BY ads_cnt DESC;

-- Длительность активности объявлений (мин/макс/среднее/медиана)
SELECT
  MIN(days_exposition) AS min_days,
  MAX(days_exposition) AS max_days,
  ROUND(AVG(days_exposition)::numeric, 2) AS avg_days,
  percentile_disc(0.5) WITHIN GROUP (ORDER BY days_exposition) AS median_days
FROM real_estate.advertisement
WHERE days_exposition IS NOT NULL;

-- Доля закрытых (снятых) объявлений
SELECT
  ROUND( (COUNT(days_exposition) * 100.0 / COUNT(*))::numeric, 2 ) AS pct_closed
FROM real_estate.advertisement;

-- Доля объявлений по Санкт-Петербургу
SELECT
  ROUND(
    (COUNT(*) FILTER (WHERE c.city = 'Санкт-Петербург') * 100.0 / COUNT(*))::numeric
  , 2) AS pct_spb
FROM real_estate.advertisement a
JOIN real_estate.flats f ON f.id = a.id
JOIN real_estate.city  c ON c.city_id = f.city_id;

-- Стоимость квадратного метра: мин/макс/среднее/медиана
WITH t AS (
  SELECT
    (a.last_price / f.total_area) AS price_per_m2
  FROM real_estate.advertisement a
  JOIN real_estate.flats f ON f.id = a.id
  WHERE a.last_price IS NOT NULL
    AND f.total_area IS NOT NULL
    AND f.total_area > 0
)
SELECT
  ROUND(MIN(price_per_m2)::numeric, 2) AS min_ppm2,
  ROUND(MAX(price_per_m2)::numeric, 2) AS max_ppm2,
  ROUND(AVG(price_per_m2)::numeric, 2) AS avg_ppm2,
  ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY price_per_m2)::numeric, 2) AS median_ppm2
FROM t;


-- ─────────────────────────────────────────────────────────────
-- Задача 1. Время активности объявлений
-- Цель: определить самые привлекательные сегменты недвижимости
-- СПб и Ленобласти по времени активности объявлений.
-- ─────────────────────────────────────────────────────────────

WITH limits AS (
    SELECT
        percentile_cont(0.99) WITHIN GROUP (ORDER BY total_area)      AS total_area_p99,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY rooms)           AS rooms_p99,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY balcony)         AS balcony_p99,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY ceiling_height)  AS ceiling_height_p99,
        percentile_cont(0.01) WITHIN GROUP (ORDER BY ceiling_height)  AS ceiling_height_p01
    FROM real_estate.flats
    WHERE total_area IS NOT NULL AND total_area > 0
),
valid_ids AS (
    -- Отсекаем аномальные значения (99-й/1-й перцентиль) — фильтр выбросов
    SELECT f.id
    FROM real_estate.flats f
    CROSS JOIN limits l
    WHERE f.total_area IS NOT NULL AND f.total_area > 0
      AND f.total_area <= l.total_area_p99
      AND (f.rooms IS NULL OR f.rooms <= l.rooms_p99)
      AND (f.balcony IS NULL OR f.balcony <= l.balcony_p99)
      AND f.ceiling_height IS NOT NULL
      AND f.ceiling_height BETWEEN l.ceiling_height_p01 AND l.ceiling_height_p99
),
prep AS (
    SELECT
        a.id,
        CASE
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        CASE
            WHEN a.days_exposition IS NULL THEN 'non category'
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            ELSE '181+ days'
        END AS expo_category,
        (a.last_price / f.total_area) AS price_per_m2,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        f.floor
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON f.id = a.id
    JOIN real_estate.city c  ON c.city_id = f.city_id
    JOIN real_estate.type t  ON t.type_id = f.type_id
    WHERE a.id IN (SELECT id FROM valid_ids)
      AND t.type = 'город'
      AND a.first_day_exposition >= DATE '2015-01-01'
      AND a.first_day_exposition <  DATE '2019-01-01'
      AND a.last_price IS NOT NULL
      AND f.total_area IS NOT NULL
      AND f.total_area > 0
)
SELECT
    region,
    expo_category,
    COUNT(*) AS ads_cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY region), 2) AS share_in_region_pct,
    ROUND(AVG(price_per_m2)::numeric, 2) AS avg_price_per_m2,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY price_per_m2)::numeric, 2) AS med_price_per_m2,
    ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY total_area)::numeric, 2) AS med_total_area,
    ROUND(AVG(rooms)::numeric, 2) AS avg_rooms,
    ROUND(AVG(balcony)::numeric, 2) AS avg_balcony,
    ROUND(AVG(ceiling_height)::numeric, 2) AS avg_ceiling_height,
    ROUND(AVG(floor)::numeric, 2) AS avg_floor
FROM prep
GROUP BY region, expo_category
ORDER BY region, CASE
    WHEN expo_category = '1-30 days' THEN 1
    WHEN expo_category = '31-90 days' THEN 2
    WHEN expo_category = '91-180 days' THEN 3
    WHEN expo_category = '181+ days' THEN 4
    WHEN expo_category = 'non category' THEN 5
END;


-- ─────────────────────────────────────────────────────────────
-- Задача 2. Сезонность объявлений
-- Цель: выявить сезонные тенденции публикации и снятия
-- объявлений в СПб и Ленобласти.
-- ─────────────────────────────────────────────────────────────

WITH base AS (
    SELECT
        a.id,
        a.first_day_exposition::date AS pub_date,
        CASE
            WHEN a.days_exposition IS NOT NULL
                 THEN (a.first_day_exposition::date + (a.days_exposition::int * INTERVAL '1 day'))::date
            ELSE NULL
        END AS close_date,
        (a.last_price / f.total_area) AS price_per_m2,
        f.total_area
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON f.id = a.id
    JOIN real_estate.type t ON t.type_id = f.type_id
    WHERE t.type = 'город'
      AND a.first_day_exposition >= DATE '2015-01-01'
      AND a.first_day_exposition <  DATE '2019-01-01'
      AND a.last_price IS NOT NULL
      AND f.total_area IS NOT NULL
      AND f.total_area > 0
),
pub AS (
    SELECT
        EXTRACT(MONTH FROM pub_date)::int AS month_num,
        COUNT(*) AS pub_cnt,
        ROUND(AVG(price_per_m2)::numeric, 2) AS pub_avg_price_m2,
        ROUND(AVG(total_area)::numeric, 2)   AS pub_avg_total_area
    FROM base
    GROUP BY 1
),
cls AS (
    SELECT
        EXTRACT(MONTH FROM close_date)::int AS month_num,
        COUNT(*) AS close_cnt,
        ROUND(AVG(price_per_m2)::numeric, 2) AS close_avg_price_m2,
        ROUND(AVG(total_area)::numeric, 2)   AS close_avg_total_area
    FROM base
    WHERE close_date IS NOT NULL
      AND close_date >= DATE '2015-01-01'
      AND close_date <  DATE '2019-01-01'
    GROUP BY 1
),
months AS (
    SELECT generate_series(1, 12) AS month_num
)
SELECT
    m.month_num,
    COALESCE(p.pub_cnt, 0) AS pub_cnt,
    ROUND(p.pub_avg_price_m2::numeric, 2) AS pub_avg_price_m2,
    ROUND(p.pub_avg_total_area::numeric, 2) AS pub_avg_total_area,
    COALESCE(c.close_cnt, 0) AS close_cnt,
    ROUND(c.close_avg_price_m2::numeric, 2) AS close_avg_price_m2,
    ROUND(c.close_avg_total_area::numeric, 2) AS close_avg_total_area
FROM months m
LEFT JOIN pub p ON p.month_num = m.month_num
LEFT JOIN cls c ON c.month_num = m.month_num
ORDER BY m.month_num;
