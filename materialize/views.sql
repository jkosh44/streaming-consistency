CREATE SECRET pgpass AS 'abc';
CREATE CONNECTION pg_connection TO POSTGRES (
       HOST 'postgres',
       PORT 5432,
       USER 'materialize',
       PASSWORD SECRET pgpass,
       DATABASE 'postgres'
);

CREATE SOURCE transactions_source
  FROM POSTGRES CONNECTION pg_connection (PUBLICATION 'mz_source')
  FOR TABLES (transactions AS raw_transactions);

CREATE MATERIALIZED VIEW transactions AS
SELECT
    *
FROM
    raw_transactions;
-- TODO: Figure out how to get temporal filters to work properly to reject some updates. The python
-- script generates records from 2021, which is less than now - 5 seconds.
--
-- WHERE
--    mz_now() <= ts + INTERVAL '5 sec';

CREATE MATERIALIZED VIEW accepted_transactions AS
SELECT
    id
FROM
    transactions;

CREATE MATERIALIZED VIEW outer_join AS
SELECT
    t1.id AS id, 
    t2.id AS other_id
FROM
    (SELECT id FROM transactions) AS t1
LEFT JOIN
    (SELECT id FROM transactions) AS t2
ON
    t1.id = t2.id;

CREATE MATERIALIZED VIEW credits AS
SELECT
    to_account AS account, 
    sum(amount) AS credits
FROM
    transactions
GROUP BY
    to_account;

CREATE MATERIALIZED VIEW debits AS
SELECT
    from_account AS account, 
    sum(amount) AS debits
FROM
    transactions
GROUP BY
    from_account;

CREATE MATERIALIZED VIEW balance AS
SELECT
    COALESCE(credits.account, debits.account) AS account,
    COALESCE(credits, 0) - COALESCE(debits, 0) AS balance
FROM
    credits FULL OUTER JOIN debits ON credits.account = debits.account;

CREATE MATERIALIZED VIEW total AS
SELECT
    sum(balance)
FROM
    balance;