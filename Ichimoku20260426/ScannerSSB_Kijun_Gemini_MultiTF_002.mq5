//+------------------------------------------------------------------+
//|        ScannerSSB_Kijun_Gemini.mq5                               |
//+------------------------------------------------------------------+
#property copyright "Version file d'attente - 1 appel/minute"
#property version   "3.00"

//--- Inputs Scanner
input int    InpTenkan    = 9;
input int    InpKijun     = 26;
input int    InpSenkouB   = 52;
input double InpProximity = 0.05;
input bool   InpPopup     = true;
input bool   InpPush      = false;

//--- Inputs Gemini
input string GeminiAPIKey = "REPLACE ME";
input string GeminiModel  = "gemini-3.5-flash";

//--- Inputs file d'attente
input int InpFlushIntervalSec = 60; // Intervalle d'envoi Gemini (secondes)

//--- Structure état alertes
struct SymbolState {
   string          name;
   ENUM_TIMEFRAMES last_tf;
   datetime        last_ssb_alert_time;
   datetime        last_kijun_alert_time;
};
SymbolState symbols_state[];

//--- File d'attente Gemini
string   pendingPromptLines = "";   // Accumulation des infos
int      pendingCount       = 0;    // Nombre d'alertes en attente
datetime lastFlushTime      = 0;    // Dernière fois qu'on a envoyé à Gemini

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(10);
   lastFlushTime = TimeCurrent();
   Print("Scanner SSB/Kijun + Gemini démarré. Flush toutes les ",
         InpFlushIntervalSec, "s.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick() { }

//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Scan tous les symboles — accumule les alertes dans la file
   ENUM_TIMEFRAMES currentTF = Period();
   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++)
      ScanSymbol(SymbolName(i, true), currentTF);

   // 2. Si le délai est écoulé ET qu'il y a des alertes en attente → envoyer
   if(pendingCount > 0 &&
      TimeCurrent() - lastFlushTime >= InpFlushIntervalSec)
   {
      FlushToGemini();
   }
}

//+------------------------------------------------------------------+
//| Ajoute une alerte dans la file d'attente                         |
//+------------------------------------------------------------------+
void QueueAlert(string symbol, ENUM_TIMEFRAMES tf,
                double close, double ssb, double kijun,
                string level_type, string direction)
{
   // Format compact d'une ligne par alerte
   string line = "- " + level_type + " " + symbol + " " + EnumToString(tf) +
                 " approche " + direction +
                 " | Prix: " + DoubleToString(close, 5) +
                 " | SSB: "  + DoubleToString(ssb,   5) +
                 " | Kijun: "+ DoubleToString(kijun, 5);

   if(pendingCount == 0)
      pendingPromptLines = line;
   else
      pendingPromptLines = pendingPromptLines + "\n" + line;

   pendingCount++;
   Print("File Gemini [", pendingCount, "] ", line);
}

//+------------------------------------------------------------------+
//| Envoie toutes les alertes accumulées à Gemini en un seul appel   |
//+------------------------------------------------------------------+
void FlushToGemini()
{
   Print("Envoi Gemini — ", pendingCount, " alerte(s) accumulée(s)...");

   string prompt = "Tu es un expert Ichimoku et trading. "
                   "Voici plusieurs alertes de proximité détectées sur différents actifs. "
                   "Pour chacune, donne une recommandation BUY / SELL / HOLD "
                   "avec une justification courte (2 lignes max par actif).\n\n"
                   + pendingPromptLines;

   string geminiResp = AskGemini(prompt);

   // Affichage propre dans le journal
   string lines[];
   int nb = StringSplit(geminiResp, '\n', lines);
   for(int l = 0; l < nb; l++)
   {
      string t = lines[l];
      StringTrimLeft(t);
      StringTrimRight(t);
      if(StringLen(t) > 0)
         Print("Gemini >> ", t);
   }

   // Alerte popup unique
   if(InpPopup) Alert("=== Gemini (" + IntegerToString(pendingCount) +
                       " alertes) ===\n" + geminiResp);
   if(InpPush)  SendNotification("Gemini >> " + geminiResp);

   // Remise à zéro de la file
   pendingPromptLines = "";
   pendingCount       = 0;
   lastFlushTime      = TimeCurrent();
}

//+------------------------------------------------------------------+
void ScanSymbol(string symbol, ENUM_TIMEFRAMES tf)
{
   int handle = iIchimoku(symbol, tf, InpTenkan, InpKijun, InpSenkouB);
   if(handle == INVALID_HANDLE) return;

   double   ssb_buffer[];
   double   kijun_buffer[];
   double   close_price[];
   datetime time_buffer[];

   ArraySetAsSeries(ssb_buffer,   true);
   ArraySetAsSeries(kijun_buffer, true);
   ArraySetAsSeries(close_price,  true);
   ArraySetAsSeries(time_buffer,  true);

   if(CopyClose(symbol, tf, 0, 2, close_price)  < 2 ||
      CopyTime(symbol,  tf, 0, 1, time_buffer)   < 1 ||
      CopyBuffer(handle, 3, 0, 2, ssb_buffer)    < 2 ||
      CopyBuffer(handle, 1, 0, 2, kijun_buffer)  < 2)
   {
      IndicatorRelease(handle);
      return;
   }

   double close_0 = close_price[0],  close_1 = close_price[1];
   double ssb_0   = ssb_buffer[0],   ssb_1   = ssb_buffer[1];
   double kijun_0 = kijun_buffer[0], kijun_1 = kijun_buffer[1];

   double dist_ssb_0   = (MathAbs(close_0 - ssb_0)   / close_0) * 100.0;
   double dist_ssb_1   = (MathAbs(close_1 - ssb_1)   / close_1) * 100.0;
   double dist_kijun_0 = (MathAbs(close_0 - kijun_0) / close_0) * 100.0;
   double dist_kijun_1 = (MathAbs(close_1 - kijun_1) / close_1) * 100.0;

   //--- Alerte SSB
   if((dist_ssb_1 > InpProximity) && (dist_ssb_0 <= InpProximity))
   {
      if(!AlreadyAlerted(symbol, time_buffer[0], tf, "SSB"))
      {
         string dir = (close_1 > ssb_1) ? "par le HAUT" : "par le BAS";
         string msg = StringFormat("APPROCHE SSB | %s | %s | Prix: %.5f | SSB: %.5f | %s",
                                   symbol, EnumToString(tf), close_0, ssb_0, dir);
         Print(msg);
         if(InpPopup) Alert(msg);
         if(InpPush)  SendNotification(msg);
         UpdateAlertState(symbol, time_buffer[0], tf, "SSB");

         // Ajout dans la file au lieu d'appeler Gemini directement
         QueueAlert(symbol, tf, close_0, ssb_0, kijun_0, "SSB", dir);
      }
   }

   //--- Alerte Kijun
   if((dist_kijun_1 > InpProximity) && (dist_kijun_0 <= InpProximity))
   {
      if(!AlreadyAlerted(symbol, time_buffer[0], tf, "KIJUN"))
      {
         string dir = (close_1 > kijun_1) ? "par le HAUT" : "par le BAS";
         string msg = StringFormat("APPROCHE KIJUN | %s | %s | Prix: %.5f | Kijun: %.5f | %s",
                                   symbol, EnumToString(tf), close_0, kijun_0, dir);
         Print(msg);
         if(InpPopup) Alert(msg);
         if(InpPush)  SendNotification(msg);
         UpdateAlertState(symbol, time_buffer[0], tf, "KIJUN");

         // Ajout dans la file au lieu d'appeler Gemini directement
         QueueAlert(symbol, tf, close_0, ssb_0, kijun_0, "KIJUN", dir);
      }
   }

   IndicatorRelease(handle);
}

//+------------------------------------------------------------------+
//| Appel API Gemini (prompt libre)                                  |
//+------------------------------------------------------------------+
string AskGemini(string prompt)
{
   string safePrompt = EscapeJSON(prompt);

   string url     = "https://generativelanguage.googleapis.com/v1beta/models/" +
                    GeminiModel + ":generateContent?key=" + GeminiAPIKey;
   string headers = "Content-Type: application/json\r\n";
   string body    = "{\"contents\":[{\"parts\":[{\"text\":\"" + safePrompt + "\"}]}]}";

   char   req[];
   char   res[];
   string resHeaders;

   StringToCharArray(body, req, 0, StringLen(body), CP_UTF8);

   int len = ArraySize(req);
   if(len > 0 && req[len - 1] == 0)
      ArrayResize(req, len - 1);

   int httpCode = WebRequest("POST", url, headers, 15000, req, res, resHeaders);

   if(httpCode == 200)
   {
      string response = CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
      return ParseGeminiResponse(response);
   }
   else
   {
      string errBody = CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
      Print("Erreur Gemini HTTP ", httpCode, " | ", errBody);
      return "Erreur HTTP " + IntegerToString(httpCode);
   }
}

//+------------------------------------------------------------------+
//| Échappe les caractères spéciaux pour JSON                        |
//+------------------------------------------------------------------+
string EscapeJSON(string text)
{
   string result = "";
   int len = StringLen(text);
   for(int i = 0; i < len; i++)
   {
      ushort c = StringGetCharacter(text, i);
      if     (c == '"')  result += "\\\"";
      else if(c == '\\') result += "\\\\";
      else if(c == '\n') result += "\\n";
      else if(c == '\r') result += "\\r";
      else if(c == '\t') result += "\\t";
      else               result += ShortToString(c);
   }
   return result;
}

//+------------------------------------------------------------------+
//| Parse la réponse JSON de Gemini                                  |
//+------------------------------------------------------------------+
string ParseGeminiResponse(string json)
{
   string marker = "\"text\": \"";
   int start = StringFind(json, marker);
   if(start == -1)
   {
      Print("ParseGeminiResponse: champ text introuvable. JSON: ", json);
      return "Pas de réponse";
   }

   start += StringLen(marker);

   int end     = start;
   int jsonLen = StringLen(json);
   while(end < jsonLen)
   {
      ushort c    = StringGetCharacter(json, end);
      ushort prev = (end > 0) ? StringGetCharacter(json, end - 1) : 0;
      if(c == '"' && prev != '\\') break;
      end++;
   }

   string raw = StringSubstr(json, start, end - start);
   StringReplace(raw, "\\n",  "\n");
   StringReplace(raw, "\\\"", "\"");

   return raw;
}

//+------------------------------------------------------------------+
//| Gestion état alertes                                             |
//+------------------------------------------------------------------+
bool AlreadyAlerted(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf, string alert_type)
{
   int size = ArraySize(symbols_state);
   for(int i = 0; i < size; i++)
   {
      if(symbols_state[i].name == symbol && symbols_state[i].last_tf == tf)
      {
         if(alert_type == "SSB"   && symbols_state[i].last_ssb_alert_time   == bar_time) return true;
         if(alert_type == "KIJUN" && symbols_state[i].last_kijun_alert_time == bar_time) return true;
         return false;
      }
   }
   return false;
}

void UpdateAlertState(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf, string alert_type)
{
   int size = ArraySize(symbols_state);
   for(int i = 0; i < size; i++)
   {
      if(symbols_state[i].name == symbol && symbols_state[i].last_tf == tf)
      {
         if(alert_type == "SSB")   symbols_state[i].last_ssb_alert_time   = bar_time;
         if(alert_type == "KIJUN") symbols_state[i].last_kijun_alert_time = bar_time;
         return;
      }
   }
   ArrayResize(symbols_state, size + 1);
   symbols_state[size].name    = symbol;
   symbols_state[size].last_tf = tf;
   symbols_state[size].last_ssb_alert_time   = (alert_type == "SSB")   ? bar_time : 0;
   symbols_state[size].last_kijun_alert_time = (alert_type == "KIJUN") ? bar_time : 0;
}
//+------------------------------------------------------------------+
