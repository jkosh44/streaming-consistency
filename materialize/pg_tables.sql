CREATE TABLE transactions (id INT, from_account INT, to_account INT, amount double precision, ts TIMESTAMP);
ALTER TABLE transactions REPLICA IDENTITY FULL;
CREATE PUBLICATION mz_source FOR TABLE transactions;

CREATE USER materialize PASSWORD 'abc';
ALTER ROLE materialize WITH REPLICATION;
GRANT CONNECT ON DATABASE postgres TO materialize;
GRANT USAGE ON SCHEMA internal_consistency TO materialize;
GRANT SELECT ON transactions TO materialize;
