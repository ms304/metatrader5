//+------------------------------------------------------------------+
#property version   "10.00"

//============== INPUTS =================
input int InpTenkan = 9;
input int InpKijun  = 26;
input int InpSenkouB= 52;

input string GeminiAPIKey = "REPLACE ME";
input string GeminiModel  = "gemini-3.5-flash";

//============== GLOBALS =================
string pendingPrompt = "";

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(10);
   Print("Scanner ELITE V10 lancé");
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}
//+------------------------------------------------------------------+
void OnTimer()
{
   pendingPrompt = "";
   Scan();

   if(pendingPrompt == "")
   {
      Print("Aucun setup trouvé");
      return;
   }

   string file="chart.png";

   // ✅ Screenshot léger
   if(!ChartScreenShot(0,file,600,300))
   {
      Print("Erreur screenshot");
      return;
   }

   string prompt =
   "Analyse Ichimoku.\n"
   "Donne:\n"
   "ACTION BUY/SELL/HOLD\n"
   "CONFIDENCE 0-100\n"
   "STOP Kijun ou SSB\n"
   "COMMENT court\n\n"
   + pendingPrompt;

   string result = AskGemini(prompt,file);

   Print("===== GEMINI =====");
   Print(result);

   EventKillTimer();
}
//+------------------------------------------------------------------+

//====================== STRUCT ======================
struct IchimokuData
{
   double close,ssa,ssb;
   string cloud;
   bool valid;
};

//====================== SCAN ======================
void Scan()
{
   int total=SymbolsTotal(true);

   for(int i=0;i<total;i++)
   {
      string symbol=SymbolName(i,true);

      IchimokuData d=GetIchimoku(symbol);
      if(!d.valid) continue;

      int score=ComputeScore(d);

      Print("DEBUG ",symbol," score=",score);

      // ✅ FIX principal
      if(score < 40) continue;

      pendingPrompt += symbol+" "+EnumToString(Period())+"\n";
      pendingPrompt += "Score:"+IntegerToString(score)+"\n";
      pendingPrompt += "Cloud:"+d.cloud+"\n\n";
   }
}
//+------------------------------------------------------------------+

//====================== ICHIMOKU ======================
IchimokuData GetIchimoku(string symbol)
{
   IchimokuData d;
   d.valid=false;

   int h=iIchimoku(symbol,Period(),InpTenkan,InpKijun,InpSenkouB);
   if(h==INVALID_HANDLE) return d;

   double ssa[],ssb[],close[];

   ArraySetAsSeries(ssa,true);
   ArraySetAsSeries(ssb,true);
   ArraySetAsSeries(close,true);

   if(CopyBuffer(h,2,0,1,ssa)<1 ||
      CopyBuffer(h,3,0,1,ssb)<1 ||
      CopyClose(symbol,Period(),0,1,close)<1)
   {
      IndicatorRelease(h);
      return d;
   }

   d.close=close[0];
   d.ssa=ssa[0];
   d.ssb=ssb[0];
   d.valid=true;

   double top=MathMax(d.ssa,d.ssb);
   double bot=MathMin(d.ssa,d.ssb);

   if(d.close>top) d.cloud="AU-DESSUS";
   else if(d.close<bot) d.cloud="EN-DESSOUS";
   else d.cloud="DANS";

   IndicatorRelease(h);
   return d;
}
//+------------------------------------------------------------------+

//====================== SCORE ======================
int ComputeScore(IchimokuData &d)
{
   int s=0;

   if(d.cloud=="AU-DESSUS") s+=50;
   if(d.cloud=="EN-DESSOUS") s+=50;
   if(d.cloud=="DANS") s+=10;

   return s;
}
//+------------------------------------------------------------------+

//====================== FILE READ ======================
bool ReadFile(string filename, uchar &data[])
{
   int f=FileOpen(filename,FILE_READ|FILE_BIN);
   if(f==INVALID_HANDLE) return false;

   int size=(int)FileSize(f);
   ArrayResize(data,size);

   FileReadArray(f,data,0,size);
   FileClose(f);

   return true;
}
//+------------------------------------------------------------------+

//====================== BASE64 ✅ FIX ======================
string Base64Encode(uchar &data[])
{
   uchar out[];
   uchar key[];

   int len=CryptEncode(CRYPT_BASE64,data,key,out);

   if(len<=0) return "";

   return CharArrayToString(out);
}
//+------------------------------------------------------------------+

//====================== ESCAPE JSON ======================
string EscapeJSON(string txt)
{
   string r=txt;
   StringReplace(r,"\\","\\\\");
   StringReplace(r,"\"","\\\"");
   StringReplace(r,"\n","\\n");
   StringReplace(r,"\r","");
   return r;
}
//+------------------------------------------------------------------+

//====================== GEMINI ======================
string AskGemini(string prompt,string file)
{
   uchar img[];
   if(!ReadFile(file,img))
      return "Erreur lecture image";

   string b64=Base64Encode(img);

   string url="https://generativelanguage.googleapis.com/v1beta/models/"
               + GeminiModel + ":generateContent?key=" + GeminiAPIKey;

   string headers="Content-Type: application/json\r\n";

   string body = "{"
   "\"contents\":[{"
   "\"parts\":["
   "{\"text\":\""+EscapeJSON(prompt)+"\"},"
   "{\"inlineData\":{"
   "\"mimeType\":\"image/png\","
   "\"data\":\""+b64+"\""
   "}}"
   "]"
   "}]"
   "}";

   Print("JSON size=",StringLen(body));

   char req[];
   int len = StringToCharArray(body, req, 0, StringLen(body), CP_UTF8);

   // 🔥 FIX CRITIQUE JSON
   if(len>0 && req[len-1]==0)
      len--;

   ArrayResize(req,len);

   char res[];
   string resHeaders;

   int code=WebRequest("POST",url,headers,15000,req,res,resHeaders);

   if(code==-1)
   {
      Print("WebRequest error:",GetLastError());
      return "Erreur WebRequest";
   }

   string response=CharArrayToString(res);

   if(code!=200)
   {
      Print("HTTP:",code," ",response);
      return "Erreur HTTP";
   }

   return response;
}
//+------------------------------------------------------------------+
