//+------------------------------------------------------------------+
//| SMC ICT Market Scanner MT5 - Distinct Colors Version             |
//+------------------------------------------------------------------+
#property copyright "SMC AI Scanner Colors"
#property link      "https://www.mql5.com"
#property version   "1.40"
#property strict

// --- Paramètres du Scanner ---
input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;  
input ENUM_TIMEFRAMES EntryTF = PERIOD_M15; 
input ENUM_TIMEFRAMES MicroTF = PERIOD_M5;  

// --- Filtres ---
input bool UseSessionFilter = true;
input int StartHour = 8;
input int EndHour   = 17;

// --- Paramètres Visuels (NOUVEAU) ---
input bool DrawZonesOnChart = true; 

// Couleurs pour ORDER BLOCKS (OB)
input color ColorOB_Buy   = clrDodgerBlue;  // Bleu pour OB Achat
input color ColorOB_Sell  = clrOrangeRed;   // Rouge pour OB Vente

// Couleurs pour FAIR VALUE GAPS (FVG)
input color ColorFVG_Buy  = clrLightGreen;  // Vert clair pour FVG Achat
input color ColorFVG_Sell = clrPink;        // Rose pour FVG Vente

// --- Alertes ---
input string TelegramBotToken = "VOTRE_TOKEN_ICI";
input string TelegramChatID = "VOTRE_CHAT_ID_ICI";
input bool SendTelegramAlerts = true;
input bool SendPopupAlerts = true; 

// --- Logging ---
input string LogFileName = "SMC_Scanner_Log.csv";
input bool EnableLogging = true;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("SMC ICT Distinct Colors Scanner Initialized...");
   InitLogFile();
   EventSetTimer(15); 
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   long currChart = ChartFirst();
   while(currChart != -1)
   {
      ObjectsDeleteAll(currChart, "SMC_");
      ChartRedraw(currChart);
      currChart = ChartNext(currChart);
   }
}

//+------------------------------------------------------------------+
void OnTimer()
{
   datetime t = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int hourNow = dt.hour;

   int total = SymbolsTotal(true); 
   
   for(int i=0; i<total; i++)
   {
      string sym = SymbolName(i, true);
      if(!SymbolInfoInteger(sym, SYMBOL_SELECT)) continue;
      
      // Filtre Session
      if(UseSessionFilter && StringFind(sym, "BTC") == -1 && StringFind(sym, "ETH") == -1) 
      {
         if(hourNow < StartHour || hourNow >= EndHour) continue;
      }

      // 1. Tendance H1
      int trend = CheckMarketStructure(sym, TrendTF);
      if (trend == 0) continue; 

      // 2. Patterns M15 
      double obLow=0, obHigh=0, fvgLow=0, fvgHigh=0, sweepLevel=0;
      datetime obTime=0, fvgTime=0; 
      
      bool foundOB = FindOrderBlock(sym, EntryTF, trend, obLow, obHigh, obTime);
      bool foundFVG = FindFairValueGap(sym, EntryTF, trend, fvgLow, fvgHigh, fvgTime);
      
      if(!foundOB && !foundFVG) continue; 
      
      // 3. Confirmation M5
      if(!FindLiquiditySweep(sym, MicroTF, trend, sweepLevel)) sweepLevel = 0;
      
      bool signal = CheckMicrostructure(sym, MicroTF, obLow, obHigh, fvgLow, fvgHigh, 0, 0, sweepLevel, trend);

      if(signal)
      {
         double currentPrice = (trend == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
         double sl = (trend == 1) ? (obLow != 0 ? obLow : fvgLow) : (obHigh != 0 ? obHigh : fvgHigh);
         
         // ALERTE
         LogAndAlert(sym, trend, obLow, obHigh, fvgLow, fvgHigh, sl, currentPrice);
         
         // DESSIN AVEC COULEURS DISTINCTES
         if(DrawZonesOnChart)
         {
            if(foundOB) {
               color c = (trend == 1) ? ColorOB_Buy : ColorOB_Sell;
               DrawOnRemoteCharts(sym, "SMC_OB", obTime, obLow, obHigh, c);
            }
            
            if(foundFVG) {
               color c = (trend == 1) ? ColorFVG_Buy : ColorFVG_Sell;
               DrawOnRemoteCharts(sym, "SMC_FVG", fvgTime, fvgLow, fvgHigh, c);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
// --- Fonction Dessin (Modifiée pour accepter la couleur en argument) ---
//+------------------------------------------------------------------+

void DrawOnRemoteCharts(string sym, string nameSuffix, datetime timeStart, double price1, double price2, color zoneColor)
{
   long currChart = ChartFirst(); 
   
   while(currChart != -1) 
   {
      if(ChartSymbol(currChart) == sym)
      {
         string objName = nameSuffix; 
         
         ObjectDelete(currChart, objName);
         
         if(ObjectCreate(currChart, objName, OBJ_RECTANGLE, 0, timeStart, price1, TimeCurrent(), price2))
         {
            // Application de la couleur passée en argument
            ObjectSetInteger(currChart, objName, OBJPROP_COLOR, (long)zoneColor);
            
            ObjectSetInteger(currChart, objName, OBJPROP_FILL, (long)true);
            ObjectSetInteger(currChart, objName, OBJPROP_BACK, (long)true);
            ObjectSetInteger(currChart, objName, OBJPROP_WIDTH, 1);
            
            ObjectSetInteger(currChart, objName, OBJPROP_TIME, 1, (long)(TimeCurrent() + PeriodSeconds(PERIOD_M15)*10));
            
            ChartRedraw(currChart);
         }
      }
      currChart = ChartNext(currChart);
   }
}

//+------------------------------------------------------------------+
// --- Fonctions Techniques --- 
//+------------------------------------------------------------------+

int CheckMarketStructure(string sym, ENUM_TIMEFRAMES tf)
{
   double high1 = iHigh(sym, tf, 1); double high2 = iHigh(sym, tf, 2);
   double low1 = iLow(sym, tf, 1);   double low2 = iLow(sym, tf, 2);
   if(high1 == 0 || high2 == 0) return 0;
   if(high1 > high2 && low1 > low2) return 1;
   if(high1 < high2 && low1 < low2) return -1;
   return 0;
}

bool FindOrderBlock(string sym, ENUM_TIMEFRAMES tf, int trend, double &obLow, double &obHigh, datetime &timeFound)
{
   for(int i=2; i<10; i++)
   {
      double open = iOpen(sym, tf, i); double close = iClose(sym, tf, i);
      double high = iHigh(sym, tf, i); double low = iLow(sym, tf, i);

      if(trend == 1 && close < open) { 
         obLow = low; obHigh = high; timeFound = iTime(sym, tf, i); return true; 
      }
      if(trend == -1 && close > open) { 
         obLow = low; obHigh = high; timeFound = iTime(sym, tf, i); return true; 
      }
   }
   return false;
}

bool FindFairValueGap(string sym, ENUM_TIMEFRAMES tf, int trend, double &fvgLow, double &fvgHigh, datetime &timeFound)
{
   for(int i=2; i<10; i++)
   {
      double high_prev = iHigh(sym, tf, i+1); double low_prev  = iLow(sym, tf, i+1);
      double high_next = iHigh(sym, tf, i-1); double low_next  = iLow(sym, tf, i-1);

      if(trend == 1 && low_next > high_prev) { 
         fvgLow = high_prev; fvgHigh = low_next; timeFound = iTime(sym, tf, i); return true; 
      }
      if(trend == -1 && high_next < low_prev) { 
         fvgLow = high_next; fvgHigh = low_prev; timeFound = iTime(sym, tf, i); return true; 
      }
   }
   return false;
}

bool FindLiquiditySweep(string sym, ENUM_TIMEFRAMES tf, int trend, double &sweepLevel)
{
   sweepLevel = (trend == 1) ? iHigh(sym, tf, 1) : iLow(sym, tf, 1);
   return true;
}

bool CheckMicrostructure(string sym, ENUM_TIMEFRAMES tf, double obLow, double obHigh, double fvgLow, double fvgHigh, double bL, double bH, double sweep, int trend)
{
   double close = iClose(sym, tf, 0); 
   if(trend == 1) {
       if((obHigh > 0 && close >= obLow && close <= obHigh) || (fvgHigh > 0 && close >= fvgLow && close <= fvgHigh)) return true;
   }
   if(trend == -1) {
       if((obLow > 0 && close >= obLow && close <= obHigh) || (fvgLow > 0 && close >= fvgLow && close <= fvgHigh)) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// --- Logging + Alertes --- 
//+------------------------------------------------------------------+

void InitLogFile()
{
   if(!EnableLogging) return;
   int handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON);
   if(handle == INVALID_HANDLE) {
      handle = FileOpen(LogFileName, FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(handle != INVALID_HANDLE) {
         FileWrite(handle, "Timestamp", "Symbol", "Direction", "Pattern_OB", "Pattern_FVG", "Current_Price");
         FileClose(handle);
      }
   } else FileClose(handle);
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
   
   Print(msg);
   if(SendPopupAlerts) Alert(msg);
   SendTelegramMessage(msg);
   
   if(EnableLogging) {
      int handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(handle != INVALID_HANDLE) {
         FileSeek(handle, 0, SEEK_END);
         FileWrite(handle, TimeToString(TimeCurrent()), symbol, dir, obLow!=0, fvgLow!=0, price);
         FileClose(handle);
      }
   }
}
