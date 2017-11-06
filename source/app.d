/*
By tony <tony2038@outlook.com>, 2017  
*/
import std.stdio;
import std.string;
import std.getopt;
import std.net.curl;
import std.json;
import std.array;
import std.zlib;
import std.range;
import std.algorithm.iteration;
import std.path : buildPath, asNormalizedPath, asAbsolutePath, dirName;
import std.uni;
import std.conv;
import std.algorithm.sorting;
//import std.algorithm.iteration;
//import std.algorithm.mutation : copy;
import dbdriver.common;

string CmdDir;
string Version = "0.1"; 



string getQuery(in string url)
{
    debug stderr.writefln("HTTPGET %s", url);
    auto http = HTTP();
    http.addRequestHeader("Accept-Encoding", "deflate, gzip");
    http.handle.set(CurlOption.encoding, "gzip");
    debug http.verbose = true;
    auto content = cast(string)get(url, http);
    //debug stderr.writeln(http.responseHeaders);
    //debug stderr.writefln("CONTENT: %s", content);
    return content;
}

string postQuery(in string url, string[string] postFields)
{
    debug stderr.writefln("HTTPPOST %s %s", url, postFields.to!string);
    auto http = HTTP();
    http.addRequestHeader("Accept-Encoding", "deflate, gzip");
    http.handle.set(CurlOption.encoding, "gzip");
    debug http.verbose = true;
    auto content = cast(string)post(url, postFields, http);
    //debug stderr.writeln(http.responseHeaders);
    //debug stderr.writefln("CONTENT: %s", content);
    return content;
}

bool testJson(T)(T v)
{
    if ("ec" !in v && "ce" !in v)
    {
        return false;
    }
    return true;
}

string[] readWords(string fileName, bool splitWords = false)
{
    dchar[] buf;
    string[] words;
    File file;
    if (fileName == "-")
    {
        file = stdin;
    }
    else
    {
        file = File(fileName, "r");
    }
    scope(exit) file.close();
    if (splitWords)
    {
        string word;
        dchar connect = 0;
        while (!file.eof())
        {
            file.readln(buf);
            auto line = chomp(buf);
            foreach (int i, dchar c; line.array)
            {
                if (c == '-' || c == '~')
                {
                    if (connect && word.length)
                    {
                        words ~= word;
                        word = "";
                    }
                    connect = c;
                    continue;    
                }
                if (isAlpha(c))
                {
                    if (connect)
                    {
                        if (word.length)
                            word ~= connect;
                        connect = 0;
                    }
                    word ~= c;
                    continue;
                }
                if (word.length)
                {
                    words ~= word;
                    word = "";
                }
                connect = 0;
            }
            if (!connect && word.length)
            {
                words ~= word;
                word = "";
            }
        }
        if (word.length) 
            words ~= word;
    }
    else
    {
        while (!file.eof())
        {
            file.readln(buf);
            auto line = chomp(buf);
            if (line != "")
                continue;
            words ~= line.to!string;
        }
    }
    return words;
}

string audioFormat = "<a hidefocus=\"true\" class=\"sp dictvoice\" title=\"真人发音\" href=\"javascript:void(0);\" ref=\"http://dict.youdao.com/dictvoice?audio=%s&keyfrom=deskdict.main.word\" onmouseover=\"this.style.cursor='hand';playVoice(this.getAttribute('ref'));return false;\" onmouseout=\"stopVoice(this.ref);return false;\" onclick=\"playVoice(this.getAttribute('ref'));return false;;\"></a><span id=\"noSoundEC\" style=\"display:none\"><a href=\"http://www.adobe.com/shockwave/download/download.cgi?P1_Prod_Version=ShockwaveFlash\" target=\"_blank\"><IMG SRC=\"images/nosound.gif\" WIDTH=\"17\" HEIGHT=\"17\" BORDER=\"0\" ALT=\"想启用英文朗读功能吗？请先安装flash插件！\" align=\"absmiddle\"></a></span>";

class YoudaoDictDriver
{
    private string[] words;
    private DBDriver db;

    this() {}

    this(DBDriver db)
    {
        this.db = db;
    }

    JSONValue query(string word)
    {
        string content = "";
        JSONValue jsonResult;
        bool queryStatus = false;
        debug stderr.writefln("Query: %s", word);
        if (db)
        {
            // get_slice().as!string 当数据比较大时会出现 bad address 错误
            //content = db.get_slice(word.toLower).as!string;
            content = db.get(word.toLower);
            debug stderr.writefln("DB query(%d): %s", content.length, content);
            if (content.length)
            {
                try
                {
                    jsonResult = parseJSON(content);
                    debug stderr.writeln(jsonResult.toPrettyString);
                    if (testJson(jsonResult))
                    {
                        queryStatus = true;
                    }
                }
                catch (std.json.JSONException e)
                {
                    debug stderr.writefln("Json parse error: %s", e);
                }
            }
        }

        if (!queryStatus)
        {
            content = postQuery("http://dict.youdao.com/jsonapi", ["keyfrom" : "deskdict.main.word", "jsonversion" : "2", "q" : word]);
            if (content.length)
            {
                try
                {
                    jsonResult = parseJSON(content);
                    debug stderr.writeln(jsonResult.toPrettyString);
                    if (testJson(jsonResult))
                    {
                        queryStatus = true;
                    }
                }
                catch (std.json.JSONException e)
                {
                    debug stderr.writefln("Json parse error: %s", e);
                }

                if (queryStatus && db && "fanyi" !in jsonResult)
                {
                    stderr.writefln("DB put %s", word);
                    db.put(word.toLower, content);    
                }
            }            
        }
        return jsonResult;
    }

    string fileQuery(string fileName)
    {
        char[] buf;
        File file = File(fileName, "r");
        while (!file.eof())
        {
            char[] line = buf;
            file.readln(line);
            if (line.length > buf.length)
                buf = line;
        }
        return cast(string)buf;
    }

    string ecToHtml(JSONValue jsonResult)
    {
        string html;
        if ("ec" !in jsonResult)
        {
            return html;
        }
        debug stderr.writeln(jsonResult["ec"].toPrettyString);
        if ("word" in jsonResult["ec"])
        {
            auto word = jsonResult["ec"]["word"][0];
            html ~= format("<H2>%s</H2>", word["return-phrase"]["l"]["i"].str);
            string[] temp;
            string[] pres = ["uk", "us"];
            bool hasSpeed = false;
            bool hasPhone = false;
            foreach(pre; pres)
            {
                string[] s;
                auto phone = pre ~ "phone";
                auto speech = pre ~ "speech";
                if (phone in word && word[phone].str != "")
                {
                    s ~= [format("<span class=\"phonetic pr-%s\">[%s]</span>", phone, word[phone])];
                    hasPhone = true;
                }
                if (speech in word && word[speech].str != "")
                {
                    s ~= [format(audioFormat, word[speech].str)]; 
                    hasSpeed = true;
                }
                if (s.length)
                {
                    temp ~= [format("<span class=\"pronounce\">%s</span>%s", pre, s.join(""))];
                }
            }
            if (!hasPhone && "phone" in word)
            {
                temp ~= format("[%s]", word["phone"].str);
            }
            if (!hasSpeed && "speech" in word)
            {
                temp ~= format(audioFormat, word["speech"].str);
            }
            if (temp.length)
            {
                html ~= format("<div>%s</div>\n", temp.join(""));
            }
            if ("trs" in word && word["trs"].type == JSON_TYPE.ARRAY)
            {
                auto trs = word["trs"];
                foreach (tr; word["trs"].array)
                {
                    foreach (item; tr["tr"].array)
                    {
                        if (item["l"]["i"].type == JSON_TYPE.STRING)
                            html ~= item["l"]["i"].str;
                        else if (item["l"]["i"].type == JSON_TYPE.ARRAY)
                        {
                            foreach (i; item["l"]["i"].array)
                            {
                                if (i.type == JSON_TYPE.STRING)
                                    html ~= i.str;
                                else
                                    html ~= i["#text"].str;
                            }
                        }
                        html ~= "<br>\n";
                    }
                }
            }
            if ("wfs" in word)
            {
                string [] wfs;
                foreach(wf; word["wfs"].array)
                {
                    wfs ~= format("%s:%s", wf["wf"]["name"].str, wf["wf"]["value"].str);
                }
                html ~= format("[%s]\n", wfs.join(" "));
            }
        }
        return html;
    }

    string ceToHtml(JSONValue jsonResult)
    {
        string html;
        if ("ce" !in jsonResult)
        {
            return html;
        }
        debug stderr.writeln(jsonResult["ce"].toPrettyString);
        if ("word" in jsonResult["ce"])
        {
            auto word = jsonResult["ce"]["word"][0];
            html ~= format("<H2>%s</H2>", word["return-phrase"]["l"]["i"].str);
            string[] temp;
            bool hasSpeed = false;
            bool hasPhone = false;
            if (!hasPhone && "phone" in word)
            {
                temp ~= format("[%s]", word["phone"].str);
            }
            if (!hasSpeed && "speech" in word)
            {
                temp ~= format(audioFormat, word["speech"].str);
            }
            if (temp.length)
            {
                html ~= format("<div>%s</div>\n", temp.join(""));
            }
            if ("trs" in word && word["trs"].type == JSON_TYPE.ARRAY)
            {
                auto trs = word["trs"];
                foreach (tr; word["trs"].array)
                {
                    foreach (item; tr["tr"].array)
                    {
                        if (item["l"]["i"].type == JSON_TYPE.STRING)
                            html ~= item["l"]["i"].str;
                        else if (item["l"]["i"].type == JSON_TYPE.ARRAY)
                        {
                            foreach (i; item["l"]["i"].array)
                            {
                                if (i.type == JSON_TYPE.STRING)
                                    html ~= i.str;
                                else
                                    html ~= i["#text"].str;
                            }
                        }
                        html ~= "<br>\n";
                    }
                }
            }
            if ("wfs" in word)
            {
                string [] wfs;
                foreach(wf; word["wfs"].array)
                {
                    wfs ~= format("%s:%s", wf["wf"]["name"].str, wf["wf"]["value"].str);
                }
                html ~= format("[%s]\n", wfs.join(" "));
            }
        }
        return html;
    }

    string fanyiToHtml(JSONValue jsonResult)
    {
        string html;
        if ("fanyi" !in jsonResult)
        {
            return html;
        }
        auto fanyi = jsonResult["fanyi"];
        html ~= "<p style=\"color:green\">\nFanyi:\n</p>\n";
        html ~= fanyi["input"].str ~ "<br>\n";
        html ~= fanyi["tran"].str ~ "<br>\n";
        html ~= "<br>\n";
        return html;
    }

    string phrsToHtml(JSONValue jsonResult)
    {
        string html;
        if ("phrs" !in jsonResult)
        {
            return html;
        }
        debug stderr.writeln(jsonResult["phrs"].toPrettyString);
        auto phrs = jsonResult["phrs"]["phrs"];
        auto word = jsonResult["phrs"]["word"];
        html ~= "<p style=\"color:green\">\nPhrases:\n</p>\n";
        foreach (phr; phrs.array)
        {
            phr["phr"]["headword"]["l"]["i"].str;
            string[] trs;
            foreach (tr; phr["phr"]["trs"].array)
            {
                trs ~= tr["tr"]["l"]["i"].str;
            }
            html ~= format("%s %s<br>\n", phr["phr"]["headword"]["l"]["i"].str, trs.join("; "));
        }
        return html;
    }

    string blngToHtml(JSONValue jsonResult)
    {
        string html;
        if ("blng_sents_part" !in jsonResult || "sentence-pair" !in jsonResult["blng_sents_part"])
        {
            return html;
        }
        html ~= "<p style=\"color:green\">\nBlng sentences:\n</p>\n";
        foreach (item; jsonResult["blng_sents_part"]["sentence-pair"].array)
        {
            html ~= item["sentence-eng"].str;
            if ("sentence-speech" in item)
            {
                html ~= format("<a hidefocus=\"true\" class=\"sp dictvoice\" title=\"真人发音\" href=\"javascript:void(0);\" ref=\"http://dict.youdao.com/dictvoice?audio=%s&keyfrom=deskdict.main.word\" onmouseover=\"this.style.cursor='hand';playVoice(this.getAttribute('ref'));return false;\" onmouseout=\"stopVoicethis.ref);return false;\" onclick=\"playVoice(this.getAttribute('ref'));return false;;\"></a><span id=\"noSoundEC\" style=\"display:none\"><a href=\"http:/www.adobe.com/shockwave/download/download.cgi?P1_Prod_Version=ShockwaveFlash\" target=\"_blank\"><IMG SRC=\"images/nosound.gif\" WIDTH=\"17\" HEIGHT=\"17\" BORDER\"0\" ALT=\"想启用英文朗读功能吗？请先安装flash插件！\" align=\"absmiddle\"></a></span>", item["sentence-speech"].str);
            }
            html ~= "<br>\n";
            if ("sentence-translation" in item)
                html ~= item["sentence-translation"].str ~ "<br>\n";
        }
        return html;
    }

    string authToHtml(JSONValue jsonResult)
    {
        string html;
        if ("auth_sents_part" !in jsonResult || "sent" !in jsonResult["auth_sents_part"])
        {
            return html;
        }
        html ~= "<div><p style=\"color:green\">\nAuth sentences:\n</p>\n";
        foreach (item; jsonResult["auth_sents_part"]["sent"].array)
        {
            html ~= item["foreign"].str;
            if ("speech" in item)
            {
                html ~= format("<a hidefocus=\"true\" class=\"sp dictvoice\" title=\"真人发音\" href=\"javascript:void(0);\" ref=\"http://dict.youdao.com/dictvoice?audio=%s&keyfrom=deskdict.main.word\" onmouseover=\"this.style.cursor='hand';playVoice(this.getAttribute('ref'));return false;\" onmouseout=\"stopVoicethis.ref);return false;\" onclick=\"playVoice(this.getAttribute('ref'));return false;;\"></a><span id=\"noSoundEC\" style=\"display:none\"><a href=\"http:/www.adobe.com/shockwave/download/download.cgi?P1_Prod_Version=ShockwaveFlash\" target=\"_blank\"><IMG SRC=\"images/nosound.gif\" WIDTH=\"17\" HEIGHT=\"17\" BORDER\"0\" ALT=\"想启用英文朗读功能吗？请先安装flash插件！\" align=\"absmiddle\"></a></span>", item["speech"].str); 
            }
            html ~= "<br>\n";
        }
        html ~= "</div>\n";
        return html;
    }

    string toHtmlResult(JSONValue jsonResult, bool simple=false)
    {
        string html;
        string ltype;
        if (jsonResult.type == JSON_TYPE.NULL)
        {
            goto end;
        }
        html ~= ecToHtml(jsonResult);
        html ~= ceToHtml(jsonResult);
        if (simple)
        {
            goto end;
        }
        html ~= fanyiToHtml(jsonResult);
        html ~= phrsToHtml(jsonResult);
        html ~= blngToHtml(jsonResult);
        html ~= authToHtml(jsonResult);
        end:
        return html;

    }

    string toHtml(string[] words, bool simple=false)
    {
        string html;

        html ~= format("<html>
<head>
<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">
<title>Local Query Result</title>
<link href=\"file://%s/css/default.css\" rel=\"stylesheet\" type=\"text/css\">
<script language=\"javascript\" src=\"file://%s/js/default.js\"></script>
</head>
<body>
<div id=\"results\">
<audio id=\"my_sound\" src=\"\"></audio>
\n", CmdDir, CmdDir);
        foreach (int i, word; words)
        {
            try
            {
                auto jsonResult = query(word);
                html ~= format("<div id=\"w-%d-%s\">\n", i, word);
                html ~= toHtmlResult(jsonResult, simple);
                html ~= "</div>\n";
            }
            catch (std.net.curl.CurlException e)
            {
                stderr.writefln("Network query error: %s", e.msg);
            }
        }    
        html ~= "</div>
</body>
</html>";
        return html;
    }    
}

void usage(string program)
{
    writefln("Usage: %s [OPTION]... [word]...", program);
}

int main(string[] args)
{
    bool simple = false;
    bool help = false;
    bool splitWords = false; 
    bool sortResults = false;
    bool showVersion = false;
    CmdDir = asNormalizedPath(asAbsolutePath(dirName(args[0]))).array;
    string dbType;
    string dbPathDefault = CmdDir ~ "/db";
    string dbPath;
    string wordfile;
    auto helpInformation = getopt(
    args, 
    std.getopt.config.caseSensitive,
    "simple|s", "Display simple results.", &simple,
    "from|f", "Read query word from file.", &wordfile,
    "split|p", "Split word from file.", &splitWords,
    "sort|S", "Sort results.", &sortResults,
    "dbtype|D", "Type of database(disabled(default), bdb, leveldb).", &dbType,
    "dbpath|P", format("Database path, default '%s/{dbtype}'.", dbPathDefault), &dbPath,
    "version|v", "Display version information.", &showVersion,
    );
    
    if (helpInformation.helpWanted)
    {
        usage(args[0]);
        writeln();
        defaultGetoptPrinter("Some information about the program.",
        helpInformation.options);
        return 0;
    }

    if (showVersion)
    {
        writeln(Version);
        return 0;
    }

    if (wordfile && args.length >1)
    {
        stderr.writefln("%s: Too many arguments!", args[0]);
        stderr.writefln("Try '%s --help' for more information.", args[0]);
        return 2;
    }

    if (!wordfile && args.length < 2)
    {
        stderr.writefln("%s: Too few arguments!", args[0]);
        stderr.writefln("Try '%s --help' for more information.", args[0]);
        return 2;
    }
    DBDriver db;
    if (dbType.length && dbType != "disabled")
    {
        db = createDB(dbType);
        dbPath = dbPath ? dbPath : buildPath(dbPathDefault, dbType);
        if (dbType == "bdb")
            db.open(dbPath ~ "/dict.db");
        else
            db.open(dbPath);
    }
    scope(exit) if (db) db.close();
    auto dictDriver = new YoudaoDictDriver(db);
    string[] words;

    if (wordfile)
    {
        words = readWords(wordfile, splitWords);
    }
    else
    {
        words = args[1..$];
    }

    foreach(int i, string word; words)
    {
        words[i] = word.toLower;
    }

    // 原地去重复
    //words.length -= words.uniq().copy(words).length;
    
    string[] newWords;
    {
        bool[string] indexes;
        foreach(word; words)
        {
            auto wordLower = word.toLower;
            if (wordLower in indexes)  // 去重复
            {
                continue;
            }
            indexes[wordLower] = true;
            newWords ~= word;
        }
    }

    if (sortResults)
        sort(words);
    debug stderr.writeln(newWords);

    writeln(dictDriver.toHtml(newWords, simple));
    return 0;
}
