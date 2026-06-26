declare v_uri string;
declare v_datadt date;
declare v_datadtraw string;
declare dynamicsql string;
--create table curatedds.etl_meta (id int64,rulesql string);
--insert into curatedds.etl_meta values(3,"gs://consumer-analytics-bucket/data/custs_header_20250701");
--set v_uri=(select rulesql from curatedds.etl_meta where id=3);--metadata driven approach
set v_uri='gs://wd36bucket1/data/custs_header_20240803';
set v_datadtraw=(select right(v_uri,8));
set v_datadt=(select parse_date('%Y%m%d',v_datadtraw));
/* Concepts Added in this 10.A usecase
What is the difference between 
Datalake(scalable FS storage layer which accepts any type/volume of data) , 
Lakehouse (managed/native table) (If I am enabling a Datawarehouse (house) on top the datalake by OWNING the data in the Datalake)
Biglake (External Table) (If I am enabling a Datawarehouse (house) on top the datalake by REFERRING the data in the Datalake)
External table restrictions - cloud side (data will not be stored in Colossus/Jupyter network), cannot be truncated, updated/deleted or data will not be dropped if table is dropped
1. BigLake (External Table Concept)
2. Dynamic SQL, Metadata/parameter driven approach
3. Merge Statement
4. Declare, Begin End block, Exception Handling...
5. CDC/Incremental(delta) data collection & SCD Type1(no history) & Type2 load (history is there)
*/
--CDC (Change Data Capture based on the date parameter suffixed in the filename)
--combining 3 different strings to make it as a single string by adding uri in the middle.
set dynamicsql=CONCAT('CREATE OR REPLACE EXTERNAL TABLE rawds.cust_ext ( custno INT64,firstname STRING,lastname STRING,age INT64,profession STRING,upd_ts timestamp) OPTIONS (  format = "CSV", uris = ["',v_uri, '"],max_bad_records = 2, skip_leading_rows=1)');

--set dynamicsql='CREATE OR REPLACE EXTERNAL TABLE rawds.cust_ext ( custno INT64,firstname STRING,lastname STRING,age INT64,profession STRING,upd_ts timestamp) OPTIONS (  format = "CSV", uris = ["%s"],max_bad_records = 2, skip_leading_rows=1)';

begin

--CREATE OR REPLACE EXTERNAL TABLE rawds.cust_ext ( custno INT64,firstname STRING,lastname STRING,age INT64,profession STRING) OPTIONS (  format = "CSV", uris = ["gs://incpetez-data-samples/dataset/bqdata/ext_src_data/custs_header_20230908"],max_bad_records = 2, skip_leading_rows=1);

--executing the single dynamic sql query string built in the above statement as a sql query using execute immediate function.
EXECUTE IMMEDIATE dynamicsql;
--EXECUTE IMMEDIATE format(dynamicsql,v_uri);
--Step1: BigLake creation is completed

--Step2: SCD2 Implementation (maintain the history and loading new data without affecting the history)
create table if not exists curatedds.cust_part_curated_scd2_append (custno INT64,name STRING,
age INT64,profession STRING,datadt date,upd_ts timestamp) partition by datadt;

--to avoid accidentially loading same day data more than 1 time..
delete from curatedds.cust_part_curated_scd2_append where datadt=v_datadt;--previous days data will be untouched..

Insert into curatedds.cust_part_curated_scd2_append
select custno, concat(firstname,",", lastname) as name,age, 
coalesce(profession,'na') as profession,
v_datadt,
upd_ts 
from rawds.cust_ext;

select datadt,COUNT(1) from curatedds.cust_part_curated_scd2_append  GROUP BY DATADT limit 10;

--Step2: Loading SCD2 table is completed


--SCD1 - If We don't want to maintain the history, we can use merge statement 

create table if not exists curatedds.cust_part_curated_scd1_merge (custno INT64,name STRING,
age INT64,profession STRING,datadt date,upd_ts timestamp) partition by datadt;

--merge is a special DML statement, can be used for performing insert or update or delete in one query itself...
MERGE `curatedds.cust_part_curated_scd1_merge` T
USING (SELECT custno, concat(firstname,",", lastname) as name,age, coalesce(profession,'na') profession,cast(v_datadt as date) datadt,upd_ts FROM rawds.cust_ext) S
ON T.custno = S.custno
WHEN MATCHED THEN
UPDATE SET T.name = S.name,T.age = S.age,T.profession = S.profession,T.datadt=S.datadt,T.upd_ts=S.upd_ts
WHEN NOT MATCHED THEN
INSERT (custno,name,age,profession,datadt,upd_ts) VALUES (S.custno,S.name,S.age,S.profession,S.datadt,S.upd_ts);

select datadt,COUNT(1) from curatedds.cust_part_curated_scd1_merge  GROUP BY DATADT limit 10;

end;
/*src:
day1:
1,chn
2,mum
day2:full/delta? delta (CDC)
1,blr
3,hyd

load1:  Dont maintain history (SCD1)
+ We dont have duplicates/size saving
- We can't see the history
target: 3
day1+2:
1,blr (u) day2
2,mum
3,hyd (i) day2

load2: Maintain history (SCD2)
- We have duplicates/size huge
+ We can see the history
day1:
1,chn,jan1
2,mum,jan1
day2:
1,blr,Jul26 (I)
3,hyd,11,Jul26 (I)
*/
