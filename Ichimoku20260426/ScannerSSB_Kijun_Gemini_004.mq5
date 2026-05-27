//+------------------------------------------------------------------+
//|        ScannerSSB_Kijun_Gemini.mq5                               |
//+------------------------------------------------------------------+
#property copyright "Version scan unique + Gemini one-shot"
#property version   "5.00"

//--- Inputs Scanner
input int    InpTenkan    = 9;
input int    InpKijun     = 26;
input int    InpSenkouB   = 52;
input double InpProximity = 0.01;
input bool   InpPopup     = true;
input bool   InpPush      = false;

//--- Inputs Gemini
input string GeminiAPIKey = "Hey Replace Me";
input string GeminiModel  = "gemini-3.1-flash-lite";

//--- Structure état alertes
struct SymbolState {
   string          name;
   ENUM_TIMEFRAMES last_tf;
   datetime        last_ssb_alert_time;
   datetime        last_kijun_alert_time;
};
SymbolState symbols_state[];

//--- File d'attente Gemini
string pendingPromptLines = "";
int    pendingCount       = 0;

//--- Contrôle one-shot
bool geminiAlreadySent = false;

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(10);
   Print("Scanner SSB/Kijun + Gemini one-shot v5 démarré.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick() { }

//+------------------------------------------------------------------+
void OnTimer()
{
   ENUM_TIMEFRAMES currentTF = Period();
   int total = SymbolsTotal(true);

   for(int i = 0; i < total; i++)
      ScanSymbol(SymbolName(i, true), currentTF);

   if(!geminiAlreadySent)
   {
      if(pendingCount > 0)
      {
         Print("Première boucle terminée — envoi unique à Gemini (",
               pendingCount, " alerte(s))...");
         FlushToGemini();
      }
      else
      {
         Print("Première boucle terminée — aucune alerte, Gemini non appelé.");
      }
      geminiAlreadySent = true;
   }
}

//+------------------------------------------------------------------+
//| Collecte toutes les données Ichimoku d'une UT donnée             |
//+------------------------------------------------------------------+
struct IchimokuData {
   double tenkan;
   double kijun;
   double ssa;
   double ssb;
   double chikou;
   double close;
   bool   valid;
   bool   above_cloud;   // prix au-dessus du nuage
   bool   bullish_cloud; // SSA > SSB (nuage haussier)
   bool   tk_cross_bull; // tenkan > kijun
   string price_vs_kijun;
   string price_vs_ssa;
   string price_vs_ssb;
};

IchimokuData GetIchimokuData(string symbol, ENUM_TIMEFRAMES tf)
{
   IchimokuData d;
   d.valid = false;

   int handle = iIchimoku(symbol, tf, InpTenkan, InpKijun, InpSenkouB);
   if(handle == INVALID_HANDLE) return d;

   double tenkan_buf[], kijun_buf[], ssa_buf[], ssb_buf[], chikou_buf[], close_buf[];
   ArraySetAsSeries(tenkan_buf, true);
   ArraySetAsSeries(kijun_buf,  true);
   ArraySetAsSeries(ssa_buf,    true);
   ArraySetAsSeries(ssb_buf,    true);
   ArraySetAsSeries(chikou_buf, true);
   ArraySetAsSeries(close_buf,  true);

   if(CopyBuffer(handle, 0, 0, 2, tenkan_buf)  < 2 ||
      CopyBuffer(handle, 1, 0, 2, kijun_buf)   < 2 ||
      CopyBuffer(handle, 2, 0, 2, ssa_buf)     < 2 ||
      CopyBuffer(handle, 3, 0, 2, ssb_buf)     < 2 ||
      CopyBuffer(handle, 4, 0, 2, chikou_buf)  < 2 ||
      CopyClose(symbol, tf, 0, 2, close_buf)   < 2)
   {
      IndicatorRelease(handle);
      return d;
   }

   IndicatorRelease(handle);

   d.tenkan = tenkan_buf[0];
   d.kijun  = kijun_buf[0];
   d.ssa    = ssa_buf[0];
   d.ssb    = ssb_buf[0];
   d.chikou = chikou_buf[0];
   d.close  = close_buf[0];
   d.valid  = true;

   double cloud_top = MathMax(d.ssa, d.ssb);
   double cloud_bot = MathMin(d.ssa, d.ssb);

   d.above_cloud   = (d.close > cloud_top);
   d.bullish_cloud = (d.ssa > d.ssb);
   d.tk_cross_bull = (d.tenkan > d.kijun);

   d.price_vs_kijun = (d.close > d.kijun) ? "au-dessus" : "en-dessous";
   d.price_vs_ssa   = (d.close > d.ssa)   ? "au-dessus" : "en-dessous";
   d.price_vs_ssb   = (d.close > d.ssb)   ? "au-dessus" : "en-dessous";

   return d;
}

//+------------------------------------------------------------------+
//| Formate un bloc Ichimoku pour le prompt Gemini                   |
//+------------------------------------------------------------------+
string FormatIchimokuBlock(string label, IchimokuData &d)
{
   if(!d.valid) return "  [" + label + "] donnees indisponibles\n";

   string cloud_dir  = d.bullish_cloud ? "HAUSSIER" : "BAISSIER";
   string tk_cross   = d.tk_cross_bull ? "BULL (Tenkan>Kijun)" : "BEAR (Tenkan<Kijun)";
   string pos_cloud  = d.above_cloud   ? "AU-DESSUS du nuage" : "EN-DESSOUS du nuage";

   string result = "";
   result += "  [" + label + "]\n";
   result += "    Prix:    " + DoubleToString(d.close,   5) + " | " + pos_cloud + "\n";
   result += "    Tenkan:  " + DoubleToString(d.tenkan,  5) + "\n";
   result += "    Kijun:   " + DoubleToString(d.kijun,   5) + " (prix " + d.price_vs_kijun + ")\n";
   result += "    SSA:     " + DoubleToString(d.ssa,     5) + " (prix " + d.price_vs_ssa   + ")\n";
   result += "    SSB:     " + DoubleToString(d.ssb,     5) + " (prix " + d.price_vs_ssb   + ")\n";
   result += "    Chikou:  " + DoubleToString(d.chikou,  5) + "\n";
   result += "    Nuage:   " + cloud_dir + " | TK cross: " + tk_cross + "\n";
   return result;
}

//+------------------------------------------------------------------+
//| Détermine les UT supérieures à analyser                         |
//+------------------------------------------------------------------+
void GetHigherTimeframes(ENUM_TIMEFRAMES current_tf,
                         ENUM_TIMEFRAMES &tf1, ENUM_TIMEFRAMES &tf2)
{
   switch(current_tf)
   {
      case PERIOD_M1:  tf1 = PERIOD_M5;  tf2 = PERIOD_M15; break;
      case PERIOD_M5:  tf1 = PERIOD_M15; tf2 = PERIOD_H1;  break;
      case PERIOD_M15: tf1 = PERIOD_H1;  tf2 = PERIOD_H4;  break;
      case PERIOD_M30: tf1 = PERIOD_H1;  tf2 = PERIOD_H4;  break;
      case PERIOD_H1:  tf1 = PERIOD_H4;  tf2 = PERIOD_D1;  break;
      case PERIOD_H4:  tf1 = PERIOD_D1;  tf2 = PERIOD_W1;  break;
      case PERIOD_D1:  tf1 = PERIOD_W1;  tf2 = PERIOD_MN1; break;
      case PERIOD_W1:  tf1 = PERIOD_MN1; tf2 = PERIOD_MN1; break;
      default:         tf1 = PERIOD_H4;  tf2 = PERIOD_D1;  break;
   }
}

//+------------------------------------------------------------------+
//| Ajoute une alerte enrichie dans la file                          |
//+------------------------------------------------------------------+
void QueueAlert(string symbol, ENUM_TIMEFRAMES tf,
                double close, double ssb, double kijun,
                string level_type, string direction)
{
   ENUM_TIMEFRAMES tf_sup1, tf_sup2;
   GetHigherTimeframes(tf, tf_sup1, tf_sup2);

   IchimokuData d_current = GetIchimokuData(symbol, tf);
   IchimokuData d_sup1    = GetIchimokuData(symbol, tf_sup1);
   IchimokuData d_sup2    = GetIchimokuData(symbol, tf_sup2);

   string tf_name     = EnumToString(tf);
   string tf_sup1_name = EnumToString(tf_sup1);
   string tf_sup2_name = EnumToString(tf_sup2);

   string block = "";
   block += "=== ALERTE " + level_type + " | " + symbol + " | " + tf_name + " | approche " + direction + " ===\n";
   block += FormatIchimokuBlock(tf_name,      d_current);
   block += FormatIchimokuBlock(tf_sup1_name, d_sup1);
   block += FormatIchimokuBlock(tf_sup2_name, d_sup2);

   if(pendingCount == 0)
      pendingPromptLines = block;
   else
      pendingPromptLines = pendingPromptLines + "\n" + block;

   pendingCount++;
   Print("File Gemini [", pendingCount, "] ", level_type, " | ", symbol, " | ", tf_name);
}

//+------------------------------------------------------------------+
//| Envoie toutes les alertes à Gemini (une seule fois)              |
//+------------------------------------------------------------------+
void FlushToGemini()
{
   string prompt =
      "Tu es un expert Ichimoku et trading professionnel.\n"
      "Voici des alertes de proximite detectees sur differents actifs.\n"
      "Pour chaque alerte, tu disposes des donnees Ichimoku completes "
      "sur l'UT de l'alerte et les 2 UT superieures.\n\n"
      "Pour chaque actif, fournis:\n"
      "1) Recommandation: BUY / SELL / HOLD\n"
      "2) Confluence multi-UT: les UT superieures confirment-elles?\n"
      "3) Justification courte (3 lignes max)\n"
      "4) Niveau stop-loss suggere (SSB ou Kijun selon contexte)\n\n"
      "--- ALERTES ---\n\n"
      + pendingPromptLines;

   string geminiResp = AskGemini(prompt);

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

   if(InpPopup) Alert("=== Gemini one-shot (" + IntegerToString(pendingCount) +
                       " alertes) ===\n" + geminiResp);
   if(InpPush)  SendNotification("Gemini >> " + geminiResp);

   pendingPromptLines = "";
   pendingCount       = 0;
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

         if(!geminiAlreadySent)
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

         if(!geminiAlreadySent)
            QueueAlert(symbol, tf, close_0, ssb_0, kijun_0, "KIJUN", dir);
      }
   }

   IndicatorRelease(handle);
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
      else if(c == '/')  result += "\\/";
      else if(c < 0x20)
      {
         ushort val = c;
         string digits = "0123456789abcdef";
         string h4 = ShortToString(StringGetCharacter(digits, (val >> 12) & 0xF));
         string h3 = ShortToString(StringGetCharacter(digits, (val >>  8) & 0xF));
         string h2 = ShortToString(StringGetCharacter(digits, (val >>  4) & 0xF));
         string h1 = ShortToString(StringGetCharacter(digits, (val      ) & 0xF));
         result += "\\u" + h4 + h3 + h2 + h1;
      }
      else result += ShortToString(c);
   }
   return result;
}

//+------------------------------------------------------------------+
//| Appel API Gemini                                                 |
//+------------------------------------------------------------------+
string AskGemini(string prompt)
{
   string safePrompt = EscapeJSON(prompt);

   string url     = "https://generativelanguage.googleapis.com/v1beta/models/" +
                    GeminiModel + ":generateContent?key=" + GeminiAPIKey;
   string headers = "Content-Type: application/json\r\n";
   string body    = "{\"contents\":[{\"parts\":[{\"text\":\"" + safePrompt + "\"}]}]}";

   Print("DEBUG body (300 premiers chars): ", StringSubstr(body, 0, 300));

   char   req[];
   char   res[];
   string resHeaders;

   int bodyLen = StringLen(body);
   ArrayResize(req, bodyLen);
   StringToCharArray(body, req, 0, bodyLen, CP_UTF8);

   int actualLen = ArraySize(req);
   if(actualLen > 0 && req[actualLen - 1] == 0)
      ArrayResize(req, actualLen - 1);

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
      Print("Body envoyé complet: ", body);
      return "Erreur HTTP " + IntegerToString(httpCode);
   }
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
      return "Pas de reponse";
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
