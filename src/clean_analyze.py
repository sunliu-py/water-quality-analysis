"""
clean_analyze.py
数据清洗与统计分析

功能：
    1. 从数据库读取监测数据、站点、指标，合并成宽表
    2. IQR + 3σ 异常检测
    3. 提取年月，供后续分析
"""
import pymysql
import pandas as pd


"""
从数据库读取监测数据、站点、指标三张表，合并成宽表。

返回：
    pandas.DataFrame

异常：
    pymysql.MySQLError：数据库连接或查询失败
"""
def load_data():
    try:
        # 建立数据库连接，charset 用 utf8mb4 支持中文
        with pymysql.connect(
            host='localhost',
            port=3306,
            user='root',
            password='123456',
            database='water_monitor',
            charset='utf8mb4'
        ) as conn:
            sql = 'select indictor_name,indictor_id from indictor'
            df1 = pd.read_sql('select * from water_quality',conn)
            df2 = pd.read_sql('select site_id,site_name from site',conn)
            df3 = pd.read_sql(sql,conn)
            df_merge=pd.merge(df1,df2,on='site_id',how='left')
            df = pd.merge(df_merge,df3,on='indictor_id',how='left')
            print('输出成功')
            return df

    except pymysql.MySQLError as e:
        print('出错',e)
        return None



"""
对单个分组做 IQR + 3σ 双重异常检测。

原理：
    IQR：超出 Q1-1.5×IQR 或 Q3+1.5×IQR 算异常，适合偏态分布
    3σ ：超出均值±3倍标准差算异常，适合正态分布

参数：
    group : pandas.DataFrame，同一站点+指标的数据

返回：
    pandas.DataFrame，新增两列：
        iqr_outlier    : bool，IQR 判定是否异常
        sigma3_outlier : bool，3σ 判定是否异常

注意：
    样本量 < 8 时不做检测，直接标 False。
"""
def iqr_1(path):
    # 复制一份，避免修改原数据
    g = path.copy()

     # 记录当前分组样本量
    g_len = len(g)
    g['sample_count']=g_len

    # 样本量太小，检测不可靠，直接返回全 False
    if g_len<8:
        g['iqr_outlier']=False
        g['sigma3_outlie'] = False
        return g

    # ---------- IQR 检测 ----------
    q1 = g['value'].quantile(0.25)
    q3 = g['value'].quantile(0.75)
    iqr=q3-q1
    lower = q1-1.5*iqr
    upper = q3+1.5*iqr
    g['iqr_outlier'] = ~g['value'].between(lower,upper)

    # ---------- 3σ 检测 ----------
    g_mean = g['value'].mean()
    g_std = g['value'].std()
    lower_3 = g_mean - 3*g_std
    upper_3 = g_mean + 3*g_std
    g['sigma3_outlier'] = ~g['value'].between(lower_3,upper_3)
    return g

# 按站点 + 指标分组，每组独立检测
# group_keys=False 避免多一层索引

def add_time_columns(df_merge2):
    # 从采集时间提取年份和月份，用于按年，月分组分析
    df_merge2['year'] = df_merge2['collect_time'].dt.year
    df_merge2['month'] = df_merge2['collect_time'].dt.month
    return df_merge2



if __name__ == '__main__':
    df_merge2=load_data() 
    # 按站点 + 指标分组，每组独立检测
    # group_keys=False 避免多一层索引
    df_merge2 = df_merge2.groupby(['site_id', 'indictor_id'], group_keys=False).apply(iqr_1)
    df_merge2 = add_time_columns(df_merge2)
    print(f'清洗完成')
    print(len(df_merge2))
    print(df_merge2)