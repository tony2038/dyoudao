module dbdriver.leveldb;
import dbdriver.common;
import leveldb;
import std.file : mkdirRecurse;

class LevelDBDriver: DBDriver
{
    private DB db;
    this()
    {

    }

    void open(string dbDir)
    {

        auto opt = new Options;
        try
        {
            mkdirRecurse(dbDir);
        }
        catch (Exception e)
        {
        }
        opt.create_if_missing = true;
        //opt.cache((new opt.LRUCache(100 * 1048576)));
        db = new DB(opt, dbDir);
    }

    string get(string key)
    {
        ReadOptions opt = new ReadOptions;
        string data = db.find(key, null, opt);
        return data;
    }

    void put(string key, string data)
    {
        WriteOptions opt = new WriteOptions;
        //opt.sync(true);
        db.put(Slice(key), data, opt);
    }

    void close()
    {
        if (db)
        {
            db.close();
            db = null;
        }
    }

    ~this()
    {
        close();
    }
}
