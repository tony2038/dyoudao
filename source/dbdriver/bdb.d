module dbdriver.bdb;
import dbdriver.common;
import std.stdio;
import std.string;
import std.array;
import std.stdint;
import std.file : mkdirRecurse;
import std.conv : to, octal;
import berkeleydb.all;
import std.path : dirName;
import std.zlib;


class BdbDriver: DBDriver
{
    private DbEnv dbenv;
    private Db db;
    void open(string dbFile)
    {
        string dbHome = dirName(dbFile);
        try
        {
            mkdirRecurse(dbHome);
        }
        catch (Exception e)
        {
        }

        dbenv = new DbEnv(0);
        uint32_t env_flags = DB_CREATE |    /* Create the environment if it does 
                                    * not already exist. */
                    DB_INIT_TXN  | /* Initialize transactions */
                    DB_INIT_LOCK | /* Initialize locking. */
                    DB_INIT_LOG  | /* Initialize logging */
                    DB_INIT_MPOOL; /* Initialize the in-memory cache. */
        dbenv.open(dbHome, env_flags, octal!666);
        db = new Db(this.dbenv, 0);
        db.open(null, dbFile, null, DB_BTREE, DB_CREATE | DB_AUTO_COMMIT | DB_MULTIVERSION, octal!600);
    }

    string get(string key)
    {
        Dbt dbt_key = key;
        Dbt dbt_data;
        auto txn = dbenv.txn_begin(null, DB_TXN_SNAPSHOT);
        auto rs = db.get(txn, &dbt_key, &dbt_data);
        txn.commit();
        if (rs != 0)
            return null;
        auto uncp = new UnCompress(HeaderFormat.gzip);
        auto result = cast(ubyte[])uncp.uncompress(dbt_data.to!string);
        result ~= cast(ubyte[])uncp.flush();
        return cast(string)result;
    }

    void put(string key, string data)
    {
        Dbt dbt_key = key;
        
        auto cp = new Compress(9, HeaderFormat.gzip);
        cp.flush(Z_SYNC_FLUSH);
        auto result = cast(ubyte[])cp.compress(data);
        result ~= cast(ubyte[])cp.flush();
        Dbt dbt_data = result;
        auto txn = dbenv.txn_begin(null);
        auto rs = db.put(txn, &dbt_key, &dbt_data);
        txn.commit();
        if (rs != 0)
            throw new DBDriverException("Put failed");
    }

    void close()
    {
        if (db)
        {
            db.close();
            db = null;
        }

        if (dbenv)
        {
            dbenv.close();
            dbenv = null;
        }
    }

    ~this()
    {
        close();
    }

}
