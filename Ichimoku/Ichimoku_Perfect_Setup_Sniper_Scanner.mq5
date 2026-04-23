//+------------------------------------------------------------------+
//|        Ichimoku_Perfect_Setup_Sniper_Scanner.mq5                 |
//|           Scan Multi-TF + Confluence + Filtre Sniper             |
//+------------------------------------------------------------------+
#property copyright "Expert Ichimoku Research"
#property version   "3.01"
#property strict

//--- Inputs
input int             InpTenkan       = 9;         
input int             InpKijun        = 26;        
input int             InpSenkouB      = 52;        
input double          InpSniperLimit  = 0.01;      // Seuil Sniper (%)
input double          InpAcceptLimit  = 0.05;      // Seuil Acceptable (%)
input int             InpMaxSpread    = 30;        // Spread Max (Points)
input int             InpTimerSeconds = 10;        // Fréquence du scan
input bool            InpFileLog      = true;      
input string          InpFileName     = "Perfect_Sniper_Logs.txt";

// Structure Timeframes
struct TimeframeInfo {
   ENUM_TIMEFRAMES tf;
   string name;
   bool enabled;
};

TimeframeInfo TFs[] = {
   {PERIOD_W1,   "W1",   true},
   {PERIOD_D1,   "D1",   true},
   {PERIOD_H4,   "H4",   true},
   {PERIOD_H1,   "H1",   true},
   {PERIOD_M30,  "M30",  true},
   {PERIOD_M15,  "M15",  true}
};

struct SymbolState {
   string name;
   ENUM_TIMEFRAMES tf;
   datetime last_alert;
   string last_type;
};

SymbolState symbols_state[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetTimer(InpTimerSeconds);
   if(InpFileLog) CreateLogFile();
   Print("🚀 Scanner Sniper Ichimoku prêt. Distance Sniper: ", InpSniperLimit, "%");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
   EventKillTimer(); 
   ArrayFree(symbols_state); 
}

//+------------------------------------------------------------------+
//| Boucle de Scan                                                   |
//+------------------------------------------------------------------+
void OnTimer() {
   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++) {
      string symbol = SymbolName(i, true);
      
      // Filtre de liquidité (Spread)
      int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpread) continue;

      for(int t = 0; t < ArraySize(TFs); t++) {
         if(TFs[t].enabled) ScanPerfectSetup(symbol, TFs[t].tf, TFs[t].name);
      }
   }
}

//+------------------------------------------------------------------+
//| Logique de Détection "Perfect Setup"                             |
//+------------------------------------------------------------------+
void ScanPerfectSetup(string symbol, ENUM_TIMEFRAMES tf, string tfName) {
   int handle = iIchimoku(symbol, tf, InpTenkan, InpKijun, InpSenkouB);
   if(handle == INVALID_HANDLE) return;

   double kijun[1], ssb[1], close[1];
   // On prend la bougie 1 (clôturée) pour les niveaux, et 0 pour le prix actuel
   if(CopyBuffer(handle, 1, 1, 1, kijun) <= 0 || 
      CopyBuffer(handle, 3, 1, 1, ssb) <= 0 || 
      CopyClose(symbol, tf, 0, 1, close) <= 0) {
      IndicatorRelease(handle);
      return;
   }

   CheckAndAlert(symbol, tf, tfName, close[0], kijun[0], "KIJUN");
   CheckAndAlert(symbol, tf, tfName, close[0], ssb[0], "SSB");

   IndicatorRelease(handle);
}

//+------------------------------------------------------------------+
//| Validation et Alertes                                            |
//+------------------------------------------------------------------+
void CheckAndAlert(string sym, ENUM_TIMEFRAMES tf, string tfName, double price, double level, string type) {
   if(level <= 0) return;

   double dist = MathAbs(price - level) / level * 100.0;
   
   // On ignore si la distance est trop élevée
   if(dist > InpAcceptLimit) return;

   // Récupérer le temps de la bougie actuelle
   datetime currentBar[];
   if(CopyTime(sym, tf, 0, 1, currentBar) <= 0) return;
   
   if(AlreadyAlerted(sym, tf, currentBar[0], type)) return;

   // Détermination de la Confluence
   bool hasConfluence = false;
   string confluenceList = "";
   
   for(int i=0; i<ArraySize(TFs); i++) {
      if(TFs[i].tf == tf) continue;
      double k_other = GetOtherLevel(sym, TFs[i].tf, 1);
      double s_other = GetOtherLevel(sym, TFs[i].tf, 3);
      
      if(k_other > 0 && MathAbs(level - k_other)/k_other*100.0 < 0.02) { hasConfluence = true; confluenceList += TFs[i].name + "(K) "; }
      if(s_other > 0 && MathAbs(level - s_other)/s_other*100.0 < 0.02) { hasConfluence = true; confluenceList += TFs[i].name + "(S) "; }
   }

   // Formatage du message
   string label = (dist <= InpSniperLimit) ? "🎯 [SNIPER]" : "[APPROCHE]";
   if(dist <= InpSniperLimit && hasConfluence) label = "⭐ [PERFECT SETUP]";

   string dir = (price > level) ? "SUPPORT" : "RESISTANCE";
   string context = GetQuickContext(sym);
   
   string msg = StringFormat("%s %s | %s %s | Dist: %.4f%% | %s | Conf: %s | %s", 
                             label, sym, tfName, type, dist, dir, confluenceList, context);

   Print(msg);
   Alert(msg);
   if(InpFileLog) WriteToLogFile(msg);
   
   UpdateState(sym, tf, currentBar[0], type);
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double GetOtherLevel(string sym, ENUM_TIMEFRAMES tf, int buffer) {
   int h = iIchimoku(sym, tf, InpTenkan, InpKijun, InpSenkouB);
   if(h == INVALID_HANDLE) return 0;
   double v[1];
   if(CopyBuffer(h, buffer, 1, 1, v) > 0) { IndicatorRelease(h); return v[0]; }
   IndicatorRelease(h); return 0;
}

string GetQuickContext(string sym) {
   double p = SymbolInfoDouble(sym, SYMBOL_BID);
   double k_d1 = GetOtherLevel(sym, PERIOD_D1, 1);
   double k_h4 = GetOtherLevel(sym, PERIOD_H4, 1);
   string d1_dir = (k_d1 > 0) ? (p > k_d1 ? "↑" : "↓") : "?";
   string h4_dir = (k_h4 > 0) ? (p > k_h4 ? "↑" : "↓") : "?";
   return StringFormat("Ctx: D1%s H4%s", d1_dir, h4_dir);
}

bool AlreadyAlerted(string sym, ENUM_TIMEFRAMES tf, datetime bar, string type) {
   for(int i=0; i<ArraySize(symbols_state); i++) {
      if(symbols_state[i].name == sym && symbols_state[i].tf == tf && symbols_state[i].last_type == type)
         return symbols_state[i].last_alert == bar;
   }
   return false;
}

void UpdateState(string sym, ENUM_TIMEFRAMES tf, datetime bar, string type) {
   for(int i=0; i<ArraySize(symbols_state); i++) {
      if(symbols_state[i].name == sym && symbols_state[i].tf == tf && symbols_state[i].last_type == type) {
         symbols_state[i].last_alert = bar; return;
      }
   }
   int s = ArraySize(symbols_state);
   ArrayResize(symbols_state, s+1);
   symbols_state[s].name = sym; symbols_state[s].tf = tf; symbols_state[s].last_alert = bar; symbols_state[s].last_type = type;
}

void WriteToLogFile(string message) {
   int h = FileOpen(InpFileName, FILE_WRITE|FILE_READ|FILE_TXT);
   if(h != INVALID_HANDLE) {
      FileSeek(h, 0, SEEK_END);
      FileWriteString(h, "[" + TimeToString(TimeCurrent()) + "] " + message + "\r\n");
      FileClose(h);
   }
}

void CreateLogFile() {
   int h = FileOpen(InpFileName, FILE_WRITE|FILE_TXT);
   if(h != INVALID_HANDLE) {
      FileWriteString(h, "--- Ichimoku Perfect Sniper Scan Start ---\r\n");
      FileClose(h);
   }
}
