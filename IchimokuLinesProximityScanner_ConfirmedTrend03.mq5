//+------------------------------------------------------------------+
//|                            KijunScanner_Massive_v4.9_Persistent.mq5|
//|                                  Copyright 2026, Didier Le HPI   |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "4.9"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input ENUM_TIMEFRAMES InpScanTimeframe = PERIOD_CURRENT; 
input int      InpTenkan         = 9;      
input int      InpKijun          = 26;     
input int      InpSenkou         = 52;     

input group "Paramètres du Scanner"
input int      InpBatchSize      = 10;     
input int      InpBatchDelay     = 1;      
input string   InpManualSymbols  = "";     
input double   InpThresholdPercent = 0.15; // Seuil de détection initiale

input group "Notifications Mobile"
input bool     InpSendPush       = true;   
input int      InpAlertCooldown  = 60;     

input group "Interface Graphique"
input int      InpXOffset        = 20;     
input int      InpYOffset        = 20;     
input int      InpFontSize       = 9;      
input color    InpHeaderColor    = clrGold; 
input color    InpBgColor        = C'25,25,25'; 

//--- Structures
struct SymbolData {
   string name;
   int    ichimokuHandle; 
   datetime lastAlertTenkan, lastAlertKijun, lastAlertSSB;
   double lastDiffTenkan, lastDiffKijun, lastDiffSSB;
   bool   isTrackedTenkan, isTrackedKijun, isTrackedSSB;
};

struct ScanResult { 
   string sym; double prc; double diff; string line; string status;
};

//--- Variables globales
SymbolData      g_symbolData[]; 
int             g_totalSymbols = 0;
string          g_prefix = "ScanIchi_";
ENUM_TIMEFRAMES g_currentTF;

int             g_currentIdx = 0;         
ScanResult      g_watchlist[]; 
int             g_watchCount = 0;
int             g_lastRowCount = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   g_currentTF = (InpScanTimeframe == PERIOD_CURRENT) ? _Period : InpScanTimeframe;
   ResetScannerState();
   InitSymbolsList();
   if(g_totalSymbols <= 0) return(INIT_FAILED);

   CreateBackground(InpXOffset - 5, InpYOffset - 5, 600, 100); 
   EventSetTimer(InpBatchDelay);
   return(INIT_SUCCEEDED);
}

void ResetScannerState() {
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   for(int i = 0; i < ArraySize(g_symbolData); i++) {
      if(g_symbolData[i].ichimokuHandle != INVALID_HANDLE) {
         IndicatorRelease(g_symbolData[i].ichimokuHandle);
         g_symbolData[i].ichimokuHandle = INVALID_HANDLE;
      }
   }
   g_currentIdx = 0; g_watchCount = 0; g_lastRowCount = 0;
   ArrayFree(g_watchlist); ArrayFree(g_symbolData);
}

void OnDeinit(const int reason) { ResetScannerState(); }

void OnTimer() {
   int limit = MathMin(g_currentIdx + InpBatchSize, g_totalSymbols);
   datetime now = TimeCurrent();
   int cooldownSec = InpAlertCooldown * 60;

   for(int i = g_currentIdx; i < limit; i++) {
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE)
         g_symbolData[i].ichimokuHandle = iIchimoku(g_symbolData[i].name, g_currentTF, InpTenkan, InpKijun, InpSenkou);
      
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) continue;

      double price = SymbolInfoDouble(g_symbolData[i].name, SYMBOL_BID);
      if(price <= 0) continue;

      double t = GetIchiValue(g_symbolData[i].ichimokuHandle, 0); 
      double k = GetIchiValue(g_symbolData[i].ichimokuHandle, 1); 
      double a = GetIchiValue(g_symbolData[i].ichimokuHandle, 2); 
      double b = GetIchiValue(g_symbolData[i].ichimokuHandle, 3); 

      CheckLogic(i, t, t, k, a, b, "Tenkan", price, now, cooldownSec, g_symbolData[i].lastDiffTenkan, g_symbolData[i].isTrackedTenkan);
      CheckLogic(i, k, t, k, a, b, "Kijun",  price, now, cooldownSec, g_symbolData[i].lastDiffKijun,  g_symbolData[i].isTrackedKijun);
      CheckLogic(i, b, t, k, a, b, "SSB",    price, now, cooldownSec, g_symbolData[i].lastDiffSSB,    g_symbolData[i].isTrackedSSB);
   }

   g_currentIdx = limit;
   UpdateLabel(g_prefix+"progress", StringFormat("Scan %s: %d / %d", StringSubstr(EnumToString(g_currentTF),7), g_currentIdx, g_totalSymbols), InpXOffset + 400, InpYOffset, clrCyan);

   if(g_currentIdx >= g_totalSymbols) {
      UpdateDashboard();
      g_currentIdx = 0;
      g_watchCount = 0;
      ArrayFree(g_watchlist);
   }
}

//+------------------------------------------------------------------+
//| Logique : Maintien tant que l'alignement est OK                  |
//+------------------------------------------------------------------+
void CheckLogic(int symIdx, double lineVal, double t, double k, double a, double b, 
                string lineName, double price, datetime now, int cooldown, double &lastDiff, bool &isTracked) {
   if(lineVal <= 0 || t <= 0 || k <= 0 || a <= 0 || b <= 0) { isTracked = false; return; }
   
   double currentDiff = ((price - lineVal) / price) * 100.0;
   double absDiff = MathAbs(currentDiff);

   // Alignement strict : prix au dessus de toutes les lignes pour un achat (ou inversement)
   bool isAligned = (price > lineVal) ? (price > t && price > k && price > a && price > b) 
                                      : (price < t && price < k && price < a && price < b);

   // CONDITION : On entre si proche (0.15%), on RESTE tant qu'aligné (isAligned)
   if((absDiff <= InpThresholdPercent || isTracked) && isAligned) {
      
      string status = "STABLE";
      if(lastDiff != 0) {
         if(absDiff > MathAbs(lastDiff)) status = "REBOUNDING";
         else if(absDiff < MathAbs(lastDiff)) status = "APPROACHING";
      }

      g_watchCount++;
      ArrayResize(g_watchlist, g_watchCount);
      int last = g_watchCount - 1;
      g_watchlist[last].sym = g_symbolData[symIdx].name;
      g_watchlist[last].prc = price;
      g_watchlist[last].diff = currentDiff;
      g_watchlist[last].line = lineName;
      g_watchlist[last].status = status;
      
      // Alerte uniquement au premier contact ou si rebond important
      if(!isTracked && absDiff <= InpThresholdPercent) {
         ManageAlerts(symIdx, lineName, price, currentDiff, now, cooldown, "ENTRY");
      }
      
      isTracked = true; 
   }
   else {
      isTracked = false; // Sortie définitive de la liste car l'alignement est brisé
   }
   
   lastDiff = currentDiff;
}

// --- Fonctions utilitaires ---

void InitSymbolsList() {
   if(InpManualSymbols != "") {
      string temp[]; ushort sep = StringGetCharacter(",", 0);
      StringSplit(InpManualSymbols, sep, temp);
      g_totalSymbols = ArraySize(temp);
      ArrayResize(g_symbolData, g_totalSymbols);
      for(int i=0; i<g_totalSymbols; i++) g_symbolData[i].name = temp[i];
   } else {
      g_totalSymbols = SymbolsTotal(true); 
      ArrayResize(g_symbolData, g_totalSymbols);
      for(int i=0; i<g_totalSymbols; i++) g_symbolData[i].name = SymbolName(i, true);
   }
   for(int i=0; i<g_totalSymbols; i++) {
      g_symbolData[i].ichimokuHandle = INVALID_HANDLE;
      g_symbolData[i].isTrackedTenkan = false; g_symbolData[i].isTrackedKijun = false; g_symbolData[i].isTrackedSSB = false;
   }
}

void UpdateDashboard() {
   string tfStr = StringSubstr(EnumToString(g_currentTF), 7);
   UpdateLabel(g_prefix+"h1", "LIVE WATCHLIST (ALIGNEMENT) - "+tfStr, InpXOffset, InpYOffset, InpHeaderColor);
   
   int startY = InpYOffset + 40;
   int lineHeight = InpFontSize + 6;
   UpdateLabel(g_prefix+"head", "SYMBOLE  | PRIX     | LIGNE  | DIST.  | STATUS", InpXOffset, startY, clrGray);

   for(int i = 0; i < g_watchCount; i++) {
      color clr = (g_watchlist[i].status == "REBOUNDING") ? clrGold : (g_watchlist[i].diff >= 0 ? clrLime : clrRed);
      
      // Si l'actif s'est déjà bien éloigné (>0.15%), on le met en blanc pour montrer qu'il est en suivi de tendance
      if(MathAbs(g_watchlist[i].diff) > InpThresholdPercent && g_watchlist[i].status != "REBOUNDING") clr = clrWhite;

      string line = StringFormat("%-8s | %-8.5f | %-6s | %+.2f%% | %-12s", 
                                 g_watchlist[i].sym, g_watchlist[i].prc, g_watchlist[i].line, 
                                 g_watchlist[i].diff, g_watchlist[i].status);
                                 
      UpdateLabel(g_prefix+"row_"+(string)i, line, InpXOffset, startY + 20 + (i*lineHeight), clr);
   }
   for(int k = g_watchCount; k < g_lastRowCount; k++) ObjectDelete(0, g_prefix+"row_"+(string)k);
   g_lastRowCount = g_watchCount;
   ObjectSetInteger(0, g_prefix+"bg", OBJPROP_YSIZE, 80 + (MathMax(1, g_watchCount) * lineHeight));
   ChartRedraw();
}

double GetIchiValue(int handle, int bufferIdx) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, bufferIdx, 0, 1, buffer) <= 0) return 0.0;
   return buffer[0];
}

void ManageAlerts(int i, string line, double price, double dev, datetime now, int cooldown, string status) {
   bool a = false;
   if(line=="Tenkan" && now - g_symbolData[i].lastAlertTenkan > cooldown) { a=true; g_symbolData[i].lastAlertTenkan=now; }
   if(line=="Kijun" && now - g_symbolData[i].lastAlertKijun > cooldown)   { a=true; g_symbolData[i].lastAlertKijun=now; }
   if(line=="SSB" && now - g_symbolData[i].lastAlertSSB > cooldown)       { a=true; g_symbolData[i].lastAlertSSB=now; }
   
   if(a && InpSendPush) {
      SendNotification(StringFormat("SCAN %s: %s sur %s détecté !", StringSubstr(EnumToString(g_currentTF),7), line, g_symbolData[i].name));
   }
}

void UpdateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas"); 
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

void CreateBackground(int x, int y, int w, int h) {
   string name = g_prefix + "bg";
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}
