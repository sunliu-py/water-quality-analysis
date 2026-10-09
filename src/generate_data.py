"""
generate_data.py
生成水质监测模拟数据并入库

功能：
    1. 随机生成 5 站点 × 8 指标的监测数据
    2. 不同指标按不同范围生成数值
    3. 分批插入 MySQL，每 1000 条提交一次
"""

# 导入数据库、随机数、时间库
import pymysql
import random
from datetime import datetime,timedelta

# 连接 MySQL，autocommit=False 表示手动提交
conn=pymysql.connect(
    host='localhost',
    port=3306,
    user='root',
    passwd='123456', # 改成你自己的数据库密码
    database='water_monitor',
    autocommit=False
)
# 创建游标，用来执行 SQL
cur = conn.cursor()
# 站点
site_id_list = [1,2,3,4,5]
# 指标
indictor_list = [1,2,3,4,5,6,7,8]
# 数据从 2025-08-01 开始
star_time = datetime(2025,8,1,0,0,0)

# 空列表 攒够 1000 条再批量插入
batch_list = []

# 生成 5000 条数据
total_rows = 5000

# 循环 5000 次，每次生成一条
for i in range(total_rows):
    # 随机选一个站点和一个指标
    s_id =  random.choice(site_id_list)
    i_id = random.choice(indictor_list)

    # 不同指标生成不同范围的随机值
    if i_id==1:
        monitor_values=round(random.uniform(0,60),2)
    elif i_id==2:
        monitor_values=round(random.uniform(0,15),2)
    elif i_id==3:
        monitor_values=round(random.uniform(0,7),2)
    elif i_id==4:
            monitor_values=round(random.uniform(0,0.8),2)
    elif i_id==5:
            monitor_values=round(random.uniform(0,20),2)
    elif i_id==6:
            monitor_values=round(random.uniform(6,10),2)
    elif i_id==7:
            monitor_values=round(random.uniform(0,8),2)
    elif i_id==8:
            monitor_values=round(random.uniform(2,16),2)
    else:
        None

    # 每条数据时间加 1 天
    collect_dt=star_time + timedelta(days=i)

    # 把一条记录打包成元组，加进批次
    one_row=(s_id,i_id,monitor_values,collect_dt)
    batch_list.append(one_row)


    # 每 1000 条批量插入并提交
    if len(batch_list)>=1000:
          sql='''
          insert into water_quality(site_id,indictor_id,value,collect_time)
          values(%s,%s,%s,%s)
          '''
          cur.executemany(sql,batch_list)
          conn.commit()
          batch_list.clear()

# 插入最后不足 1000 条的数据
if len(batch_list)>0:
    sql='''
    insert into water_quality(site_id,indictor_id,value,collect_time)
    values(%s,%s,%s,%s)
    '''
    cur.executemany(sql,batch_list)
    conn.commit()
# 关闭游标和连接
cur.close()
conn.close()

print('数据插入完毕')