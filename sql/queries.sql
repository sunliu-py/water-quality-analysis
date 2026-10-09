-- ============================================================
-- queries.sql
-- 水质监测数据分析查询
--
-- 功能：
--   1. 从监测数据派生预警记录
--   2. 7 条分析查询：
--      - 各站点各指标月均值
--      - 各指标超标率和超标条数
--      - 各站点超标次数
--      - 各指标超标次数
--      - 各站点最近一次超标
--      - 各站点 COD 环比
--      - 预警等级分布
--
-- 执行方式：
--   mysql -u root -p < sql/queries.sql
--
-- 依赖：
--   必须先执行 schema.sql 和 init_data.sql
-- ============================================================

USE water_monitor;

-- ------------------------------------------------------------
-- 从监测数据派生预警记录
-- 规则：
--   value > 国标上限 × 1.5  → 高
--   value > 国标上限        → 中
--   value < 国标下限        → 低（异常低值）
-- 用事务保证：要么全部插入，要么全部回滚
-- ------------------------------------------------------------
-- 对所有的超标记录，进行低中高的判断，超过i.standard_max * 1.5 为高，超过wq.value > i.standard_max为中，其余为低。
start transaction;
insert
	into
	alarm_record (record_id,
	create_time,
	alarm_level)
select
	wq.record_id ,
	wq.collect_time,
	case 
		when wq.value > i.standard_max * 1.5 then '高'
		when wq.value > i.standard_max then '中'
		else '低'
	end as alarm_level
from
	indictor i
join water_quality wq on
	i.indictor_id = wq.indictor_id
where wq.value > i.standard_max or wq.value < i.standard_min;

commit ;


-- ------------------------------------------------------------
-- 补充预警说明
-- 根据 alarm_level 回填 alarm_msg：
--   中 → 超过国标上限
--   高 → 超过 1.5 倍国标上限
--   低 → 低于国标下限
-- ------------------------------------------------------------
-- 预警说明
start transaction;
update
	alarm_record ar
set
	alarm_mas = case
		when alarm_level = '中' then '超过国标上限'
		when alarm_level = '高' then '超过1.5倍国标上限'
		when alarm_level = '低' then '低于国标下限'
		else ar.alarm_mas
	end ;
commit ;



-- ------------------------------------------------------------
-- 查询 1：每个站点每项指标的月均值
-- 思路：site JOIN water_quality JOIN indictor，按 站点+指标+年+月 分组
-- ------------------------------------------------------------
select
	s.site_name ,i.indictor_name,YEAR(wq.collect_time ),MONTH(wq.collect_time ),avg(wq.value)
from
	site s
join water_quality wq on
	s.site_id = wq.site_id
join indictor i on
	wq.indictor_id = i.indictor_id
group by wq.site_id ,wq.indictor_id ,YEAR(wq.collect_time ),MONTH(wq.collect_time ),s.site_name,i.indictor_name;



-- ------------------------------------------------------------
-- 查询 2：各指标超标条数和超标率
-- 思路：
--   子查询 t 先算每个指标的总条数
--   主查询 JOIN t，统计超标条数
--   超标率 = 超标条数 / 总条数 × 100
-- 注意：超标 = value > 国标上限 或 value < 国标下限
-- ------------------------------------------------------------
select
	i.indictor_id ,
	i.indictor_name ,
	t.total_cnt as '总条数',
	count(wq.record_id) '超标条数',
	round(count(wq.record_id)/t.total_cnt *100,2) as '超标率%'
from
	water_quality wq
join indictor i on
	wq.indictor_id = i.indictor_id
join (
	select
		i.indictor_name ,
		i.indictor_id ,
		count(wq.record_id) total_cnt
	from
		water_quality wq
	join indictor i on
		wq.indictor_id = i.indictor_id
	group by
		wq.indictor_id) as t on
	t.indictor_id = i.indictor_id
where
	wq.value > i.standard_max
	or wq.value <i.standard_min
group by
	wq.indictor_id ;



-- ------------------------------------------------------------
-- 查询 3：各站点超标次数
-- 思路：用 SUM(IF(超标, 1, 0)) 统计
-- ------------------------------------------------------------
select
	s.site_name ,sum(if(wq.value >i.standard_max  or wq.value <i.standard_min,1,0)) 'Number of exceedances'
from
	site s
join water_quality wq on
	s.site_id = wq.site_id
join indictor i on
	wq.indictor_id = i.indictor_id
group by s.site_id ,s.site_name 
order by sum(if(wq.value >i.standard_max  or wq.value <i.standard_min,1,0)) desc;



-- ------------------------------------------------------------
-- 查询 4：各指标超标次数，降序排列
-- 用途：定位最容易超标的指标
-- ------------------------------------------------------------
-- 哪项指标最容易超标？
select
	i.indictor_name ,sum(if(wq.value > i.standard_max
	or wq.value <i.standard_min,1,0)) as cccf
from
	water_quality wq
join indictor i on
	wq.indictor_id = i.indictor_id
group by wq.indictor_id 
order by cccf  desc;



-- ------------------------------------------------------------
-- 查询 5：每个站点最近一次超标时间
-- 思路：筛选超标记录，按站点分组取 MAX(collect_time)
-- 用途：判断哪些站点最近有问题
-- ------------------------------------------------------------
select
    s.site_name ,
	max(wq.collect_time)
from
	site s
join water_quality wq on
	s.site_id = wq.site_id
join indictor i on
	wq.indictor_id = i.indictor_id
where wq.value > i.standard_max
	or wq.value <i.standard_min
group by wq.site_id, s.site_name;



-- ------------------------------------------------------------
-- 查询 6：各站点 COD 月均值环比（本月 vs 上月）
-- 思路：
--   子查询 a 算本月均值，子查询 b 算上月均值
--   LEFT JOIN 条件：a.site_id = b.site_id
--                AND a.indictor_id = b.indictor_id
--                AND PERIOD_ADD(a.ym_key, -1) = b.ym_key
--   PERIOD_ADD('202502', -1) → '202501'，即上月
-- 注意：
--   1. 用 LEFT JOIN 保留第一个月（上月为 NULL）
--   2. CASE 防除零
-- 用途：分析短期波动
-- ------------------------------------------------------------
select
	a.site_id,
	a.indictor_id,
	round(a.avg_value, 2) as '本月均值',
	round(b.avg_value , 2) as '上月均值',
	case
		when a.avg_value is null
		or a.avg_value = 0 then null
		else round((a.avg_value - b.avg_value) / b.avg_value * 100 , 2)
		end as '环比%'
	from
		(
		select
			s.site_id ,
			i.indictor_id,
			year(wq.collect_time),
			month(wq.collect_time),
			avg(wq.value) avg_value,
			DATE_FORMAT(wq.collect_time, '%Y%m') as ym_key
		from
			water_quality wq
		join site s on
			wq.site_id = s.site_id
		join indictor i on
			wq.indictor_id = i.indictor_id
		where
			wq.indictor_id in (
			select
				i.indictor_id
			from
				indictor i
			where
				i.indictor_name = 'COD')
		group by
			wq.site_id ,
			year(wq.collect_time),
			month(wq.collect_time) ,
			i.indictor_id,
			DATE_FORMAT(wq.collect_time, '%Y%m')
		order by
			s.site_id ,
			year(wq.collect_time),
			month(wq.collect_time)

) as a
	left join (
		select
			s.site_id ,
			i.indictor_id,
			year(wq.collect_time),
			month(wq.collect_time),
			avg(wq.value) avg_value,
			DATE_FORMAT(wq.collect_time, '%Y%m') as ym_key
		from
			water_quality wq
		join site s on
			wq.site_id = s.site_id
		join indictor i on
			wq.indictor_id = i.indictor_id
		where
			wq.indictor_id in (
			select
				i.indictor_id
			from
				indictor i
			where
				i.indictor_name = 'COD')
		group by
			wq.site_id ,
			year(wq.collect_time),
			month(wq.collect_time) ,
			i.indictor_id,
			DATE_FORMAT(wq.collect_time, '%Y%m')
		order by
			s.site_id ,
			year(wq.collect_time),
			month(wq.collect_time)) as b on
		a.site_id = b.site_id
		and a.indictor_id = b.indictor_id
		and period_add(a.ym_key,-1)= b.ym_key  ;



-- ------------------------------------------------------------
-- 查询 7：预警等级分布（高/中/低各多少条）
-- 思路：按 alarm_level 分组计数
-- 用途：画饼图或柱状图展示预警构成
-- ------------------------------------------------------------
-- 预警等级分布（高/中/低各多少条）？
select
	ar.alarm_level ,
	count(ar.alarm_level) '总条数'
from
	alarm_record ar
group by
	ar.alarm_level,
	ar.alarm_level ;
