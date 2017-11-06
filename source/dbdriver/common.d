module dbdriver.common;
import std.format;
import std.exception;

class DBDriverException : Exception
{
    /++
        Params:
            msg  = The message for the exception.
            file = The file where the exception occurred.
            line = The line number where the exception occurred.
            next = The previous exception in the chain of exceptions, if any.
      +/
    @safe pure nothrow
    this(string msg,
         string file = __FILE__,
         size_t line = __LINE__,
         Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

interface DBDriver
{
    void open(string dbDir);
    string get(string key);
    void put(string key, string data);
    void close();
}

DBDriver createDB(string dbType = "bdb")
{
    DBDriver db;
    if (dbType == "bdb")
    {
        import dbdriver.bdb;
        db = cast(DBDriver) new BdbDriver();
    }
    else if (dbType == "leveldb")
    {
        import dbdriver.leveldb;
        db = cast(DBDriver) new LevelDBDriver();
    }
    else
    {
        throw new DBDriverException(format("Unsupport db type: \'%s\'", dbType));
    }
    return db;
}

unittest
{
    string uniqueTempPath() @safe
    {
        import std.file : tempDir;
        import std.path : buildPath;
        import std.uuid : randomUUID;
        // Path should contain spaces to test escaping whitespace
        return buildPath(tempDir(), "dyoudao unittest temporary file " ~
            randomUUID().toString());
    }

    import std.file : mkdirRecurse, rmdirRecurse;
    auto dbPath = uniqueTempPath();
    mkdirRecurse(dbPath);
    scope(exit) rmdirRecurse(dbPath);
    // bdb unittest
    {
        auto db = createDB("bdb");
        db.open(dbPath ~ "/bdb/test.db");
        scope(exit) db.close();
        db.put("test", "testxxx33333333333333dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd");
        assert(db.get("test") == "testxxx33333333333333dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd");
    }
    // leveldb unittest
    {
        auto db = createDB("leveldb");
        db.open(dbPath ~ "/leveldb");
        scope(exit) db.close();
        db.put("test", "testxxx33333333333333dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd");
        assert(db.get("test") == "testxxx33333333333333dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd");
    }
}
