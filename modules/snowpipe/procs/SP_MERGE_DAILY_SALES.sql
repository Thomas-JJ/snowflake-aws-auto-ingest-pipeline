DECLARE
 
  -- handy fully-qualified names
  v_tbl_fq         STRING    DEFAULT DB_NAME || '.' || SCHEMA_NAME || '.' || TARGET_TABLE;
  v_stg_fq         STRING    DEFAULT DB_NAME || '.' || SCHEMA_NAME || '.' || 'STG_' || TARGET_TABLE || '_STREAM';

BEGIN TRANSACTION;

  --MERGE from Stage table into Base table
  EXECUTE IMMEDIATE
    'MERGE INTO ' || v_tbl_fq || ' AS T
       USING ' || v_stg_fq || ' AS S
         ON T.DATE = S.DATE
         AND T.STORE_ID = S.STORE_ID
     WHEN MATCHED THEN UPDATE SET
         T.NET_SALES         = S.NET_SALES,
         T.GUEST_COUNT     = S.GUEST_COUNT,
         T.UPDATED_AT     = CURRENT_TIMESTAMP(),
         T.UPDATED_BY     = ''' || SPROC_NAME ||'''
     WHEN NOT MATCHED THEN INSERT
        (
          DATE
          , STORE_ID
          , NET_SALES
          , GUEST_COUNT
          , CREATED_AT
          , CREATED_BY
        )
       VALUES
        (
          S.DATE
          , S.STORE_ID
          , S.NET_SALES
          , S.GUEST_COUNT
          , CURRENT_TIMESTAMP()
          , ''' || SPROC_NAME ||'''
        )';
COMMIT;

EXCEPTION
  WHEN OTHER THEN
    RAISE;

END;