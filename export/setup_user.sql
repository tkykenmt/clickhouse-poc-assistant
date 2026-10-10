-- Create a read-only user for the sizing export. Run once as an admin user.
-- The user can read system tables and object names only; it cannot read rows from your tables.
CREATE USER IF NOT EXISTS sizing_reader IDENTIFIED BY '<choose a strong password>';
GRANT SHOW DATABASES, SHOW TABLES, SHOW COLUMNS, SHOW DICTIONARIES ON *.* TO sizing_reader;
GRANT SELECT ON system.* TO sizing_reader;
-- clusterAllReplicas() needs these two to read every replica.
GRANT REMOTE ON *.* TO sizing_reader;
GRANT CREATE TEMPORARY TABLE ON *.* TO sizing_reader;

-- When the export is done:
-- DROP USER sizing_reader;
