/* Проект: Анализ базы доноров
 * Автор: Алексей Котов
 * Почта: alexkotov1001@yandex.ru
 */


-- 1. Определим регионы с наибольшим количеством зарегистрированных доноров.
SELECT region, 
	   COUNT(id) AS donor_count
FROM donorsearch.user_anon_data
GROUP BY region
ORDER BY donor_count DESC
LIMIT 10;
/* Много доноров находится в крупных городах,
 * но видим, что большая часть вообще не указала регион
 * (либо их региона нет в списке при регистрации) - это стоит исправить.
 */


-- 2. Изучим динамику общего количества донаций в месяц за 2022 и 2023 годы.
SELECT DATE_TRUNC('month', donation_date::timestamp) AS date,
       COUNT(*) AS donation_count
FROM donorsearch.donation_anon
WHERE donation_date BETWEEN '2022-01-01' AND '2023-12-31'
GROUP BY date
ORDER BY date ASC;
/* В 2022 году наблюдается устойчивый рост числа дотаций, 
 * а в 2023 наблюдается устойчивая убыль.
 * Пики активности весной (март-апрель).
 */


-- 3. Определим наиболее активных доноров в системе, учитывая только данные о зарегистрированных и подтвержденных донациях.
SELECT id,
	   confirmed_donations
FROM donorsearch.user_anon_data
ORDER BY confirmed_donations DESC
LIMIT 20;


-- 4. Оценим, как система бонусов влияет на зарегистрированные в системе донации.
WITH donor_bonus AS
  (SELECT u.id,
          u.confirmed_donations,
          COALESCE(b.user_bonus_count, 0) AS user_bonus_count
   FROM donorsearch.user_anon_data AS u
   LEFT JOIN donorsearch.user_anon_bonus AS b ON u.id = b.user_id)
SELECT CASE
           WHEN user_bonus_count > 0 THEN 'Получали бонусы'
           ELSE 'Не получали бонусы'
       END AS bonus_status,
       COUNT(id) AS donor_count,
       AVG(confirmed_donations) AS avg_count_donations
FROM donor_bonus
GROUP BY bonus_status;
-- Доноры, получающие бонусы, делают значительно больше донаций.


-- 5. Исследуем вовлечение новых доноров через социальные сети. 
-- Сколько по каким каналам пришло доноров, и среднее количество донаций по каждому каналу.

-- Иммет смысл сначала узнать количество донор каждой соцсети перед запросами ниже.
WITH social_donors AS
	(SELECT id,
	        confirmed_donations,
			autho_vk :: int,
			autho_ok :: int,
			autho_tg :: int,
			autho_yandex :: int,
			autho_google :: int
	 FROM donorsearch.user_anon_data
	)
SELECT 
	   SUM(autho_vk) AS autho_vk,
	   SUM(autho_ok) AS autho_ok,
	   SUM(autho_tg) AS autho_tg,
	   SUM(autho_yandex) AS autho_yandex,
	   SUM(autho_google) AS autho_google
FROM social_donors;
-- Основной запрос
SELECT CASE
           WHEN autho_tg THEN 'Telegram'
           WHEN autho_yandex THEN 'Яндекс'
           WHEN autho_ok THEN 'Одноклассники'
           WHEN autho_google THEN 'Google'
           WHEN autho_vk THEN 'ВКонтакте'
           ELSE 'Без авторизации через соцсети'
       END AS social_network,
       COUNT(id) AS count_donors,
       AVG(confirmed_donations) AS avg_count_donations
FROM donorsearch.user_anon_data
GROUP BY social_network
ORDER BY avg_count_donations DESC;
/* Доноры, не использующие социальные сети для авторизации или зарегистрированные в Одноклассниках, показывают низкий уровень активности.
 * Количество донаций пользователей Телеграм и Яндекса самое большое, но количество пользователей значительно меньше ВКонтакте и без регистрации.
 * В данном решении есть недостаток: доноры учтенные в соцсетях выше, уже не учитываются в соцсетях ниже по списку!
 * Но именно поэтому в CASE стоят соцсети по возрастанию количества доноров.
 */

WITH social_donors AS
	(SELECT id,
	        confirmed_donations,
			autho_vk :: int,
			autho_ok :: int,
			autho_tg :: int,
			autho_yandex :: int,
			autho_google :: int
	 FROM donorsearch.user_anon_data
	)
SELECT (autho_vk :: int + autho_ok :: int + autho_tg :: int + autho_yandex :: int +
		autho_google :: int) AS count_social_networks,
	   COUNT(id) AS count_donors,
       AVG(confirmed_donations) AS avg_count_donations
FROM social_donors
GROUP BY count_social_networks
ORDER BY avg_count_donations DESC;
/* В данном запросе уже лучше видно, что существует связь: чем больше соцсетей, тем больше донаций.
 * Социально активные, общительные люди.
 */


-- 6. Сравним активность однократных доноров со средней активностью повторных доноров.
WITH repeat_vs_single_donors AS (
  SELECT user_id,
         COUNT(*) AS total_donations
  FROM donorsearch.donation_anon
  GROUP BY user_id
)
SELECT CASE 
           WHEN total_donations BETWEEN 0 AND 1 THEN '1 донация'
		   WHEN total_donations BETWEEN 2 AND 3 THEN '2-3 донации'
           WHEN total_donations BETWEEN 4 AND 5 THEN '4-5 донаций'
           WHEN total_donations BETWEEN 6 AND 7 THEN '6-7 донаций'
           WHEN total_donations BETWEEN 8 AND 9 THEN '8-9 донаций'
           ELSE '10 и более донаций'
       END AS donation_frequency_group,
	   COUNT(*) AS count_donors
FROM repeat_vs_single_donors
GROUP BY donation_frequency_group
ORDER BY count_donors DESC;
/* Видим, что количество единократных доноров крайне большое по сравнению с количеством повторных доноров.
 * Надо стимулировать повторную сдачу донаций и понять причины, почему повторно не совершают донации.
 */

-- Группировка по времени: рассмотрим, как изменяется активность доноров в зависимости от года первой донации.
-- Анализ частоты донаций: разделим повторных доноров по количеству донаций (например, 2-3, 4-5, 6 и более донаций).
-- Возраст активности доноров: выясним, сколько времени прошло с первой донации до текущего момента, чтобы понять, насколько давними являются активные доноры.
WITH donor_activity AS (
  SELECT user_id,
         COUNT(*) AS total_donations,
         (MAX(donation_date) - MIN(donation_date)) AS activity_duration_days,
         (MAX(donation_date) - MIN(donation_date)) / (COUNT(*) - 1) AS avg_days_between_donations,
         EXTRACT(YEAR FROM MIN(donation_date)) AS first_donation_year,
         EXTRACT(YEAR FROM AGE(CURRENT_DATE, MIN(donation_date))) AS years_since_first_donation
  FROM donorsearch.donation_anon
  GROUP BY user_id
  HAVING COUNT(*) > 1
)
SELECT first_donation_year,
       CASE 
           WHEN total_donations BETWEEN 2 AND 3 THEN '2-3 донации'
           WHEN total_donations BETWEEN 4 AND 5 THEN '4-5 донаций'
           ELSE '6 и более донаций'
       END AS donation_frequency_group,
       COUNT(user_id) AS donor_count,
       AVG(total_donations) AS avg_donations_per_donor,
       AVG(activity_duration_days) AS avg_activity_duration_days,
       AVG(avg_days_between_donations) AS avg_days_between_donations,
       AVG(years_since_first_donation) AS avg_years_since_first_donation
FROM donor_activity
WHERE first_donation_year > 1990
GROUP BY first_donation_year, donation_frequency_group
ORDER BY first_donation_year, donation_frequency_group;
/* Были выявлены аномалии в данных о годе первой донации, поэтому была фильтрация года больше 1990.
 * Вывод: Повторные доноры — ключевая аудитория. Они совершают большее количество донаций.
 */


-- 7. Сравнение данных о планируемых донациях с фактическими данными, чтобы оценить эффективность планирования.
WITH planned_donations AS (
  SELECT user_id, donation_date, donation_type
  FROM donorsearch.donation_plan
),
actual_donations AS (
  SELECT user_id, donation_date, donation_type
  FROM donorsearch.donation_anon
),
planned_vs_actual AS (
  SELECT
    pd.user_id,
    pd.donation_date AS planned_date,
    pd.donation_type,
    CASE WHEN ad.user_id IS NOT NULL THEN 1 ELSE 0 END AS completed
  FROM planned_donations pd
  LEFT JOIN actual_donations ad ON pd.user_id = ad.user_id AND pd.donation_date = ad.donation_date
--  AND pd.donation_type = ad.donation_type -- если учитывать тип донации: «платно» или «безвозмездно».
)
SELECT
  donation_type,
  COUNT(*) AS total_planned_donations,
  SUM(completed) AS completed_donations,
  ROUND(SUM(completed) * 100.0 / COUNT(*), 2) AS completion_rate
FROM planned_vs_actual
GROUP BY donation_type;
-- Процент выполнения плана донаций низок для обоих типов доноров.


-- 8. Оценка влияния пола на количество донаций
WITH repeat_vs_single_donors AS (
  SELECT user_id,
  		 gender,
         COUNT(*) AS total_donations
  FROM donorsearch.donation_anon AS da
  LEFT JOIN donorsearch.user_anon_data AS uad ON da.user_id = uad.id 
  GROUP BY user_id, gender
)
SELECT CASE 
           WHEN total_donations BETWEEN 0 AND 1 THEN '1 донация'
		   WHEN total_donations BETWEEN 2 AND 3 THEN '2-3 донации'
           WHEN total_donations BETWEEN 4 AND 6 THEN '4-6 донаций'
           ELSE '7 и более донаций'
       END AS donation_frequency_group,
       gender,
	   COUNT(*) AS count_donors
FROM repeat_vs_single_donors
GROUP BY donation_frequency_group, gender
ORDER BY donation_frequency_group, gender;
/* Существенных различий в количестве донаций от пола нет, 
 * кроме группы "7 и более донаций", где мужчин в 1.5 раза больше.
 * Стоит отметить, что большое количество доноров не указало свой пол, 
 * из-за этого выводы могут быть неверными.
 */

