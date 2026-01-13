//+------------------------------------------------------------------+
//| SMC ICT Market Scanner MT5 - All Market Watch (No Trade)         |
//+------------------------------------------------------------------+
#property copyright "SMC AI Scanner"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// --- Paramètres du Scanner ---
input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;  // Timeframe de Tendance
input ENUM_TIMEFRAMES EntryTF = PERIOD_M15; // Timeframe des Patterns (OB/FVG)
input ENUM_TIMEFRAMES MicroTF = PERIOD_M5;  // Timeframe de Confirmation

// --- Filtres ---
input bool UseSessionFilter = true;
input int StartHour = 8;
input int EndHour   = 17;

// --- Alertes ---
input string TelegramBotToken = "VOTRE_TOKEN_ICI";
input string TelegramChatID = "VOTRE_CHAT_ID_ICI";
input bool SendTelegramAlerts = true;
input bool SendPopupAlerts = true; // Ajout d'alerte écran

// --- Logging ---
input string LogFileName = "SMC_Scanner_Log.csv";
input bool EnableLogging = true;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("SMC ICT Scanner Initialized - Scanning Market Watch...");
   InitLogFile();
   
   // On utilise un Timer pour ne pas surcharger le processeur
   // Le scan se fera toutes les 15 secondes au lieu de chaque tick
   EventSetTimer(15); 
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
// Remplacement de OnTick par OnTimer pour scanner la liste
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime t = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int hourNow = dt.hour;

   // Boucle sur TOUS les symboles du Market Watch
   int total = SymbolsTotal(true); 
   
   for(int i=0; i<total; i++)
   {
      string sym = SymbolName(i, true);
      
      // Vérification basique des données
      if(!SymbolInfoInteger(sym, SYMBOL_SELECT)) continue;
      
      // Filtre de Session (Sauf pour les cryptos qui contiennent souvent "BTC" ou "ETH")
      if(UseSessionFilter && StringFind(sym, "BTC") == -1 && StringFind(sym, "ETH") == -1) 
      {
         if(hourNow < StartHour || hourNow >= EndHour) continue;
      }

      // 1. Détection Tendance (H1)
      int trend = CheckMarketStructure(sym, TrendTF);
      if (trend == 0) continue; 

      // 2. Détection Patterns ICT (M15)
      double obLow=0, obHigh=0, fvgLow=0, fvgHigh=0, breakerLow=0, breakerHigh=0, sweepLevel=0;
      
      bool foundOB = FindOrderBlock(sym, EntryTF, trend, obLow, obHigh);
      bool foundFVG = FindFairValueGap(sym, EntryTF, trend, fvgLow, fvgHigh);
      
      if(!foundOB && !foundFVG) continue; 
      
      // Optionnel
      FindBreakerBlock(sym, EntryTF, trend, breakerLow, breakerHigh);
      if(!FindLiquiditySweep(sym, MicroTF, trend, sweepLevel)) sweepLevel = 0;

      // 3. Confirmation Microstructure (M5)
      // Si le prix actuel est dans la zone
      bool signal = CheckMicrostructure(sym, MicroTF, obLow, obHigh, fvgLow, fvgHigh, breakerLow, breakerHigh, sweepLevel, trend);

      if(signal)
      {
         // Calcul des niveaux théoriques pour l'alerte
         double currentPrice = (trend == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
         double sl = (trend == 1) ? (obLow != 0 ? obLow : fvgLow) : (obHigh != 0 ? obHigh : fvgHigh);
         
         // On envoie l'alerte seulement, PAS DE TRADE
         LogAndAlert(sym, trend, obLow, obHigh, fvgLow, fvgHigh, sl, currentPrice);
      }
   }
}

//+------------------------------------------------------------------+
// --- Fonctions d'Analyse (Identiques à l'original) --- 
//+------------------------------------------------------------------+

int CheckMarketStructure(string sym, ENUM_TIMEFRAMES tf)
{
   double high1 = iHigh(sym, tf, 1);
   double high2 = iHigh(sym, tf, 2);
   double low1 = iLow(sym, tf, 1);
   double low2 = iLow(sym, tf, 2);
   
   if(high1 == 0 || high2 == 0) return 0; // Données manquantes

   if(high1 > high2 && low1 > low2) return 1;  // Higher Highs & Higher Lows
   if(high1 < high2 && low1 < low2) return -1; // Lower Highs & Lower Lows
   return 0;
}

bool FindOrderBlock(string sym, ENUM_TIMEFRAMES tf, int trend, double &obLow, double &obHigh)
{
   for(int i=2; i<10; i++)
   {
      double open = iOpen(sym, tf, i);
      double close = iClose(sym, tf, i);
      double high = iHigh(sym, tf, i);
      double low = iLow(sym, tf, i);

      if(trend == 1 && close < open) { obLow = low; obHigh = high; return true; }
      if(trend == -1 && close > open) { obLow = low; obHigh = high; return true; }
   }
   return false;
}

bool FindFairValueGap(string sym, ENUM_TIMEFRAMES tf, int trend, double &fvgLow, double &fvgHigh)
{
   for(int i=2; i<10; i++)
   {
      double high_prev = iHigh(sym, tf, i+1); 
      double low_prev  = iLow(sym, tf, i+1);
      double high_next = iHigh(sym, tf, i-1); 
      double low_next  = iLow(sym, tf, i-1);

      if(trend == 1 && low_next > high_prev) { fvgLow = high_prev; fvgHigh = low_next; return true; }
      if(trend == -1 && high_next < low_prev) { fvgLow = high_next; fvgHigh = low_prev; return true; }
   }
   return false;
}

bool FindBreakerBlock(string sym, ENUM_TIMEFRAMES tf, int trend, double &breakerLow, double &breakerHigh)
{
   return false; // Désactivé pour alléger le scanner, réactivez si besoin
}

bool FindLiquiditySweep(string sym, ENUM_TIMEFRAMES tf, int trend, double &sweepLevel)
{
   double high = iHigh(sym, tf, 1);
   double low = iLow(sym, tf, 1);
   sweepLevel = (trend == 1) ? high : low;
   return true;
}

bool CheckMicrostructure(string sym, ENUM_TIMEFRAMES tf, double obLow, double obHigh, double fvgLow, double fvgHigh, double breakerLow, double breakerHigh, double sweepLevel, int trend)
{
   double close = iClose(sym, tf, 0); // Prix actuel
   
   if(trend == 1) // Achat potentiel
   {
       // Prix dans zone OB ou FVG
       if((obHigh > 0 && close >= obLow && close <= obHigh) || (fvgHigh > 0 && close >= fvgLow && close <= fvgHigh)) return true;
   }
   if(trend == -1) // Vente potentielle
   {
       if((obLow > 0 && close >= obLow && close <= obHigh) || (fvgLow > 0 && close >= fvgLow && close <= fvgHigh)) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// --- Logging + Alertes (Sans Trading) --- 
//+------------------------------------------------------------------+

void InitLogFile()
{
   if(!EnableLogging) return;
   int handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      handle = FileOpen(LogFileName, FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(handle != INVALID_HANDLE)
      {
         FileWrite(handle, "Timestamp", "Symbol", "Direction", "Pattern_OB", "Pattern_FVG", "Current_Price");
         FileClose(handle);
      }
   }
   else FileClose(handle);
}

void SendTelegramMessage(string message)
{
   if(!SendTelegramAlerts) return;
   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage?chat_id=" + TelegramChatID + "&text=" + message;
   char data[]; char result[]; string resultHeaders; string headers = "";
   WebRequest("GET", url, headers, 5000, data, result, resultHeaders);
}

void LogAndAlert(string symbol, int trend, double obLow, double obHigh, double fvgLow, double fvgHigh, double sl, double price)
{
   string dir = (trend == 1) ? "BUY POTENTIAL" : "SELL POTENTIAL";
   string patterns = "";
   if(obLow!=0) patterns += " [OrderBlock]";
   if(fvgLow!=0) patterns += " [FVG]";
   
   string msg = "🔎 SCANNER: " + symbol + " | " + dir + "\n";
   msg += "Patterns:" + patterns + "\n";
   msg += "Zone Price: " + DoubleToString(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   
   // Alerte Console
   Print(msg);
   
   // Alerte Popup MT5
   if(SendPopupAlerts) Alert(msg);
   
   // Alerte Telegram
   SendTelegramMessage(msg);
   
   // Log CSV
   if(EnableLogging) {
      int handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(handle != INVALID_HANDLE) {
         FileSeek(handle, 0, SEEK_END);
         FileWrite(handle, TimeToString(TimeCurrent()), symbol, dir, obLow!=0, fvgLow!=0, price);
         FileClose(handle);
      }
   }
}
