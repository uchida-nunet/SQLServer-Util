USE [master]
GO

-- =========================================================
:CONNECT VM-01
-- エンドポイントの作成 (プライマリ)
CREATE ENDPOINT [Hadr_endpoint] 
	STATE=STARTED
	AS TCP (LISTENER_PORT = 5022)
	FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES)
GO

-- エンドポイントへの権限の付与 (プライマリ)
CREATE LOGIN [VM-01\SQLServiceUser] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [VM-01\SQLServiceUser]
GO

-- =========================================================
:CONNECT VM-02
-- エンドポイントの作成 (セカンダリ)
CREATE ENDPOINT [Hadr_endpoint] 
	STATE=STARTED
	AS TCP (LISTENER_PORT = 5022)
	FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES)
GO

-- エンドポイントへの権限の付与 (セカンダリ)
CREATE LOGIN [VM-02\SQLServiceUser] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [VM-02\SQLServiceUser]
GO

-- =========================================================
:CONNECT VM-01
-- 可用性グループの作成 (プライマリ)
CREATE AVAILABILITY GROUP [AG-01]
WITH (AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
-- BASIC
DB_FAILOVER = ON,
DTC_SUPPORT = PER_DB)
FOR 
REPLICA ON 
	N'VM-01' WITH (ENDPOINT_URL = N'TCP://VM-01.alwayson.local:5022', SEEDING_MODE = AUTOMATIC, FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, SESSION_TIMEOUT = 10, BACKUP_PRIORITY = 50, PRIMARY_ROLE(ALLOW_CONNECTIONS = ALL), SECONDARY_ROLE(ALLOW_CONNECTIONS = ALL)),
	N'VM-02' WITH (ENDPOINT_URL = N'TCP://VM-02.alwayson.local:5022', SEEDING_MODE = AUTOMATIC, FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, SESSION_TIMEOUT = 10, BACKUP_PRIORITY = 50, PRIMARY_ROLE(ALLOW_CONNECTIONS = ALL), SECONDARY_ROLE(ALLOW_CONNECTIONS = ALL));
GO

-- 自動シード処理用の権付与
ALTER AVAILABILITY GROUP [AG-01] GRANT CREATE ANY DATABASE

-- =========================================================
:CONNECT VM-02
-- 可用性グループに参加 (セカンダリ)
ALTER AVAILABILITY GROUP [AG-01] JOIN;
GO

-- 自動シード処理用の権付与
ALTER AVAILABILITY GROUP [AG-01] GRANT CREATE ANY DATABASE
GO

-- =========================================================
:CONNECT VM-01
-- データベースの追加
CREATE DATABASE AGDB01
GO
BACKUP DATABASE AGDB01 TO DISK=N'NUL'
GO
ALTER AVAILABILITY GROUP [AG-01] ADD DATABASE [AGDB01]
GO

-- DB のシード処理の再実行
ALTER AVAILABILITY GROUP [AG-01]  MODIFY REPLICA ON N'VM-01' 
WITH (SEEDING_MODE= AUTOMATIC)
GO
ALTER AVAILABILITY GROUP [AG-01]  MODIFY REPLICA ON N'VM-02' 
WITH (SEEDING_MODE= AUTOMATIC)
GO


-- =========================================================
-- リスナーの作成
USE [master]
GO
ALTER AVAILABILITY GROUP [AG-01]
ADD LISTENER N'AG-01-LN' (
WITH IP
((N'10.0.0.122', N'255.255.255.0')
)
, PORT=1433);
GO

/*
USE [master]
GO
ALTER AVAILABILITY GROUP [AG-01]
ADD LISTENER N'AG-01-LN' (
WITH DHCP
 ON (N'10.0.0.0', N'255.0.0.0'
)
, PORT=1433);
GO
*/

-- =========================================================
-- 読み取りセカンダリの設定
USE [master] 
GO

ALTER AVAILABILITY GROUP [AG-01]
MODIFY REPLICA ON N'VM-01' 
WITH ( 
SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'TCP://VM-01.alwayson.local:1433') 
)
GO

ALTER AVAILABILITY GROUP [AG-01]
MODIFY REPLICA ON N'VM-02' 
WITH ( 
SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'TCP://VM-02.alwayson.local:1433') 
)
GO

-- 従来までのセカンダリへのアクセス方法
ALTER AVAILABILITY GROUP [AG-01] 
MODIFY REPLICA ON N'VM-01'
WITH ( 
PRIMARY_ROLE(READ_ONLY_ROUTING_LIST=(N'VM-02', N'VM-01') 
))
GO

ALTER AVAILABILITY GROUP [AG-01] 
MODIFY REPLICA ON N'VM-02'
WITH ( 
PRIMARY_ROLE(READ_ONLY_ROUTING_LIST=(N'VM-01', N'VM-02') 
))
GO

-- 負荷分散セカンダリ
ALTER AVAILABILITY GROUP [AG-01] 
MODIFY REPLICA ON N'VM-01'
WITH ( 
PRIMARY_ROLE(READ_ONLY_ROUTING_LIST=((N'VM-02', N'VM-01')) 
))
GO

ALTER AVAILABILITY GROUP [AG-01] 
MODIFY REPLICA ON N'VM-02'
WITH ( 
PRIMARY_ROLE(READ_ONLY_ROUTING_LIST=((N'VM-01', N'VM-02'))
))
GO
