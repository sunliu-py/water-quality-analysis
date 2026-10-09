-- ============================================================
-- schema.sql
-- 水质监测数据库建表与初始化脚本
-- 功能：
--   1. 创建 4 张表：site、indictor、water_quality、alarm_record
--   2. 添加主键、外键、唯一、CHECK 约束
--   3. 添加索引加速查询
-- ============================================================
-- 打开数据库
use water_monitor;


-- ------------------------------------------------------------
-- 表 1：站点表
-- 存储 5 个污水处理厂的基本信息
-- ------------------------------------------------------------

create table site(
	site_id int primary key auto_increment comment '站点编号',
	site_name varchar(20) not null unique  comment '站点名称',
	site_city varchar(20) comment '位置',
	site_time datetime  comment '创建时间'
) comment '站点表';




-- ------------------------------------------------------------
-- 表 2：指标字典表
-- 存储 8 项水质指标的国标上下限
-- ------------------------------------------------------------

create table indictor(
	indictor_id  int primary key auto_increment comment '指标编号',
	indictor_name varchar(30) not null unique comment '指标名称',
	unit varchar(10)  comment '单位',
	standard_max decimal(10,2) not null comment '国标上限',
	standard_min decimal(10,2) default 0 comment '国标下限',
	constraint ck_standard check (standard_max > standard_min)
)comment '水质指标字典表';



-- ------------------------------------------------------------
-- 表 3：监测数据表（核心）
-- 按天监测 随机存储 5 站点 × 8 指标 约 5000 条
-- 外键关联 site 和 indictor，value 加 CHECK 约束
-- ------------------------------------------------------------
create table water_quality(
	record_id int  primary key auto_increment comment '记录号',
	site_id int not null comment '站点编号',
	indictor_id int not null comment '指标编号',
	value decimal(10,2) check(value>=0) not null comment '监测值',
	collect_time datetime not null comment '采集时间',
	
	-- 外键
	constraint fk_wq_site foreign key (site_id)
	references site (site_id),
	constraint fk_wq_indictor foreign key (indictor_id)
	references indictor(indictor_id),
	
	-- 约束
	constraint ck_value check(value >=0),
	
	-- 索引
	index idx_collect_time (collect_time),
	index idx_site_indictor (site_id ,indictor_id)
	
)comment '水质检测数据表';




-- ------------------------------------------------------------
-- 表 4：预警记录表
-- 存储超标记录的预警等级和说明
-- 外键关联 water_quality，等级用 CHECK 限制为 低/中/高
-- ------------------------------------------------------------
create table alarm_record(
	alarm_id int  primary key auto_increment comment '预警编号',
	record_id int not null comment '关联检测记录',
	alarm_level varchar(10) not null comment '预警等级',
	alarm_mas varchar(200) comment '预警说明',
	create_time datetime default CURRENT_TIMESTAMP() comment '触发时间',
	
	-- 外键
	constraint fk_alarm_record foreign key (record_id)
	references water_quality (record_id),
	
	-- 约束
	constraint ck_alarm_level  check(alarm_level in ('低','中','高'))
)comment '预警记录表';